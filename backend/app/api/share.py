"""Public card sharing: unlisted links anyone can open.

- POST   /cards/{card_id}/share   (owner)  create (idempotent) or fetch the link
- GET    /cards/{card_id}/share   (owner)  fetch the active link, 404 when none
- DELETE /cards/{card_id}/share   (owner)  revoke the link
- GET    /share/{token}           (public) JSON payload (the app's save sheet)
- POST   /share/{token}/save      (auth)   clone the card into the caller's
  library — "Save to my Cachy". No quota charge: the card is already
  structured, so saving costs no AI.
- GET    /s/{token}               (public) server-rendered page with OG tags
  (link previews need server HTML — a client SPA can't do OG). noindex:
  unlisted means unguessable, not discoverable.
- GET    /s/{token}/media/{name}  (public) the card's own thumbnail/keyframes,
  token-gated so only link holders can fetch them.
- GET    /.well-known/assetlinks.json     Android verified-app-links file.

Only READY cards can be shared. Deleting a card deletes its link.
"""

from __future__ import annotations

import asyncio
import html
import json
import logging
import secrets
import uuid

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import HTMLResponse, JSONResponse

from app.api.media import stream_card_media
from app.auth import OwnerDep
from app.config import get_settings
from app.models.card import CardState
from app.rate_limit import RateLimiter
from app.store import db
from app.store import media as media_store

log = logging.getLogger("api.share")
router = APIRouter(tags=["share"])

_share_limiter = RateLimiter(limit=30, window_seconds=60.0)
_save_limiter = RateLimiter(limit=20, window_seconds=60.0)


# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #

async def _resolve_share(token: str) -> tuple[db.ShareLinkRow, db.CardRow]:
    """The link + its card, or 404. A link whose card is gone or not READY
    reads as invalid (never leak why)."""
    async with db.session() as s:
        link = await db.get_share_link_by_token(s, token=token)
        if link is None:
            raise HTTPException(status_code=404, detail="link not found")
        row = await db.get_card_row(s, link.card_id)
        if row is None or row.state != CardState.READY.value:
            raise HTTPException(status_code=404, detail="link not found")
    return link, row


def _base_url(request: Request) -> str:
    return str(request.base_url).rstrip("/")


def _media_filenames(row: db.CardRow) -> list[str]:
    """Filenames of this card's own thumbnail/keyframes (for the token-gated
    media route — never serve arbitrary dataset paths)."""
    prefix = f"/media/{row.id}/"
    fns: list[str] = []
    refs: list = [row.thumbnail, *(row.keyframes or [])]
    for ref in refs:
        if isinstance(ref, str) and ref.startswith(prefix):
            fn = ref[len(prefix):]
            if fn and "/" not in fn and not fn.startswith(".") and fn not in fns:
                fns.append(fn)
    return fns


def _public_thumbnail(row: db.CardRow, token: str, base: str) -> str | None:
    """Absolute thumbnail URL for the share page / OG tags. Owner-gated
    /media/ paths are rewritten to the token-gated share route."""
    ref = media_store.to_media_url(row.thumbnail)
    if not ref:
        return None
    if ref.startswith("/media/"):
        parts = ref.split("/")
        if len(parts) == 4 and parts[3]:
            return f"{base}/s/{token}/media/{parts[3]}"
        return None
    if ref.startswith("http://") or ref.startswith("https://"):
        return ref
    return None


def _public_payload(
    link: db.ShareLinkRow, row: db.CardRow, token: str, base: str
) -> dict:
    """The safe public subset of a card — never owner_id, raw_bundle, or
    job internals."""
    return {
        "token": token,
        "url": f"{base}/s/{token}",
        "one_liner": row.one_liner,
        "tldr": row.tldr,
        "content_type": row.content_type,
        "tags": row.tags or [],
        "blocks": row.blocks or [],
        "platform": row.platform,
        "creator": row.creator,
        "source_url": row.source_url,
        "thumbnail_url": _public_thumbnail(row, token, base),
        "shared_at": link.created_at.isoformat(),
    }


def _deepcopy_json(value):
    return json.loads(json.dumps(value)) if value is not None else value


def _fresh_blocks(blocks: list | None) -> list:
    """Deep copy with per-user state reset — the saver's copy starts unchecked."""
    out = _deepcopy_json(blocks) or []
    for b in out:
        if isinstance(b, dict) and b.get("type") == "checklist":
            for item in b.get("items") or []:
                if isinstance(item, dict):
                    item["checked"] = False
    return out


def _fresh_action_items(ai: dict | None) -> dict | None:
    if not ai:
        return None
    out = _deepcopy_json(ai)
    out["followed"] = False
    for item in out.get("items") or []:
        if isinstance(item, dict):
            item["done"] = False
    return out


async def _duplicate_media(orig_id: str, new_id: str, filenames: list[str]) -> set[str]:
    """Copy the card's media files to the new card's dataset namespace.
    Best-effort: failures are logged and the copy simply has no thumbnail."""
    settings = get_settings()
    if not settings.hf_media_enabled or not filenames:
        return set()
    from huggingface_hub import hf_hub_download, upload_file

    copied: set[str] = set()
    for fn in filenames:
        try:
            local = await asyncio.to_thread(
                hf_hub_download,
                repo_id=settings.hf_media_repo,
                repo_type="dataset",
                filename=f"media/{orig_id}/{fn}",
                token=settings.hf_api_key,
            )
            await asyncio.to_thread(
                upload_file,
                path_or_fileobj=local,
                path_in_repo=f"media/{new_id}/{fn}",
                repo_id=settings.hf_media_repo,
                repo_type="dataset",
                token=settings.hf_api_key,
            )
            copied.add(fn)
        except Exception as exc:
            log.warning("share save: media copy failed for %s/%s: %s", orig_id, fn, exc)
    return copied


# --------------------------------------------------------------------------- #
# Owner endpoints
# --------------------------------------------------------------------------- #

@router.post("/cards/{card_id}/share")
async def create_share_link(
    card_id: str, request: Request, owner_id: OwnerDep
) -> dict:
    """Create the public share link for a card (idempotent — re-sharing
    returns the existing link). Only READY cards can be shared."""
    _share_limiter.check(request)
    async with db.session() as s:
        row = await db.get_card_row(s, card_id, owner_id=owner_id)
        if row is None:
            raise HTTPException(status_code=404, detail="card not found")
        if row.state != CardState.READY.value:
            raise HTTPException(
                status_code=409, detail="only finished cards can be shared"
            )
        existing = await db.get_share_link_by_card(
            s, card_id=card_id, owner_id=owner_id
        )
        if existing is not None:
            token = existing.token
        else:
            token = secrets.token_urlsafe(24)
            await db.create_share_link(
                s, token=token, card_id=card_id, owner_id=owner_id
            )
    base = _base_url(request)
    log.info("share link created for card %s", card_id)
    return {"url": f"{base}/s/{token}", "token": token}


@router.get("/cards/{card_id}/share")
async def get_share_link(
    card_id: str, request: Request, owner_id: OwnerDep
) -> dict:
    async with db.session() as s:
        row = await db.get_share_link_by_card(s, card_id=card_id, owner_id=owner_id)
        if row is None:
            raise HTTPException(status_code=404, detail="no active share link")
    base = _base_url(request)
    return {"url": f"{base}/s/{row.token}", "token": row.token}


@router.delete("/cards/{card_id}/share")
async def revoke_share_link(card_id: str, owner_id: OwnerDep) -> dict:
    async with db.session() as s:
        row = await db.get_share_link_by_card(s, card_id=card_id, owner_id=owner_id)
        if row is None:
            raise HTTPException(status_code=404, detail="no active share link")
        await db.delete_share_links_for_card(s, card_id=card_id)
    log.info("share link revoked for card %s", card_id)
    return {"revoked": True}


# --------------------------------------------------------------------------- #
# Public endpoints
# --------------------------------------------------------------------------- #

@router.get("/share/{token}")
async def share_json(token: str, request: Request) -> dict:
    """Public JSON payload for a share link (used by the app's save sheet)."""
    link, row = await _resolve_share(token)
    return _public_payload(link, row, token, _base_url(request))


@router.post("/share/{token}/save")
async def save_shared_card(
    token: str, request: Request, owner_id: OwnerDep
) -> dict:
    """"Save to my Cachy": clone the shared card into the caller's library.

    No quota charge — the card is already structured. Idempotent per source
    URL: saving the same shared card twice returns the first copy."""
    _save_limiter.check(request)
    link, row = await _resolve_share(token)
    if link.owner_id == owner_id:
        raise HTTPException(status_code=409, detail="you already own this card")
    async with db.session() as s:
        dup = await db.find_card_by_url(s, row.source_url, owner_id=owner_id)
        if dup is not None:
            return {"card_id": dup.id, "already_saved": True}
        new_id = uuid.uuid4().hex
        filenames = _media_filenames(row)
        copied = await _duplicate_media(row.id, new_id, filenames)

        def _rewrite(ref: str | None) -> str | None:
            if isinstance(ref, str) and ref.startswith(f"/media/{row.id}/"):
                fn = ref[len(f"/media/{row.id}/"):]
                if fn in copied:
                    return f"/media/{new_id}/{fn}"
                return None
            return ref

        keyframes = [
            r for k in (row.keyframes or [])
            if (r := _rewrite(k)) is not None
        ]
        new_row = db.CardRow(
            id=new_id,
            state=CardState.READY.value,
            owner_id=owner_id,
            source_url=row.source_url,
            platform=row.platform,
            creator=row.creator,
            caption=row.caption,
            duration_seconds=row.duration_seconds,
            content_type=row.content_type,
            type_confidence=row.type_confidence,
            one_liner=row.one_liner,
            tldr=row.tldr,
            tags=list(row.tags or []),
            primary_action=_deepcopy_json(row.primary_action),
            action_items=_fresh_action_items(row.action_items),
            blocks=_fresh_blocks(row.blocks),
            insight=_deepcopy_json(row.insight),
            thumbnail=_rewrite(row.thumbnail),
            keyframes=keyframes or None,
            extraction=_deepcopy_json(row.extraction),
        )
        s.add(new_row)
        await s.commit()
    log.info("shared card saved: %s -> %s (owner %s)", row.id, new_id, owner_id)
    return {"card_id": new_id, "already_saved": False}


@router.get("/s/{token}/media/{filename}")
async def share_media(token: str, filename: str):
    """Token-gated media for a share link — only the card's own thumbnail /
    keyframes, never arbitrary dataset paths."""
    _, row = await _resolve_share(token)
    if filename not in _media_filenames(row):
        raise HTTPException(status_code=404, detail="not found")
    return await stream_card_media(row.id, filename)


@router.get("/s/{token}", response_class=HTMLResponse)
async def share_page(token: str, request: Request) -> str:
    """Server-rendered share page (OG tags need server HTML)."""
    link, row = await _resolve_share(token)
    base = _base_url(request)
    return _render_share_page(_public_payload(link, row, token, base))


@router.get("/.well-known/assetlinks.json")
async def assetlinks() -> JSONResponse:
    """Android verified-app-links file. Set ASSETLINKS_JSON (HF Space secret)
    to the JSON array with the release keystore's SHA-256; until then the
    https intent-filter falls back to the browser/app chooser gracefully."""
    raw = get_settings().assetlinks_json.strip()
    try:
        data = json.loads(raw) if raw else []
    except json.JSONDecodeError:
        data = []
    return JSONResponse(content=data)


# --------------------------------------------------------------------------- #
# Server-rendered share page
# --------------------------------------------------------------------------- #

def _block_html(block: dict) -> str:
    """One card block -> HTML. Unknown types are skipped; everything is
    escaped (blocks are LLM/user-authored)."""
    if not isinstance(block, dict):
        return ""
    t = block.get("type")
    e = html.escape

    def txt(v) -> str:
        return e(str(v or ""))

    if t == "heading":
        level = 3 if block.get("level", 2) >= 3 else 2
        return f"<h{level}>{txt(block.get('text'))}</h{level}>"
    if t == "paragraph":
        return f"<p>{txt(block.get('text'))}</p>"
    if t == "bullet_list":
        items = "".join(f"<li>{txt(i)}</li>" for i in block.get("items") or [])
        return f"<ul>{items}</ul>" if items else ""
    if t == "step_list":
        items = "".join(
            f"<li>{txt(s.get('text') if isinstance(s, dict) else s)}</li>"
            for s in block.get("steps") or []
        )
        return f"<ol>{items}</ol>" if items else ""
    if t == "key_value":
        rows = "".join(
            f"<div class='kv'><dt>{txt(p.get('key') if isinstance(p, dict) else '')}</dt>"
            f"<dd>{txt(p.get('value') if isinstance(p, dict) else '')}</dd></div>"
            for p in block.get("pairs") or []
        )
        return f"<dl class='kvlist'>{rows}</dl>" if rows else ""
    if t == "checklist":
        items = "".join(
            f"<li><span class='box'>&#9744;</span> {txt(i.get('text') if isinstance(i, dict) else i)}</li>"
            for i in block.get("items") or []
        )
        return f"<ul class='checklist'>{items}</ul>" if items else ""
    if t == "callout":
        return f"<div class='callout'>{txt(block.get('text'))}</div>"
    if t == "link":
        url = str(block.get("url") or "")
        if not url.startswith(("http://", "https://")):
            return ""
        label = txt(block.get("label") or url)
        return f"<p class='extlink'><a href='{e(url, quote=True)}'>{label}</a></p>"
    if t == "table":
        headers = "".join(f"<th>{txt(h)}</th>" for h in block.get("headers") or [])
        rows = "".join(
            "<tr>" + "".join(f"<td>{txt(c)}</td>" for c in r) + "</tr>"
            for r in block.get("rows") or []
        )
        return f"<table><thead><tr>{headers}</tr></thead><tbody>{rows}</tbody></table>" if rows else ""
    if t == "map":
        items = "".join(
            f"<li>{txt(p.get('name') if isinstance(p, dict) else p)}</li>"
            for p in block.get("places") or []
        )
        return f"<ul class='places'>{items}</ul>" if items else ""
    return ""


def _render_share_page(p: dict) -> str:
    """Full HTML share page. `p` is the public payload (already safe), but
    everything interpolated is escaped anyway."""
    e = html.escape
    title = e(str(p.get("one_liner") or "A card shared from Cachy"))
    tldr = e(str(p.get("tldr") or ""))
    desc = (str(p.get("tldr") or "")[:197] + "...") if len(str(p.get("tldr") or "")) > 200 else str(p.get("tldr") or "")
    desc = e(desc)
    url = e(str(p.get("url") or ""), quote=True)
    token = e(str(p.get("token") or ""), quote=True)
    thumb = p.get("thumbnail_url")
    thumb_tag = (
        f"<meta property='og:image' content='{e(thumb, quote=True)}'>"
        f"<meta name='twitter:image' content='{e(thumb, quote=True)}'>"
        if thumb else ""
    )
    thumb_img = (
        f"<img class='thumb' src='{e(thumb, quote=True)}' alt=''>" if thumb else ""
    )
    ctype = e(str(p.get("content_type") or "card").replace("_", " ").title())
    tags = "".join(
        f"<span class='tag'>{e(str(t))}</span>" for t in (p.get("tags") or [])
    )
    blocks = "".join(_block_html(b) for b in (p.get("blocks") or []))
    platform = e(str(p.get("platform") or ""))
    creator = e(str(p.get("creator") or ""))
    source_url = str(p.get("source_url") or "")
    src_line = " ".join(x for x in [platform, ("@" + creator) if creator else ""] if x)
    src_html = ""
    if src_line or source_url:
        link = (
            f" <a href='{e(source_url, quote=True)}'>original</a>"
            if source_url.startswith(("http://", "https://")) else ""
        )
        src_html = f"<p class='source'>From {e(src_line)}{link}</p>" if src_line else (
            f"<p class='source'><a href='{e(source_url, quote=True)}'>View original</a></p>"
            if link else ""
        )
    return f"""<!DOCTYPE html>
<html lang='en'>
<head>
<meta charset='utf-8'>
<meta name='viewport' content='width=device-width, initial-scale=1'>
<meta name='robots' content='noindex, nofollow'>
<title>{title} · Cachy</title>
<meta property='og:title' content='{title}'>
<meta property='og:description' content='{desc}'>
<meta property='og:url' content='{url}'>
<meta property='og:type' content='article'>
{thumb_tag}
<meta name='twitter:card' content='summary_large_image'>
<style>
  :root {{ --bg:#F5F0E8; --ink:#181818; --muted:#6b6259; --line:#e2d9c8; --card:#fffdf8; }}
  * {{ box-sizing:border-box; }}
  body {{ margin:0; background:var(--bg); color:var(--ink);
         font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;
         line-height:1.6; }}
  .wrap {{ max-width:640px; margin:0 auto; padding:24px 20px 64px; }}
  .brand {{ display:flex; align-items:center; gap:10px; margin-bottom:28px; }}
  .brand .mark {{ width:30px; height:30px; border-radius:9px; background:var(--ink);
                  color:var(--bg); display:flex; align-items:center; justify-content:center;
                  font-weight:800; font-size:17px; }}
  .brand span {{ font-weight:700; letter-spacing:.02em; }}
  .thumb {{ width:100%; border-radius:14px; margin:0 0 20px; display:block; }}
  .pills {{ display:flex; flex-wrap:wrap; gap:8px; margin-bottom:14px; }}
  .pill {{ font-size:12px; font-weight:700; text-transform:uppercase; letter-spacing:.08em;
           background:var(--ink); color:var(--bg); padding:4px 12px; border-radius:999px; }}
  .tag {{ font-size:12px; color:var(--muted); border:1px solid var(--line);
          padding:4px 12px; border-radius:999px; }}
  h1 {{ font-size:28px; line-height:1.25; margin:0 0 16px; letter-spacing:-.01em; }}
  .tldr {{ background:var(--card); border:1px solid var(--line); border-left:4px solid var(--ink);
           border-radius:12px; padding:16px 18px; margin:0 0 24px; font-size:17px; }}
  h2 {{ font-size:21px; margin:28px 0 10px; }} h3 {{ font-size:17px; margin:24px 0 8px; }}
  p {{ margin:0 0 14px; }} ul, ol {{ margin:0 0 14px; padding-left:22px; }}
  li {{ margin-bottom:6px; }}
  .kvlist {{ margin:0 0 14px; }} .kv {{ display:flex; gap:12px; padding:8px 0;
           border-bottom:1px solid var(--line); }}
  .kv dt {{ font-weight:700; min-width:110px; }} .kv dd {{ margin:0; }}
  .checklist {{ list-style:none; padding-left:0; }}
  .checklist .box {{ margin-right:8px; }}
  .callout {{ background:#f3ecdd; border-radius:10px; padding:12px 16px; margin:0 0 14px; }}
  .extlink a, .source a, p a {{ color:var(--ink); }}
  table {{ border-collapse:collapse; width:100%; margin:0 0 14px; font-size:14px; }}
  th, td {{ border:1px solid var(--line); padding:8px 10px; text-align:left; }}
  th {{ background:#efe8d8; }}
  .source {{ color:var(--muted); font-size:14px; margin-top:26px; }}
  .cta {{ position:sticky; bottom:0; padding:16px 0 8px;
          background:linear-gradient(transparent, var(--bg) 40%); }}
  .cta button {{ width:100%; padding:16px; font-size:17px; font-weight:700;
                  background:var(--ink); color:var(--bg); border:0; border-radius:16px;
                  cursor:pointer; }}
  #getapp {{ display:none; background:var(--card); border:1px solid var(--line);
             border-radius:14px; padding:18px; margin-top:14px; text-align:center; }}
  #getapp p {{ color:var(--muted); font-size:14px; }}
  #getapp .row {{ display:flex; gap:10px; margin-top:12px; }}
  #getapp .row button {{ flex:1; padding:12px; border-radius:12px; font-weight:700;
                         cursor:pointer; }}
  #getapp .primary {{ background:var(--ink); color:var(--bg); border:0; }}
  #getapp .ghost {{ background:transparent; border:1px solid var(--line); color:var(--ink); }}
  footer {{ margin-top:44px; text-align:center; color:var(--muted); font-size:13px; }}
</style>
</head>
<body>
<div class='wrap'>
  <div class='brand'><div class='mark'>C</div><span>Cachy</span></div>
  {thumb_img}
  <div class='pills'><span class='pill'>{ctype}</span>{tags}</div>
  <h1>{title}</h1>
  {f"<div class='tldr'>{tldr}</div>" if tldr else ""}
  {blocks}
  {src_html}
  <div class='cta'>
    <button onclick='saveToCachy()'>Save to my Cachy</button>
    <div id='getapp'>
      <p>You'll need the Cachy app to save this card.</p>
      <div class='row'>
        <button class='ghost' onclick='copyLink()'>Copy link</button>
      </div>
    </div>
  </div>
  <footer>Shared via Cachy · turn reels into knowledge</footer>
</div>
<script>
(function() {{
  var left = false;
  document.addEventListener('visibilitychange', function() {{ left = document.hidden; }});
  window.saveToCachy = function() {{
    window.location.href = 'cachy://s/{token}';
    setTimeout(function() {{
      if (!left) document.getElementById('getapp').style.display = 'block';
    }}, 1500);
  }};
  window.copyLink = function() {{
    var u = '{url}';
    if (navigator.clipboard) navigator.clipboard.writeText(u);
  }};
}})();
</script>
</body>
</html>"""
