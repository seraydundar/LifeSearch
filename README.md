# LifeSearch

[![CI](https://github.com/seraydundar/LifeSearch/actions/workflows/ci.yml/badge.svg)](https://github.com/seraydundar/LifeSearch/actions/workflows/ci.yml)

**Multimodal Personal AI Search Engine.** Save photos, screenshots, PDFs,
notes, voice memos and links from daily life, then find them again with
natural-language, semantic search — *"Google Search, but for your personal
digital life."*

> Status: all 9 planned phases done, plus a post-Phase-9 pass that closed
> four gaps found by re-reading the requirements doc (tags, offline
> keyword search, structured logging, EXIF location). See
> [`docs/roadmap.md`](docs/roadmap.md) for the phase-by-phase detail.
> Full requirements: [`docs/requirements.md`](docs/requirements.md).

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

> macOS/Homebrew note: Homebrew's Python and macOS's system `libexpat`
> disagree on ABI, which breaks anything importing `xml`/`pyexpat` —
> `venv` creation, and later `pypdf` (used for PDF text extraction). Run
> `brew install expat` once, then prefix every backend command —
> `venv` creation, `uvicorn`, `pytest`, `ruff` — with
> `DYLD_LIBRARY_PATH="$(brew --prefix expat)/lib"`.

For AI processing (`POST /ai/process-item`) to actually produce
embeddings, `AI_PROVIDER=openai` and `OPENAI_API_KEY` need to be set in
`backend/.env`. Without a key, the endpoint still responds and the item's
`processing_status` correctly flips to `failed` with a clear
`error_message` on its `processing_jobs` row — it degrades, it doesn't
crash.

For the mobile app to reach a locally-running backend, set
`BACKEND_URL` in `mobile/.env` — `http://127.0.0.1:8000` works from the
iOS Simulator (shares the Mac's network stack); Android emulator needs
`http://10.0.2.2:8000`; a physical device needs the Mac's LAN IP.

### Local Postgres + pgvector (optional, for backend tests)

```bash
docker compose up -d db
```

## Environment variables

Copy `backend/.env.example` to `backend/.env`. Never commit `.env` files —
API keys and the Supabase service role key live only in the backend
environment, never in the Flutter app (see requirements doc, section 36).

## Tests

```bash
# Backend
cd backend && DYLD_LIBRARY_PATH="$(brew --prefix expat)/lib" .venv/bin/pytest
cd backend && DYLD_LIBRARY_PATH="$(brew --prefix expat)/lib" .venv/bin/ruff check .

# Mobile
cd mobile && flutter analyze
cd mobile && flutter test
```

Every push/PR to `main` runs the same checks in CI — see
[`.github/workflows/ci.yml`](.github/workflows/ci.yml).

## Roadmap

See [`docs/roadmap.md`](docs/roadmap.md) — the project is built in phases,
starting with a backend-less Flutter shell (auth + navigation) and adding
AI capabilities incrementally.
