# Cachy Documentation Suite

Welcome to the comprehensive technical and product documentation for **Cachy**.

---

## Documentation Index

1. **[01 — Product Requirements Document (PRD)](file:///Users/vatsal/MyStuff/Android_Apps/Cachy/docs/01_PRODUCT_REQUIREMENTS_DOCUMENT.md)**  
   *Vision, target personas, user journeys, core feature specifications, non-functional requirements, and success metrics.*

2. **[02 — System Architecture Specification](file:///Users/vatsal/MyStuff/Android_Apps/Cachy/docs/02_SYSTEM_ARCHITECTURE.md)**  
   *High-level topology, Flutter MVVM client architecture, FastAPI backend structure, pipeline worker, and database schemas.*

3. **[03 — Ingestion Pipelines & Instagram Bot](file:///Users/vatsal/MyStuff/Android_Apps/Cachy/docs/03_INGESTION_AND_INSTAGRAM_BOT.md)**  
   *Complete documentation of the `@cachyapp` Instagram DM auto-save bot, pending message request approval, multi-format reel parsing, cloud TLS discipline, and video scrapers.*

4. **[04 — On-Device AI & Fallback Chains](file:///Users/vatsal/MyStuff/Android_Apps/Cachy/docs/04_ON_DEVICE_AI_AND_FALLBACKS.md)**  
   *Google Gemma 3 1B on-device structuring (`flutter_gemma`), local Faster-Whisper, quota accounting, and the multi-tiered LLM fallback chain.*

5. **[05 — Authentication & Security Architecture](file:///Users/vatsal/MyStuff/Android_Apps/Cachy/docs/05_AUTHENTICATION_AND_SECURITY.md)**  
   *Dual-auth system (Firebase anonymous-first + Google linking, Cachy ID password auth), `OwnerDep` route validation, IP rate limits, and zero-leak secret management.*

6. **[06 — REST API & Streaming Reference](file:///Users/vatsal/MyStuff/Android_Apps/Cachy/docs/06_API_REFERENCE.md)**  
   *Complete specification of REST endpoints, Server-Sent Events (SSE) progress streams, request/response models, and status codes.*

7. **[07 — Deployment & Operations Guide](file:///Users/vatsal/MyStuff/Android_Apps/Cachy/docs/07_DEPLOYMENT_AND_OPERATIONS.md)**  
   *Hugging Face Spaces one-command deployment (`./deploy_hf.sh`), required container environment variables, Neon PostgreSQL migrations, and APK compilation.*

8. **[Mobile Connection Guide](file:///Users/vatsal/MyStuff/Android_Apps/Cachy/docs/MOBILE_CONNECTION_GUIDE.md)**  
   *Instructions for connecting local development Android/iOS devices to local backend servers over LAN.*
