"""Thin wrapper over `AIProvider.generate_embeddings` so the pipeline never
calls the provider directly.
"""

from .ai_provider import AIProvider


async def embed_chunks(chunks: list[str], provider: AIProvider) -> list[list[float]]:
    return await provider.generate_embeddings(chunks)


def format_embedding_literal(embedding: list[float]) -> str:
    """pgvector's REST insert path needs a text literal, not a JSON array —
    Postgres has no json->vector cast, only text->vector.
    """
    return "[" + ",".join(repr(v) for v in embedding) + "]"
