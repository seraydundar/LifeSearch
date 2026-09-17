from app.services.chunking_service import chunk_pages, chunk_text


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
    # Regression guard: this used to pass even with zero real overlap,
    # because every paragraph here reuses the same handful of words
    # ("Sentence", "about", "topic") — checking that *some* word from the
    # tail shows up *anywhere* in the next chunk passed trivially whether
    # or not an actual suffix carried over. Asserting the exact tail is a
    # literal prefix of the next chunk is what the docstring's "starts the
    # next one with a small overlap from its tail" actually promises.
    tail_of_first = chunks[0][-40:].strip()
    assert chunks[1].startswith(tail_of_first)


# P3 (docs/requirements-audit-2026-09-13.md): chunk_pages() is chunk_text()
# applied per page, with each resulting chunk tagged with its page number —
# used only by the PDF branch of processing_pipeline.py.
class TestChunkPages:
    def test_tags_each_chunk_with_its_1_based_page_number(self):
        pages = ["Page one content.", "Page two content.", "Page three content."]

        result = chunk_pages(pages)

        assert result == [
            ("Page one content.", 1),
            ("Page two content.", 2),
            ("Page three content.", 3),
        ]

    def test_an_empty_page_contributes_no_chunks_but_does_not_shift_page_numbers(self):
        pages = ["Page one.", "", "Page three."]

        result = chunk_pages(pages)

        assert result == [("Page one.", 1), ("Page three.", 3)]

    def test_a_page_longer_than_the_target_still_becomes_multiple_chunks_of_that_page(self):
        pages = ["short page", "word " * 400]  # second page ~2000 chars

        result = chunk_pages(pages, target_chars=500, overlap_chars=50)

        page_numbers = [page for _, page in result]
        assert page_numbers[0] == 1
        assert len(result) > 2  # the long second page alone splits into several chunks
        assert all(page == 2 for page in page_numbers[1:])

    def test_two_short_pages_are_never_packed_into_one_chunk_unlike_chunk_text(self):
        # chunk_text() alone would pack these two short paragraphs into a
        # single chunk — chunk_pages() must not, since that would make the
        # resulting chunk's page_number ambiguous.
        pages = ["Short page one.", "Short page two."]

        result = chunk_pages(pages, target_chars=800)

        assert result == [("Short page one.", 1), ("Short page two.", 2)]
