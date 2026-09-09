"""AI-extracted named entities (requirements doc, section 44-48: "entity
extraction") — people, places, organizations, and dates mentioned in an
item's content. Complements tags (generic, free-text) with structured,
typed data — the same content an item is already being tagged from, just
asked a different question of.
"""

from .ai_provider import AIProvider

_VALID_TYPES = {"person", "place", "organization", "date"}


async def extract_entities(
    text: str, provider: AIProvider, *, max_entities: int = 10
) -> list[dict[str, str]]:
    """Best-effort by design — same contract as `generate_tags`: a
    failure here should never be a reason to fail the item's own
    processing.

    Returns up to `max_entities` `{"name": ..., "type": ...}` dicts,
    `type` one of 'person' | 'place' | 'organization' | 'date'. A
    line-based "type: name" format is used instead of JSON — same choice
    `generate_tags` made for its comma-separated format: one malformed
    line just gets skipped, instead of one stray character anywhere in
    the response throwing away the whole response the way a JSON parse
    failure would.
    """
    if not text.strip():
        return []

    prompt = (
        f"Aşağıdaki metinden en fazla {max_entities} varlık (entity) çıkar: "
        "kişi adları, yer adları, kurum/organizasyon adları ve tarihler. "
        "Her satıra bir tane olacak şekilde 'tür: ad' biçiminde yaz (tür "
        "şunlardan biri olmalı: person, place, organization, date). Başka "
        "hiçbir şey yazma, açıklama ekleme.\n\n"
        "Örnek:\nperson: Ahmet Yılmaz\nplace: İstanbul\ndate: 15 Ocak 2026\n\n"
        f"{text[:2000]}"
    )
    try:
        response = await provider.generate_text(prompt)
    except Exception:
        return []

    # dict preserves first-seen order and first-seen casing while deduping
    # case-insensitively on (name, type) — same reasoning as generate_tags.
    seen: dict[tuple[str, str], str] = {}
    for line in response.splitlines():
        if ":" not in line:
            continue
        entity_type, _, name = line.partition(":")
        entity_type = entity_type.strip().lower()
        name = name.strip()
        if not name or entity_type not in _VALID_TYPES:
            continue
        seen.setdefault((name.lower(), entity_type), name)

    entities = [
        {"name": name, "type": entity_type} for (_, entity_type), name in seen.items()
    ]
    return entities[:max_entities]
