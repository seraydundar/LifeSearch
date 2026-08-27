# LifeSearch

**Multimodal Personal AI Search Engine.** Save photos, screenshots, PDFs,
notes, voice memos and links from daily life, then find them again with
natural-language, semantic search — *"Google Search, but for your personal
digital life."*

> Status: early scaffolding. See [`docs/roadmap.md`](docs/roadmap.md) for
> where we are and what's next. Full requirements:
> [`docs/requirements.md`](docs/requirements.md).

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
cp .env.example .env   # fill in Supabase + AI provider keys
uvicorn app.main:app --reload
```

> macOS/Homebrew note: if `python3 -m venv` fails with a `pyexpat` /
> `ensurepip` error, it's a known Homebrew Python + system `libexpat`
> mismatch. Run `brew install expat` then prefix venv creation with
> `DYLD_LIBRARY_PATH="$(brew --prefix expat)/lib"`.

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
cd backend && .venv/bin/pytest

# Mobile
cd mobile && flutter test
```

## Roadmap

See [`docs/roadmap.md`](docs/roadmap.md) — the project is built in phases,
starting with a backend-less Flutter shell (auth + navigation) and adding
AI capabilities incrementally.
