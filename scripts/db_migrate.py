#!/usr/bin/env python3
"""Move the Cachy database between any two Postgres hosts, and verify the copy.

Provider-agnostic: it speaks plain libpq, so the same commands work for Neon,
Supabase, Aiven, or a box you own. Credentials are read from the environment and
the password is handed to the child process via PGPASSWORD rather than argv, so
it never shows up in `ps` or your shell history.

    export SOURCE_DATABASE_URL='postgresql://...neon...'
    python scripts/db_migrate.py dump cachy-backup.dump

    export TARGET_DATABASE_URL='postgresql://...new-host...'
    python scripts/db_migrate.py restore cachy-backup.dump
    python scripts/db_migrate.py verify        # exact per-table row counts

`dump` on its own is also the backup you should be taking on a schedule
regardless of provider: every free tier can evaporate, and a dump file is the
only thing that makes that survivable.

Note the app stores its URL in SQLAlchemy form (postgresql+asyncpg://). libpq
does not understand the +asyncpg driver suffix, so it is stripped here. Query
parameters such as sslmode and channel_binding are kept, because libpq does
understand those and dropping them would silently downgrade or break TLS.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from urllib.parse import unquote, urlsplit, urlunsplit


class MigrateError(RuntimeError):
    pass


def to_libpq_url(url: str) -> str:
    """Strip the SQLAlchemy driver suffix so libpq tools accept the URL.

    `postgresql+asyncpg://h/db` -> `postgresql://h/db`. Anything already in
    libpq form passes through untouched.
    """
    if not url:
        raise MigrateError("empty database URL")
    scheme, rest = (url.split("://", 1) + [""])[:2] if "://" in url else (url, "")
    if "://" not in url:
        raise MigrateError(f"not a connection URL: {url!r}")
    base = scheme.split("+", 1)[0]
    if base not in ("postgresql", "postgres"):
        raise MigrateError(
            f"only Postgres is supported here, got scheme {scheme!r}. "
            "A SQLite source has no pg_dump equivalent; export via the API instead."
        )
    return f"{base}://{rest}"


def split_password(url: str) -> tuple[str, str | None]:
    """Return (url without password, decoded password).

    Keeping the password out of the command line means it never appears in `ps`
    output or shell history; it goes to the child through PGPASSWORD instead.

    The password is percent-decoded on the way out. Inside a URL it is encoded
    (`pw%40123`), but PGPASSWORD is a raw value, so handing over the encoded form
    fails authentication for any password containing @ : / or similar — which
    provider-generated passwords routinely do.
    """
    parts = urlsplit(url)
    if not parts.password:
        return url, None
    host = parts.hostname or ""
    if parts.port:
        host = f"{host}:{parts.port}"
    userinfo = parts.username or ""
    netloc = f"{userinfo}@{host}" if userinfo else host
    stripped = urlunsplit((parts.scheme, netloc, parts.path, parts.query, parts.fragment))
    return stripped, unquote(parts.password)


def require_tool(name: str) -> str:
    path = shutil.which(name)
    if not path:
        raise MigrateError(
            f"{name} not found on PATH. Install the Postgres client tools "
            "(macOS: brew install libpq && brew link --force libpq)."
        )
    return path


def env_url(var: str) -> str:
    raw = os.environ.get(var, "").strip()
    if not raw:
        raise MigrateError(f"{var} is not set")
    return to_libpq_url(raw)


def run(argv: list[str], password: str | None) -> None:
    env = dict(os.environ)
    if password:
        env["PGPASSWORD"] = password
    # Fail fast rather than hanging forever on an unreachable or suspended host.
    env.setdefault("PGCONNECT_TIMEOUT", "30")
    proc = subprocess.run(argv, env=env)
    if proc.returncode != 0:
        raise MigrateError(f"{argv[0]} exited {proc.returncode}")


def psql_scalar_rows(url: str, sql: str) -> list[list[str]]:
    """Run a query and return rows as lists of strings, via psql's TSV output."""
    clean, password = split_password(url)
    env = dict(os.environ)
    if password:
        env["PGPASSWORD"] = password
    env.setdefault("PGCONNECT_TIMEOUT", "30")
    proc = subprocess.run(
        [require_tool("psql"), clean, "-At", "-F", "\t", "-c", sql],
        env=env,
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise MigrateError(f"psql failed: {proc.stderr.strip()}")
    return [line.split("\t") for line in proc.stdout.splitlines() if line]


def table_counts(url: str) -> dict[str, int]:
    """Exact row count per user table.

    Deliberately not pg_stat_user_tables.n_live_tup: that is a planner estimate
    and can be wrong by a lot right after a bulk restore, which is exactly when
    this check runs and exactly when a wrong answer would be believed.
    """
    tables = [
        r[0]
        for r in psql_scalar_rows(
            url,
            "select tablename from pg_tables where schemaname = 'public' "
            "order by tablename",
        )
    ]
    if not tables:
        return {}
    union = " union all ".join(
        f"select '{t}' as t, count(*) from public.\"{t}\"" for t in tables
    )
    return {r[0]: int(r[1]) for r in psql_scalar_rows(url, f"{union} order by t")}


def cmd_dump(path: str) -> int:
    url = env_url("SOURCE_DATABASE_URL")
    clean, password = split_password(url)
    # Custom format (-Fc): compressed, and restorable selectively with pg_restore.
    # --no-owner/--no-privileges because role names never match across providers,
    # and without them every GRANT and OWNER TO fails on the target.
    run(
        [
            require_tool("pg_dump"),
            clean,
            "--format=custom",
            "--no-owner",
            "--no-privileges",
            "--verbose",
            "--file",
            path,
        ],
        password,
    )
    size = os.path.getsize(path)
    print(f"\nwrote {path} ({size:,} bytes)")
    if size < 1024:
        print(
            "WARNING: that dump is suspiciously small. Check the source really "
            "holds your data before trusting it."
        )
    counts = table_counts(url)
    print("source row counts:")
    for table, n in sorted(counts.items()):
        print(f"  {table:<24} {n:>8,}")
    return 0


def cmd_restore(path: str) -> int:
    if not os.path.isfile(path):
        raise MigrateError(f"no such dump file: {path}")
    url = env_url("TARGET_DATABASE_URL")
    clean, password = split_password(url)
    # --clean --if-exists makes a re-run idempotent instead of erroring on every
    # existing object, which matters because the app's init_db() may already have
    # created empty tables on the target before you get here.
    run(
        [
            require_tool("pg_restore"),
            "--dbname",
            clean,
            "--no-owner",
            "--no-privileges",
            "--clean",
            "--if-exists",
            "--verbose",
            path,
        ],
        password,
    )
    print("\nrestore finished; run `verify` before you switch DATABASE_URL over")
    return 0


def cmd_verify() -> int:
    source = env_url("SOURCE_DATABASE_URL")
    target = env_url("TARGET_DATABASE_URL")
    src, tgt = table_counts(source), table_counts(target)
    names = sorted(set(src) | set(tgt))
    if not names:
        print("no tables found on either side")
        return 1
    width = max(len(n) for n in names)
    ok = True
    print(f"{'table'.ljust(width)}  {'source':>10}  {'target':>10}")
    for name in names:
        a, b = src.get(name), tgt.get(name)
        match = a == b
        ok &= match
        flag = "" if match else "   <-- MISMATCH"
        print(
            f"{name.ljust(width)}  {('-' if a is None else f'{a:,}'):>10}  "
            f"{('-' if b is None else f'{b:,}'):>10}{flag}"
        )
    print("\n" + ("every table matches" if ok else "MISMATCH: do not switch over yet"))
    return 0 if ok else 1


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    sub = parser.add_subparsers(dest="cmd", required=True)
    d = sub.add_parser("dump", help="pg_dump SOURCE_DATABASE_URL to a file")
    d.add_argument("path")
    r = sub.add_parser("restore", help="pg_restore a file into TARGET_DATABASE_URL")
    r.add_argument("path")
    sub.add_parser("verify", help="compare exact row counts on both sides")
    args = parser.parse_args()
    try:
        if args.cmd == "dump":
            return cmd_dump(args.path)
        if args.cmd == "restore":
            return cmd_restore(args.path)
        return cmd_verify()
    except MigrateError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
