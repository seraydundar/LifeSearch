from datetime import datetime
from io import BytesIO

import pytest
from PIL import ExifTags, Image

from app.services.exif_service import extract_exif_metadata


def _jpeg(*, exif: "Image.Exif | None" = None) -> bytes:
    image = Image.new("RGB", (4, 4), color="red")
    buffer = BytesIO()
    if exif is not None:
        image.save(buffer, format="JPEG", exif=exif.tobytes())
    else:
        image.save(buffer, format="JPEG")
    return buffer.getvalue()


def _exif_with_gps(lat: float, lon: float, when: str | None = None) -> "Image.Exif":
    exif = Image.Exif()
    if when:
        exif[ExifTags.Base.DateTimeOriginal] = when
    exif[ExifTags.IFD.GPSInfo] = {
        ExifTags.GPS.GPSLatitudeRef: "N" if lat >= 0 else "S",
        ExifTags.GPS.GPSLatitude: (abs(lat), 0.0, 0.0),
        ExifTags.GPS.GPSLongitudeRef: "E" if lon >= 0 else "W",
        ExifTags.GPS.GPSLongitude: (abs(lon), 0.0, 0.0),
    }
    return exif


def test_a_plain_photo_with_no_exif_returns_all_none():
    result = extract_exif_metadata(_jpeg())

    assert result == {"latitude": None, "longitude": None, "captured_at": None}


def test_garbage_bytes_never_raise():
    result = extract_exif_metadata(b"not actually a jpeg")

    assert result == {"latitude": None, "longitude": None, "captured_at": None}


def test_extracts_northern_eastern_coordinates():
    photo = _jpeg(exif=_exif_with_gps(39.9334, 32.8597))

    result = extract_exif_metadata(photo)

    assert result["latitude"] == pytest.approx(39.9334, abs=1e-3)
    assert result["longitude"] == pytest.approx(32.8597, abs=1e-3)


def test_south_and_west_refs_produce_negative_coordinates():
    photo = _jpeg(exif=_exif_with_gps(-33.8688, -70.6693))

    result = extract_exif_metadata(photo)

    assert result["latitude"] == pytest.approx(-33.8688, abs=1e-3)
    assert result["longitude"] == pytest.approx(-70.6693, abs=1e-3)


def test_extracts_capture_time():
    photo = _jpeg(exif=_exif_with_gps(0, 0, when="2026:03:15 10:30:00"))

    result = extract_exif_metadata(photo)

    assert result["captured_at"] == datetime(2026, 3, 15, 10, 30, 0)


def test_no_gps_ifd_leaves_coordinates_none_but_keeps_the_date():
    exif = Image.Exif()
    exif[ExifTags.Base.DateTimeOriginal] = "2026:03:15 10:30:00"
    photo = _jpeg(exif=exif)

    result = extract_exif_metadata(photo)

    assert result["latitude"] is None
    assert result["longitude"] is None
    assert result["captured_at"] == datetime(2026, 3, 15, 10, 30, 0)


def test_a_malformed_date_string_is_ignored_not_raised():
    exif = Image.Exif()
    exif[ExifTags.Base.DateTimeOriginal] = "not a date"
    photo = _jpeg(exif=exif)

    result = extract_exif_metadata(photo)

    assert result["captured_at"] is None
