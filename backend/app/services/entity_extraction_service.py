"""AI-extracted named entities — complements free-text tags with structured,
typed data (people, places, organizations, dates, ...) from the same content.
"""

from .ai_provider import AIProvider

_VALID_TYPES = {
    "person",
    "place",
    "organization",
    "date",
    # Must match the check constraint in 0020_entity_types_extend.sql.
    "product",
    "price",
    "website",
    "technology",
}


async def extract_entities(
    text: str, provider: AIProvider, *, max_entities: int = 10
) -> list[dict[str, str]]:
    """Best-effort, like generate_tags. Uses a line-based "type: name" format
    rather than JSON so one malformed line is skipped instead of breaking the
    whole response.
    """
    if not text.strip():
        return []

    # No few-shot example: a weaker model echoed a past example's fake names
    # back as "extracted" entities, so the prompt relies on the instruction below.
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

    # dedupe case-insensitively on (name, type), keep first-seen casing/order.
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
