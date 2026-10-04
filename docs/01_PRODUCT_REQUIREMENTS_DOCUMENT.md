# Product Requirements Document (PRD) — Cachy

**Product:** Cachy — The Short-Form Media to Knowledge Engine  
**Version:** 2.0 (Schema Version `1.6`)  
**Status:** In Production (Android Native APK + Web App)  
**Distribution:** Direct Download (GitHub APK) + Hosted Web App (`vatxzz-cachy.hf.space`)  

---

## 1. Executive Summary & Vision

Every day, people scroll through dozens of high-value Instagram Reels, TikToks, YouTube Shorts, and insightful web articles. They tap "Save" or "Bookmark", yet 90% of saved videos are never watched again. Native bookmarking creates a **link graveyard**: videos are unsearchable, slow to retrieve, and require re-watching 60–90 seconds of audio/video just to find a single ingredient, code snippet, or workout step.

**Cachy transforms ephemeral video clips into structured, permanent knowledge cards.**

Instead of storing dead links, Cachy extracts actionable steps, recipes, frameworks, and entities, connects them into an interactive **knowledge graph**, and replays them through an intelligent **knowledge feed**.

---

## 2. Target Personas & Core User Journeys

### 2.1 Personas
1. **The Casual Scroller (Primary):**
   - *Profile:* Uses Instagram/TikTok on commute or evening downtime; finds cooking tips, fitness routines, tech hacks, and book summaries.
   - *Pain Point:* "I saw an amazing recipe on Instagram 3 weeks ago, but can't find it among my 500 saved reels."
   - *Journey:* DMs the reel to `@cachyapp` on Instagram or shares via the Android share sheet. Later opens Cachy to see a fully structured ingredient list, checklist, and timer.
2. **The Knowledge Worker & Student:**
   - *Profile:* Reads substacks, tech tutorials, and watch educational shorts.
   - *Pain Point:* Needs concepts interconnected and exportable to tools like Obsidian.
   - *Journey:* Collects articles and tutorials, explores cross-card connections via the graph, asks questions to the entire library via AI chat, and exports as an Obsidian markdown vault.

---

## 3. Core Functional Requirements

### 3.1 Seamless Ingestion Channels
- **FR-1.1: Native Mobile Share Sheet:** Registered via `receive_sharing_intent` on Android. Sharing any URL to Cachy opens the transparent pipeline overlay.
- **FR-1.2: Instagram Bot Auto-Save (`@cachyapp`):**
  - Users link their Instagram username in the Cachy profile (`/me/instagram`).
  - Sending reels or posts to `@cachyapp` triggers automated ingestion, message request approval, and an immediate DM confirmation reply.
  - Supports burst sharing (up to 10 consecutive reels in a single batch).
- **FR-1.3: In-App Manual Capture:** Fast paste dialog with URL preview and real-time Server-Sent Events (SSE) progress bar.

### 3.2 Processing Pipeline & Extraction Engine
- **FR-2.1: Keyless & Fallback Downloading:** Keyless resolver chain (`yt-dlp` → `vidssave` → `savethevideo` → `saveig` → `downloadgram`) ensuring high reliability without paid scraping APIs.
- **FR-2.2: Audio Transcription:** Primary Groq Whisper Turbo (`whisper-large-v3-turbo`) with fallback to local in-process `faster-whisper`.
- **FR-2.3: Visual OCR & Keyframes:** OpenCV keyframe extraction and `pytesseract` OCR for on-screen text, carousel slides, and diagrams.
- **FR-2.4: Ephemeral Media Storage:** Original source video is deleted immediately after extraction; only lightweight keyframes and thumbnails are retained.

### 3.3 Structured Knowledge Schema (Schema `1.6`)
Every card is structured into typed, interactive blocks rather than a monolithic wall of text:
1. **`HeadingBlock`**: Section demarcation (`level: 2 | 3`).
2. **`ParagraphBlock`**: Core explanations and narrative insights.
3. **`StepListBlock`**: Ordered step-by-step procedures with interactive checkboxes (`checkable: true`).
4. **`KeyValueBlock`**: Structured parameter pairs (e.g., Cooking Time: 25 mins, Difficulty: Medium).
5. **`ChecklistBlock`**: Interactive to-do and ingredient lists with persistent checked state.
6. **`CalloutBlock`**: Highlights, pro-tips, warnings, and quotes with confidence scores and source URLs.
7. **`LinkBlock`**: External references, papers, and product URLs.
8. **`MapBlock`**: Geographic coordinates (`lat`, `lng`, `name`, `address`) that link directly to native Maps.
9. **`TableBlock`**: Tabular comparisons with named columns and rows.

### 3.4 Deep Insight Layer & Learning
- **FR-3.1: Interactive Quizzes:** 3–5 multiple-choice questions per card with explanations to test user comprehension.
- **FR-3.2: Rabbit Hole Explorations:** Branching topical exploration prompts that let users dive deeper into sub-topics with breadcrumb trails.
- **FR-3.3: Card & Library AI Chat:** Contextual Q&A on a single card or cross-referencing insights across the entire library.

### 3.5 Discovery, Feed & Knowledge Graph
- **FR-4.1: Serendipity Engine:** Discovers non-obvious conceptual links between cards using mid-band semantic cosine similarity (`0.26`–`0.66`) with a cross-content-type bonus.
- **FR-4.2: Knowledge Replay Feed:** TikTok-style vertical scroll feed that serves micro-moments from saved cards (Insights, Quizzes, Highlights, Connections) at zero LLM cost.
- **FR-4.3: Interactive Force-Directed Graph:** Live physics-based knowledge graph rendered client-side in Flutter, with clustering calculated via pure-Python label propagation.

### 3.6 Public Sharing & Web Reader
- **FR-5.1: Unlisted Share Links:** Public short URLs (`/share/{token}` and `/s/{token}`) with server-rendered OpenGraph meta tags for rich social previews on WhatsApp, iMessage, and Telegram.
- **FR-5.2: "Save to My Cachy":** One-click cloning of shared cards into the receiver's personal library with zero quota deduction.
- **FR-5.3: Android App Links:** Deep linking (`/.well-known/assetlinks.json`) allowing shared web links to open natively in the Android app.

### 3.7 Self-Driving Presenter Mode
- **FR-6.1: Autonomous Interactive Tour:** Integrated demo agent floating as a glowing glyph. Uses the Web Speech API to speak while autonomously navigating, clicking, and driving the app across all features.
- **FR-6.2: Audience Q&A:** Visitors can ask questions; the backend orchestrates ordered `{say, action}` beats so the agent *performs* the answer directly in the UI.

### 3.8 Obsidian Vault Export
- **FR-7.1: One-Click Markdown Zip:** Client-side generation of an Obsidian-ready vault containing YAML frontmatter, tags, Markdown blocks, and local media attachments.

---

## 4. Non-Functional Requirements & Design Aesthetics

- **Design Philosophy:** "Calm Editorial Glass" — warm paper / deep charcoal dark mode, Fraunces serif display, Inter body text, IBM Plex Mono labels.
- **Quota & Cost Discipline:**
  - 10 cards/day for free users; 30 chat queries/day.
  - Scale-to-zero database protection: 30-minute idle worker backoff to prevent draining serverless Neon Postgres compute limits.
- **Graceful Degradation:** Automatic cascade from Gemini 2.5 Flash → Cerebras Llama 3.3 → Groq Llama 3.3 → On-Device Gemma 3 1B → Plain Text Fallback.
