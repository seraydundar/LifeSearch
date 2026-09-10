"""Splits normalized text into embedding-sized chunks (requirements doc,
section 42). Paragraph-aware: packs whole paragraphs together up to
`target_chars`, and only cuts inside a paragraph when that paragraph alone
exceeds the target — so a chunk boundary lands between ideas, not
mid-sentence, whenever the source text allows it.
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
        # A single paragraph bigger than the target gets sliced on its own,
        # with the running buffer flushed first so it isn't split apart.
        if len(paragraph) > target_chars:
            flush()
            chunks.extend(_slice_long_paragraph(paragraph, target_chars, overlap_chars))
            continue

        candidate = f"{buffer}\n\n{paragraph}" if buffer else paragraph
        if len(candidate) <= target_chars:
            buffer = candidate
            continue

        # Adding this paragraph would overflow — grab a small overlap from
        # the current buffer's tail *before* closing it out (flush() resets
        # buffer to "", so computing this after flush() would always yield
        # an empty overlap — that was the bug here), so a concept spanning
        # the boundary still appears in both chunks.
        overlap = buffer[-overlap_chars:] if overlap_chars else ""
        flush()
        buffer = f"{overlap}\n\n{paragraph}".strip() if overlap else paragraph

    flush()
    return chunks


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
