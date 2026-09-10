"""Retrieval-Augmented Generation (requirements doc, sections 23-24):

    User question -> Query embedding -> Vector Search -> Relevant chunks
        -> LLM -> Answer (+ the sources it came from)

Reuses Phase 5's `semantic_search` for the retrieval half — RAG is
"search, then hand the results to an LLM," not a separate lookup path.
That also means it gets reranking (section 65) for free: the sources an
answer is grounded in are exactly what `/search/` would have shown, in
the same LLM-reordered relevance order. The system prompt is deliberately
strict about not answering from outside the given sources, so the
assistant doesn't fabricate facts that aren't in the user's own archive.
"""

from typing import Any

from ..repositories.search_repository import SearchRepository
from .ai_provider import AIProvider
from .search_service import semantic_search

_SYSTEM_PROMPT = (
    "You are LifeSearch's assistant. You answer questions using ONLY the "
    "numbered sources below, each pulled from the user's own personal "
    "archive (notes, PDFs, photos). Never use outside knowledge. If the "
    "sources don't actually answer the question, say so plainly instead "
    "of guessing. When you use a source, refer to it inline as [Kaynak N]. "
    "Answer in Turkish, concisely, in a few sentences."
)

_NO_SOURCES_ANSWER = "Arşivinde bu soruyla ilgili bir şey bulamadım."


async def answer_question(
    question: str,
    repo: SearchRepository,
    provider: AIProvider,
    *,
    limit: int = 8,
) -> dict[str, Any]:
    matches = await semantic_search(question, repo, provider, limit=limit)

    if not matches:
        # Nothing to ground an answer in — don't spend a completion call
        # only to have the model (correctly) say the same thing.
        return {"answer": _NO_SOURCES_ANSWER, "sources": []}

    context = "\n\n---\n\n".join(
        f"[Kaynak {i + 1}] ({match['item_type']}, "
        f"{match.get('item_title') or 'Untitled'}):\n{match['content']}"
        for i, match in enumerate(matches)
    )
    prompt = f"Kaynaklar:\n\n{context}\n\nSoru: {question}"

    answer = await provider.generate_text(prompt, system=_SYSTEM_PROMPT)
    return {"answer": answer, "sources": matches}
