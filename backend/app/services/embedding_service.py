"""Thin wrapper over `AIProvider.generate_embeddings` — its own file so the
pipeline doesn't call the provider directly, matching the layering in
requirements doc, section 40.
"""

from .ai_provider import AIProvider


async def embed_chunks(chunks: list[str], provider: AIProvider) -> list[list[float]]:
    return await provider.generate_embeddings(chunks)


def format_embedding_literal(embedding: list[float]) -> str:
    """pgvector's REST/PostgREST insert path needs the value as its text
    literal (`"[0.1,0.2,...]"`), not a native JSON array — Postgres has no
    implicit json->vector cast, but it does have one from text.
    """
    return "[" + ",".join(repr(v) for v in embedding) + "]"
