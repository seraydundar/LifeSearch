"""Reads location/time from EXIF metadata (Pillow only, no AI provider).
Most photos lack this data, so every failure path returns None instead of
raising — it's optional metadata, never worth failing an item's processing.
"""

from datetime import datetime
from io import BytesIO
from typing import Any

from PIL import ExifTags, Image


def extract_exif_metadata(image_bytes: bytes) -> dict[str, Any]:
    result: dict[str, Any] = {"latitude": None, "longitude": None, "captured_at": None}

    try:
        exif = Image.open(BytesIO(image_bytes)).getexif()
    except Exception:
        return result
    if not exif:
        return result

    result["captured_at"] = _extract_captured_at(exif)
    result["latitude"], result["longitude"] = _extract_gps(exif)
    return result


def _extract_captured_at(exif: Image.Exif) -> datetime | None:
    tags = {ExifTags.TAGS.get(tag_id, tag_id): value for tag_id, value in exif.items()}
    raw = tags.get("DateTimeOriginal") or tags.get("DateTime")
    if not raw:
        return None
    try:
        return datetime.strptime(str(raw), "%Y:%m:%d %H:%M:%S")
    except ValueError:
        return None


def _extract_gps(exif: Image.Exif) -> tuple[float | None, float | None]:
    try:
        gps_ifd = exif.get_ifd(ExifTags.IFD.GPSInfo)
    except Exception:
        return None, None
    if not gps_ifd:
        return None, None

    tags = {ExifTags.GPSTAGS.get(tag_id, tag_id): value for tag_id, value in gps_ifd.items()}
    latitude = _dms_to_decimal(tags.get("GPSLatitude"), tags.get("GPSLatitudeRef"))
    longitude = _dms_to_decimal(tags.get("GPSLongitude"), tags.get("GPSLongitudeRef"))
    return latitude, longitude


def _dms_to_decimal(dms: Any, ref: str | None) -> float | None:
    """`dms` is (degrees, minutes, seconds), EXIF's GPS coordinate format."""
    if not dms or not ref:
        return None
    try:
        degrees, minutes, seconds = (float(component) for component in dms)
    except (TypeError, ValueError):
        return None

    decimal = degrees + minutes / 60 + seconds / 3600
    return -decimal if ref in ("S", "W") else decimal
