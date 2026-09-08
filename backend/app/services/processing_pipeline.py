"""Orchestrates the AI pipeline (requirements doc, section 41):

    INPUT (note | pdf | image | screenshot | audio | url)
        -> CONTENT EXTRACTION -> NORMALIZED TEXT
        -> CHUNKS -> EMBEDDINGS -> VECTOR DB

Runs as a FastAPI background task (see api/ai/routes.py) so the mobile
app's request returns immediately — the item's `processing_status` and a
`processing_jobs` row are what the client polls/watches instead
(requirements doc, section 12).
"""

import logging
import time
from collections.abc import Callable

from ..repositories.items_repository import SupabaseRestRepository
from ..repositories.search_repository import SearchRepository
from .ai_provider import AIProvider
from .chunking_service import chunk_text
from .document_service import extract_pdf_text, normalize_text
from .embedding_service import embed_chunks, format_embedding_literal
from .ocr_service import extract_text as extract_ocr_text
from .tagging_service import generate_tags
from .url_service import fetch_and_extract
from .vision_service import analyze_image

logger = logging.getLogger(__name__)

SUPPORTED_TYPES = {"note", "pdf", "image", "screenshot", "audio", "url"}


class UnsupportedItemType(Exception):
    pass


async def process_item(
    item_id: str,
    repo: SupabaseRestRepository,
    get_provider: Callable[[], AIProvider],
    get_search_repo: Callable[[], SearchRepository] | None = None,
    user_id: str | None = None,
) -> None:
    """`get_provider` is resolved *inside* the try block, deliberately —
    a missing API key or bad AI_PROVIDER config is exactly the kind of
    failure this should report on the item/job (requirements doc, rule
    15), not crash the request that kicked processing off.

    `get_search_repo` is optional (and `None` in tests that don't care
    about it) — it powers the best-effort duplicate check after
    embedding, see `_check_for_duplicate`. `user_id` is likewise optional
    and, when given, powers the best-effort tagging step, see
    `_attach_tags` — `tags`/`item_tags` need an explicit owner
    (requirements doc, section 8-12), unlike every other table this
    pipeline writes to, which infers ownership from the item itself.
    """
    job_id = await repo.create_job(item_id, job_type="chunk_and_embed")
    started = time.monotonic()

    try:
        await repo.mark_job_started(job_id)
        await repo.update_item_status(item_id, "processing")

        provider = get_provider()
        item = await repo.get_item(item_id)
        item_type = item["type"]
        if item_type not in SUPPORTED_TYPES:
            raise UnsupportedItemType(f"Processing for type '{item_type}' isn't implemented yet.")

        # Images get theirs for free from the vision call below; everything
        # else falls back to a text-completion call once `text` is ready.
        image_tags: list[str] = []

        if item_type == "note":
            raw_text = await repo.get_note_content(item_id)
        elif item_type == "pdf":
            storage_path = item.get("storage_path")
            if not storage_path:
                raise ValueError("PDF item has no storage_path.")
            pdf_bytes = await repo.download_file(storage_path)
            raw_text = extract_pdf_text(pdf_bytes)
        elif item_type in {"image", "screenshot"}:
            storage_path = item.get("storage_path")
            if not storage_path:
                raise ValueError("Image item has no storage_path.")
            image_bytes = await repo.download_file(storage_path)
            mime_type = item.get("mime_type") or "image/jpeg"

            analysis = await analyze_image(image_bytes, mime_type, provider)
            ocr_text = extract_ocr_text(analysis)
            description = analysis["description"]
            image_tags = analysis.get("tags") or []

            # AI-generated title/description replace the filename-based
            # placeholder set at upload time (requirements doc, section 14).
            await repo.update_item_metadata(
                item_id, title=analysis["title"], description=description
            )
            await repo.replace_item_content(
                item_id, raw_text=description, ocr_text=ocr_text, ai_description=description
            )
            raw_text = f"{description}\n\n{ocr_text}".strip()
        elif item_type == "audio":
            storage_path = item.get("storage_path")
            if not storage_path:
                raise ValueError("Audio item has no storage_path.")
            audio_bytes = await repo.download_file(storage_path)
            mime_type = item.get("mime_type") or "audio/m4a"

            transcript = await provider.transcribe_audio(audio_bytes, mime_type)
            if transcript.strip():
                # "LLM metadata extraction" (requirements doc, section 18) —
                # a short title beats the recording's generic filename.
                title = await provider.generate_text(
                    "Summarize this voice note transcript as a title under 8 "
                    f"words, in Turkish:\n\n{transcript}"
                )
                await repo.update_item_metadata(item_id, title=title.strip())
            await repo.replace_item_content(item_id, raw_text=transcript)
            raw_text = transcript
        else:  # url
            source_url = item.get("source_url")
            if not source_url:
                raise ValueError("URL item has no source_url.")
            extracted = await fetch_and_extract(source_url)

            await repo.update_item_metadata(
                item_id, title=extracted["title"], description=extracted["description"]
            )
            await repo.replace_item_content(item_id, raw_text=extracted["text"])
            raw_text = extracted["text"]

        text = normalize_text(raw_text)
        if not text:
            raise ValueError("No extractable text found in this item.")

        pieces = chunk_text(text)
        embeddings = await embed_chunks(pieces, provider)

        chunk_rows = [
            {
                "item_id": item_id,
                "content": piece,
                "chunk_index": index,
                "embedding": format_embedding_literal(embedding),
                "metadata": {},
            }
            for index, (piece, embedding) in enumerate(zip(pieces, embeddings, strict=True))
        ]
        await repo.replace_chunks(item_id, chunk_rows)

        if get_search_repo is not None:
            await _check_for_duplicate(item_id, repo, get_search_repo)

        if user_id is not None:
            tag_names = (
                image_tags
                if item_type in {"image", "screenshot"}
                else await generate_tags(text, provider)
            )
            await _attach_tags(item_id, user_id, tag_names, repo)

        await repo.update_item_status(item_id, "completed")
        await repo.mark_job_completed(job_id)
        logger.info(
            "item processed",
            extra={
                "item_id": item_id,
                "job_id": job_id,
                "item_type": item_type,
                "chunk_count": len(chunk_rows),
                "processing_time_ms": round((time.monotonic() - started) * 1000, 1),
            },
        )
    except Exception as error:
        # Never log `text`/chunk content — only identifiers and the error
        # itself (requirements doc, section 53).
        logger.warning(
            "processing failed",
            extra={
                "item_id": item_id,
                "job_id": job_id,
                "error": str(error),
                "processing_time_ms": round((time.monotonic() - started) * 1000, 1),
            },
        )
        await repo.update_item_status(item_id, "failed")
        await repo.mark_job_failed(job_id, str(error))


async def _check_for_duplicate(
    item_id: str,
    repo: SupabaseRestRepository,
    get_search_repo: Callable[[], SearchRepository],
) -> None:
    """Best-effort (requirements doc, section 46): this only ever *flags*
    a possible duplicate for the user to review, so a failure here should
    never fail the item's own processing job.
    """
    try:
        search_repo = get_search_repo()
        candidate = await search_repo.find_duplicate_candidate(item_id)
        if candidate:
            await repo.mark_duplicate(item_id, candidate["item_id"], candidate["similarity"])
    except Exception as error:
        logger.warning(
            "duplicate check failed", extra={"item_id": item_id, "error": str(error)}
        )


async def _attach_tags(
    item_id: str,
    user_id: str,
    tag_names: list[str],
    repo: SupabaseRestRepository,
) -> None:
    """Best-effort, same contract as `_check_for_duplicate` — tags are a
    nice-to-have on top of a working item, never a reason to fail one.
    """
    try:
        await repo.attach_tags(item_id, user_id, tag_names)
    except Exception as error:
        logger.warning("tagging failed", extra={"item_id": item_id, "error": str(error)})
