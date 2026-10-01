"""Text extraction and normalization: every content type is reduced to the
same "normalized text" shape before chunking/embedding.
"""

import io
import re
import zipfile
from xml.etree import ElementTree

import pymupdf
from pypdf import PdfReader


def extract_pdf_text(pdf_bytes: bytes) -> str:
    """Best-effort whole-document text extraction; a scanned/image-only PDF
    yields little, which `render_pdf_pages_to_images()` exists to handle.
    """
    return "\n\n".join(page for page in extract_pdf_text_per_page(pdf_bytes) if page)


def extract_pdf_text_per_page(pdf_bytes: bytes) -> list[str]:
    """Per-page text (empty string, not dropped, for a page with no text
    layer), so the OCR fallback can target only the pages that need it.
    """
    reader = PdfReader(io.BytesIO(pdf_bytes))
    return [(page.extract_text() or "").strip() for page in reader.pages]


def render_pdf_pages_to_images(
    pdf_bytes: bytes,
    *,
    max_pages: int | None = None,
    page_indices: list[int] | None = None,
) -> list[bytes]:
    """Rasterizes PDF pages to PNGs for vision-model OCR. Pass exactly one of
    `max_pages` (whole doc scanned) or `page_indices` (only some pages lack
    a text layer); this also bounds how many paid vision calls get triggered.
    """
    if (max_pages is None) == (page_indices is None):
        raise ValueError("Pass exactly one of max_pages or page_indices.")

    document = pymupdf.open(stream=pdf_bytes, filetype="pdf")
    try:
        if page_indices is not None:
            return [document[index].get_pixmap().tobytes("png") for index in page_indices]
        images: list[bytes] = []
        for index, page in enumerate(document):
            if index >= max_pages:
                break
            images.append(page.get_pixmap().tobytes("png"))
        return images
    finally:
        document.close()


_DOCX_MIME_TYPES = {"application/vnd.openxmlformats-officedocument.wordprocessingml.document"}
_TEXT_MIME_TYPES = {"text/plain"}
_WORDPROCESSING_NS = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"


def extract_document_text(
    file_bytes: bytes, mime_type: str | None, filename: str | None
) -> str:
    """Routes to the right extractor; falls back to the filename extension
    when `mime_type` is uninformative (e.g. a generic `application/octet-stream`).
    """
    extension = filename.rsplit(".", 1)[-1].lower() if filename and "." in filename else ""

    if mime_type in _DOCX_MIME_TYPES or extension == "docx":
        return _extract_docx_text(file_bytes)
    if mime_type in _TEXT_MIME_TYPES or extension == "txt":
        return file_bytes.decode("utf-8", errors="replace")
    raise ValueError(f"Unsupported document type (mime_type={mime_type!r}, filename={filename!r}).")


def _extract_docx_text(docx_bytes: bytes) -> str:
    """A .docx is a zip archive with its body in `word/document.xml`
    (WordprocessingML); parsed with stdlib only, skipping the python-docx dep.
    """
    try:
        with zipfile.ZipFile(io.BytesIO(docx_bytes)) as archive:
            xml_bytes = archive.read("word/document.xml")
    except (zipfile.BadZipFile, KeyError) as error:
        raise ValueError("Not a valid .docx file.") from error

    root = ElementTree.fromstring(xml_bytes)
    paragraphs = [
        "".join(node.text or "" for node in paragraph.iter(f"{_WORDPROCESSING_NS}t"))
        for paragraph in root.iter(f"{_WORDPROCESSING_NS}p")
    ]
    return "\n\n".join(p for p in paragraphs if p.strip())


_MULTI_BLANK_LINES = re.compile(r"\n{3,}")
_TRAILING_SPACES = re.compile(r"[ \t]+\n")
_MULTI_SPACES = re.compile(r"[ \t]{2,}")


def normalize_text(text: str) -> str:
    """Whitespace cleanup only — paragraph breaks are meaningful to chunking."""
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = _TRAILING_SPACES.sub("\n", text)
    text = _MULTI_SPACES.sub(" ", text)
    text = _MULTI_BLANK_LINES.sub("\n\n", text)
    return text.strip()
