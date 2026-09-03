"""PDF text extraction and text normalization — the front of the pipeline
described in requirements doc, section 41: every content type gets reduced
to the same "normalized text" shape before chunking/embedding, so the
search layer never has to know what a chunk originally came from.
"""

import io
import re

from pypdf import PdfReader


def extract_pdf_text(pdf_bytes: bytes) -> str:
    """Best-effort text layer extraction. A scanned/image-only PDF yields
    little or nothing here — OCR fallback (requirements doc, section 15)
    lands alongside OCR itself in Phase 6, sharing `ocr_service.py`.
    """
    reader = PdfReader(io.BytesIO(pdf_bytes))
    pages = [page.extract_text() or "" for page in reader.pages]
    return "\n\n".join(page.strip() for page in pages if page.strip())


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
