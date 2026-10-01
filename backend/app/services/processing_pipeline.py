"""Orchestrates the AI pipeline:

    INPUT (note | pdf | image | screenshot | audio | url)
        -> CONTENT EXTRACTION -> NORMALIZED TEXT
        -> CHUNKS -> EMBEDDINGS -> VECTOR DB

Runs as a FastAPI background task; the client polls `processing_status`/
`processing_jobs` instead of waiting on the request.
"""

import logging
import time
from collections.abc import Callable

from ..repositories.items_repository import SupabaseRestRepository
from ..repositories.search_repository import SearchRepository
from .ai_provider import AIProvider
from .chunking_service import chunk_pages, chunk_text
from .document_service import (
    extract_document_text,
    extract_pdf_text_per_page,
    normalize_text,
    render_pdf_pages_to_images,
)
from .embedding_service import embed_chunks, format_embedding_literal
from .entity_extraction_service import extract_entities
from .exif_service import extract_exif_metadata
from .ocr_service import extract_text as extract_ocr_text
from .tagging_service import generate_tags
from .url_service import fetch_and_extract
from .vision_service import analyze_image

logger = logging.getLogger(__name__)

SUPPORTED_TYPES = {"note", "pdf", "image", "screenshot", "audio", "url", "document"}

# Bounds paid vision calls one PDF's OCR fallback can trigger; counts only
# pages actually needing OCR, not the document's total page count.
_MAX_OCR_PDF_PAGES = 30


class UnsupportedItemType(Exception):
    pass


async def process_item(
    item_id: str,
    job_id: str,
    repo: SupabaseRestRepository,
    get_provider: Callable[[], AIProvider],
    get_search_repo: Callable[[], SearchRepository] | None = None,
    user_id: str | None = None,
) -> None:
    """`get_provider` is resolved inside the try block so a missing/bad
    AI_PROVIDER config reports as a failed item/job instead of crashing the
    caller. `job_id` is created by the caller, before the "202 accepted"
    response, so a process death before this background task even starts
    still leaves a recoverable row for job_recovery.py. `user_id`, when
    given, is needed because tags/entities require an explicit owner.
    """
    started = time.monotonic()

    try:
        await repo.mark_job_started(job_id)
        await repo.update_item_status(item_id, job_id, "processing")

        provider = get_provider()
        item = await repo.get_item(item_id)
        item_type = item["type"]
        if item_type not in SUPPORTED_TYPES:
            raise UnsupportedItemType(f"Processing for type '{item_type}' isn't implemented yet.")

        # Images get tags free from the vision call; others fall back to generate_tags().
        image_tags: list[str] = []

        if item_type == "note":
            raw_text = await repo.get_note_content(item_id)
        elif item_type == "pdf":
            storage_path = item.get("storage_path")
            if not storage_path:
                raise ValueError("PDF item has no storage_path.")
            pdf_bytes = await repo.download_file(storage_path)
            # OCR per-page (only pages missing a text layer), kept as a list
            # (not joined yet) so chunking below can tag each chunk with its page.
            page_texts = await _ocr_missing_pdf_pages(pdf_bytes, provider)
            raw_text = "\n\n".join(text for text in page_texts if text)
            await repo.replace_item_content(item_id, job_id, raw_text=raw_text)
        elif item_type == "document":
            storage_path = item.get("storage_path")
            if not storage_path:
                raise ValueError("Document item has no storage_path.")
            document_bytes = await repo.download_file(storage_path)
            raw_text = extract_document_text(
                document_bytes, item.get("mime_type"), item.get("original_filename")
            )
            await repo.replace_item_content(item_id, job_id, raw_text=raw_text)
        elif item_type in {"image", "screenshot"}:
            storage_path = item.get("storage_path")
            if not storage_path:
                raise ValueError("Image item has no storage_path.")
            image_bytes = await repo.download_file(storage_path)
            mime_type = item.get("mime_type") or "image/jpeg"

            analysis = await analyze_image(
                image_bytes, mime_type, provider, is_screenshot=item_type == "screenshot"
            )
            ocr_text = extract_ocr_text(analysis)
            description = analysis["description"]
            image_tags = analysis.get("tags") or []
            exif_data = extract_exif_metadata(image_bytes)

            await repo.update_item_metadata(
                item_id,
                job_id,
                title=analysis["title"],
                description=description,
                latitude=exif_data["latitude"],
                longitude=exif_data["longitude"],
                captured_at=exif_data["captured_at"],
            )
            await repo.replace_item_content(
                item_id,
                job_id,
                raw_text=description,
                ocr_text=ocr_text,
                ai_description=description,
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
                title = await provider.generate_text(
                    "Summarize this voice note transcript as a title under 8 "
                    f"words, in Turkish:\n\n{transcript}"
                )
                await repo.update_item_metadata(item_id, job_id, title=title.strip())
            await repo.replace_item_content(item_id, job_id, raw_text=transcript)
            raw_text = transcript
        else:  # url
            source_url = item.get("source_url")
            if not source_url:
                raise ValueError("URL item has no source_url.")
            extracted = await fetch_and_extract(source_url)

            await repo.update_item_metadata(
                item_id, job_id, title=extracted["title"], description=extracted["description"]
            )
            await repo.replace_item_content(item_id, job_id, raw_text=extracted["text"])
            raw_text = extracted["text"]

        text = normalize_text(raw_text)
        if not text:
            raise ValueError("No extractable text found in this item.")

        if item_type == "pdf":
            # PDF is the one type with a page concept, so its chunks carry a page_number.
            pairs = chunk_pages([normalize_text(page) for page in page_texts])
            pieces = [chunk for chunk, _ in pairs]
            page_numbers: list[int | None] = [page for _, page in pairs]
        else:
            pieces = chunk_text(text)
            page_numbers = [None] * len(pieces)

        embeddings = await embed_chunks(pieces, provider)

        chunk_rows = [
            {
                "item_id": item_id,
                "content": piece,
                "chunk_index": index,
                "embedding": format_embedding_literal(embedding),
                # Lets a later switch identify stale vectors; see reembedding_service.py.
                "embedding_provider": provider.provider_name,
                "embedding_model": provider.embedding_model,
                "metadata": {"page_number": page_number} if page_number is not None else {},
            }
            for index, (piece, embedding, page_number) in enumerate(
                zip(pieces, embeddings, page_numbers, strict=True)
            )
        ]
        await repo.replace_chunks(item_id, job_id, chunk_rows)

        if get_search_repo is not None:
            await _check_for_duplicate(item_id, job_id, repo, get_search_repo)

        if user_id is not None:
            tag_names = (
                image_tags
                if item_type in {"image", "screenshot"}
                else await generate_tags(text, provider)
            )
            await _attach_tags(item_id, job_id, user_id, tag_names, repo)
            entities = await extract_entities(text, provider)
            await _attach_entities(item_id, job_id, user_id, entities, repo)

        await repo.update_item_status(item_id, job_id, "completed")
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
        # Never log item text/chunk content, only identifiers and the error.
        logger.warning(
            "processing failed",
            extra={
                "item_id": item_id,
                "job_id": job_id,
                "error": str(error),
                "processing_time_ms": round((time.monotonic() - started) * 1000, 1),
            },
        )
        await repo.update_item_status(item_id, job_id, "failed")
        await repo.mark_job_failed(job_id, str(error))
    finally:
        # repo is constructed fresh per call; this is what releases its HTTP connection.
        await repo.aclose()


async def _ocr_missing_pdf_pages(pdf_bytes: bytes, provider: AIProvider) -> list[str]:
    """OCRs (via the same vision call a photo gets) only the pages whose
    text layer came back empty; returns one entry per page, kept as a list
    (not joined) so the caller can still feed it to chunk_pages() for page
    numbers. Pages past _MAX_OCR_PDF_PAGES are silently left blank.
    """
    page_texts = extract_pdf_text_per_page(pdf_bytes)
    missing_indices = [index for index, text in enumerate(page_texts) if not text]
    if not missing_indices:
        return page_texts

    ocr_indices = missing_indices[:_MAX_OCR_PDF_PAGES]
    page_images = render_pdf_pages_to_images(pdf_bytes, page_indices=ocr_indices)
    for index, image_bytes in zip(ocr_indices, page_images, strict=True):
        analysis = await analyze_image(image_bytes, "image/png", provider)
        page_texts[index] = extract_ocr_text(analysis).strip()

    return page_texts


async def _check_for_duplicate(
    item_id: str,
    job_id: str,
    repo: SupabaseRestRepository,
    get_search_repo: Callable[[], SearchRepository],
) -> None:
    """Best-effort: only flags a possible duplicate, never fails the item's job."""
    try:
        search_repo = get_search_repo()
        candidate = await search_repo.find_duplicate_candidate(item_id)
        if candidate:
            await repo.mark_duplicate(
                item_id, job_id, candidate["item_id"], candidate["similarity"]
            )
    except Exception as error:
        logger.warning(
            "duplicate check failed", extra={"item_id": item_id, "error": str(error)}
        )


async def _attach_tags(
    item_id: str,
    job_id: str,
    user_id: str,
    tag_names: list[str],
    repo: SupabaseRestRepository,
) -> None:
    """Best-effort — tags are a nice-to-have, never a reason to fail the item."""
    try:
        await repo.attach_tags(item_id, job_id, user_id, tag_names)
    except Exception as error:
        logger.warning("tagging failed", extra={"item_id": item_id, "error": str(error)})


async def _attach_entities(
    item_id: str,
    job_id: str,
    user_id: str,
    entities: list[dict[str, str]],
    repo: SupabaseRestRepository,
) -> None:
    """Best-effort, same contract as `_attach_tags`."""
    try:
        await repo.attach_entities(item_id, job_id, user_id, entities)
    except Exception as error:
        logger.warning("entity attach failed", extra={"item_id": item_id, "error": str(error)})
