"""Extraction (docs/03): turn downloaded media into the labeled text bundle the
structuring step consumes. All-free stack, keeps Gemini doing as little as possible.

  media (video.mp4 | images)
    -> ffmpeg:       audio + scene-change frames + thumbnail
    -> frame dedup:  perceptual hash -> distinct frames
    -> Groq Whisper: audio -> transcript            (off Gemini, skipped if no key)
    -> Tesseract:    distinct frames -> on-screen text (local, skipped if absent)
    -> aggregate:    one labeled text bundle

Every step is wrapped so a single failure degrades the bundle, never aborts the
job. Scene description (VLM) is omitted in v1 (docs/03 permits)."""

from __future__ import annotations

import logging
import os
import shutil
import subprocess
from dataclasses import dataclass, field

from app.config import get_settings
from app.pipeline.ingestion.downloader import DownloadResult

log = logging.getLogger("pipeline.extraction")

_FRAME_DIR = "frames"
_MAX_FRAMES = 12          # cap distinct frames sent to OCR
_DEDUP_HASH_DISTANCE = 6  # perceptual-hash hamming distance below which frames are "same"


@dataclass
class ExtractionResult:
    aggregated_text: str
    transcript: str = ""
    ocr_text: str = ""
    thumbnail: str | None = None
    keyframes: list[str] = field(default_factory=list)
    had_transcript: bool = False
    had_ocr: bool = False
    had_visual: bool = False


# --------------------------------------------------------------------------- #
# ffmpeg helpers
# --------------------------------------------------------------------------- #

def _have(cmd: str) -> bool:
    return shutil.which(cmd) is not None


def _extract_audio(video_path: str, out_wav: str) -> str | None:
    if not _have("ffmpeg"):
        log.warning("ffmpeg not found; skipping audio extraction")
        return None
    try:
        subprocess.run(
            ["ffmpeg", "-y", "-i", video_path, "-ac", "1", "-ar", "16000",
             "-vn", out_wav],
            check=True, capture_output=True, timeout=120,
        )
        return out_wav if os.path.exists(out_wav) else None
    except (subprocess.SubprocessError, OSError) as e:
        log.warning("audio extract failed: %s", e)
        return None


def _extract_frames(video_path: str, frame_dir: str) -> list[str]:
    """Sample candidate frames on scene changes (not a fixed 1/sec)."""
    if not _have("ffmpeg"):
        return []
    os.makedirs(frame_dir, exist_ok=True)
    out_pattern = os.path.join(frame_dir, "frame_%03d.jpg")
    try:
        # scene-change selection; fall back to ~1 frame/2s via fps if no scenes hit.
        subprocess.run(
            ["ffmpeg", "-y", "-i", video_path,
             "-vf", "select='gt(scene,0.3)',showinfo", "-vsync", "vfr",
             "-frames:v", "30", out_pattern],
            check=True, capture_output=True, timeout=120,
        )
    except (subprocess.SubprocessError, OSError) as e:
        log.warning("scene-frame extract failed (%s); trying fps fallback", e)
    frames = _list_frames(frame_dir)
    if not frames:
        try:
            subprocess.run(
                ["ffmpeg", "-y", "-i", video_path, "-vf", "fps=1/2",
                 "-frames:v", "20", out_pattern],
                check=True, capture_output=True, timeout=120,
            )
        except (subprocess.SubprocessError, OSError) as e:
            log.warning("fps-frame extract failed: %s", e)
        frames = _list_frames(frame_dir)
    return frames


def _list_frames(frame_dir: str) -> list[str]:
    if not os.path.isdir(frame_dir):
        return []
    return sorted(
        os.path.join(frame_dir, f)
        for f in os.listdir(frame_dir)
        if f.lower().endswith((".jpg", ".jpeg", ".png", ".webp"))
    )


# --------------------------------------------------------------------------- #
# Frame dedup (perceptual hash)
# --------------------------------------------------------------------------- #

def _dedup_frames(frames: list[str]) -> list[str]:
    """Drop near-identical frames before OCR. Cheap perceptual-hash comparison."""
    try:
        import imagehash
        from PIL import Image
    except Exception:
        return frames[:_MAX_FRAMES]

    distinct: list[str] = []
    hashes: list = []
    for path in frames:
        try:
            with Image.open(path) as im:
                h = imagehash.phash(im)
        except Exception:
            continue
        if all((h - prev) > _DEDUP_HASH_DISTANCE for prev in hashes):
            hashes.append(h)
            distinct.append(path)
        if len(distinct) >= _MAX_FRAMES:
            break
    return distinct or frames[:_MAX_FRAMES]


# --------------------------------------------------------------------------- #
# Transcription (Groq Whisper, off Gemini)
# --------------------------------------------------------------------------- #

def _transcribe(audio_path: str | None) -> str:
    settings = get_settings()
    if not audio_path or not settings.groq_enabled:
        return ""
    try:
        from groq import Groq

        client = Groq(api_key=settings.groq_api_key)
        with open(audio_path, "rb") as f:
            resp = client.audio.transcriptions.create(
                file=(os.path.basename(audio_path), f.read()),
                model=settings.groq_whisper_model,
            )
        return (getattr(resp, "text", "") or "").strip()
    except Exception as e:
        log.warning("groq whisper failed: %s", e)
        return ""


# --------------------------------------------------------------------------- #
# OCR (Tesseract, local)
# --------------------------------------------------------------------------- #

def _ocr(frames: list[str]) -> str:
    if not frames:
        return ""
    try:
        import pytesseract
        from PIL import Image
    except Exception:
        return ""
    if not _have("tesseract"):
        log.warning("tesseract binary not found; skipping OCR")
        return ""

    chunks: list[str] = []
    seen: set[str] = set()
    for path in frames:
        try:
            with Image.open(path) as im:
                text = pytesseract.image_to_string(im).strip()
        except Exception:
            continue
        # de-dup repeated overlay text across frames
        norm = " ".join(text.split())
        if norm and norm.lower() not in seen:
            seen.add(norm.lower())
            chunks.append(norm)
    return "\n".join(chunks)


# --------------------------------------------------------------------------- #
# Vision reader (Groq VLM, free tier) — for stylized carousel slides
# --------------------------------------------------------------------------- #

_VISION_PROMPT = (
    "This is one slide from a social-media carousel post. Transcribe ALL text "
    "shown on it verbatim, preserving reading order, and briefly note any key "
    "visual that carries meaning (chart, diagram, product, place). Output plain "
    "text only — no preamble, no markdown, no commentary."
)


def _vision_read(frames: list[str]) -> str:
    """Read stylized carousel/infographic slides with Groq's free vision model.

    Tesseract mangles social-media text (docs/03 step 5: stylized overlays read
    far worse than a VLM). Carousel slides are text-as-image, so a vision model
    recovers the slide's real content + structure that OCR loses. Each image is an
    isolated call — one failure skips that slide, never the whole pass."""
    settings = get_settings()
    if not frames or not settings.groq_vision_enabled:
        return ""
    try:
        import base64

        from groq import Groq
    except Exception:
        return ""

    client = Groq(api_key=settings.groq_api_key)
    chunks: list[str] = []
    for idx, path in enumerate(frames, 1):
        try:
            with open(path, "rb") as f:
                b64 = base64.b64encode(f.read()).decode()
            ext = os.path.splitext(path)[1].lstrip(".").lower() or "jpeg"
            if ext == "jpg":
                ext = "jpeg"
            resp = client.chat.completions.create(
                model=settings.groq_vision_model,
                messages=[{
                    "role": "user",
                    "content": [
                        {"type": "text", "text": _VISION_PROMPT},
                        {"type": "image_url",
                         "image_url": {"url": f"data:image/{ext};base64,{b64}"}},
                    ],
                }],
                temperature=0.0,
                max_tokens=512,
            )
            text = (resp.choices[0].message.content or "").strip() if resp.choices else ""
        except Exception as e:
            log.warning("groq vision failed on slide %d: %s", idx, e)
            continue
        if text and text.lower() not in {"none", "no text", "no text shown"}:
            chunks.append(f"[slide {idx}] {text}")
    return "\n".join(chunks)


# --------------------------------------------------------------------------- #
# Aggregate
# --------------------------------------------------------------------------- #

def _aggregate(caption: str, transcript: str, ocr_text: str, source_line: str) -> str:
    parts = [
        f"CAPTION: {caption.strip()}" if caption.strip() else "CAPTION:",
        f"TRANSCRIPT: {transcript.strip()}" if transcript.strip() else "TRANSCRIPT:",
        f"ON-SCREEN TEXT: {ocr_text.strip()}" if ocr_text.strip() else "ON-SCREEN TEXT:",
        f"SOURCE: {source_line}",
    ]
    return "\n".join(parts)


def _aggregate_article(
    title: str, text: str, author: str | None, source_line: str
) -> str:
    """Text-source bundle (docs/02 article path): no audio/frames, the body is the
    content. Same labeled shape the structuring prompt already consumes."""
    parts = [
        f"TITLE: {title.strip()}" if title.strip() else "TITLE:",
        f"AUTHOR: {author.strip()}" if author and author.strip() else "AUTHOR:",
        f"ARTICLE TEXT: {text.strip()}" if text.strip() else "ARTICLE TEXT:",
        f"SOURCE: {source_line}",
    ]
    return "\n".join(parts)


def _extract_article(download: DownloadResult, source_line: str) -> ExtractionResult:
    """Article path: skip ffmpeg/Whisper/OCR entirely. The lead image (if any) is
    a remote URL used directly as the thumbnail — nothing is downloaded."""
    aggregated = _aggregate_article(
        download.title, download.text, download.author, source_line
    )
    return ExtractionResult(
        aggregated_text=aggregated,
        transcript=download.text,  # gives base-synth / paragraph-fallback real text
        ocr_text="",
        thumbnail=download.image_url,
        keyframes=[],
        had_transcript=False,
        had_ocr=False,
        had_visual=False,
    )


# --------------------------------------------------------------------------- #
# Entry point
# --------------------------------------------------------------------------- #

def extract(
    download: DownloadResult, work_dir: str, source_line: str = ""
) -> ExtractionResult:
    """Run the extraction pipeline against a DownloadResult. `work_dir` is the
    per-card directory where audio/frames live."""
    if download.media_type == "article":
        return _extract_article(download, source_line)

    os.makedirs(work_dir, exist_ok=True)
    settings = get_settings()
    is_carousel = download.media_type != "video"
    transcript = ""
    frames: list[str] = []

    if download.media_type == "video":
        video_path = str(download.data)
        audio_path = _extract_audio(video_path, os.path.join(work_dir, "audio.wav"))
        transcript = _transcribe(audio_path)
        raw_frames = _extract_frames(video_path, os.path.join(work_dir, _FRAME_DIR))
        frames = _dedup_frames(raw_frames)
    else:
        # Image carousel: every slide is curated, distinct content. Do NOT
        # perceptual-dedup — that's for redundant video frames and would collapse
        # infographic slides that share a template, dropping real content (docs/03).
        imgs = download.data if isinstance(download.data, list) else [download.data]
        frames = [str(p) for p in imgs][:_MAX_FRAMES]

    # Carousel slides are stylized text-as-image; Tesseract reads them poorly
    # (docs/03 step 5), so prefer the free Groq VLM, falling back to OCR.
    had_visual = False
    if is_carousel and settings.groq_vision_enabled:
        ocr_text = _vision_read(frames)
        if ocr_text.strip():
            had_visual = True
        else:
            ocr_text = _ocr(frames)
    else:
        ocr_text = _ocr(frames)

    thumbnail = frames[0] if frames else None

    aggregated = _aggregate(download.caption or "", transcript, ocr_text, source_line)

    return ExtractionResult(
        aggregated_text=aggregated,
        transcript=transcript,
        ocr_text=ocr_text,
        thumbnail=thumbnail,
        keyframes=frames,
        had_transcript=bool(transcript.strip()),
        had_ocr=bool(ocr_text.strip()),
        had_visual=had_visual,
    )


async def extract_async(
    download: DownloadResult, work_dir: str, source_line: str = ""
) -> ExtractionResult:
    import asyncio

    return await asyncio.to_thread(extract, download, work_dir, source_line)
