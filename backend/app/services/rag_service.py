"""RAG: question -> embedding -> semantic_search (reused as-is, so reranking
comes for free) -> LLM answer grounded only in the retrieved sources.
"""

import re
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
    "Always state the actual answer yourself, using what the source says — "
    "never tell the user to go read a source themselves instead of "
    "answering; that is not an answer. Answer in Turkish, concisely, in a "
    "few sentences."
)

_CITATION_RE = re.compile(r"\[Kaynak (\d+)\]")


def _cited_sources(answer: str, matches: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Filters matches to only the ones [Kaynak N] actually cites (1-indexed,
    keeping `matches`' relevance order), so unrelated retrieved items don't show
    as sources; falls back to all matches if the answer cites nothing at all.
    """
    cited = {int(n) for n in _CITATION_RE.findall(answer)}
    if not cited:
        return matches
    return [match for i, match in enumerate(matches, start=1) if i in cited]

_NO_SOURCES_ANSWER = "Arşivinde bu soruyla ilgili bir şey bulamadım."

# Caps replayed history so a long chat doesn't grow every prompt's token cost.
_MAX_HISTORY_TURNS = 10


def _format_history(history: list[dict[str, str]]) -> str:
    speaker_labels = {"user": "Kullanıcı", "assistant": "Asistan"}
    lines = [
        f"{speaker_labels.get(turn['role'], turn['role'])}: {turn['text']}"
        for turn in history[-_MAX_HISTORY_TURNS:]
    ]
    return "\n".join(lines)


async def answer_question(
    question: str,
    repo: SearchRepository,
    provider: AIProvider,
    *,
    limit: int = 8,
    history: list[dict[str, str]] | None = None,
) -> dict[str, Any]:
    """`history` (oldest first) is replayed into the prompt, not into the
    retrieval query itself — so a follow-up like "peki onun boyu?" still
    searches on just those words, while the model resolves "onun" from history.
    """
    # No include_private: chat has no device-level private reveal like Search does.
    matches = await semantic_search(question, repo, provider, limit=limit)

    if not matches:
        return {"answer": _NO_SOURCES_ANSWER, "sources": []}

    context = "\n\n---\n\n".join(
        f"[Kaynak {i + 1}] ({match['item_type']}, "
        f"{match.get('item_title') or 'Untitled'}):\n{match['content']}"
        for i, match in enumerate(matches)
    )
    history_section = f"Önceki konuşma:\n{_format_history(history)}\n\n" if history else ""
    prompt = f"{history_section}Kaynaklar:\n\n{context}\n\nSoru: {question}"

    answer = await provider.generate_text(prompt, system=_SYSTEM_PROMPT)
    return {"answer": answer, "sources": _cited_sources(answer, matches)}
