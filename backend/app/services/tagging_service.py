"""Tags for non-image items; images already get tags from analyze_image()'s vision call."""

from .ai_provider import AIProvider


async def generate_tags(text: str, provider: AIProvider, *, max_tags: int = 5) -> list[str]:
    """Best-effort: failures return [] rather than failing the item's processing."""
    if not text.strip():
        return []

    prompt = (
        f"Aşağıdaki metne uygun en fazla {max_tags} kısa Türkçe etiket öner "
        "(tek kelime veya çok kısa öbek). Sadece etiketleri virgülle "
        "ayırarak yaz, başka hiçbir şey yazma.\n\n"
        f"{text[:2000]}"
    )
    try:
        response = await provider.generate_text(prompt)
    except Exception:
        return []

    candidates = (t.strip().lower() for t in response.replace("\n", ",").split(","))
    # dict.fromkeys dedupes while preserving order; set() would shuffle it.
    tags = [t for t in dict.fromkeys(candidates) if t]
    return tags[:max_tags]
