"""Text extraction from images (requirements doc, section 14).

Not a separate OCR engine — the transcription comes from the same
multimodal vision call `vision_service.analyze_image` makes (its
`ocr_text` field). Kept as its own function so swapping in a dedicated
OCR engine (Tesseract, Google Vision, ...) later, without touching the
pipeline, is a one-function change.
"""

from typing import Any


def extract_text(analysis: dict[str, Any]) -> str:
    return analysis.get("ocr_text") or ""
