"""Re-embeds chunks left behind by a provider/model switch. User-triggered
only (a Settings button) to avoid a surprise bulk AI-cost spike, and scoped
to embeddings only — chunk content/boundaries are untouched and not re-run.
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
    """Returns how many items were re-embedded. Best-effort per item, so one
    item's failure doesn't stop the rest. Doesn't touch items.processing_status
    — this is a quiet maintenance pass, not a user-visible reprocess.
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
        return

    contents = [chunk["content"] for chunk in chunks]
    embeddings = await embed_chunks(contents, provider)

    # Needed so replace_chunks' "still the item's latest job" gate
    # (0015_replace_chunks_atomic.sql) can serialize against a concurrent reprocess.
    job_id = await repo.create_job(item_id, job_type="reembed")

    chunk_rows = [
        {
            "chunk_index": chunk["chunk_index"],
            "content": chunk["content"],
            "embedding": format_embedding_literal(embedding),
            # Carried over as-is — this refreshes embeddings, not chunk metadata.
            "metadata": chunk.get("metadata") or {},
            "embedding_provider": provider.provider_name,
            "embedding_model": provider.embedding_model,
        }
        for chunk, embedding in zip(chunks, embeddings, strict=True)
    ]
    await repo.replace_chunks(item_id, job_id, chunk_rows)
