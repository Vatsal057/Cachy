# 03 — Extraction

Turns downloaded media into the raw signal the structuring step consumes. Goal:
an all-free stack that **keeps the structuring LLM doing as little as possible**, so
the free tier survives bursts. Heavy lifting (transcription, OCR) runs off the LLM —
on free hosted Whisper and on local compute — and the LLM receives pre-digested text.

## Pipeline

```
media (video.mp4 or images)
  → ffmpeg:        extract audio + sample candidate frames (scene-change based)
  → frame dedup:   drop near-identical frames → keep distinct frames
  → Groq Whisper:  audio → transcript                         (off the LLM)
  → Tesseract OCR: distinct frames → on-screen text (local)   (off the LLM)
  → [conditional]  scene description: ONLY if transcript+OCR thin → HF Inference VLM
  → aggregate:     labeled text bundle
  → Structuring LLM: text-only call → validated blocks        (see 04)
```

Per card, the structuring LLM does **one text-only call** — always. Every vision
task (OCR via local Tesseract, scene description via a hosted open VLM) runs off the
LLM, so the structuring model (text-only by design) only ever sees lightweight text.

### 1. ffmpeg (free, local)
- Extract the audio track for transcription.
- Sample candidate frames on scene changes (not a fixed 1/sec — adjacent frames
  in a reel are near-identical).
- Pick the card thumbnail from the frames.
- For image carousels, the images themselves are the frames.

### 2. Frame dedup (free, local)
Drop near-identical frames before OCR so Tesseract runs on a handful of *distinct*
frames, not 30 copies of the same overlay. Cheap perceptual-hash comparison.

### 3. Transcription — Groq Whisper (free tier, off the LLM)
Audio → transcript via Groq's hosted Whisper (free, fast, off-device — keeps the
HF Space light). `faster-whisper` (local) is the fallback if you move to a GPU
Space. Empty/music-only audio is valid; the card leans on OCR + caption instead.

### 4. OCR — Tesseract (local, free, off the LLM)
On-screen text overlays often carry the real information. Run Tesseract locally on
the distinct frames. No API, no quota — unlimited local compute.

> **Quality trade-off (test early):** Tesseract reads stylized social-media text
> (fancy fonts, text over busy backgrounds, emoji) noticeably worse than a hosted
> vision model. For a project demo the quota safety usually wins, but test on a real
> reel — if Tesseract mangles the overlay text, route that frame to the conditional
> HF Inference VLM (step 5) for a vision OCR pass. Measure, then decide.

### 5. Scene description — conditional, HF Inference VLM (rare)
Scene description is a vision task and can't run on the free HF Space CPU (a local
captioning model is too slow/RAM-heavy there). Instead, route it to a **hosted
open VLM via HF Inference** — keeping it off both the Space CPU *and* the structuring
LLM:

- **Model:** `HuggingFaceM4/idefics2-8b` (strong open VLM for captioning/VQA), or
  its lighter successor **SmolVLM** / Idefics3. Prefer whichever is currently live
  and best-supported on HF Inference.
- **Trigger:** only when transcript AND OCR both come back empty/thin (a purely
  visual reel). Most cards skip this entirely.
- **Free-tier fit:** free serverless inference allows a few hundred requests/hour
  for sub-~10B models (idefics2-8b qualifies), with 10–30s cold starts on less
  popular models. Because this step is *rare*, neither the rate limit nor the cold
  start meaningfully bites.

> **Verify before depending on it:** the old "Serverless Inference API" is now
> *Inference Providers*, and Idefics2 runs on TGI (maintenance mode as of 2026).
> Confirm the chosen model actually responds on HF Inference today before wiring
> it in; have a fallback (SmolVLM, or skip scene description) if it's gone cold.

For maximum simplicity in v1, scene description may be omitted altogether.

### 6. Aggregate (free, local)
Combine the signals into one labeled text bundle for the LLM. **Loose aggregation
is enough for v1** — no timestamp-level syncing needed:

```
CAPTION: <caption>
TRANSCRIPT: <whisper output>
ON-SCREEN TEXT: <deduped OCR text>
[SCENE: <only if scene description ran>]
SOURCE: platform / creator / duration
```

Timestamp-aligning OCR-vs-transcript-vs-scene is a real technique but a phase-2
refinement with marginal payoff for structured cards. Don't build it now.

### 7. Structuring — text-only LLM call (see 04)
The aggregated text bundle goes to a single **text-only** LLM call that returns the
validated block list. Default backend is **HuggingFace Inference Providers**
(`Qwen/Qwen2.5-72B-Instruct`); **Groq** (`llama-3.1-70b-versatile`) is a selectable
fallback. Both are free-tier, both text-only — no images in this call.

## The free stack, summarized

| Stage | Tool | Free path | On the LLM? |
|-------|------|-----------|-------------|
| Audio + frame extract | ffmpeg | free, local | no |
| Frame dedup | perceptual hash | free, local | no |
| Transcription | Groq Whisper | hosted free tier | no |
| OCR | Tesseract | free, local | no |
| Scene description | HF Inference VLM (Idefics2 / SmolVLM) | hosted free tier, **conditional/rare** | no |
| Structuring | HF Inference (Qwen2.5-72B) / Groq (llama-3.1-70b) | free tier | yes — **text-only, always** |

## Quota reality

The biggest levers against the free-tier ceiling are **call count** (one text-only
call per card) and **duplicate caching** (re-shared reels never re-call the model).
This pipeline adds a third: the structuring call carries **no images**, which keeps
each call light on tokens and leaves any vision work to the rare conditional VLM pass.

At project scale (tens–low hundreds of reels/day) the free tier likely survives
regardless; this design is the defensive version, strongest against burst-sharing.

Verify current HF Inference / Groq free-tier limits before budgeting around them —
numbers shift. The structuring backend is selectable via `LLM_BACKEND` (see 05).

## Inputs handed to structuring

- `aggregated_text` (caption + transcript + OCR [+ scene], labeled)
- `keyframes` (used only by the conditional HF Inference VLM pass, never the LLM)
- `source` metadata (platform, creator, url, duration, resolver)

Must produce a usable card even if transcript *and* OCR *and* caption are all thin,
falling back to the conditional scene pass or a minimal base card.
