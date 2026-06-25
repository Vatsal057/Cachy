# 09 — Features

Full feature list by area. Phase tags: **[P1]** MVP, **[P2]**, **[P3]**.

## Ingestion
- Share-sheet integration (Instagram first) **[P1]**, TikTok + YouTube Shorts **[P2]**
- Link paste fallback **[P1]**
- Batch share — multiple reels queue independently without blocking **[P1]**
- Duplicate detection — re-share returns existing card **[P1]**
- Graceful late-surfaced failure for unsupported/private/unavailable **[P1]**

## Extraction
- Audio transcription (Whisper) **[P1]**
- On-screen text OCR (via local Tesseract) **[P1]**
- Visual context understanding (conditional HF Inference VLM) **[P1]**
- Metadata capture (caption, creator, url, duration) **[P1]**

## Structuring
- Content-type detection **[P1]**
- Single adaptive structuring pass (text-only HF/Groq LLM) **[P1]**
- Block vocabulary: heading, paragraph, bullet_list, step_list, key_value,
  checklist, callout, link **[P1]**; map, table **[P2]**
- Strict schema validation + paragraph fallback **[P1]**
- Unconditional base layer (one_liner, tldr, source) **[P1]**

## Reading experience
- Multi-depth hierarchy (instant / skim / depth) **[P1]**
- Progressive top-down rendering **[P1]**
- Checkable steps **[P1]**
- Confidence/source signal on claims **[P1]**
- Lookup-able products **[P2]**
- Mappable places **[P2]**

## Action layer
- One primary action per card **[P1]** (kind derived from content type)
- Shopping/checklist generation **[P2]**
- Reminders / calendar events **[P2]**
- Export to Notion / Obsidian / Apple Notes / markdown **[P2]**

## Visual
- Keyframe thumbnails + visual library grid **[P1]**
- Color/motion/depth system, progressive-render animation **[P1]**
- Maps with pins, charts, product thumbnails, visual step strips **[P2]**

## Library & retrieval
- Card states surfaced (queued/processing/ready/failed) **[P1]**
- Basic search (full-text) **[P1]**
- Collections + auto-tagging **[P2]**
- Semantic search **[P2]**
- Chat-with-your-library **[P3]**

## Resurfacing
- Weekly digest **[P3]**
- Spaced resurfacing (opt-in) **[P3]**

## Trust & safety
- Claim-quality signals on health/finance/medical content **[P3]**
- Clear "AI-generated, may contain errors" labeling **[P1]**

## Cross-cutting (production)
- Offline reading of cached cards **[P1]**
- Offline share queueing + sync **[P1]**
- Retry + dead-letter on failed jobs **[P1]**
- Observability (resolver success, stage timing, failure reasons, LLM call count) **[P1]**
- Card + media deletion (data ownership) **[P1]**
