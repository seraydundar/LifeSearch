"""Orchestrates the AI pipeline (requirements doc, section 41):

    INPUT (note | pdf | image | screenshot) -> CONTENT EXTRACTION
        -> NORMALIZED TEXT -> CHUNKS -> EMBEDDINGS -> VECTOR DB

Runs as a FastAPI background task (see api/ai/routes.py) so the mobile
app's request returns immediately — the item's `processing_status` and a
`processing_jobs` row are what the client polls/watches instead
(requirements doc, section 12).
"""

import logging
from collections.abc import Callable

from ..repositories.items_repository import SupabaseRestRepository
from .ai_provider import AIProvider
from .chunking_service import chunk_text
from .document_service import extract_pdf_text, normalize_text
from .embedding_service import embed_chunks, format_embedding_literal
from .ocr_service import extract_text as extract_ocr_text
from .vision_service import analyze_image

logger = logging.getLogger(__name__)

# Audio/URL extraction (Phase 8) is the only thing still missing its own
# step ahead of the shared chunk/embed tail below.
SUPPORTED_TYPES = {"note", "pdf", "image", "screenshot"}


class UnsupportedItemType(Exception):
    pass


async def process_item(
    item_id: str,
    repo: SupabaseRestRepository,
    get_provider: Callable[[], AIProvider],
) -> None:
    """`get_provider` is resolved *inside* the try block, deliberately —
    a missing API key or bad AI_PROVIDER config is exactly the kind of
    failure this should report on the item/job (requirements doc, rule
    15), not crash the request that kicked processing off.
    """
    job_id = await repo.create_job(item_id, job_type="chunk_and_embed")

    try:
        await repo.mark_job_started(job_id)
        await repo.update_item_status(item_id, "processing")

        provider = get_provider()
        item = await repo.get_item(item_id)
        item_type = item["type"]
        if item_type not in SUPPORTED_TYPES:
            raise UnsupportedItemType(f"Processing for type '{item_type}' isn't implemented yet.")

        if item_type == "note":
            raw_text = await repo.get_note_content(item_id)
        elif item_type == "pdf":
            storage_path = item.get("storage_path")
            if not storage_path:
                raise ValueError("PDF item has no storage_path.")
            pdf_bytes = await repo.download_file(storage_path)
            raw_text = extract_pdf_text(pdf_bytes)
        else:  # image | screenshot
            storage_path = item.get("storage_path")
            if not storage_path:
                raise ValueError("Image item has no storage_path.")
            image_bytes = await repo.download_file(storage_path)
            mime_type = item.get("mime_type") or "image/jpeg"

            analysis = await analyze_image(image_bytes, mime_type, provider)
            ocr_text = extract_ocr_text(analysis)
            description = analysis["description"]

            # AI-generated title/description replace the filename-based
            # placeholder set at upload time (requirements doc, section 14).
            await repo.update_item_metadata(
                item_id, title=analysis["title"], description=description
            )
            await repo.replace_item_content(
                item_id, raw_text=description, ocr_text=ocr_text, ai_description=description
            )
            raw_text = f"{description}\n\n{ocr_text}".strip()

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

        await repo.update_item_status(item_id, "completed")
        await repo.mark_job_completed(job_id)
    except Exception as error:
        # Never log `text`/chunk content — only identifiers and the error
        # itself (requirements doc, section 53).
        logger.warning("processing failed for item_id=%s: %s", item_id, error)
        await repo.update_item_status(item_id, "failed")
        await repo.mark_job_failed(job_id, str(error))
