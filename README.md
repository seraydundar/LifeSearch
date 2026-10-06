# LifeSearch

[![CI](https://github.com/seraydundar/LifeSearch/actions/workflows/ci.yml/badge.svg)](https://github.com/seraydundar/LifeSearch/actions/workflows/ci.yml)

**Multimodal Personal AI Search Engine.** Save photos, screenshots, PDFs,
notes, voice memos and links from daily life, then find them again with
natural-language, semantic search — *"Google Search, but for your personal
digital life."*

A solo-built, full-stack mobile project: offline-first Flutter client,
FastAPI AI backend, Supabase/pgvector for auth + storage + vector search.
310 mobile + 238 backend tests, built incrementally across 40+ phases
(full history in [`docs/roadmap.md`](docs/roadmap.md)).

**Highlights**
- Hybrid (keyword + vector) semantic search with LLM reranking
- RAG-based "Ask AI" chat, citation-filtered sources, multi-turn context
- Offline-first sync: every write lands in a local Drift cache first,
  then queues to Supabase in the background, with conflict resolution
  and incremental pulls
- Per-item **and** device-level Privacy Mode, biometric-gated
- Pluggable `AIProvider` interface — OpenAI, Gemini, or a fully local
  Ollama pipeline, swappable without touching the processing pipeline
- Duplicate detection, EXIF-based location/capture metadata, OCR
  fallback for scanned PDFs

## Screenshots

<table>
<tr>
<td><img src="docs/screenshots/home.png" width="260" alt="Home screen"></td>
<td><img src="docs/screenshots/library.png" width="260" alt="Library, grid view"></td>
<td><img src="docs/screenshots/settings.png" width="260" alt="Settings screen"></td>
</tr>
<tr>
<td align="center">Home</td>
<td align="center">Library (grid)</td>
<td align="center">Settings</td>
</tr>
</table>

## Architecture

```mermaid
flowchart LR
    subgraph Mobile["Flutter app (mobile/)"]
        UI["Screens\n(Riverpod ConsumerWidgets)"]
        Repo["Repositories\n(Item / Auth / Search / Collection)"]
        Drift[("Drift\nlocal cache + sync queue")]
        UI --> Repo
        Repo <--> Drift
    end

    subgraph Supabase["Supabase"]
        Auth["Auth"]
        PG[("Postgres + pgvector\nRLS on every table")]
        Storage["Private Storage bucket\n(signed URLs)"]
    end

    subgraph Backend["FastAPI AI service (backend/)"]
        API["/ai/process-item\n/ai/ask\n/search/\n/collections/\n/account/"]
        Pipeline["Processing pipeline\nchunk → embed → tag → EXIF"]
        Provider["AIProvider interface"]
        API --> Pipeline --> Provider
    end

    AI["OpenAI / Gemini / Ollama\n(embeddings, vision, transcription, chat)"]

    Repo -- "REST + signed URLs" --> Storage
    Repo -- "auth, CRUD, RPCs" --> PG
    Repo -- "sign in / sign up" --> Auth
    Repo -- "process/search/ask\n(own Supabase JWT, never a service key)" --> API
    Pipeline -- "reads/writes" --> PG
    Pipeline -- "reads files" --> Storage
    Provider --> AI
```

Every mobile write lands in Drift first, then syncs to Supabase in the
background — no Realtime channel, a background job's status reaches the
device through `SyncService`'s own pull/poll cycle instead. The backend
never holds the user's password or the `service_role` key; it verifies
the caller's own JWT on every request and acts only as that user.

## Monorepo layout

```
LifeSearch/
├── mobile/    Flutter app (Android/iOS), feature-first architecture
├── backend/   FastAPI AI service (OCR, embeddings, RAG, vector search)
├── infra/     Supabase SQL migrations, deployment config
├── docs/      Requirements, roadmap, architecture notes
└── docker-compose.yml   Local Postgres+pgvector for backend dev
```

## Stack

- **Mobile**: Flutter, Riverpod, go_router, Dio, Drift, freezed
- **Backend**: Python, FastAPI, provider-agnostic `AIProvider` interface
- **Cloud**: Supabase (Auth, Postgres, private Storage, pgvector)

## Getting started

### Mobile

```bash
cd mobile
flutter pub get
flutter run
```

### Backend

```bash
cd backend
python3.12 -m venv .venv
source .venv/bin/activate
pip install -r requirements-dev.txt
cp .env.example .env   # fill in Supabase URL/anon key + an AI provider key
uvicorn app.main:app --reload
```

> **macOS note**: Homebrew's Python and macOS's system `libexpat`
> disagree on ABI. Run `brew install expat` once, then prefix every
> backend command with `DYLD_LIBRARY_PATH="$(brew --prefix expat)/lib"`.

For AI processing to actually produce embeddings, set `AI_PROVIDER`
(`openai` / `gemini` / `local`) and the matching key in `backend/.env`
— without one, items still save, just stay unprocessed. For the mobile
app to reach a local backend, set `BACKEND_URL` in `mobile/.env`
(`http://127.0.0.1:8000` on iOS Simulator, `http://10.0.2.2:8000` on
Android emulator). A local Postgres+pgvector for backend tests:
`docker compose up -d db`.

## Tests

```bash
cd backend && DYLD_LIBRARY_PATH="$(brew --prefix expat)/lib" .venv/bin/pytest
cd mobile && flutter test
```

CI runs the same checks on every push — see
[`.github/workflows/ci.yml`](.github/workflows/ci.yml).
