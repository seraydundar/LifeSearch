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

# Bounds the number of (paid) vision calls one PDF's OCR fallback can
# trigger — see _ocr_missing_pdf_pages(). Counts only pages that actually
# need OCR (P2-04, docs/requirements-audit-2026-09-13.md), not every page
# in the document — well past what a "PDF" normally means in this app (a
# document, not a scanned book); a huge scan is better served by whatever
# text its first pages have than by an unbounded per-page API bill.
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

    `job_id` is created by the caller (see `api/ai/routes.py`), not here
    (P1-05, docs/requirements-audit-2026-09-13.md) — it used to be
    created as this function's first line, but this function only ever
    runs as a `BackgroundTasks` callback, which FastAPI starts *after*
    the "202 accepted" response is already on the wire. A process death
    in that gap (a deploy, an OOM kill) used to leave nothing behind at
    all: no `processing_jobs` row for `job_recovery.py`'s startup sweep
    to find, no way to tell the accepted-but-never-actually-started
    request apart from one silently lost. Creating the job before the
    response is sent means a request that got "202 accepted" always has
    a durable, recoverable row from that moment on.
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
            # Per-page, not whole-document (P2-04, docs/requirements-audit-
            # 2026-09-13.md): a PDF where only *some* pages are scanned
            # images (e.g. a signed page scanned back into an otherwise
            # text-based document) used to get no OCR at all — the old
            # check only ran OCR when literally every page came back
            # empty. See _ocr_missing_pdf_pages()'s own docstring. Kept as
            # a per-page list (not joined into one string yet) so the
            # chunking step below can tag each chunk with the page it
            # actually came from (P3, docs/requirements-audit-2026-09-13.md).
            page_texts = await _ocr_missing_pdf_pages(pdf_bytes, provider)
            raw_text = "\n\n".join(text for text in page_texts if text)
            # P2-05 (docs/requirements-audit-2026-09-13.md): every other
            # non-note type (image/audio/url) already saves its extracted
            # text to `item_contents` — PDF never did, so there was no
            # way to see or reuse a PDF's actual extracted text outside
            # of the chunks it got split into.
            await repo.replace_item_content(item_id, job_id, raw_text=raw_text)
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
            # Same P2-05 fix as the PDF branch above.
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

            # AI-generated title/description replace the filename-based
            # placeholder set at upload time (requirements doc, section 14);
            # EXIF location/capture time (section 8-12) is `None` for most
            # photos (screenshots, downloaded images, location off) and
            # that's fine — it's optional metadata, not a failure.
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
                # "LLM metadata extraction" (requirements doc, section 18) —
                # a short title beats the recording's generic filename.
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
            # Page-aware chunking (P3, docs/requirements-audit-2026-09-13.md):
            # a PDF is the one content type with an actual page concept, so
            # its chunks carry a page_number — everything else has no pages
            # to speak of. See chunk_pages()'s own docstring for why this
            # chunks per page rather than the whole joined document.
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
                # P3 (docs/requirements-audit-2026-09-13.md): which
                # AI_PROVIDER/model actually produced this vector — lets a
                # later switch tell exactly which chunks now live in a
                # stale, incomparable embedding space. See
                # reembedding_service.py, the on-request fix for that.
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
        await repo.update_item_status(item_id, job_id, "failed")
        await repo.mark_job_failed(job_id, str(error))
    finally:
        # `repo` is constructed fresh per call (see api/ai/routes.py) and
        # never reused afterward — this is the one place responsible for
        # releasing its HTTP connection (see SupabaseRestRepository.aclose).
        await repo.aclose()


async def _ocr_missing_pdf_pages(pdf_bytes: bytes, provider: AIProvider) -> list[str]:
    """Extracts each page's text layer, then OCRs — through the same
    vision call a photo already gets (`vision_service.analyze_image`),
    keeping only its `ocr_text` — exactly the pages that came back empty
    (P2-04, docs/requirements-audit-2026-09-13.md). Per-page, not "OCR
    the whole document if *any* page lacks text": a PDF with a text layer
    on most pages but one or two scanned ones (e.g. a signed page
    scanned back in) used to get zero OCR for those pages, since the old
    check only ever ran when the *entire* document came back empty.

    Returns one entry per page (empty string for a page with nothing
    extractable even after OCR) rather than a single joined string — kept
    as a list, not flattened here, so the caller can both join it for
    `item_contents.raw_text` *and* feed it to `chunk_pages()` for P3's
    page-numbered chunk metadata (docs/requirements-audit-2026-09-13.md),
    which needs the page boundaries a flattened string would have lost.

    A scanned page isn't a photo, so its `title`/`description`/`tags`
    are simply discarded here rather than reused for anything — this is
    one vision call per page either way, and splitting OCR into its own
    cheaper provider call is a bigger change than reusing what already
    exists.

    Bounded at `_MAX_OCR_PDF_PAGES` pages actually needing OCR — a page
    past that limit is silently left blank rather than failing the whole
    item, same tradeoff the old whole-document version made (just scoped
    to the pages that need it, not the document's total page count).
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
    """Best-effort (requirements doc, section 46): this only ever *flags*
    a possible duplicate for the user to review, so a failure here should
    never fail the item's own processing job.
    """
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
    """Best-effort, same contract as `_check_for_duplicate` — tags are a
    nice-to-have on top of a working item, never a reason to fail one.
    """
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
