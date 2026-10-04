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

On mobile devices (Android), Cachy integrates Google's Gemma 3 1B model using `flutter_gemma`.

### 2.1 Workflow for Degraded Cards
1. **Cloud Quota Exhaustion:** When an unauthenticated user or free account exceeds the daily quota (`quota_cards_per_day = 10`), the server extracts keyframes and audio transcript as usual, but skips cloud LLM structuring.
2. **Card State:** The card is saved with `degraded = True` and its raw extraction bundle is stored in the database.
3. **Client Notification:** The mobile app detects `card.degraded == true` on synchronization.
4. **On-Device Inference:** The Flutter app prompts or automatically passes the raw extraction text into the locally hosted Gemma 3 1B model, generating typed blocks directly on the phone.
5. **Sync Back:** The structured blocks are uploaded back to the server via `PUT /cards/{id}/structure`, promoting the card to fully structured status without burning cloud tokens.

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
