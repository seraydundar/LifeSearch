"""Re-embeds chunks left behind by a provider/model switch (P3, docs/
requirements-audit-2026-09-13.md: "sağlayıcı değişiminde eski vektörlerin
yeniden indekslenmesini yönet").

User-triggered only (a Settings button — see `POST /ai/reprocess-stale-
embeddings` in api/ai/routes.py) rather than automatic: bulk re-embedding
an entire archive is exactly the kind of AI-cost spike that should never
happen without the user asking for it.

Scoped to embeddings only, not the whole pipeline: an affected chunk's
own content (its OCR/PDF/transcript text, its page_number metadata, ...)
never changed, only which vector space it lives in — re-running vision/
Whisper/tagging for every affected item would be needlessly expensive
and could also silently change tags/entities the user never asked to
touch. Chunk boundaries themselves aren't recomputed either, for the
same reason.
"""

import logging
from typing import Any, Protocol

from .ai_provider import AIProvider
from .embedding_service import embed_chunks, format_embedding_literal

logger = logging.getLogger(__name__)


class _ReembeddingRepo(Protocol):
    async def find_stale_chunk_item_ids(
        self, current_provider: str, current_embedding_model: str
    ) -> list[str]: ...
    async def get_chunks_for_item(self, item_id: str) -> list[dict[str, Any]]: ...
    async def create_job(self, item_id: str, job_type: str) -> str: ...
    async def replace_chunks(
        self, item_id: str, job_id: str, chunks: list[dict[str, Any]]
    ) -> None: ...


async def reembed_stale_items(repo: _ReembeddingRepo, provider: AIProvider) -> int:
    """Returns how many items were actually re-embedded. Best-effort per
    item, same contract as `_check_for_duplicate`/`_attach_tags` in
    `processing_pipeline.py`: one item's transient failure (a provider
    hiccup) shouldn't stop every other stale item from being fixed.

    Deliberately doesn't touch `items.processing_status` or create a
    "processing" state the mobile app would poll for — a chunk's own
    content didn't change, so from the item's point of view nothing
    user-visible did either; this is a quiet maintenance pass, not a
    reprocessing run.
    """
    item_ids = await repo.find_stale_chunk_item_ids(
        provider.provider_name, provider.embedding_model
    )
    reembedded = 0
    for item_id in item_ids:
        try:
            await _reembed_item(item_id, repo, provider)
            reembedded += 1
        except Exception as error:
            logger.warning(
                "re-embedding failed", extra={"item_id": item_id, "error": str(error)}
            )
    return reembedded


async def _reembed_item(item_id: str, repo: _ReembeddingRepo, provider: AIProvider) -> None:
    chunks = await repo.get_chunks_for_item(item_id)
    if not chunks:
        return  # nothing to re-embed — an item mid-reprocessing elsewhere, say

    contents = [chunk["content"] for chunk in chunks]
    embeddings = await embed_chunks(contents, provider)

    # A fresh job, same as a normal reprocess — replace_chunks_for_job's
    # own "still the item's latest job" gate (0015_replace_chunks_atomic.sql)
    # needs one to serialize safely against a concurrent real reprocess of
    # the same item (e.g. the user hits "Tekrar Dene" mid-sweep).
    job_id = await repo.create_job(item_id, job_type="reembed")

    chunk_rows = [
        {
            "chunk_index": chunk["chunk_index"],
            "content": chunk["content"],
            "embedding": format_embedding_literal(embedding),
            # Untouched — this is an embedding refresh, not a re-chunk;
            # an existing page_number (P3's other chunk-metadata addition)
            # must survive it.
            "metadata": chunk.get("metadata") or {},
            "embedding_provider": provider.provider_name,
            "embedding_model": provider.embedding_model,
        }
        for chunk, embedding in zip(chunks, embeddings, strict=True)
    ]
    await repo.replace_chunks(item_id, job_id, chunk_rows)
