"""Network safety guards shared by the ingestion scrapers.

Two concerns, one place:
  - SSRF: users submit arbitrary URLs. Reject anything that isn't plain http(s)
    to a public host, so a submitted URL can't be pointed at loopback / private
    ranges / cloud metadata endpoints (N17). Matters most on LAN/self-host
    deploys where internal services are reachable.
  - Disk/RAM exhaustion: streamed downloads have only a timeout, no size cap. A
    huge (or hostile) source can fill the ephemeral disk and take the process
    down. Cap bytes while streaming to a file (M5).
"""

from __future__ import annotations

import ipaddress
import socket
from pathlib import Path
from urllib.parse import urlparse

# Default cap for a single streamed download. Generous for a short-form video,
# tight vs. an attacker. ponytail: bump if legit sources ever exceed it.
MAX_DOWNLOAD_BYTES = 200 * 1024 * 1024  # 200 MB


class UnsafeUrlError(ValueError):
    """Raised when a submitted URL targets a non-public / non-http(s) host."""


class DownloadTooLargeError(ValueError):
    """Raised when a streamed download exceeds the byte cap."""


def _host_is_public(host: str) -> bool:
    """True only if EVERY resolved address for `host` is a global (public) IP.

    Resolving here (not just parsing) closes DNS-rebinding-style bypasses where a
    public-looking name resolves to a private address."""
    try:
        infos = socket.getaddrinfo(host, None)
    except socket.gaierror:
        return False
    for info in infos:
        ip = info[4][0]
        try:
            addr = ipaddress.ip_address(ip)
        except ValueError:
            return False
        if not addr.is_global or addr.is_loopback or addr.is_private:
            return False
    return bool(infos)


def check_url(url: str) -> None:
    """Raise [UnsafeUrlError] if `url` isn't plain http(s) to a public host."""
    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https"):
        raise UnsafeUrlError(f"unsupported URL scheme: {parsed.scheme!r}")
    host = parsed.hostname
    if not host:
        raise UnsafeUrlError("URL has no host")
    if not _host_is_public(host):
        raise UnsafeUrlError(f"URL host is not a public address: {host}")


def stream_to_file(response, target_path: Path, *, chunk_size: int = 65536,
                   max_bytes: int = MAX_DOWNLOAD_BYTES) -> int:
    """Stream a `requests` response body to `target_path`, capped at `max_bytes`.

    Raises [DownloadTooLargeError] (after deleting the partial file) if the body
    exceeds the cap. Also honours a Content-Length header for an early reject.
    Returns the number of bytes written."""
    declared = response.headers.get("Content-Length")
    if declared is not None:
        try:
            if int(declared) > max_bytes:
                raise DownloadTooLargeError(
                    f"declared size {declared} exceeds cap {max_bytes}"
                )
        except ValueError:
            pass  # malformed header — fall through to the streaming cap

    written = 0
    target_path = Path(target_path)
    with target_path.open("wb") as f:
        for chunk in response.iter_content(chunk_size=chunk_size):
            if not chunk:
                continue
            written += len(chunk)
            if written > max_bytes:
                f.close()
                target_path.unlink(missing_ok=True)
                raise DownloadTooLargeError(
                    f"download exceeded cap {max_bytes} bytes"
                )
            f.write(chunk)
    return written


def capped_content(response, *, max_bytes: int = MAX_DOWNLOAD_BYTES) -> bytes:
    """Read a `requests` response body into memory, capped at `max_bytes`.

    For the small-image download sites that use `.content`. Raises
    [DownloadTooLargeError] past the cap."""
    declared = response.headers.get("Content-Length")
    if declared is not None:
        try:
            if int(declared) > max_bytes:
                raise DownloadTooLargeError(
                    f"declared size {declared} exceeds cap {max_bytes}"
                )
        except ValueError:
            pass
    buf = bytearray()
    for chunk in response.iter_content(chunk_size=65536):
        if not chunk:
            continue
        buf.extend(chunk)
        if len(buf) > max_bytes:
            raise DownloadTooLargeError(f"body exceeded cap {max_bytes} bytes")
    return bytes(buf)


def demo() -> None:
    """Self-check (ponytail): the guard's core decisions must hold."""
    # public host passes scheme+host checks (resolution may vary in CI, so only
    # assert the scheme/loopback logic which is deterministic).
    for bad in ("ftp://example.com", "file:///etc/passwd", "http://127.0.0.1",
                "http://localhost", "http://169.254.169.254", "http://10.0.0.1"):
        try:
            check_url(bad)
        except UnsafeUrlError:
            continue
        raise AssertionError(f"expected {bad!r} to be rejected")

    # streaming cap trips at the right point
    class _Resp:
        def __init__(self, chunks):
            self._chunks = chunks
            self.headers = {}

        def iter_content(self, chunk_size=0):
            return iter(self._chunks)

    import tempfile

    with tempfile.TemporaryDirectory() as d:
        p = Path(d) / "out.bin"
        try:
            stream_to_file(_Resp([b"x" * 10]), p, max_bytes=5)
        except DownloadTooLargeError:
            assert not p.exists(), "partial file should be deleted on overflow"
        else:
            raise AssertionError("expected DownloadTooLargeError")
        n = stream_to_file(_Resp([b"x" * 4]), p, max_bytes=5)
        assert n == 4 and p.read_bytes() == b"xxxx"
    print("net_guard demo: OK")


if __name__ == "__main__":
    demo()
