# 03 — Extraction

Turns downloaded media into the raw signal the structuring step consumes. Goal:
an all-free stack that **keeps Gemini doing as little as possible**, so the free
tier survives bursts. Heavy lifting (transcription, OCR) runs off Gemini — on
free hosted Whisper and on local compute — and Gemini receives pre-digested text.

## Pipeline

```
media (video.mp4 or images)
  → ffmpeg:        extract audio + sample candidate frames (scene-change based)
  → frame dedup:   drop near-identical frames → keep distinct frames
  → Groq Whisper:  audio → transcript                         (off Gemini)
  → Tesseract OCR: distinct frames → on-screen text (local)   (off Gemini)
  → [conditional]  scene description: ONLY if transcript+OCR thin → HF Inference VLM
  → aggregate:     labeled text bundle
  → Gemini (Flash): text-only structuring call → validated blocks   (see 04)
```

Per card, Gemini does **one text-only call** — always. Every vision task (OCR via
local Tesseract, scene description via a hosted open VLM) runs off Gemini, so the
Gemini free tier only ever sees lightweight text structuring.

### 1. ffmpeg (free, local)
- Extract the audio track for transcription.
- Sample candidate frames on scene changes (not a fixed 1/sec — adjacent frames
  in a reel are near-identical).
- Pick the card thumbnail from the frames.
- For image carousels, the images themselves are the frames.

### 2. Frame dedup (free, local)
Drop near-identical frames before OCR so Tesseract runs on a handful of *distinct*
frames, not 30 copies of the same overlay. Cheap perceptual-hash comparison.

### 3. Transcription — Groq Whisper (free tier, off Gemini)
Audio → transcript via Groq's hosted Whisper (free, fast, off-device — keeps the
HF Space light). `faster-whisper` (local) is the fallback if you move to a GPU
Space. Empty/music-only audio is valid; the card leans on OCR + caption instead.

### 4. OCR — Tesseract (local, free, off Gemini)
On-screen text overlays often carry the real information. Run Tesseract locally on
the distinct frames. No API, no quota — unlimited local compute.

> **Quality trade-off (test early):** Tesseract reads stylized social-media text
> (fancy fonts, text over busy backgrounds, emoji) noticeably worse than Gemini's
> vision. For a project demo the quota safety usually wins, but test on a real reel
> — if Tesseract mangles the overlay text, consider a Gemini vision OCR call for
> that case. Measure, then decide.

### 5. Scene description — conditional, HF Inference VLM (rare)
Scene description is a vision task and can't run on the free HF Space CPU (a local
captioning model is too slow/RAM-heavy there). Instead, route it to a **hosted
open VLM via HF Inference** — keeping it off both the Space CPU *and* Gemini:

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

### 7. Structuring — Gemini Flash, text-only (see 04)
The aggregated text bundle goes to a single **text-only** Gemini call that returns
the validated block list. Use a **Flash-tier** model (higher free limits than Pro;
plenty for text structuring). No images in this call in the normal case.

## The free stack, summarized

| Stage | Tool | Free path | On Gemini? |
|-------|------|-----------|------------|
| Audio + frame extract | ffmpeg | free, local | no |
| Frame dedup | perceptual hash | free, local | no |
| Transcription | Groq Whisper | hosted free tier | no |
| OCR | Tesseract | free, local | no |
| Scene description | HF Inference VLM (Idefics2 / SmolVLM) | hosted free tier, **conditional/rare** | no |
| Structuring | Gemini Flash | free tier | yes — **text-only, always** |

## Quota reality

The biggest levers against the free-tier ceiling are **call count** (one text-only
call per card) and **duplicate caching** (re-shared reels never re-call the model).
This pipeline adds a third: most Gemini calls carry **no images**, which keeps each
call light on tokens and protects the heavier vision quota for the rare case that
needs it.

At project scale (tens–low hundreds of reels/day) the free tier likely survives
regardless; this design is the defensive version, strongest against burst-sharing.

Verify current Gemini/Groq free-tier limits before budgeting around them — numbers
shift. Use Gemini Flash for the higher free ceiling.

## Inputs handed to structuring

- `aggregated_text` (caption + transcript + OCR [+ scene], labeled)
- `keyframes` (only attached to the Gemini call in the conditional vision case)
- `source` metadata (platform, creator, url, duration, resolver)

Must produce a usable card even if transcript *and* OCR *and* caption are all thin,
falling back to the conditional scene pass or a minimal base card.
