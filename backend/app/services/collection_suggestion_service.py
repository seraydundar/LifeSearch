"""Smart Collections suggestion: cluster not-yet-collected items by embedding
similarity (`item_similarity_pairs`, computed in SQL), then name each cluster.
Naming needs an AI provider; clustering doesn't, and degrades to a plain
type-based name when no provider is configured.
"""

import asyncio
from typing import Any

from ..repositories.search_repository import SearchRepository
from .ai_provider import AIProvider

_TYPE_LABELS = {
    "note": "Not",
    "image": "Görsel",
    "screenshot": "Screenshot",
    "pdf": "PDF",
    "audio": "Ses",
    "url": "Link",
    "document": "Belge",
}


class _UnionFind:
    """Groups items connected directly or transitively (A~B~C -> one cluster)."""

    def __init__(self) -> None:
        self._parent: dict[str, str] = {}

    def find(self, x: str) -> str:
        self._parent.setdefault(x, x)
        while self._parent[x] != x:
            self._parent[x] = self._parent[self._parent[x]]  # path halving
            x = self._parent[x]
        return x

    def union(self, a: str, b: str) -> None:
        root_a, root_b = self.find(a), self.find(b)
        if root_a != root_b:
            self._parent[root_a] = root_b


def _cluster(pairs: list[dict[str, Any]]) -> list[dict[str, dict[str, Any]]]:
    uf = _UnionFind()
    meta: dict[str, dict[str, Any]] = {}

    for pair in pairs:
        item_a, item_b = pair["item_a"], pair["item_b"]
        meta[item_a] = {"title": pair["item_a_title"], "type": pair["item_a_type"]}
        meta[item_b] = {"title": pair["item_b_title"], "type": pair["item_b_type"]}
        uf.union(item_a, item_b)

    groups: dict[str, dict[str, dict[str, Any]]] = {}
    for item_id in meta:
        groups.setdefault(uf.find(item_id), {})[item_id] = meta[item_id]
    return list(groups.values())


def _fallback_name(items: dict[str, dict[str, Any]]) -> str:
    """No AI provider, or it failed — a plain name beats no suggestion."""
    type_counts: dict[str, int] = {}
    for item in items.values():
        type_counts[item["type"]] = type_counts.get(item["type"], 0) + 1
    dominant = max(type_counts, key=lambda t: type_counts[t])
    label = _TYPE_LABELS.get(dominant, dominant)
    return f"{label} Grubu ({len(items)})"


async def _named_via_ai(items: dict[str, dict[str, Any]], provider: AIProvider) -> str | None:
    titles = [item["title"] for item in items.values() if item["title"]]
    if not titles:
        return None
    prompt = (
        "Aşağıdaki başlıklar birbirine anlamca yakın içerikler. Bunları "
        "kapsayan, en fazla 4 kelimelik kısa bir Türkçe koleksiyon adı "
        "öner. Sadece adı yaz, başka bir şey yazma.\n\n"
        + "\n".join(f"- {title}" for title in titles[:10])
    )
    try:
        name = await provider.generate_text(prompt)
    except Exception:
        return None
    return name.strip().strip('"').strip("'") or None


async def suggest_collections(
    repo: SearchRepository,
    provider: AIProvider | None,
    *,
    similarity_threshold: float = 0.75,
    min_group_size: int = 3,
) -> list[dict[str, Any]]:
    """Clusters smaller than `min_group_size` are dropped — a mere pair is
    already covered by "Related items".
    """
    pairs = await repo.item_similarity_pairs(similarity_threshold=similarity_threshold)
    clusters = [c for c in _cluster(pairs) if len(c) >= min_group_size]

    # Run naming calls concurrently; gather() keeps results aligned with clusters.
    if provider is not None:
        names = await asyncio.gather(*(_named_via_ai(c, provider) for c in clusters))
    else:
        names = [None] * len(clusters)

    return [
        {
            "suggested_name": name or _fallback_name(cluster),
            "items": [
                {"item_id": item_id, "title": meta["title"], "item_type": meta["type"]}
                for item_id, meta in cluster.items()
            ],
        }
        for cluster, name in zip(clusters, names, strict=True)
    ]
