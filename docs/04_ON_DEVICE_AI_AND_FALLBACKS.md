# On-Device AI & Fallback Chains — Cachy

**Version:** 2.0  
**Stack:** Google Gemma 3 1B (`flutter_gemma`), Faster-Whisper, Gemini / Cerebras / Groq  

---

## 1. The "Never Fail a Job" Philosophy

Cachy operates on the principle that lack of cloud API credits or network throttling should never cause a user's capture job to fail. If third-party AI keys are exhausted, rate-limited, or unavailable, the system cascades gracefully down multiple backup layers.

```
                   [Incoming Content]
                           │
                           ▼
                 [Transcribe Audio]
                 ├─► Groq Whisper API (whisper-large-v3-turbo)
                 └─► Fallback: Local faster-whisper (Tiny / Base / Small)
                           │
                           ▼
                  [Structure Card]
                 ├─► Primary: Google Gemini 2.5 Flash
                 ├─► Fallback 1: Cerebras Llama 3.3 70B (60k TPM tier)
                 ├─► Fallback 2: Groq Llama 3.3 70B
                 └─► Fallback 3: Extractive Plain-Paragraph Parser
                           │
                 [Quota Exceeded in Cloud?]
                           │
                  Yes ─────┴─────► [degraded = True]
                                         │
                                         ▼
                            [Persist Raw Extract Bundle]
                                         │
                                         ▼
                            [Flutter Client Downloads Bundle]
                                         │
                                         ▼
                            [Local Gemma 3 1B Structures Card]
```

---

## 2. On-Device AI: Google Gemma 3 1B

On mobile devices (Android), Cachy integrates Google's **Gemma 3 1B IT (int4)** model via `flutter_gemma` (backed by Google MediaPipe LLM Inference C++ runtime).

### 2.1 Scope: What On-Device AI Does vs. Does NOT Do

| Task | Where It Runs | Technology | Handled by On-Device Gemma? |
| :--- | :--- | :--- | :--- |
| **Reel Ingestion & Download** | Cloud Backend | `yt-dlp` / Instagram Private API | ❌ **No.** Reels require network, cookies, and video download. |
| **Audio Transcription** | Cloud Backend | Groq Whisper / Faster-Whisper | ❌ **No.** Gemma is a text-only SLM; cannot process audio. |
| **Visual OCR / Keyframes** | Cloud Backend | Tesseract / MediaPipe Vision | ❌ **No.** Gemma 3 1B IT int4 is text-only. |
| **Raw Bundle Assembly** | Cloud Backend | Python Worker Pipeline | ❌ **No.** Server packages transcript + captions into raw bundle. |
| **Card Structuring & Synthesis** | **User's Android Phone** | **Gemma 3 1B IT (MediaPipe)** | ✅ **YES.** Turns raw bundle text into checklists, headings, and one-liners. |

> **Note on Instagram DM Bot (`@cachyapp`):** Reels sent via Instagram DM are processed entirely in the cloud backend (Hugging Face Spaces) using Google Gemini. The Instagram DM bot does **not** invoke the on-device model.

### 2.2 Model Artifact & Storage
- **Model File:** `gemma3-1b-it-int4.task` (~554 MB, int4 quantized).
- **Distribution:** Hosted on GitHub Releases (`https://github.com/Vatsal057/Cachy/releases/download/model-v1/gemma3-1b-it-int4.task`).
- **Storage:** Downloaded on-demand via Settings into the app's sandboxed storage (`FlutterGemma.installModel()`). It is never bundled directly into the base APK.

### 2.3 Hardware & OS Requirements
- **OS Support:** Android only (`Platform.isAndroid`). iOS, Web, and desktop platforms report `LocalAiPhase.unsupported`.
- **Architecture:** 64-bit ARM (`arm64-v8a`), Android 8.0+ (API 26+).
- **RAM Requirement:** Requires ~1.2 GB to 1.5 GB available RAM during inference. Devices with ≥ 6 GB RAM run at ~15–25 tokens/sec. On low-end 3 GB RAM devices, Android Low Memory Killer (LMK) may terminate the app under background load.

### 2.4 Prompt & Target JSON Schema
To guarantee deterministic JSON from a 1B model, the target schema is simplified to 3 primitive blocks (`paragraph`, `checklist`, `heading`) instead of the full 9-block cloud schema:

```json
{
  "base": {
    "one_liner": "Single concise sentence",
    "tldr": "2-3 sentence overview",
    "content_type": "recipe|tutorial|tip|product_list|travel|news_explainer|other",
    "tags": ["tag1", "tag2"]
  },
  "blocks": [
    {"type": "paragraph", "text": "..."},
    {"type": "checklist", "items": [{"text": "...", "checked": false}]},
    {"type": "heading", "text": "..."}
  ]
}
```

#### Writing Style Discipline (Crisp Technical English)
Both on-device Gemma 3 1B and cloud models (Gemini Flash / Cerebras Llama) enforce **Crisp Technical English** (Caveman brevity + 80% ASD-STE100 structural discipline in natural English):
- **No Meta-Commentary:** Speak directly about the subject. Never write "The video shows", "The creator discusses", or "It is argued that".
- **Sentence Length Cap:** Maximum 15–20 words per sentence. One distinct thought per sentence.
- **Bullets for Long / Multi-part Details:** If a thought or explanation requires multiple steps, attributes, or reasons, break it into checklist items or concise bullets rather than writing run-on compound sentences.
- **Active Voice & Imperatives:** Use active voice for explanations and direct imperative verbs for actionable steps ("Boil pasta", "Batch emails").
- **Zero Fluff:** Purge throat-clearing, hedging, and filler phrases ("basically", "in order to", "serves to"). Keep proper articles (`a`, `the`) and grammatical English.

### 2.5 Defensive JSON Guardrails
In `app/lib/data/services/local_ai/local_ai_service.dart`:
1. **Fencing & Clamping:** `parseModelCardJson()` strips markdown code fences (` ```json `) and clamps to the outermost `{` and `}`, discarding conversational prefixes or suffixes.
2. **Silent Grace:** If JSON decoding fails, the error is caught, and the clean extractive paragraph card remains intact without crashing.
3. **Server Validation:** Uploading the generated JSON to `POST /cards/{id}/structure` passes through backend `_validate()`. Malformed payloads receive HTTP 422 and are rejected, preserving the paragraph card.

### 2.6 Step-by-Step Workflow for Degraded Cards
1. **Cloud Quota Exhaustion / Prefer Local:** When an unauthenticated or quota-limited user saves a reel, or when `prefer_local = true` is set, the server extracts keyframes and audio transcript as usual, but skips cloud LLM structuring.
2. **Card State:** The card is saved with `degraded = True` and its raw extraction bundle is stored in `CardRow.raw_bundle`.
3. **Client Detection:** The Flutter app detects `_quotaDegraded && ai.canStructure` in `ShareViewModel`.
4. **Bundle Retrieval:** The client fetches the stored bundle from `GET /cards/{id}/bundle`.
5. **On-Device Inference:** `GemmaLocalAiService.structureBundle()` runs the local Gemma 3 1B model at temperature `0.3` (capped at 4,000 characters).
6. **Upload & Promotion:** The structured payload is sent via `POST /cards/{id}/structure`, promoting the card to fully structured status without burning cloud tokens.

---

## 3. Audio Transcription Fallback: Local Faster-Whisper

When running locally or when `GROQ_API_KEY` is not provided:
- Cachy initializes `faster-whisper` (`local_whisper_model = "base"`).
- Models are cached locally in the container or device filesystem.
- Zero external network requests are made; audio transcription executes in-process on CPU.

---

## 4. Multi-Account Spare Pool

To absorb burst traffic on the primary Google Gemini key without requiring paid tier commitments:
- `app/config.py` defines a multi-account spare key pool (`GEMINI_KVA`, `GEMINI_VPN`, `GEMINI_VVA`, `GEMINI_VV`, `GEMINI_D08`, `GEMINI_DVU`).
- When the primary structuring key throws an HTTP 429 (Resource Exhausted), the pipeline rotates seamlessly to the next available spare key in the chain before degrading to Cerebras or Groq.
