"""AI-generated tags (requirements doc, section 8-12: `tags`/`item_tags` —
"kullanıcı ve AI tarafından üretilen etiketler"). Images already get tags
from `analyze_image()`'s vision call for free; this covers everything
else (note/pdf/audio/url), where a plain text-completion call does the
job just as well once the content's normalized text is available.
"""

from .ai_provider import AIProvider


async def generate_tags(text: str, provider: AIProvider, *, max_tags: int = 5) -> list[str]:
    """Best-effort by design — callers should treat a failure here the
    same as an empty result, never as a reason to fail the item's own
    processing (same pattern as duplicate detection).
    """
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
    # dict.fromkeys dedupes while keeping first-seen order — plain set()
    # would shuffle which tag order the user sees.
    tags = [t for t in dict.fromkeys(candidates) if t]
    return tags[:max_tags]
