"""Text extraction and normalization — the front of the pipeline
described in requirements doc, section 41: every content type gets reduced
to the same "normalized text" shape before chunking/embedding, so the
search layer never has to know what a chunk originally came from.
"""

import io
import re
import zipfile
from xml.etree import ElementTree

import pymupdf
from pypdf import PdfReader


def extract_pdf_text(pdf_bytes: bytes) -> str:
    """Best-effort text layer extraction, whole document. A scanned/
    image-only PDF yields little or nothing here — `render_pdf_pages_to_images()`
    below is the OCR fallback for exactly that case (requirements doc,
    section 15). Prefer `extract_pdf_text_per_page()` for anything that
    needs to tell *which* pages have no text layer (see
    processing_pipeline.py's PDF branch, P2-04) — this just joins that
    same per-page result together.
    """
    return "\n\n".join(page for page in extract_pdf_text_per_page(pdf_bytes) if page)


def extract_pdf_text_per_page(pdf_bytes: bytes) -> list[str]:
    """Same extraction as `extract_pdf_text()`, but one entry per page
    (empty string for a page with no text layer at all, not dropped) —
    lets the OCR fallback in processing_pipeline.py target only the
    pages that actually need it (P2-04, docs/requirements-audit-2026-09-13.md).
    A single scanned page mixed into an otherwise text-based PDF used to
    get no OCR at all, since the old whole-document check only ran OCR
    when *every* page came back empty.
    """
    reader = PdfReader(io.BytesIO(pdf_bytes))
    return [(page.extract_text() or "").strip() for page in reader.pages]


def render_pdf_pages_to_images(
    pdf_bytes: bytes,
    *,
    max_pages: int | None = None,
    page_indices: list[int] | None = None,
) -> list[bytes]:
    """Rasterizes pages of a PDF to PNGs — what a scanned/image-only page
    (no text layer for `extract_pdf_text_per_page()` to find) needs
    before it can go through the same vision-model OCR call a photo
    already gets (`vision_service.analyze_image`'s `ocr_text`, see
    processing_pipeline.py).

    Exactly one of [max_pages] (the first N pages, in order — the
    whole-document-is-scanned case) or [page_indices] (specific pages,
    in the given order — P2-04's mixed-PDF case, where only *some* pages
    lack a text layer) must be given. `max_pages`/`len(page_indices)`
    bounds the number of (paid) vision calls a single PDF can trigger —
    the caller decides the actual limit (see
    processing_pipeline._MAX_OCR_PDF_PAGES).
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
    """Routes a generic 'document' upload (requirements doc, section 13's
    "Upload Document", broadened past PDF-only — see docs/roadmap.md,
    Faz 10c) to the right extractor. Falls back to the filename's
    extension when `mime_type` doesn't say enough on its own — a picker
    that doesn't recognize an extension can hand back
    `application/octet-stream`, and this shouldn't fail a `.txt` upload
    just because of that.
    """
    extension = filename.rsplit(".", 1)[-1].lower() if filename and "." in filename else ""

    if mime_type in _DOCX_MIME_TYPES or extension == "docx":
        return _extract_docx_text(file_bytes)
    if mime_type in _TEXT_MIME_TYPES or extension == "txt":
        return file_bytes.decode("utf-8", errors="replace")
    raise ValueError(f"Unsupported document type (mime_type={mime_type!r}, filename={filename!r}).")


def _extract_docx_text(docx_bytes: bytes) -> str:
    """A .docx is a zip archive; its body lives in `word/document.xml` as
    WordprocessingML. Parsed with the standard library only (`zipfile` +
    `ElementTree`) rather than pulling in `python-docx` (and its `lxml`
    dependency) for what is, structurally, just "walk the paragraphs,
    concatenate each one's text runs" — plenty for extracting plain text,
    which is all the AI pipeline ever needs from any content type.
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
    """Whitespace cleanup only — paragraph breaks are meaningful (chunking
    uses them), so this never joins lines into one another.
    """
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = _TRAILING_SPACES.sub("\n", text)
    text = _MULTI_SPACES.sub(" ", text)
    text = _MULTI_BLANK_LINES.sub("\n\n", text)
    return text.strip()
