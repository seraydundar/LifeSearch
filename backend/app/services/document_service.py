"""Text extraction and normalization — the front of the pipeline
described in requirements doc, section 41: every content type gets reduced
to the same "normalized text" shape before chunking/embedding, so the
search layer never has to know what a chunk originally came from.
"""

import io
import re
import zipfile
from xml.etree import ElementTree

from pypdf import PdfReader


def extract_pdf_text(pdf_bytes: bytes) -> str:
    """Best-effort text layer extraction. A scanned/image-only PDF yields
    little or nothing here — OCR fallback (requirements doc, section 15)
    lands alongside OCR itself in Phase 6, sharing `ocr_service.py`.
    """
    reader = PdfReader(io.BytesIO(pdf_bytes))
    pages = [page.extract_text() or "" for page in reader.pages]
    return "\n\n".join(page.strip() for page in pages if page.strip())


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
