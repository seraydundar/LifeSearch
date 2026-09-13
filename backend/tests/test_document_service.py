import io
import zipfile

import pymupdf
import pytest

from app.services.document_service import (
    extract_document_text,
    extract_pdf_text_per_page,
    normalize_text,
    render_pdf_pages_to_images,
)


def _blank_pdf(num_pages: int) -> bytes:
    """A scanned/image-only PDF has no text layer at all — a PDF with
    blank pages is the simplest stand-in for that, without needing a
    real scanned file as a fixture.
    """
    document = pymupdf.open()
    for _ in range(num_pages):
        document.new_page()
    return document.tobytes()


def _mixed_pdf(*, text_pages: list[str], blank_page_count: int) -> bytes:
    document = pymupdf.open()
    for text in text_pages:
        page = document.new_page()
        page.insert_text((72, 72), text)
    for _ in range(blank_page_count):
        document.new_page()
    return document.tobytes()

_WORDPROCESSING_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"


def _minimal_docx(paragraphs: list[str]) -> bytes:
    """A real .docx needs several other parts ([Content_Types].xml,
    relationships, ...) to open in Word — but `extract_document_text()`
    only ever reads `word/document.xml`, so that's the only part this
    needs to actually exercise it.
    """
    body = "".join(f"<w:p><w:r><w:t>{p}</w:t></w:r></w:p>" for p in paragraphs)
    document_xml = (
        f'<w:document xmlns:w="{_WORDPROCESSING_NS}"><w:body>{body}</w:body></w:document>'
    )
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        archive.writestr("word/document.xml", document_xml)
    return buffer.getvalue()


def test_normalizes_line_endings():
    assert normalize_text("a\r\nb\rc") == "a\nb\nc"


def test_collapses_repeated_blank_lines_but_keeps_paragraph_breaks():
    text = "Paragraph one.\n\n\n\n\nParagraph two."
    assert normalize_text(text) == "Paragraph one.\n\nParagraph two."


def test_collapses_repeated_spaces_without_touching_newlines():
    text = "Docker   compose    postgres.\n\nAnother   line."
    assert normalize_text(text) == "Docker compose postgres.\n\nAnother line."


def test_strips_trailing_whitespace_on_each_line():
    text = "Line one.   \nLine two.\t\n\nParagraph two."
    assert normalize_text(text) == "Line one.\nLine two.\n\nParagraph two."


def test_strips_leading_and_trailing_whitespace_overall():
    assert normalize_text("\n\n  hello world  \n\n") == "hello world"


def test_extract_document_text_reads_plain_text_by_mime_type():
    text = extract_document_text(
        "Docker Compose notları.".encode(), "text/plain", "notes.txt"
    )
    assert text == "Docker Compose notları."


def test_extract_document_text_reads_plain_text_by_extension_when_mime_type_is_generic():
    # A picker that doesn't recognize .txt can hand back a generic
    # content-type instead of leaving it empty — the extension still
    # has to save this from being rejected as "unsupported".
    text = extract_document_text(b"hello", "application/octet-stream", "notes.txt")
    assert text == "hello"


def test_extract_document_text_reads_docx_by_mime_type():
    docx_bytes = _minimal_docx(["First paragraph.", "Second paragraph."])
    text = extract_document_text(
        docx_bytes,
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "report.docx",
    )
    assert text == "First paragraph.\n\nSecond paragraph."


def test_extract_document_text_reads_docx_by_extension_when_mime_type_is_generic():
    docx_bytes = _minimal_docx(["Only paragraph."])
    text = extract_document_text(docx_bytes, "application/octet-stream", "report.docx")
    assert text == "Only paragraph."


def test_extract_document_text_skips_empty_paragraphs():
    docx_bytes = _minimal_docx(["Real content.", "", "   "])
    text = extract_document_text(docx_bytes, None, "report.docx")
    assert text == "Real content."


def test_extract_document_text_rejects_a_corrupt_docx():
    with pytest.raises(ValueError, match="valid .docx"):
        extract_document_text(b"not actually a zip file", None, "report.docx")


def test_extract_document_text_rejects_an_unsupported_type():
    with pytest.raises(ValueError, match="Unsupported document type"):
        extract_document_text(b"...", "application/vnd.ms-excel", "report.xlsx")


def test_extract_document_text_rejects_when_neither_mime_type_nor_extension_help():
    with pytest.raises(ValueError, match="Unsupported document type"):
        extract_document_text(b"...", None, None)


def test_render_pdf_pages_to_images_returns_one_png_per_page():
    images = render_pdf_pages_to_images(_blank_pdf(3), max_pages=10)

    assert len(images) == 3
    assert all(image.startswith(b"\x89PNG\r\n\x1a\n") for image in images)


def test_render_pdf_pages_to_images_respects_max_pages():
    images = render_pdf_pages_to_images(_blank_pdf(5), max_pages=2)

    assert len(images) == 2


def test_render_pdf_pages_to_images_on_a_single_page_pdf():
    images = render_pdf_pages_to_images(_blank_pdf(1), max_pages=30)

    assert len(images) == 1


def test_render_pdf_pages_to_images_requires_exactly_one_of_max_pages_or_page_indices():
    with pytest.raises(ValueError):
        render_pdf_pages_to_images(_blank_pdf(1))
    with pytest.raises(ValueError):
        render_pdf_pages_to_images(_blank_pdf(1), max_pages=1, page_indices=[0])


def test_render_pdf_pages_to_images_with_page_indices_renders_only_those_pages_in_order():
    # 3 pages; ask for the last and first, in that order.
    images_in_order = render_pdf_pages_to_images(_blank_pdf(3), page_indices=[2, 0])

    assert len(images_in_order) == 2
    assert all(image.startswith(b"\x89PNG\r\n\x1a\n") for image in images_in_order)


# P2-04 (docs/requirements-audit-2026-09-13.md): `extract_pdf_text_per_page`
# is what lets processing_pipeline.py OCR only the pages that actually
# lack a text layer, instead of treating a PDF as either fully text or
# fully scanned.
def test_extract_pdf_text_per_page_returns_one_entry_per_page():
    pages = extract_pdf_text_per_page(_blank_pdf(3))

    assert len(pages) == 3
    assert all(page == "" for page in pages)


def test_extract_pdf_text_per_page_distinguishes_text_pages_from_blank_ones():
    pdf_bytes = _mixed_pdf(text_pages=["Docker Compose notlarım."], blank_page_count=2)

    pages = extract_pdf_text_per_page(pdf_bytes)

    assert len(pages) == 3
    assert "Docker Compose" in pages[0]
    assert pages[1] == ""
    assert pages[2] == ""
