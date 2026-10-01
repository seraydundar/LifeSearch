"""Thin wrapper over `AIProvider.analyze_image` so the pipeline never calls
the provider directly.
"""

from typing import Any

from .ai_provider import AIProvider


async def analyze_image(
    image_bytes: bytes, mime_type: str, provider: AIProvider, *, is_screenshot: bool = False
) -> dict[str, Any]:
    return await provider.analyze_image(image_bytes, mime_type, is_screenshot=is_screenshot)
