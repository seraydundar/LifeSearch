"""AI-extracted named entities (requirements doc, section 44-48: "entity
extraction") — people, places, organizations, and dates mentioned in an
item's content. Complements tags (generic, free-text) with structured,
typed data — the same content an item is already being tagged from, just
asked a different question of.
"""

from .ai_provider import AIProvider

_VALID_TYPES = {
    "person",
    "place",
    "organization",
    "date",
    # P3 (docs/requirements-audit-2026-09-13.md): the original four types
    # left out anything commercial/technical — a note about a purchase or
    # a tool couldn't tag the thing itself as a structured entity, only as
    # a free-text tag. See 0020_entity_types_extend.sql for the matching
    # check constraint.
    "product",
    "price",
    "website",
    "technology",
}


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

    # P3 (docs/requirements-audit-2026-09-13.md): this used to end with a
    # few-shot example ("Örnek:\nperson: Ahmet Yılmaz\nplace: İstanbul...")
    # — realistic-looking values a weaker/local model could echo back as
    # if they were extracted from the actual input, instead of treating
    # them as a pure format illustration. Confirmed live: a flower-garden
    # photo (nothing resembling a person, date, or city anywhere in its
    # description) still came back tagged with "Cemil Kaya", a date, and
    # "İstanbul" — values that trace straight back to this example, not
    # the image. No example at all (same choice `generate_tags` already
    # made for its own, simpler format) plus an explicit anti-hallucination
    # instruction removes the thing being echoed, rather than just asking
    # the model more firmly not to echo it.
    prompt = (
        f"Aşağıdaki metinden en fazla {max_entities} varlık (entity) çıkar: "
        "kişi adları, yer adları, kurum/organizasyon adları, tarihler, "
        "ürün adları, fiyatlar, web sitesi/URL'ler ve teknoloji/araç adları "
        "(programlama dili, framework, kütüphane, yazılım ürünü). Her "
        "satıra bir tane olacak şekilde 'tür: ad' biçiminde yaz (tür "
        "şunlardan biri olmalı: person, place, organization, date, "
        "product, price, website, technology). Başka hiçbir şey yazma, "
        "açıklama ekleme.\n\n"
        "Yalnızca metinde GERÇEKTEN geçen varlıkları yaz — metinde "
        "bulunmayan hiçbir ismi, tarihi, yeri ya da kurumu uydurma. "
        "Metinde hiçbir varlık geçmiyorsa (örneğin yalnızca bir manzara "
        "ya da nesne açıklamasıysa) hiçbir satır yazma, tamamen boş "
        "bırak.\n\n"
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
