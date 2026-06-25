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


# --------------------------------------------------------------------------- #
# Entry point
# --------------------------------------------------------------------------- #

def extract(
    download: DownloadResult, work_dir: str, source_line: str = ""
) -> ExtractionResult:
    """Run the extraction pipeline against a DownloadResult. `work_dir` is the
    per-card directory where audio/frames live."""
    os.makedirs(work_dir, exist_ok=True)
    transcript = ""
    frames: list[str] = []

    if download.media_type == "video":
        video_path = str(download.data)
        audio_path = _extract_audio(video_path, os.path.join(work_dir, "audio.wav"))
        transcript = _transcribe(audio_path)
        raw_frames = _extract_frames(video_path, os.path.join(work_dir, _FRAME_DIR))
        frames = _dedup_frames(raw_frames)
    else:
        # image carousel: the images themselves are the frames (docs/03)
        imgs = download.data if isinstance(download.data, list) else [download.data]
        frames = _dedup_frames([str(p) for p in imgs])

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
        had_visual=False,  # scene description omitted in v1
    )


async def extract_async(
    download: DownloadResult, work_dir: str, source_line: str = ""
) -> ExtractionResult:
    import asyncio

    return await asyncio.to_thread(extract, download, work_dir, source_line)
