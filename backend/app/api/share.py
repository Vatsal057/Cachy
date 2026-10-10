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
from sqlalchemy import select

from app.api.media import stream_card_media
from app.auth import OptionalOwnerDep, OwnerDep
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

async def _resolve_share(
    token: str,
) -> tuple[db.ShareLinkRow, db.CardRow, list[dict], list[dict]]:
    """The link + its card, artifacts, and concepts, or 404. A link whose card
    is gone or not READY reads as invalid (never leak why)."""
    async with db.session() as s:
        link = await db.get_share_link_by_token(s, token=token)
        if link is None:
            raise HTTPException(status_code=404, detail="link not found")
        row = await db.get_card_row(s, link.card_id)
        if row is None or row.state != CardState.READY.value:
            raise HTTPException(status_code=404, detail="link not found")

        # Load linked catalog references for this card
        artifacts = []
        try:
            art_stmt = select(db.ArtifactRow).order_by(db.ArtifactRow.created_at.desc())
            all_arts = (await s.execute(art_stmt)).scalars().all()
            for a in all_arts:
                sc_ids = a.source_card_ids if isinstance(a.source_card_ids, list) else []
                if link.card_id in sc_ids:
                    artifacts.append({
                        "id": a.id,
                        "type": a.type,
                        "title": a.title,
                        "creator": a.creator,
                        "year": a.year,
                        "thumbnail": a.thumbnail,
                        "description": a.description,
                    })
        except Exception as exc:
            log.warning("error loading artifacts for share: %s", exc)

        # Load linked concepts for this card
        concepts = []
        try:
            conc_stmt = select(db.ConceptRow).order_by(db.ConceptRow.created_at.desc())
            all_concs = (await s.execute(conc_stmt)).scalars().all()
            for c in all_concs:
                sc_ids = c.source_card_ids if isinstance(c.source_card_ids, list) else []
                if link.card_id in sc_ids:
                    concepts.append({
                        "id": c.id,
                        "name": c.name,
                        "description": getattr(c, "definition", None) or getattr(c, "description", None),
                        "source_count": len(sc_ids),
                    })
        except Exception as exc:
            log.warning("error loading concepts for share: %s", exc)
    return link, row, artifacts, concepts


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
    /media/ paths are rewritten to the token-gated share route.
    If the thumbnail points to local/missing media but the card is a YouTube
    video, fall back to YouTube's public thumbnail CDN so it always renders."""
    from app.pipeline.verdicts import video_id_from_url

    vid = video_id_from_url(row.source_url or "") if row.source_url else None
    yt_thumb = f"https://img.youtube.com/vi/{vid}/hqdefault.jpg" if vid else None

    ref = media_store.to_media_url(row.thumbnail)
    if not ref:
        return yt_thumb
    if ref.startswith("/media/"):
        parts = ref.split("/")
        if len(parts) == 4 and parts[3]:
            # If we have a direct YouTube thumb, prefer it to avoid missing local scratch files
            if yt_thumb:
                return yt_thumb
            return f"{base}/s/{token}/media/{parts[3]}"
        return yt_thumb
    if ref.startswith("http://") or ref.startswith("https://"):
        return ref
    return yt_thumb



def _estimate_read_minutes(row: db.CardRow) -> int:
    words = len((row.tldr or "").split())
    for b in (row.blocks or []):
        if isinstance(b, dict):
            words += len(str(b.get("text") or "").split())
            for it in (b.get("items") or []):
                words += len(str(it.get("text") if isinstance(it, dict) else it).split())
            for st in (b.get("steps") or []):
                words += len(str(st.get("text") if isinstance(st, dict) else st).split())
    return max(1, (words + 199) // 200)


def _public_payload(
    link: db.ShareLinkRow,
    row: db.CardRow,
    artifacts: list[dict],
    concepts: list[dict],
    token: str,
    base: str,
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
        "action_items": row.action_items or {},
        "insight": row.insight or {},
        "enrichment": row.enrichment or {},
        "verdicts": row.verdicts or {},
        "artifacts": artifacts,
        "concepts": concepts,
        "read_minutes": _estimate_read_minutes(row),
        "platform": row.platform,
        "creator": row.creator,
        "source_url": row.source_url,
        "thumbnail_url": _public_thumbnail(row, token, base),
        "shared_at": link.created_at.isoformat() if getattr(link, "created_at", None) else None,
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
async def share_json(
    token: str, request: Request, caller_id: OptionalOwnerDep = None
) -> dict:
    """Public JSON payload for a share link (used by the app's save sheet).

    If the caller is the card's owner, includes `is_owner: True` and `card_id`
    so the app can offer 'Open in Reader' instead of a clone prompt."""
    link, row, artifacts, concepts = await _resolve_share(token)
    payload = _public_payload(
        link, row, artifacts, concepts, token, _base_url(request)
    )
    if caller_id is not None and caller_id == link.owner_id:
        payload["is_owner"] = True
        payload["card_id"] = row.id
    else:
        payload["is_owner"] = False
    return payload


@router.post("/share/{token}/save")
async def save_shared_card(
    token: str, request: Request, owner_id: OwnerDep
) -> dict:
    """"Save to my Cachy": clone the shared card into the caller's library.

    No quota charge — the card is already structured. Idempotent per source
    URL: saving the same shared card twice returns the first copy.
    Saving own card returns the existing card_id without error."""
    _save_limiter.check(request)
    link, row, _, _ = await _resolve_share(token)
    if link.owner_id == owner_id:
        return {"card_id": row.id, "already_saved": True, "is_owner": True}
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

        coll_id = None
        if row.content_type:
            try:
                coll = await db.get_or_create_collection(
                    s, owner_id=owner_id, system_type=row.content_type
                )
                coll_id = coll.id
            except Exception as e:
                log.warning("could not assign system collection on save: %s", e)

        new_row = db.CardRow(
            id=new_id,
            state=CardState.READY.value,
            owner_id=owner_id,
            collection_id=coll_id,
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

        # Link catalog artifacts to the saver's card copy
        from sqlalchemy.orm.attributes import flag_modified
        art_stmt = select(db.ArtifactRow)
        all_arts = (await s.execute(art_stmt)).scalars().all()
        for art in all_arts:
            if row.id in (art.source_card_ids or []):
                if new_id not in (art.source_card_ids or []):
                    art.source_card_ids = [*(art.source_card_ids or []), new_id]
                    flag_modified(art, "source_card_ids")

        # Link concepts to the saver's card copy
        conc_stmt = select(db.ConceptRow)
        all_concs = (await s.execute(conc_stmt)).scalars().all()
        for conc in all_concs:
            if row.id in (conc.source_card_ids or []):
                if new_id not in (conc.source_card_ids or []):
                    conc.source_card_ids = [*(conc.source_card_ids or []), new_id]
                    flag_modified(conc, "source_card_ids")

        await s.commit()
    log.info("shared card saved: %s -> %s (owner %s)", row.id, new_id, owner_id)
    return {"card_id": new_id, "already_saved": False}


@router.get("/s/{token}/media/{filename}")
async def share_media(token: str, filename: str):
    """Token-gated media for a share link — only the card's own thumbnail /
    keyframes, never arbitrary dataset paths."""
    _, row, _, _ = await _resolve_share(token)
    if filename not in _media_filenames(row):
        raise HTTPException(status_code=404, detail="not found")
    return await stream_card_media(row.id, filename)


@router.get("/s/{token}", response_class=HTMLResponse)
async def share_page(token: str, request: Request) -> str:
    """Server-rendered share page (OG tags need server HTML)."""
    link, row, artifacts, concepts = await _resolve_share(token)
    base = _base_url(request)
    payload = _public_payload(link, row, artifacts, concepts, token, base)
    try:
        return _render_share_page(payload)
    except Exception as exc:
        log.error("Failed to render rich share page for %s: %s", token, exc, exc_info=True)
        title = html.escape(str(row.one_liner or "A card shared from Cachy"))
        tldr = html.escape(str(row.tldr or ""))
        return f"""<!DOCTYPE html><html><head><meta charset='utf-8'><title>{title} · Cachy</title></head><body style='font-family:sans-serif;padding:24px;background:#181818;color:#ede8df'><h1>{title}</h1><p>{tldr}</p></body></html>"""


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
# Server-rendered share page with full Cachy app design & styling
# --------------------------------------------------------------------------- #

def _is_self_carded(block: dict) -> bool:
    t = block.get("type") if isinstance(block, dict) else None
    return t in {"callout", "link", "table", "map", "key_value"}


def _render_step_list(block: dict) -> str:
    steps = block.get("steps") or []
    if not steps:
        return ""
    e = html.escape
    out: list[str] = []

    # Visual step strip for sequences of 3+ steps (matching app _StepStrip)
    if len(steps) >= 3:
        strip_items: list[str] = []
        for i in range(len(steps)):
            if i > 0:
                strip_items.append("<div class='step-connector'></div>")
            strip_items.append(f"<div class='step-node'>{i + 1}</div>")
        out.append(f"<div class='step-strip'>{''.join(strip_items)}</div>")

    rows: list[str] = []
    for i, s in enumerate(steps):
        stext = s.get("text") if isinstance(s, dict) else s
        rows.append(
            f"<div class='step-row'>"
            f"  <div class='step-badge'>{i + 1}</div>"
            f"  <div class='step-body'>{e(str(stext or ''))}</div>"
            f"</div>"
        )
    out.append(f"<div class='step-items'>{''.join(rows)}</div>")
    return "".join(out)


def _render_block_content(b: dict) -> str:
    if not isinstance(b, dict):
        return ""
    t = b.get("type")
    e = html.escape

    def txt(v) -> str:
        return e(str(v or ""))

    if t == "heading":
        try:
            _lvl = int(b.get("level") or 2)
        except (TypeError, ValueError):
            _lvl = 2
        lvl = 3 if _lvl >= 3 else 2
        return f"<h{lvl} class='block-heading'>{txt(b.get('text'))}</h{lvl}>"
    if t == "paragraph":
        return f"<p class='block-para'>{txt(b.get('text'))}</p>"
    if t == "bullet_list":
        items = "".join(
            f"<li class='bullet-item'><span class='bullet-dot'></span><span>{txt(i.get('text') if isinstance(i, dict) else i)}</span></li>"
            for i in (b.get("items") or [])
        )
        return f"<ul class='bullet-list'>{items}</ul>" if items else ""
    if t == "step_list":
        return _render_step_list(b)
    if t == "checklist":
        items = "".join(
            f"<div class='check-row'><span class='check-box'>&#9744;</span><span class='check-text'>{txt(i.get('text') if isinstance(i, dict) else i)}</span></div>"
            for i in (b.get("items") or [])
        )
        return f"<div class='checklist'>{items}</div>" if items else ""
    if t == "key_value":
        rows = "".join(
            f"<div class='kv-row'><dt class='kv-dt'>{txt(p.get('key') if isinstance(p, dict) else '')}</dt>"
            f"<dd class='kv-dd'>{txt(p.get('value') if isinstance(p, dict) else '')}</dd></div>"
            for p in (b.get("pairs") or [])
        )
        return f"<dl class='kv-list'>{rows}</dl>" if rows else ""
    if t == "callout":
        return (
            f"<div class='callout-card'>"
            f"  <div class='callout-bar'></div>"
            f"  <div class='callout-text'>{txt(b.get('text'))}</div>"
            f"</div>"
        )
    if t == "table":
        headers = "".join(f"<th>{txt(h)}</th>" for h in (b.get("headers") or []))
        rows = "".join(
            "<tr>" + "".join(f"<td>{txt(c)}</td>" for c in (r if isinstance(r, list) else [r])) + "</tr>"
            for r in (b.get("rows") or [])
        )
        return (
            f"<div class='table-wrap'><table>"
            f"<thead><tr>{headers}</tr></thead><tbody>{rows}</tbody>"
            f"</table></div>" if rows else ""
        )
    if t == "map":
        items = "".join(
            f"<div class='place-row'><span class='pin-icon'>📍</span><span>{txt(p.get('name') if isinstance(p, dict) else p)}</span></div>"
            for p in (b.get("places") or [])
        )
        return f"<div class='places-card'>{items}</div>" if items else ""
    if t == "link":
        url = str(b.get("url") or "")
        if not url.startswith(("http://", "https://")):
            return ""
        label = txt(b.get("label") or url)
        return f"<div class='extlink-card'><a href='{e(url, quote=True)}' target='_blank' rel='noopener'>{label} ↗</a></div>"
    return ""


def _render_segmented_blocks(raw_blocks: list) -> str:
    """Group blocks into section cards matching the Flutter BlockList design."""
    segments: list[list[dict]] = []
    section: list[dict] | None = None
    for b in raw_blocks:
        if not isinstance(b, dict):
            continue
        if _is_self_carded(b):
            if section is not None and len(section) == 1 and section[0].get("type") == "heading":
                section.append(b)
            else:
                segments.append([b])
            section = None
        elif b.get("type") == "heading":
            section = [b]
            segments.append(section)
        elif section is not None:
            section.append(b)
        else:
            section = [b]
            segments.append(section)

    html_parts: list[str] = []
    for seg in segments:
        if len(seg) == 1 and _is_self_carded(seg[0]):
            html_parts.append(_render_block_content(seg[0]))
        else:
            content = "".join(_render_block_content(item) for item in seg)
            if content.strip():
                html_parts.append(f"<div class='section-card'>{content}</div>")
    return "".join(html_parts)


def _render_action_items_html(ai: dict | None) -> str:
    if not ai or not isinstance(ai, dict):
        return ""
    items = ai.get("items") or []
    if not items:
        return ""
    e = html.escape
    count = len(items)
    item_rows = "".join(
        f"<div class='action-item'><span class='action-bullet'></span><span class='action-text'>{e(str(i.get('text') if isinstance(i, dict) else i))}</span></div>"
        for i in items
    )
    return f"""
    <div class='section-group'>
      <div class='section-eyebrow'>
        <span class='eyebrow-bar'></span>
        <span class='eyebrow-text'>ACTIONS</span>
        <span class='eyebrow-count'>{count}</span>
      </div>
      <div class='section-card actions-card'>
        <div class='action-items-list'>{item_rows}</div>
        <button class='track-actions-btn' onclick='saveToCachy()'>
          <svg width='18' height='18' viewBox='0 0 256 256' fill='currentColor'>
            <path d='M224,48H32A16,16,0,0,0,16,64V192a16,16,0,0,0,16,16H224a16,16,0,0,0,16-16V64A16,16,0,0,0,224,48Zm0,144H32V64H224V192ZM80,96a8,8,0,0,1,8-8h80a8,8,0,0,1,0,16H88A8,8,0,0,1,80,96Zm0,32a8,8,0,0,1,8-8h80a8,8,0,0,1,0,16H88A8,8,0,0,1,80,128Zm0,32a8,8,0,0,1,8-8h80a8,8,0,0,1,0,16H88A8,8,0,0,1,80,160Z'/>
          </svg>
          <span>Track in Actions</span>
        </button>
      </div>
    </div>
    """


def _render_insight_html(insight: dict | None, read_minutes: int) -> str:
    if not insight or not isinstance(insight, dict):
        return ""
    rh = insight.get("rabbit_hole") or {}
    if not isinstance(rh, dict):
        rh = {}
    questions = rh.get("questions") if isinstance(rh.get("questions"), list) else []
    topics = rh.get("adjacent_topics") if isinstance(rh.get("adjacent_topics"), list) else []
    concepts_list = rh.get("advanced_concepts") if isinstance(rh.get("advanced_concepts"), list) else []
    threads_count = min(5, len(questions) + len(topics) + len(concepts_list))

    quiz = insight.get("quiz")
    if isinstance(quiz, list):
        quiz_q = quiz
    elif isinstance(quiz, dict):
        quiz_q = quiz.get("questions") if isinstance(quiz.get("questions"), list) else []
    else:
        quiz_q = []
    quiz_count = len(quiz_q)
    deep_prompt = insight.get("deep_research_prompt")

    if not threads_count and not quiz_count and not deep_prompt:
        return ""

    e = html.escape
    stat_cells = [
        f"<div class='stat-cell'><span class='stat-val'>{read_minutes}m</span><span class='stat-lbl'>READ</span></div>"
    ]
    if threads_count > 0:
        stat_cells.append(
            f"<div class='stat-cell stat-highlight'><span class='stat-val'>{threads_count}</span><span class='stat-lbl'>THREADS</span></div>"
        )
    if quiz_count > 0:
        stat_cells.append(
            f"<div class='stat-cell'><span class='stat-val'>{quiz_count}</span><span class='stat-lbl'>QUIZ</span></div>"
        )

    # Detailed expandable sections
    expanded_blocks: list[str] = []
    if questions or topics or concepts_list:
        thread_items = "".join(f"<li>{e(str(q))}</li>" for q in questions[:5])
        expanded_blocks.append(
            f"<div class='dive-subcard'>"
            f"  <div class='dive-subhead'>Starter Threads & Inquiries</div>"
            f"  <ul class='dive-list'>{thread_items}</ul>"
            f"</div>"
        )
    if quiz_q:
        first_q = quiz_q[0]
        if isinstance(first_q, dict):
            q_text = e(str(first_q.get("question") or ""))
            opts = first_q.get("options") if isinstance(first_q.get("options"), list) else []
        else:
            q_text = e(str(first_q or ""))
            opts = []
        opt_html = "".join(
            f"<div class='quiz-opt'><span>{e(str(o))}</span></div>" for o in opts
        )
        expanded_blocks.append(
            f"<div class='dive-subcard'>"
            f"  <div class='dive-subhead'>Active Recall Quiz (Sample)</div>"
            f"  <p class='quiz-q'>{q_text}</p>"
            f"  <div class='quiz-opts'>{opt_html}</div>"
            f"</div>"
        )
    if deep_prompt:
        expanded_blocks.append(
            f"<div class='dive-subcard'>"
            f"  <div class='dive-subhead'>Deep Research Prompt</div>"
            f"  <p class='deep-prompt'>{e(str(deep_prompt))}</p>"
            f"</div>"
        )

    return f"""
    <div class='section-group'>
      <div class='section-eyebrow'>
        <span class='eyebrow-bar'></span>
        <span class='eyebrow-text'>GOING DEEPER</span>
      </div>
      <div class='stat-strip'>{''.join(stat_cells)}</div>
      <div class='dive-deeper-wrap'>
        <button class='dive-toggle' onclick='toggleDiveDeeper()' id='diveToggleBtn'>
          <svg class='compass-icon' width='18' height='18' viewBox='0 0 256 256' fill='currentColor'>
            <path d='M128,24A104,104,0,1,0,232,128,104.11,104.11,0,0,0,128,24Zm0,192a88,88,0,1,1,88-88A88.1,88.1,0,0,1,128,216Zm45.66-122.34-56,24a8,8,0,0,0-4.32,4.32l-24,56a8,8,0,0,0,10.34,10.34l56-24a8,8,0,0,0,4.32-4.32l24-56A8,8,0,0,0,173.66,93.66ZM128,136a8,8,0,1,1,8-8A8,8,0,0,1,128,136Z'/>
          </svg>
          <span class='dive-title'>Dive deeper</span>
          <svg class='caret-icon' id='diveCaret' width='16' height='16' viewBox='0 0 256 256' fill='currentColor'>
            <path d='M213.66,101.66l-80,80a8,8,0,0,1-11.32,0l-80-80A8,8,0,0,1,53.66,90.34L128,164.69l74.34-74.35a8,8,0,0,1,11.32,11.32Z'/>
          </svg>
        </button>
        <div class='dive-content' id='diveContent' style='display:none;'>
          {''.join(expanded_blocks)}
        </div>
      </div>
    </div>
    """


def _render_references_html(artifacts: list[dict]) -> str:
    if not artifacts:
        return ""
    e = html.escape
    tiles: list[str] = []
    for a in artifacts:
        title = e(str(a.get("title") or "Reference"))
        thumb = a.get("thumbnail")
        if thumb and thumb.startswith(("http://", "https://")):
            media_box = f"<img class='ref-img' src='{e(thumb, quote=True)}' alt='{title}' loading='lazy'>"
        else:
            media_box = (
                f"<div class='ref-placeholder'>"
                f"  <svg width='28' height='28' viewBox='0 0 256 256' fill='currentColor'>"
                f"    <path d='M216,40H40A16,16,0,0,0,24,56V200a16,16,0,0,0,16,16H216a16,16,0,0,0,16-16V56A16,16,0,0,0,216,40Zm0,160H40V56H216V200ZM184,96a8,8,0,0,1-8,8H80a8,8,0,0,1,0-16h96A8,8,0,0,1,184,96Zm0,32a8,8,0,0,1-8,8H80a8,8,0,0,1,0-16h96A8,8,0,0,1,184,128Zm0,32a8,8,0,0,1-8,8H80a8,8,0,0,1,0-16h96A8,8,0,0,1,184,160Z'/>"
                f"  </svg>"
                f"</div>"
            )
        tiles.append(
            f"<div class='ref-tile'>"
            f"  <div class='ref-aspect'>{media_box}</div>"
            f"  <div class='ref-title' title='{title}'>{title}</div>"
            f"</div>"
        )
    return f"""
    <div class='section-group'>
      <div class='section-eyebrow'>
        <span class='eyebrow-bar'></span>
        <span class='eyebrow-text'>REFERENCES</span>
      </div>
      <div class='ref-scroll-strip'>{''.join(tiles)}</div>
    </div>
    """


def _render_concepts_html(concepts: list[dict]) -> str:
    if not concepts:
        return ""
    e = html.escape
    pills: list[str] = []
    for c in concepts:
        name = e(str(c.get("name") or ""))
        cnt = c.get("source_count") or 1
        cnt_badge = f"<span class='concept-count'>{cnt}</span>" if cnt > 1 else ""
        pills.append(
            f"<div class='concept-pill'>"
            f"  <svg class='bulb-icon' width='13' height='13' viewBox='0 0 256 256' fill='currentColor'>"
            f"    <path d='M128,24A80,80,0,0,0,48,104a79.44,79.44,0,0,0,24.78,57.73l.22.21A39.81,39.81,0,0,1,85,189.79V200a16,16,0,0,0,16,16h54a16,16,0,0,0,16-16V189.79a39.81,39.81,0,0,1,12-27.85l.22-.21A79.44,79.44,0,0,0,208,104,80.09,80.09,0,0,0,128,24Zm16,176H112V192h32Zm13.23-38.48A55.77,55.77,0,0,0,141,180.51H115a55.77,55.77,0,0,0-16.23-18.99A64,64,0,1,1,192,104,63.63,63.63,0,0,1,157.23,161.52ZM104,224a8,8,0,0,1,8-8h32a8,8,0,0,1,0,16H112A8,8,0,0,1,104,224Z'/>"
            f"  </svg>"
            f"  <span class='concept-name'>{name}</span>"
            f"  {cnt_badge}"
            f"</div>"
        )
    return f"""
    <div class='section-group'>
      <div class='section-eyebrow'>
        <span class='eyebrow-bar'></span>
        <span class='eyebrow-text'>CONCEPTS</span>
      </div>
      <div class='concepts-wrap'>{''.join(pills)}</div>
    </div>
    """


def _render_verdicts_html(data: dict | None) -> str:
    """Render per-window factual claim verdicts with color-coded ticks and evidence chips."""
    if not isinstance(data, dict):
        return ""
    claims = data.get("claims") or data.get("verdicts") or []
    if not claims:
        return ""
    e = html.escape
    counts = data.get("counts")
    if not counts or not isinstance(counts, dict):
        counts = {}
        for c in claims:
            if isinstance(c, dict):
                v = str(c.get("verdict") or "grey").lower()
                counts[v] = counts.get(v, 0) + 1

    parts = []
    if counts.get("green", 0) > 0:
        parts.append(f"{counts['green']} confirmed")
    if counts.get("amber", 0) > 0:
        parts.append(f"{counts['amber']} one source")
    if counts.get("red", 0) > 0:
        parts.append(f"{counts['red']} contradicted")
    if counts.get("grey", 0) > 0:
        parts.append(f"{counts['grey']} unverified")

    summary_text = f"{len(claims)} factual claims"
    if parts:
        summary_text += " · " + ", ".join(parts)

    rows: list[str] = []
    total = len(claims)
    for idx, item in enumerate(claims):
        if not isinstance(item, dict):
            continue
        v = str(item.get("verdict") or "grey").lower()
        if v not in ("green", "amber", "red", "grey"):
            v = "grey"
        v_labels = {
            "green": "Confirmed",
            "amber": "One source",
            "red": "Contradicted",
            "grey": "Unverified",
        }
        v_label = v_labels.get(v, "Unverified")

        # Window timestamp label
        ts = item.get("timestamp_label")
        if not ts:
            w_start = int(item.get("window_start") or 0)
            w_end = int(item.get("window_end") or 0)
            def fmt(s: int) -> str:
                return f"{s // 60}:{s % 60:02d}"
            ts = f"{fmt(w_start)}-{fmt(w_end)}" if w_end > 0 else "0:00"
        ts = e(str(ts))

        claim_text = e(str(item.get("claim") or ""))
        note_text = item.get("note") or item.get("notes") or ""
        notes = e(str(note_text))

        ev_chips: list[str] = []
        for ev in (item.get("evidence") or []):
            if not isinstance(ev, dict):
                continue
            raw_src = ev.get("source") or ""
            link = str(ev.get("link") or "")
            if not raw_src or raw_src.startswith("{"):
                try:
                    from urllib.parse import urlparse
                    raw_src = urlparse(link).netloc.replace("www.", "")
                except Exception:
                    raw_src = "Source"
            src = e(str(raw_src or "Source"))
            safe_link = e(link, quote=True)
            dt = e(str(ev.get("date") or ""))
            dt_span = f" <span class='chip-date'>· {dt}</span>" if dt else ""
            if safe_link and safe_link.startswith(("http://", "https://")):
                ev_chips.append(
                    f"<a class='evidence-chip' href='{safe_link}' target='_blank' rel='noopener'>"
                    f"  <span>{src}</span>{dt_span}"
                    f"  <svg width='10' height='10' viewBox='0 0 256 256' fill='currentColor'>"
                    f"    <path d='M200,64V168a8,8,0,0,1-16,0V83.31L69.66,197.66a8,8,0,0,1-11.32-11.32L172.69,72H88a8,8,0,0,1,0-16H192A8,8,0,0,1,200,64Z'/>"
                    f"  </svg>"
                    f"</a>"
                )
            else:
                ev_chips.append(
                    f"<span class='evidence-chip'><span>{src}</span>{dt_span}</span>"
                )
        ev_html = f"<div class='evidence-wrap'>{''.join(ev_chips)}</div>" if ev_chips else ""
        notes_html = f"<div class='verdict-notes'>{notes}</div>" if notes else ""
        line_html = "<div class='verdict-line'></div>" if idx < total - 1 else ""

        # Agent Audit Trace
        trace = item.get("trace") or {}
        trace_html = ""
        query_val = item.get("query") or trace.get("search_query")
        if query_val or trace:
            raw_engines = trace.get("engines") or ["Google Search", "Google News"]
            eng_map = {"google": "Google Search", "google_news": "Google News"}
            engines_str = ", ".join(eng_map.get(e_name, e_name) for e_name in raw_engines)
            rule_str = trace.get("decision_rule") or ""
            scanned = trace.get("sources_scanned", len(item.get("evidence") or []))
            corrobs = trace.get("corroborations", 0)
            contras = trace.get("contradictions", 0)
            rule_row = f"<div class='trace-row'><span class='trace-k'>Rule</span><span class='trace-v'>{e(rule_str)}</span></div>" if rule_str else ""
            trace_html = (
                f"<details class='agent-trace'>"
                f"  <summary>Search & Decision Trace</summary>"
                f"  <div class='agent-trace-body'>"
                f"    <div class='trace-row'><span class='trace-k'>Query</span><span class='trace-v mono'>&ldquo;{e(str(query_val or ''))}&rdquo;</span></div>"
                f"    <div class='trace-row'><span class='trace-k'>Engines</span><span class='trace-v'>{e(engines_str)}</span></div>"
                f"    <div class='trace-row'><span class='trace-k'>Audit</span><span class='trace-v'>{scanned} sources · {corrobs} corroborating · {contras} contradicting</span></div>"
                f"    {rule_row}"
                f"  </div>"
                f"</details>"
            )

        rows.append(
            f"<div class='verdict-item'>"
            f"  <div class='verdict-rail'>"
            f"    <div class='verdict-dot {v}'></div>"
            f"    {line_html}"
            f"  </div>"
            f"  <div class='verdict-content'>"
            f"    <div class='verdict-badge {v}'>{ts} · {v_label}</div>"
            f"    <div class='verdict-claim'>{claim_text}</div>"
            f"    {notes_html}"
            f"    {ev_html}"
            f"    {trace_html}"
            f"  </div>"
            f"</div>"
        )

    return f"""
    <div class='section-group'>
      <div class='section-eyebrow'>
        <span class='eyebrow-bar'></span>
        <span class='eyebrow-text'>FACT CHECK TIMELINE</span>
        <span class='eyebrow-count'>{total}</span>
      </div>
      <div class='verdict-summary'>{e(summary_text)}</div>
      <div class='verdict-list'>
        {''.join(rows)}
      </div>
    </div>
    """


def _render_share_page(p: dict) -> str:
    """Full HTML share page rendered with Cachy editorial aesthetics."""
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
    thumb_html = (
        f"<div class='hero-media'>"
        f"  <img class='hero-img' src='{e(thumb, quote=True)}' alt='{title}' onerror=\"this.closest('.hero-media').style.display='none'\">"
        f"  <div class='hero-fade'></div>"
        f"</div>"
        if thumb else ""
    )
    ctype = e(str(p.get("content_type") or "card").replace("_", " ").upper())
    tags = "".join(
        f"<span class='tag-pill'>{e(str(t).upper())}</span>" for t in (p.get("tags") or [])
    )
    read_mins = p.get("read_minutes", 1)

    try:
        blocks_html = _render_segmented_blocks(p.get("blocks") or [])
    except Exception as exc:
        log.warning("error rendering blocks for share: %s", exc)
        blocks_html = ""

    try:
        verdicts_html = _render_verdicts_html(p.get("verdicts"))
    except Exception as exc:
        log.warning("error rendering verdicts for share: %s", exc)
        verdicts_html = ""

    try:
        actions_html = _render_action_items_html(p.get("action_items"))
    except Exception as exc:
        log.warning("error rendering action items for share: %s", exc)
        actions_html = ""

    try:
        insight_html = _render_insight_html(p.get("insight"), read_mins)
    except Exception as exc:
        log.warning("error rendering insight for share: %s", exc)
        insight_html = ""

    try:
        references_html = _render_references_html(p.get("artifacts") or [])
    except Exception as exc:
        log.warning("error rendering references for share: %s", exc)
        references_html = ""

    try:
        concepts_html = _render_concepts_html(p.get("concepts") or [])
    except Exception as exc:
        log.warning("error rendering concepts for share: %s", exc)
        concepts_html = ""

    platform = e(str(p.get("platform") or ""))
    creator = e(str(p.get("creator") or ""))
    source_url = str(p.get("source_url") or "")
    src_line = " ".join(x for x in [platform, ("@" + creator) if creator else ""] if x)
    src_html = ""
    if src_line or source_url:
        link = (
            f" · <a href='{e(source_url, quote=True)}' target='_blank' rel='noopener'>original reel</a>"
            if source_url.startswith(("http://", "https://")) else ""
        )
        src_html = f"<div class='source-line'>From {e(src_line)}{link}</div>" if src_line else (
            f"<div class='source-line'><a href='{e(source_url, quote=True)}' target='_blank' rel='noopener'>View original reel</a></div>"
            if link else ""
        )

    return f"""<!DOCTYPE html>
<html lang='en' data-theme='dark'>
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
<link rel='preconnect' href='https://fonts.googleapis.com'>
<link rel='preconnect' href='https://fonts.gstatic.com' crossorigin>
<link href='https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght@9..144,500;600;700&family=IBM+Plex+Mono:wght@500;600;700&family=Inter:wght@400;500;600;700&display=swap' rel='stylesheet'>
<style>
  :root {{
    --bg: #181818;
    --raised: #222120;
    --ink: #EDE8DF;
    --muted: #9A928A;
    --line: rgba(237, 232, 223, 0.08);
    --accent: #96A885;
    --accent-tint: rgba(150, 168, 133, 0.15);
    --accent-border: rgba(150, 168, 133, 0.35);
    --card-bg: #222120;
    --card-border: rgba(237, 232, 223, 0.08);
    --btn-primary-bg: #96A885;
    --btn-primary-ink: #181818;
    --hero-fade: linear-gradient(to bottom, transparent 65%, #181818);
  }}
  html[data-theme='light'] {{
    --bg: #F5F0E8;
    --raised: #EBE3D5;
    --ink: #1C1917;
    --muted: #6B6259;
    --line: #E2D9C8;
    --accent: #7D8472;
    --accent-tint: rgba(125, 132, 114, 0.12);
    --accent-border: rgba(125, 132, 114, 0.35);
    --card-bg: #FFFDF8;
    --card-border: #E2D9C8;
    --btn-primary-bg: #1C1917;
    --btn-primary-ink: #F5F0E8;
    --hero-fade: linear-gradient(to bottom, transparent 65%, #F5F0E8);
  }}
  * {{ box-sizing: border-box; -webkit-tap-highlight-color: transparent; }}
  body {{
    margin: 0;
    background: var(--bg);
    color: var(--ink);
    font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    font-size: 15px;
    line-height: 1.55;
    transition: background 0.2s ease, color 0.2s ease;
  }}
  .wrap {{
    max-width: 620px;
    margin: 0 auto;
    padding: 18px 18px 120px;
  }}
  /* Header */
  .header {{
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 20px;
  }}
  .brand {{
    display: flex;
    align-items: center;
    gap: 10px;
    text-decoration: none;
    color: var(--ink);
  }}
  .brand .mark {{
    width: 30px;
    height: 30px;
    border-radius: 9px;
    background: var(--accent);
    color: var(--bg);
    display: flex;
    align-items: center;
    justify-content: center;
    font-weight: 800;
    font-size: 16px;
    font-family: 'Fraunces', serif;
  }}
  .brand span {{
    font-weight: 700;
    font-size: 16px;
    letter-spacing: .02em;
  }}
  .theme-toggle {{
    background: transparent;
    border: 1px solid var(--line);
    color: var(--muted);
    border-radius: 999px;
    padding: 6px 12px;
    cursor: pointer;
    display: flex;
    align-items: center;
    gap: 6px;
    font-family: 'IBM Plex Mono', monospace;
    font-size: 11px;
    font-weight: 600;
  }}
  /* Hero Media */
  .hero-media {{
    position: relative;
    width: 100%;
    border-radius: 16px;
    overflow: hidden;
    margin-bottom: 20px;
    background: var(--card-bg);
  }}
  .hero-img {{
    width: 100%;
    display: block;
    max-height: 480px;
    object-fit: cover;
  }}
  .hero-fade {{
    position: absolute;
    inset: 0;
    background: var(--hero-fade);
    pointer-events: none;
  }}
  /* Category Pills */
  .category-bar {{
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    margin-bottom: 16px;
  }}
  .type-pill {{
    display: inline-flex;
    align-items: center;
    gap: 5px;
    font-family: 'IBM Plex Mono', monospace;
    font-size: 10px;
    font-weight: 700;
    letter-spacing: .08em;
    background: var(--accent-tint);
    color: var(--accent);
    border: 1px solid var(--accent-border);
    padding: 4px 11px;
    border-radius: 999px;
  }}
  .tag-pill {{
    font-family: 'IBM Plex Mono', monospace;
    font-size: 10px;
    font-weight: 600;
    letter-spacing: .06em;
    color: var(--muted);
    background: var(--raised);
    border: 1px solid var(--line);
    padding: 4px 10px;
    border-radius: 999px;
  }}
  /* Title & Meta */
  h1.headline {{
    font-family: 'Fraunces', Georgia, serif;
    font-size: 27px;
    font-weight: 600;
    line-height: 1.25;
    letter-spacing: -0.4px;
    margin: 0 0 14px;
    color: var(--ink);
  }}
  .meta-strip {{
    display: flex;
    align-items: center;
    gap: 8px;
    margin-bottom: 24px;
  }}
  .read-badge {{
    display: inline-flex;
    align-items: center;
    gap: 5px;
    background: var(--raised);
    border-radius: 6px;
    padding: 4px 9px;
    font-family: 'IBM Plex Mono', monospace;
    font-size: 11px;
    color: var(--muted);
    font-weight: 600;
  }}
  /* Section Eyebrow */
  .section-eyebrow {{
    display: flex;
    align-items: center;
    gap: 8px;
    margin: 28px 0 10px;
  }}
  .eyebrow-bar {{
    width: 3px;
    height: 13px;
    background: var(--accent);
    border-radius: 2px;
  }}
  .eyebrow-text {{
    font-family: 'IBM Plex Mono', monospace;
    font-size: 10px;
    font-weight: 800;
    letter-spacing: 1.4px;
    color: var(--accent);
  }}
  .eyebrow-count {{
    background: var(--accent-tint);
    color: var(--accent);
    font-family: 'IBM Plex Mono', monospace;
    font-size: 10px;
    font-weight: 700;
    padding: 2px 7px;
    border-radius: 999px;
  }}
  /* Section Cards */
  .section-card {{
    background: var(--card-bg);
    border: 1px solid var(--card-border);
    border-radius: 16px;
    padding: 18px 20px;
    margin-bottom: 14px;
  }}
  .tldr-card {{
    font-size: 16px;
    line-height: 1.65;
    color: var(--ink);
  }}
  /* Typography inside cards */
  .block-heading {{
    font-family: 'Fraunces', Georgia, serif;
    font-size: 19px;
    font-weight: 600;
    letter-spacing: -0.2px;
    margin: 0 0 10px;
    color: var(--ink);
  }}
  .block-para {{
    margin: 0 0 10px;
    line-height: 1.6;
    color: var(--ink);
  }}
  .block-para:last-child {{ margin-bottom: 0; }}
  /* Lists */
  .bullet-list {{
    list-style: none;
    padding: 0;
    margin: 0 0 10px;
  }}
  .bullet-item {{
    display: flex;
    align-items: flex-start;
    gap: 10px;
    margin-bottom: 8px;
    line-height: 1.5;
  }}
  .bullet-dot {{
    width: 5px;
    height: 5px;
    border-radius: 50%;
    background: var(--accent);
    margin-top: 8px;
    flex-shrink: 0;
  }}
  /* Step Lists */
  .step-strip {{
    display: flex;
    align-items: center;
    gap: 8px;
    margin-bottom: 16px;
    overflow-x: auto;
    padding-bottom: 4px;
  }}
  .step-node {{
    width: 26px;
    height: 26px;
    border-radius: 50%;
    background: var(--accent-tint);
    border: 1px solid var(--accent);
    color: var(--accent);
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 11px;
    font-weight: 700;
    font-family: 'IBM Plex Mono', monospace;
    flex-shrink: 0;
  }}
  .step-connector {{
    flex: 1;
    min-width: 16px;
    height: 1px;
    background: var(--line);
  }}
  .step-row {{
    display: flex;
    align-items: flex-start;
    gap: 12px;
    padding: 10px 0;
    border-bottom: 1px solid var(--line);
  }}
  .step-row:last-child {{ border-bottom: 0; padding-bottom: 0; }}
  .step-badge {{
    width: 22px;
    height: 22px;
    border-radius: 50%;
    background: var(--raised);
    color: var(--muted);
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 11px;
    font-family: 'IBM Plex Mono', monospace;
    font-weight: 700;
    flex-shrink: 0;
    margin-top: 2px;
  }}
  .step-body {{ flex: 1; line-height: 1.55; }}
  /* Checklists */
  .checklist {{ margin: 0 0 10px; }}
  .check-row {{
    display: flex;
    align-items: flex-start;
    gap: 10px;
    margin-bottom: 8px;
  }}
  .check-box {{
    color: var(--muted);
    font-size: 18px;
    line-height: 1;
  }}
  .check-text {{ flex: 1; line-height: 1.5; }}
  /* Callout & Other Blocks */
  .callout-card {{
    display: flex;
    gap: 12px;
    background: var(--accent-tint);
    border-radius: 12px;
    padding: 14px 16px;
    margin-bottom: 14px;
    border: 1px solid var(--accent-border);
  }}
  .callout-bar {{
    width: 3px;
    border-radius: 2px;
    background: var(--accent);
    flex-shrink: 0;
  }}
  .callout-text {{ line-height: 1.55; }}
  .kv-list {{ margin: 0; }}
  .kv-row {{
    display: flex;
    gap: 12px;
    padding: 8px 0;
    border-bottom: 1px solid var(--line);
  }}
  .kv-dt {{ font-weight: 700; min-width: 110px; color: var(--muted); }}
  .kv-dd {{ margin: 0; flex: 1; }}
  .table-wrap {{ overflow-x: auto; margin-bottom: 14px; }}
  table {{ width: 100%; border-collapse: collapse; font-size: 14px; }}
  th, td {{ padding: 8px 12px; border: 1px solid var(--line); text-align: left; }}
  th {{ background: var(--raised); font-weight: 600; }}
  .places-card, .extlink-card {{
    background: var(--card-bg);
    border: 1px solid var(--card-border);
    border-radius: 14px;
    padding: 14px 16px;
    margin-bottom: 14px;
  }}
  .extlink-card a {{ color: var(--accent); text-decoration: none; font-weight: 600; }}
  /* Actions Card */
  .actions-card {{
    padding: 18px;
  }}
  .action-items-list {{
    margin-bottom: 16px;
  }}
  .action-item {{
    display: flex;
    align-items: flex-start;
    gap: 10px;
    margin-bottom: 10px;
  }}
  .action-item:last-child {{ margin-bottom: 0; }}
  .action-bullet {{
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: var(--accent);
    margin-top: 7px;
    flex-shrink: 0;
  }}
  .action-text {{
    line-height: 1.5;
    flex: 1;
  }}
  .track-actions-btn {{
    width: 100%;
    padding: 13px 18px;
    background: var(--accent);
    color: var(--btn-primary-ink);
    border: 0;
    border-radius: 12px;
    font-weight: 700;
    font-size: 15px;
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    transition: opacity 0.15s ease;
  }}
  .track-actions-btn:hover {{ opacity: 0.9; }}
  /* Going Deeper & Stat Strip */
  .stat-strip {{
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(80px, 1fr));
    gap: 10px;
    margin-bottom: 12px;
  }}
  .stat-cell {{
    background: var(--card-bg);
    border: 1px solid var(--card-border);
    border-radius: 12px;
    padding: 12px 10px;
    text-align: center;
  }}
  .stat-val {{
    display: block;
    font-family: 'Fraunces', serif;
    font-size: 20px;
    font-weight: 700;
    color: var(--ink);
  }}
  .stat-lbl {{
    display: block;
    font-family: 'IBM Plex Mono', monospace;
    font-size: 10px;
    font-weight: 700;
    letter-spacing: .08em;
    color: var(--muted);
    margin-top: 2px;
  }}
  .stat-highlight .stat-val {{ color: var(--accent); }}
  .dive-toggle {{
    width: 100%;
    padding: 14px 16px;
    background: var(--card-bg);
    border: 1px solid var(--card-border);
    border-radius: 12px;
    color: var(--ink);
    cursor: pointer;
    display: flex;
    align-items: center;
    gap: 10px;
    font-weight: 700;
    font-size: 15px;
    text-align: left;
  }}
  .compass-icon {{ color: var(--accent); }}
  .dive-title {{ flex: 1; }}
  .caret-icon {{ color: var(--muted); transition: transform 0.2s ease; }}
  .dive-content {{
    margin-top: 10px;
  }}
  .dive-subcard {{
    background: var(--card-bg);
    border: 1px solid var(--card-border);
    border-radius: 12px;
    padding: 14px 16px;
    margin-bottom: 10px;
  }}
  .dive-subhead {{
    font-family: 'IBM Plex Mono', monospace;
    font-size: 11px;
    font-weight: 700;
    color: var(--accent);
    text-transform: uppercase;
    letter-spacing: .06em;
    margin-bottom: 8px;
  }}
  .dive-list {{ margin: 0; padding-left: 20px; line-height: 1.6; }}
  .quiz-q {{ font-weight: 600; margin: 0 0 10px; }}
  .quiz-opts {{ display: flex; flex-direction: column; gap: 6px; }}
  .quiz-opt {{
    background: var(--raised);
    padding: 8px 12px;
    border-radius: 8px;
    font-size: 14px;
    border: 1px solid var(--line);
  }}
  .deep-prompt {{ margin: 0; font-size: 14px; line-height: 1.5; color: var(--muted); }}
  /* References Strip */
  .ref-scroll-strip {{
    display: flex;
    gap: 12px;
    overflow-x: auto;
    padding-bottom: 6px;
    scroll-snap-type: x mandatory;
  }}
  .ref-tile {{
    flex: 0 0 96px;
    scroll-snap-align: start;
    cursor: pointer;
  }}
  .ref-aspect {{
    width: 96px;
    height: 134px;
    border-radius: 10px;
    overflow: hidden;
    background: var(--raised);
    border: 1px solid var(--card-border);
    position: relative;
  }}
  .ref-img {{
    width: 100%;
    height: 100%;
    object-fit: cover;
    display: block;
  }}
  .ref-placeholder {{
    width: 100%;
    height: 100%;
    display: flex;
    align-items: center;
    justify-content: center;
    color: var(--muted);
  }}
  .ref-title {{
    margin-top: 6px;
    font-size: 12px;
    font-weight: 600;
    line-height: 1.25;
    color: var(--ink);
    display: -webkit-box;
    -webkit-line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }}
  /* Concepts Wrap */
  .concepts-wrap {{
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
  }}
  .concept-pill {{
    display: inline-flex;
    align-items: center;
    gap: 6px;
    background: var(--raised);
    border: 1px solid var(--card-border);
    border-radius: 999px;
    padding: 6px 12px;
    font-size: 13px;
    color: var(--ink);
  }}
  .bulb-icon {{ color: var(--accent); }}
  .concept-count {{
    background: var(--accent);
    color: var(--bg);
    font-size: 10px;
    font-weight: 700;
    border-radius: 999px;
    padding: 1px 6px;
    font-family: 'IBM Plex Mono', monospace;
  }}
  /* Verdict Timeline */
  .verdict-summary {{
    font-size: 13px;
    color: var(--muted);
    margin: 2px 0 16px;
  }}
  .verdict-list {{
    display: flex;
    flex-direction: column;
  }}
  .verdict-item {{
    display: flex;
    gap: 12px;
  }}
  .verdict-rail {{
    display: flex;
    flex-direction: column;
    align-items: center;
    width: 14px;
    flex-shrink: 0;
  }}
  .verdict-dot {{
    width: 12px;
    height: 12px;
    border-radius: 50%;
    margin-top: 5px;
    flex-shrink: 0;
  }}
  .verdict-dot.green {{ background: #2E9E5B; box-shadow: 0 0 8px rgba(46, 158, 91, 0.4); }}
  .verdict-dot.amber {{ background: #D9930D; box-shadow: 0 0 8px rgba(217, 147, 13, 0.4); }}
  .verdict-dot.red {{ background: #E5484D; box-shadow: 0 0 8px rgba(229, 72, 77, 0.4); }}
  .verdict-dot.grey {{ background: var(--muted); }}
  .verdict-line {{
    width: 2px;
    flex: 1;
    background: var(--line);
    margin: 4px 0;
  }}
  .verdict-content {{
    flex: 1;
    padding-bottom: 20px;
  }}
  .verdict-item:last-child .verdict-content {{
    padding-bottom: 4px;
  }}
  .verdict-badge {{
    display: inline-flex;
    align-items: center;
    gap: 6px;
    font-family: 'IBM Plex Mono', monospace;
    font-size: 11px;
    font-weight: 700;
    padding: 3px 9px;
    border-radius: 999px;
    margin-bottom: 8px;
  }}
  .verdict-badge.green {{
    background: rgba(46, 158, 91, 0.15);
    color: #2E9E5B;
    border: 1px solid rgba(46, 158, 91, 0.35);
  }}
  .verdict-badge.amber {{
    background: rgba(217, 147, 13, 0.15);
    color: #D9930D;
    border: 1px solid rgba(217, 147, 13, 0.35);
  }}
  .verdict-badge.red {{
    background: rgba(229, 72, 77, 0.15);
    color: #E5484D;
    border: 1px solid rgba(229, 72, 77, 0.35);
  }}
  .verdict-badge.grey {{
    background: var(--raised);
    color: var(--muted);
    border: 1px solid var(--line);
  }}
  .verdict-claim {{
    font-size: 15px;
    font-weight: 600;
    line-height: 1.45;
    color: var(--ink);
    margin-bottom: 6px;
  }}
  .verdict-notes {{
    font-size: 13px;
    line-height: 1.5;
    color: var(--muted);
    margin-bottom: 8px;
  }}
  .evidence-wrap {{
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
  }}
  .evidence-chip {{
    display: inline-flex;
    align-items: center;
    gap: 5px;
    background: var(--raised);
    border: 1px solid var(--card-border);
    border-radius: 6px;
    padding: 4px 9px;
    font-size: 12px;
    color: var(--ink);
    text-decoration: none;
    transition: border-color 0.15s ease, background 0.15s ease;
  }}
  .evidence-chip:hover {{
    border-color: var(--accent);
    background: var(--accent-tint);
  }}
  .evidence-chip .chip-date {{
    color: var(--muted);
    font-size: 11px;
  }}
  .evidence-chip svg {{
    color: var(--muted);
  }}
  /* Agent Search & Decision Trace */
  .agent-trace {{
    margin-top: 10px;
    background: var(--raised);
    border: 1px solid var(--card-border);
    border-radius: 8px;
    font-size: 12px;
    overflow: hidden;
  }}
  .agent-trace summary {{
    padding: 6px 10px;
    font-weight: 600;
    color: var(--muted);
    cursor: pointer;
    user-select: none;
    font-family: 'IBM Plex Mono', monospace;
    font-size: 11px;
    transition: color 0.15s ease;
  }}
  .agent-trace summary:hover {{
    color: var(--ink);
  }}
  .agent-trace-body {{
    padding: 8px 10px 10px;
    border-top: 1px solid var(--line);
    display: flex;
    flex-direction: column;
    gap: 5px;
    font-size: 12px;
  }}
  .trace-row {{
    display: flex;
    gap: 8px;
    align-items: baseline;
    line-height: 1.4;
  }}
  .trace-k {{
    font-family: 'IBM Plex Mono', monospace;
    font-size: 10px;
    font-weight: 700;
    color: var(--muted);
    text-transform: uppercase;
    min-width: 55px;
    flex-shrink: 0;
  }}
  .trace-v {{
    color: var(--ink);
  }}
  .trace-v.mono {{
    font-family: 'IBM Plex Mono', monospace;
    font-size: 11px;
    color: var(--accent);
  }}
  /* Source Line & Footer */
  .source-line {{
    margin-top: 24px;
    color: var(--muted);
    font-size: 13px;
    text-align: center;
  }}
  .source-line a {{ color: var(--accent); text-decoration: none; }}
  footer {{
    margin-top: 36px;
    text-align: center;
    color: var(--muted);
    font-size: 12px;
    font-family: 'IBM Plex Mono', monospace;
  }}
  /* Sticky Bottom Bar */
  .cta-bar {{
    position: fixed;
    bottom: 0;
    left: 0;
    right: 0;
    padding: 14px 20px 20px;
    background: linear-gradient(to top, var(--bg) 75%, transparent);
    z-index: 50;
    display: flex;
    justify-content: center;
  }}
  .cta-inner {{
    width: 100%;
    max-width: 600px;
  }}
  .cta-btn {{
    width: 100%;
    padding: 16px;
    font-size: 16px;
    font-weight: 700;
    background: var(--btn-primary-bg);
    color: var(--btn-primary-ink);
    border: 0;
    border-radius: 14px;
    cursor: pointer;
    box-shadow: 0 4px 20px rgba(0,0,0,0.25);
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 10px;
  }}
  #getapp {{
    display: none;
    background: var(--card-bg);
    border: 1px solid var(--card-border);
    border-radius: 14px;
    padding: 16px;
    margin-top: 12px;
    text-align: center;
    box-shadow: 0 8px 30px rgba(0,0,0,0.3);
  }}
  #getapp p {{ margin: 0 0 10px; font-size: 14px; color: var(--muted); }}
  #getapp .row {{ display: flex; gap: 8px; justify-content: center; }}
  #getapp button {{
    padding: 10px 16px;
    border-radius: 10px;
    font-weight: 600;
    font-size: 13px;
    cursor: pointer;
  }}
  #getapp .primary {{ background: var(--accent); color: var(--btn-primary-ink); border: 0; }}
  #getapp .ghost {{ background: transparent; border: 1px solid var(--line); color: var(--ink); }}
</style>
</head>
<body>
<div class='wrap'>
  <header class='header'>
    <div class='brand'>
      <div class='mark'>C</div>
      <span>Cachy</span>
    </div>
    <button class='theme-toggle' onclick='toggleTheme()'>
      <span id='themeLabel'>LIGHT</span> ◐
    </button>
  </header>

  {thumb_html}

  <div class='category-bar'>
    <span class='type-pill'>{ctype}</span>
    {tags}
  </div>

  <h1 class='headline'>{title}</h1>

  <div class='meta-strip'>
    <div class='read-badge'>
      <svg width='12' height='12' viewBox='0 0 256 256' fill='currentColor'>
        <path d='M128,24A104,104,0,1,0,232,128,104.11,104.11,0,0,0,128,24Zm0,192a88,88,0,1,1,88-88A88.1,88.1,0,0,1,128,216Zm64-88a8,8,0,0,1-8,8H128a8,8,0,0,1-8-8V72a8,8,0,0,1,16,0v48h48A8,8,0,0,1,192,128Z'/>
      </svg>
      <span>{read_mins} min read</span>
    </div>
  </div>

  {f"<div class='section-group'><div class='section-eyebrow'><span class='eyebrow-bar'></span><span class='eyebrow-text'>CORE TAKEAWAY</span></div><div class='section-card tldr-card'>{tldr}</div></div>" if tldr else ""}

  {blocks_html}

  {verdicts_html}

  {actions_html}

  {insight_html}

  {references_html}

  {concepts_html}

  {src_html}

  <footer>Shared via Cachy · turn reels into knowledge</footer>
</div>

<div class='cta-bar'>
  <div class='cta-inner'>
    <button class='cta-btn' onclick='saveToCachy()'>
      <svg width='18' height='18' viewBox='0 0 256 256' fill='currentColor'>
        <path d='M192,24H64A16,16,0,0,0,48,40V224a8,8,0,0,0,12.65,6.51L128,183.3l67.35,47.21A8,8,0,0,0,208,224V40A16,16,0,0,0,192,24Zm0,182.45-59.35-41.59a8,8,0,0,0-9.3,0L64,206.45V40H192Z'/>
      </svg>
      <span>Save to my Cachy</span>
    </button>
    <div id='getapp'>
      <p>Save to your Cachy account and access this card offline anytime.</p>
      <div class='row'>
        <button class='ghost' onclick='copyLink()'>Copy link</button>
      </div>
    </div>
  </div>
</div>

<script>
(function() {{
  var theme = localStorage.getItem('cachy_theme') || 'dark';
  function applyTheme(t) {{
    document.documentElement.setAttribute('data-theme', t);
    var lbl = document.getElementById('themeLabel');
    if (lbl) lbl.textContent = t === 'dark' ? 'LIGHT' : 'DARK';
  }}
  applyTheme(theme);

  window.toggleTheme = function() {{
    var cur = document.documentElement.getAttribute('data-theme') || 'dark';
    var next = cur === 'dark' ? 'light' : 'dark';
    localStorage.setItem('cachy_theme', next);
    applyTheme(next);
  }};

  window.toggleDiveDeeper = function() {{
    var content = document.getElementById('diveContent');
    var caret = document.getElementById('diveCaret');
    if (!content) return;
    if (content.style.display === 'none') {{
      content.style.display = 'block';
      if (caret) caret.style.transform = 'rotate(180deg)';
    }} else {{
      content.style.display = 'none';
      if (caret) caret.style.transform = 'rotate(0deg)';
    }}
  }};

  var left = false;
  document.addEventListener('visibilitychange', function() {{ left = document.hidden; }});
  window.saveToCachy = function() {{
    window.location.href = 'cachy://s/{token}';
    setTimeout(function() {{
      if (!left) {{
        var modal = document.getElementById('getapp');
        if (modal) modal.style.display = 'block';
      }}
    }}, 1500);
  }};

  window.copyLink = function() {{
    var u = '{url}';
    if (navigator.clipboard) {{
      navigator.clipboard.writeText(u);
      alert('Link copied to clipboard!');
    }}
  }};
}})();
</script>
</body>
</html>"""

