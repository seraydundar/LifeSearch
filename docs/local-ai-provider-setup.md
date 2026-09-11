# Local AI provider — external setup checklist

The code for this (Faz 11, madde 6a — see `docs/roadmap.md`) is done and
tested, but `AI_PROVIDER=local` can't actually do anything until **you**
install and run the pieces it talks to — none of that can be done or
verified from inside this repo.

## Why "local" at all

`AI_PROVIDER=openai` and `AI_PROVIDER=gemini` both send every prompt,
embedding input, image and (for OpenAI) audio clip to that vendor's
cloud API. `AI_PROVIDER=local` sends none of it anywhere — text,
embeddings and vision go through **Ollama**, a model server you run
yourself, and transcription runs **in-process** in the backend via
`faster-whisper`. Nothing leaves the machine the backend runs on.

The trade-off is real: local models (the ones that fit on a personal
machine) are meaningfully weaker than GPT-4o-mini or Gemini 2.0 Flash at
things like RAG answer quality and image analysis. This is for people
who want zero-cloud-dependency over best-possible answers, not a free
upgrade.

## 1. Install and run Ollama

Download from [ollama.com/download](https://ollama.com/download) (macOS/
Windows/Linux) and start it — on macOS/Windows the installer sets it up
to run as a background service; on Linux, `ollama serve`. It listens on
`http://localhost:11434` by default, matching `LOCAL_OLLAMA_BASE_URL`'s
default in `backend/.env.example`.

## 2. Pull the models the backend expects

`backend/.env`'s defaults:

```
ollama pull llama3.2          # LOCAL_TEXT_MODEL — RAG answers, tags/summaries
ollama pull nomic-embed-text  # LOCAL_EMBEDDING_MODEL — chunk + query embeddings
ollama pull llava             # LOCAL_VISION_MODEL — image analysis (Faz 6)
```

Any Ollama chat-capable model works for `LOCAL_TEXT_MODEL`/
`LOCAL_VISION_MODEL` (must accept the `images` field on a chat message
for vision), and any Ollama embedding model for `LOCAL_EMBEDDING_MODEL`
— override the three in `backend/.env` to swap. Bigger models need more
RAM; check each model's page on [ollama.com/library](https://ollama.com/library)
before pulling if the host is memory-constrained.

## 3. `backend/.env`

```
AI_PROVIDER=local
LOCAL_OLLAMA_BASE_URL=http://localhost:11434
LOCAL_TEXT_MODEL=llama3.2
LOCAL_EMBEDDING_MODEL=nomic-embed-text
LOCAL_VISION_MODEL=llava
LOCAL_WHISPER_MODEL=base
```

`LOCAL_WHISPER_MODEL` needs nothing installed separately — `faster-whisper`
downloads the model file itself (to its own local cache) the first time
`transcribe_audio` actually runs. `base` is a reasonable default; bump to
`small`/`medium` for better accuracy on a host with the CPU (or GPU) to
spare — see [faster-whisper's model list](https://github.com/SYSTRAN/faster-whisper#model-conversion).

## Switching providers on a database with existing embeddings

Same caveat as switching to/from Gemini (see `GeminiProvider`'s
docstring in `backend/app/services/ai_provider.py`): a local embedding
model's vector space has nothing to do with OpenAI's or Gemini's.
Flipping `AI_PROVIDER` on an archive that already has chunks embedded
by a *different* provider needs a full manual re-embed of every
existing chunk — there's no migration for that here.

## What was **not** verified

None of this — a real Ollama round trip, a real `faster-whisper`
transcription — could be run from inside this session: it needs Ollama
actually installed and running with real models pulled, which isn't
possible in this sandboxed environment. The code was verified as far as
it can be without that: `ruff check` clean, and
`backend/tests/test_ai_provider.py`'s `TestLocalProviderOllamaCalls`
exercises every `LocalProvider` code path (text, embeddings + padding,
vision, and the "Ollama isn't running" error path) against
`httpx.MockTransport` standing in for a real Ollama server — see
`docs/roadmap.md`, Faz 11, madde 6a. `faster-whisper` itself is a
well-established, widely-used library; its own transcription correctness
is out of scope to re-verify here, only that this backend calls it
correctly (model construction, temp-file handoff, running it off the
event loop via `asyncio.to_thread`).
