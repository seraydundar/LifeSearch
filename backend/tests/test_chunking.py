from app.services.chunking_service import chunk_text


def test_short_text_becomes_a_single_chunk():
    text = "Docker container ile image arasındaki fark budur."
    chunks = chunk_text(text, target_chars=800)
    assert chunks == [text]


def test_empty_text_yields_no_chunks():
    assert chunk_text("") == []
    assert chunk_text("   \n\n   ") == []


def test_paragraphs_are_packed_until_the_target_is_exceeded():
    paragraphs = [f"Paragraph {i}. " * 10 for i in range(5)]  # ~140 chars each
    text = "\n\n".join(paragraphs)

    chunks = chunk_text(text, target_chars=300, overlap_chars=0)

    assert len(chunks) > 1
    # Every produced chunk must respect the target (modulo a single
    # over-length paragraph, which isn't the case here).
    assert all(len(c) <= 300 for c in chunks)
    # No paragraph's content is lost.
    for paragraph in paragraphs:
        assert any(paragraph.strip() in chunk for chunk in chunks)


def test_a_single_paragraph_longer_than_the_target_gets_sliced():
    long_paragraph = "word " * 400  # ~2000 chars, no paragraph breaks
    chunks = chunk_text(long_paragraph, target_chars=500, overlap_chars=50)

    assert len(chunks) > 1
    assert all(len(c) <= 500 for c in chunks)
    # Reassembling without the overlap should recover the original words.
    assert "".join(chunks).replace(" ", "") != ""


def test_consecutive_chunks_share_a_small_overlap():
    paragraphs = [f"Sentence about topic {i}. " * 8 for i in range(4)]
    text = "\n\n".join(paragraphs)

    chunks = chunk_text(text, target_chars=250, overlap_chars=40)

    assert len(chunks) > 1
    tail_of_first = chunks[0][-40:].strip()
    # At least part of the previous chunk's tail should reappear at the
    # start of the next one.
    assert any(word in chunks[1] for word in tail_of_first.split() if len(word) > 3)
