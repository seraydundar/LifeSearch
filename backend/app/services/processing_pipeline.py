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
from .document_service import (
    extract_document_text,
    extract_pdf_text,
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

# Bounds the number of (paid) vision calls one scanned PDF's OCR fallback
# can trigger — see _ocr_scanned_pdf(). Well past what a "PDF" normally
# means in this app (a document, not a scanned book); a huge scan is
# better served by whatever text its first pages have than by an
# unbounded per-page API bill.
_MAX_OCR_PDF_PAGES = 30


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
    and, when given, powers the best-effort tagging and entity-extraction
    steps, see `_attach_tags`/`_attach_entities` — `tags`/`item_tags` and
    `entities`/`item_entities` need an explicit owner (requirements doc,
    section 8-12, 44-48), unlike every other table this pipeline writes
    to, which infers ownership from the item itself.
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
            if not raw_text.strip():
                # No text layer at all — a scanned/image-only PDF
                # (requirements doc, section 15; see docs/roadmap.md,
                # Faz 10c). Rather than failing the item outright, OCR
                # each page through the same vision call a photo
                # already gets.
                raw_text = await _ocr_scanned_pdf(pdf_bytes, provider)
        elif item_type == "document":
            # "Upload Document" (requirements doc, section 13), broadened
            # past PDF-only in Faz 10c (see docs/roadmap.md) — .docx/.txt
            # today, routed by extract_document_text() itself.
            storage_path = item.get("storage_path")
            if not storage_path:
                raise ValueError("Document item has no storage_path.")
            document_bytes = await repo.download_file(storage_path)
            raw_text = extract_document_text(
                document_bytes, item.get("mime_type"), item.get("original_filename")
            )
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
            exif_data = extract_exif_metadata(image_bytes)

            # AI-generated title/description replace the filename-based
            # placeholder set at upload time (requirements doc, section 14);
            # EXIF location/capture time (section 8-12) is `None` for most
            # photos (screenshots, downloaded images, location off) and
            # that's fine — it's optional metadata, not a failure.
            await repo.update_item_metadata(
                item_id,
                title=analysis["title"],
                description=description,
                latitude=exif_data["latitude"],
                longitude=exif_data["longitude"],
                captured_at=exif_data["captured_at"],
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
            entities = await extract_entities(text, provider)
            await _attach_entities(item_id, user_id, entities, repo)

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
    finally:
        # `repo` is constructed fresh per call (see api/ai/routes.py) and
        # never reused afterward — this is the one place responsible for
        # releasing its HTTP connection (see SupabaseRestRepository.aclose).
        await repo.aclose()


async def _ocr_scanned_pdf(pdf_bytes: bytes, provider: AIProvider) -> str:
    """OCR fallback for a PDF with no text layer (see the PDF branch
    above) — rasterizes each page and runs it through the same vision
    call a photo already gets (`vision_service.analyze_image`), keeping
    only its `ocr_text`. A scanned page isn't a photo, so its `title`/
    `description`/`tags` are simply discarded here rather than reused
    for anything — this is one vision call per page either way, and
    splitting OCR into its own cheaper provider call is a bigger change
    than reusing what already exists.
    """
    page_images = render_pdf_pages_to_images(pdf_bytes, max_pages=_MAX_OCR_PDF_PAGES)
    page_texts: list[str] = []
    for page_bytes in page_images:
        analysis = await analyze_image(page_bytes, "image/png", provider)
        page_text = extract_ocr_text(analysis)
        if page_text.strip():
            page_texts.append(page_text)
    return "\n\n".join(page_texts)


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


async def _attach_entities(
    item_id: str,
    user_id: str,
    entities: list[dict[str, str]],
    repo: SupabaseRestRepository,
) -> None:
    """Best-effort, same contract as `_attach_tags`."""
    try:
        await repo.attach_entities(item_id, user_id, entities)
    except Exception as error:
        logger.warning("entity attach failed", extra={"item_id": item_id, "error": str(error)})
