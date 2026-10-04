---
title: Cachy
emoji: 🧠
colorFrom: purple
colorTo: blue
sdk: docker
app_port: 7860
pinned: false
---

<div align="center">

# 🧠 Cachy

### *Turn short-form media into permanent, structured knowledge.*

[![Live Web App](https://img.shields.io/badge/Live_App-vatxzz--cachy.hf.space-blue?style=for-the-badge&logo=huggingface)](https://vatxzz-cachy.hf.space)
[![Android APK](https://img.shields.io/badge/Download_APK-Android_Release-green?style=for-the-badge&logo=android)](https://github.com/Vatsal057/Cachy/releases/latest)
[![Documentation](https://img.shields.io/badge/Docs-Complete_Suite-purple?style=for-the-badge&logo=googledocs)](docs/README.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge)](LICENSE)

</div>

---

## 💡 What is Cachy?

Every week, you save dozens of useful Instagram Reels, TikToks, YouTube Shorts, and web articles. Yet native bookmarks become a **link graveyard**: videos are unsearchable, slow to retrieve, and require re-watching 60–90 seconds of audio just to find a single ingredient, workout step, or command.

**Cachy extracts the signal from the noise.**

Share any reel, video, or article to Cachy — or simply **DM it to `@cachyapp` on Instagram** — and get back a clean, structured **knowledge card**:
- **Executive One-Liner & TL;DR**
- **Interactive Checklists & Step-by-Step Instructions**
- **Key-Value Facts, Ingredients & Specs**
- **Callout Tips, Warnings & Quotes**
- **Locations & Interactive Maps**
- **Extracted Concepts & Referenced Books/Movies/Products**

Your cards connect automatically into an interactive **knowledge graph**, and a reel-style **Feed** replays your saved insights back to you so you actually retain what you learn.

---

## ✨ Flagship Features

### 📥 1. Instagram Auto-Save Bot (`@cachyapp`)
No need to switch apps. Link your Instagram handle in your Cachy profile and **DM reels directly to `@cachyapp`**. 
- Automatically approves message requests and extracts reel URLs (including mobile share-sheet links).
- Enqueues background downloading, transcribes audio, and sends an immediate confirmation DM.
- Supports burst queues (send up to 10 reels in a row; all will be batched and saved).

### 📋 2. Interactive Typed Knowledge Cards (Schema `1.6`)
Say goodbye to walls of AI text. Cards are built from modular, interactive blocks:
- **Step Lists:** Step-by-step guides with checkable progress.
- **Checklists:** Dynamic ingredient and to-do lists that preserve your checked state.
- **Key-Value Blocks:** Structured parameters (e.g. prep time, difficulty, camera settings).
- **Interactive Quizzes:** 3–5 multiple-choice questions per card to test your retention.
- **Rabbit Hole Research:** Tap any concept to explore branching follow-up threads.

### 📱 3. On-Device Local AI (Google Gemma 3 1B)
Cachy respects free-tier limits. If cloud daily card quotas are reached:
- The backend extracts raw transcripts and OCR, then flags the card as `degraded`.
- Your phone’s local **Gemma 3 1B** model (`flutter_gemma`) automatically structures the card on-device with zero cloud API usage.

### 🕸️ 4. Dynamic Knowledge Graph & Replay Feed
- **Force-Directed Graph:** An Obsidian-style physics graph rendered client-side in Flutter. Links cards by semantic vector similarity (`0.26`–`0.66`), shared tags, and referenced entities.
- **Knowledge Replay Feed:** A TikTok-style vertical feed that resurfaces micro-moments from your own library: key takeaways, quiz questions, punchy highlights, and serendipitous cross-card links.

### 💬 5. Card & Full-Library AI Chat
- **Card Chat:** Ask questions specific to a single card (e.g., *"What can I substitute for coconut milk in this recipe?"*).
- **Library Chat:** Ask questions across your entire knowledge base (e.g., *"Summarize all productivity techniques I've saved across different videos"*).

### 🔗 6. Unlisted Sharing & "Save to My Cachy"
- Generate unlisted share links (`/share/{token}`) with server-rendered OpenGraph previews for WhatsApp, iMessage, and Twitter.
- Anyone can read the card on the web without logging in, or tap **"Save to my Cachy"** to clone it directly into their library with zero quota charge.

### 🎙️ 7. Self-Driving Presenter Agent
Built right into the web app: tap **Present** to launch an autonomous AI demo agent that speaks using the browser's Web Speech API while navigating, clicking, and demonstrating features across the entire app.

### 📦 8. Obsidian Vault Export
Export your entire personal knowledge base in one click as a `.zip` archive formatted as an **Obsidian vault** with YAML frontmatter, Markdown blocks, tags, and local media keyframes.

---

## 🏗️ Architecture & Tech Stack

```
[Flutter Client (Android / Web)]
              │
              │ REST + Server-Sent Events (SSE)
              ▼
[FastAPI Asynchronous Backend (Port 7860)]
       │                      │
       ├─► In-Process Worker  ├─► Instagram DM Poller (@cachyapp)
       │   (6 Pipeline Steps) │   (instagrapi + requests transport)
       │                      │
       ├─► AI Fallback Chain  └─► Database Layer
       │   1. Gemini 2.5 Flash    • Production: Neon PostgreSQL
       │   2. Cerebras Llama 3.3  • Local Dev: SQLite (aiosqlite)
       │   3. Groq Llama 3.3
       │   4. On-Device Gemma 3
```

- **Frontend:** Flutter 3+ (Dart) with MVVM architecture, Provider state management, and CanvasKit/Wasm rendering.
- **Backend:** FastAPI (Python 3.11), SQLAlchemy 2.0 async, `instagrapi` for DM polling, and `trafilatura` for clean article scraping.
- **AI & Audio Engine:** Groq Whisper Turbo (`whisper-large-v3-turbo`) with fallback to local `faster-whisper`; Gemini 2.5 Flash + Cerebras Llama 3.3 70B for structuring; `BAAI/bge-small-en-v1.5` for vector embeddings.
- **Cloud Infrastructure:** Hugging Face Spaces (Docker SDK), Neon Serverless PostgreSQL.

---

## 📚 Documentation Suite

Complete, deep-dive specifications are maintained in the [`docs/`](docs/README.md) directory:

| Document | Topic |
|---|---|
| **[`docs/01_PRODUCT_REQUIREMENTS_DOCUMENT.md`](docs/01_PRODUCT_REQUIREMENTS_DOCUMENT.md)** | Product Vision, Personas, Schema 1.6 specifications, and PRD |
| **[`docs/02_SYSTEM_ARCHITECTURE.md`](docs/02_SYSTEM_ARCHITECTURE.md)** | Detailed subsystem architecture, data flow, and database models |
| **[`docs/03_INGESTION_AND_INSTAGRAM_BOT.md`](docs/03_INGESTION_AND_INSTAGRAM_BOT.md)** | Instagram `@cachyapp` DM bot, pending inbox rules, and resolvers |
| **[`docs/04_ON_DEVICE_AI_AND_FALLBACKS.md`](docs/04_ON_DEVICE_AI_AND_FALLBACKS.md)** | Google Gemma 3 1B on-device structuring and LLM fallback cascades |
| **[`docs/05_AUTHENTICATION_AND_SECURITY.md`](docs/05_AUTHENTICATION_AND_SECURITY.md)** | Firebase Auth + Cachy ID password auth, quotas, and security |
| **[`docs/06_API_REFERENCE.md`](docs/06_API_REFERENCE.md)** | Full REST API & SSE streaming reference (26+ endpoints) |
| **[`docs/07_DEPLOYMENT_AND_OPERATIONS.md`](docs/07_DEPLOYMENT_AND_OPERATIONS.md)** | Hugging Face Spaces deployment, Docker configuration, and APK builds |

---

## 🚀 Quickstart & Local Setup

### 1. Run the Full Stack
To spin up both the FastAPI backend and the web frontend locally:
```bash
./start.py
```

### 2. Backend Alone
```bash
cd backend
python -m venv venv && source venv/bin/activate
pip install -e .
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

### 3. Flutter App (Web & Mobile)
```bash
cd app
flutter pub get
flutter run -d chrome --dart-define=CACHY_API_BASE=http://localhost:8000
```

### 4. Build Release Android APK
```bash
cd app
flutter build apk --release --target-platform android-arm64 --split-per-abi
```

---

## 🚢 Cloud Deployment (Hugging Face Spaces)

Cachy runs entirely on a free-tier Hugging Face Space. Deploy changes with one command:
```bash
./deploy_hf.sh "feat: your update message"
```
This builds the Flutter web distribution, detaches a clean deployment commit, and pushes to your Hugging Face Space.

---

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
