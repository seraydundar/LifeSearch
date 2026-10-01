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
    """The mobile client's own contract for `sources` is "the archive
    items its answer actually came from" (see `chat_message.dart`) — but
    every retrieved/reranked match used to come back regardless of
    whether the answer's text ever cited it. A question about one note
    could show five unrelated photos as "sources" just because they'd
    been pulled into the prompt's context, never because the answer
    itself said anything about them (confirmed live: asking about a note
    mentioning Docker returned garden photos and an unrelated voice note
    alongside it, none of which the answer actually referenced).

    `[Kaynak N]` is 1-indexed in the prompt (`enumerate(matches, start=1)`
    below matches that). Filters to only the cited ones, keeping
    `matches`' own relevance order rather than citation-appearance order.
    If the answer cites nothing at all (a weaker model ignoring the
    instruction, or a plain "I don't know" with no citation) falls back
    to returning every match — hiding sources nobody confirmed are
    irrelevant would be a worse regression than the original bug.
    """
    cited = {int(n) for n in _CITATION_RE.findall(answer)}
    if not cited:
        return matches
    return [match for i, match in enumerate(matches, start=1) if i in cited]

_NO_SOURCES_ANSWER = "Arşivinde bu soruyla ilgili bir şey bulamadım."

# Bounds how much of the conversation gets replayed into the prompt on
# every turn (P2-03, docs/requirements-audit-2026-09-13.md) — a long-
# running chat shouldn't make every subsequent question cost more tokens
# than the last few turns' worth of context is actually likely to help
# with. Enforced here, not trusted to whatever the client sends.
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
    """`history` is the conversation so far (P2-03, docs/requirements-
    audit-2026-09-13.md), oldest first, each entry `{"role": "user" |
    "assistant", "text": ...}` — **not** included in the query embedded
    for retrieval (a follow-up like "peki onun boyu?" still only
    searches on those few words), only replayed into the prompt so the
    model itself can resolve what "onun" refers to. A question used to
    be answered with zero awareness that any previous turn existed.
    """
    # No `include_private` here, deliberately — chat has no device-level
    # private reveal concept the way Search does (Faz 13/14, P1-02, see
    # docs/requirements-audit-2026-09-13.md). A private item should never
    # enter the LLM context, revealed or not.
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
    history_section = f"Önceki konuşma:\n{_format_history(history)}\n\n" if history else ""
    prompt = f"{history_section}Kaynaklar:\n\n{context}\n\nSoru: {question}"

    answer = await provider.generate_text(prompt, system=_SYSTEM_PROMPT)
    return {"answer": answer, "sources": _cited_sources(answer, matches)}
