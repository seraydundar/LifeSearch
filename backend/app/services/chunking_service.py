"""Splits text into embedding-sized chunks, paragraph-aware: packs whole
paragraphs up to `target_chars` and only cuts inside one that alone exceeds it.
"""

DEFAULT_TARGET_CHARS = 800
DEFAULT_OVERLAP_CHARS = 100


def chunk_text(
    text: str,
    *,
    target_chars: int = DEFAULT_TARGET_CHARS,
    overlap_chars: int = DEFAULT_OVERLAP_CHARS,
) -> list[str]:
    paragraphs = [p.strip() for p in text.split("\n\n") if p.strip()]
    if not paragraphs:
        return []

    chunks: list[str] = []
    buffer = ""

    def flush() -> None:
        nonlocal buffer
        stripped = buffer.strip()
        if stripped:
            chunks.append(stripped)
        buffer = ""

    for paragraph in paragraphs:
        # Flush the buffer first so an oversized paragraph doesn't split it apart.
        if len(paragraph) > target_chars:
            flush()
            chunks.extend(_slice_long_paragraph(paragraph, target_chars, overlap_chars))
            continue

        candidate = f"{buffer}\n\n{paragraph}" if buffer else paragraph
        if len(candidate) <= target_chars:
            buffer = candidate
            continue

        # Grab overlap before flush() clears buffer (grabbing it after was the bug).
        overlap = buffer[-overlap_chars:] if overlap_chars else ""
        flush()
        buffer = f"{overlap}\n\n{paragraph}".strip() if overlap else paragraph

    flush()
    return chunks


def chunk_pages(
    pages: list[str],
    *,
    target_chars: int = DEFAULT_TARGET_CHARS,
    overlap_chars: int = DEFAULT_OVERLAP_CHARS,
) -> list[tuple[str, int]]:
    """Like `chunk_text`, but per-page (PDFs), tagging each chunk with its
    1-based page number. Chunks never straddle a page boundary, so the page
    number is always exact, at the cost of occasional smaller chunks.
    """
    return [
        (chunk, page_number)
        for page_number, page_text in enumerate(pages, start=1)
        for chunk in chunk_text(page_text, target_chars=target_chars, overlap_chars=overlap_chars)
    ]


def _slice_long_paragraph(paragraph: str, target_chars: int, overlap_chars: int) -> list[str]:
    slices: list[str] = []
    start = 0
    length = len(paragraph)
    while start < length:
        end = min(start + target_chars, length)
        slices.append(paragraph[start:end].strip())
        if end == length:
            break
        start = end - overlap_chars if overlap_chars < target_chars else end
    return [s for s in slices if s]
