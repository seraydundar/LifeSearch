from datetime import datetime

from app.services.query_parser import parse_query

_NOW = datetime(2026, 9, 7, 12, 0, 0)  # a Monday


def test_extracts_a_type_keyword_and_cleans_the_query():
    result = parse_query("geçen ay baktığım PDF'ler", now=_NOW)

    assert result.item_types == ["pdf"]
    # The full previous calendar month (August), not a rolling 30 days
    # back from _NOW (which would have been Aug 8) — see
    # test_gecen_ay_is_the_full_previous_calendar_month_not_a_rolling_window.
    assert result.date_from == datetime(2026, 8, 1)
    assert result.date_to == datetime(2026, 8, 31, 23, 59, 59, 999999)
    assert "pdf" not in result.cleaned_query.lower()
    assert "baktığım" in result.cleaned_query


def test_extracts_multiple_type_keywords():
    result = parse_query("geçen hafta eklediğim resimler ve notlar", now=_NOW)

    assert result.item_types == ["image", "note"]


# P2-02 (docs/requirements-audit-2026-09-13.md): "sesli not"/"sesli
# notlar" contain "not"/"notlar" as a complete, word-bounded substring
# — these used to match as plain text notes (the shorter keyword) before
# the longer, more specific "sesli ..." phrase ever got a chance, since
# extraction went in the dict's own declared order rather than
# longest-keyword-first.
def test_sesli_not_is_recognized_as_audio_not_note():
    result = parse_query("geçen ay kaydettiğim sesli not", now=_NOW)

    assert result.item_types == ["audio"]
    assert "sesli" not in result.cleaned_query.lower()


def test_sesli_notlar_is_recognized_as_audio_not_note():
    result = parse_query("sesli notlar", now=_NOW)

    assert result.item_types == ["audio"]
    # Not left over as a stray, meaningless word once the type keyword
    # is stripped — falls back to the original text instead of an
    # empty-looking cleaned query (see parse_query's own fallback).
    assert result.cleaned_query.strip() != "sesli"


def test_bugun_resolves_to_start_of_today_with_no_upper_bound():
    result = parse_query("bugün eklediğim not", now=_NOW)

    assert result.date_from == datetime(2026, 9, 7)
    # Nothing is dated in the future, so "today" doesn't need a closing
    # bound the way "dün" (a *past*, closed day) does.
    assert result.date_to is None
    assert result.item_types == ["note"]


def test_dun_is_a_closed_range_that_does_not_bleed_into_today():
    result = parse_query("dün aldığım ekran görüntüsü", now=_NOW)

    assert result.date_from == datetime(2026, 9, 6)
    # The actual bug this fixes: "dün" used to have no upper bound at
    # all, so it matched everything from yesterday onward — today
    # included. It's now closed off at the last instant of yesterday.
    assert result.date_to == datetime(2026, 9, 6, 23, 59, 59, 999999)
    assert result.date_to < datetime(2026, 9, 7)  # never reaches into today
    assert result.item_types == ["screenshot"]


def test_bu_hafta_resolves_to_monday_with_no_upper_bound():
    result = parse_query("bu hafta eklediğim notlar", now=_NOW)

    assert result.date_from == datetime(2026, 9, 7)  # _NOW is itself a Monday
    assert result.date_to is None


def test_gecen_hafta_is_the_full_previous_calendar_week():
    result = parse_query("GEÇEN HAFTA EKLEDİĞİM NOTLAR", now=_NOW)

    assert result.item_types == ["note"]
    assert result.date_from == datetime(2026, 8, 31)  # Monday of the week before
    assert result.date_to == datetime(2026, 9, 6, 23, 59, 59, 999999)  # Sunday, end of day


def test_bu_ay_resolves_to_the_1st_of_this_month_with_no_upper_bound():
    result = parse_query("bu ay kaydettiğim linkler", now=_NOW)

    assert result.date_from == datetime(2026, 9, 1)
    assert result.date_to is None
    assert result.item_types == ["url"]


def test_gecen_ay_is_the_full_previous_calendar_month_not_a_rolling_window():
    # August has 31 days — the old `today - timedelta(days=30)` gave
    # Aug 8, missing the first week of the actual previous month
    # entirely and reaching one week into the wrong (August, correctly)
    # month regardless. A month-length-independent check needs a month
    # that isn't 30 days; August (31) already isn't, but the case that
    # would have broken the old code hardest is a short February.
    now = datetime(2026, 3, 1, 9, 0, 0)  # 2026 is not a leap year: Feb has 28 days
    result = parse_query("geçen ay aldığım notlar", now=now)

    assert result.date_from == datetime(2026, 2, 1)
    assert result.date_to == datetime(2026, 2, 28, 23, 59, 59, 999999)


def test_gecen_ay_crosses_a_year_boundary_correctly():
    now = datetime(2026, 1, 15, 9, 0, 0)
    result = parse_query("geçen ay aldığım notlar", now=now)

    assert result.date_from == datetime(2025, 12, 1)
    assert result.date_to == datetime(2025, 12, 31, 23, 59, 59, 999999)


def test_bu_yil_resolves_to_jan_1st_with_no_upper_bound():
    result = parse_query("bu yıl aldığım fotoğraflar", now=_NOW)

    assert result.date_from == datetime(2026, 1, 1)
    assert result.date_to is None


def test_gecen_yil_is_the_full_previous_calendar_year():
    result = parse_query("geçen yıl aldığım fotoğraflar", now=_NOW)

    assert result.date_from == datetime(2025, 1, 1)
    assert result.date_to == datetime(2025, 12, 31, 23, 59, 59, 999999)


def test_no_filter_words_leaves_the_query_untouched():
    result = parse_query("Docker container ile image arasındaki fark", now=_NOW)

    assert result.item_types is None
    assert result.date_from is None
    assert result.date_to is None
    assert result.cleaned_query == "Docker container ile image arasındaki fark"


def test_a_query_that_is_only_filter_words_falls_back_to_the_original_text():
    result = parse_query("geçen ay pdfler", now=_NOW)

    assert result.item_types == ["pdf"]
    assert result.date_from is not None
    assert result.date_to is not None
    # Stripping both filter phrases would leave nothing to embed — the
    # original text is a better search input than an empty string.
    assert result.cleaned_query == "geçen ay pdfler"


def test_is_case_insensitive():
    result = parse_query("GEÇEN HAFTA EKLEDİĞİM NOTLAR", now=_NOW)

    assert result.item_types == ["note"]
    assert result.date_from == datetime(2026, 8, 31)


def test_timezone_offset_of_zero_matches_the_default_behavior():
    """Same phrase, same `now`, offset made explicit rather than omitted
    — must be a no-op, since every other test in this file relies on the
    implicit default staying UTC-equivalent.
    """
    result = parse_query("bugün eklediğim not", now=_NOW, timezone_offset_minutes=0)

    assert result.date_from == datetime(2026, 9, 7)
    assert result.date_to is None


def test_bugun_with_a_positive_timezone_offset_uses_the_local_day_boundary():
    """P2-02 (docs/requirements-audit-2026-09-13.md): `now` is 22:30 UTC —
    already past local midnight for a UTC+3 client (01:30 local, into
    the *next* calendar day locally). Without the offset, "bugün" would
    resolve to UTC's still-current Sept 7th; a UTC+3 user actually means
    Sept 8th.
    """
    now = datetime(2026, 9, 7, 22, 30, 0)

    result = parse_query("bugün eklediğim not", now=now, timezone_offset_minutes=180)

    # Local midnight (Sept 8, 00:00 +03:00) expressed as its UTC instant.
    assert result.date_from == datetime(2026, 9, 7, 21, 0, 0)
    assert result.date_to is None


def test_a_negative_timezone_offset_shifts_the_other_direction():
    """US Pacific, UTC-8: `now` is 03:00 UTC — already the *previous*
    calendar day locally (19:00 the day before).
    """
    now = datetime(2026, 9, 7, 3, 0, 0)

    result = parse_query("bugün eklediğim not", now=now, timezone_offset_minutes=-480)

    # Local midnight (Sept 6, 00:00 -08:00) expressed as its UTC instant.
    assert result.date_from == datetime(2026, 9, 6, 8, 0, 0)
    assert result.date_to is None
