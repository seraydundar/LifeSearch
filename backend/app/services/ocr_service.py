"""Not a separate OCR engine — reuses vision_service's `ocr_text` field; kept
isolated so swapping in a real OCR engine later is a one-function change.
"""

from typing import Any


def extract_text(analysis: dict[str, Any]) -> str:
    return analysis.get("ocr_text") or ""
