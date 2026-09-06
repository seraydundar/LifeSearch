from datetime import datetime

from app.services.query_parser import parse_query

_NOW = datetime(2026, 9, 7, 12, 0, 0)  # a Monday


def test_extracts_a_type_keyword_and_cleans_the_query():
    result = parse_query("geçen ay baktığım PDF'ler", now=_NOW)

    assert result.item_types == ["pdf"]
    assert result.date_from == datetime(2026, 8, 8)  # 30 days before _NOW
    assert "pdf" not in result.cleaned_query.lower()
    assert "baktığım" in result.cleaned_query


def test_extracts_multiple_type_keywords():
    result = parse_query("geçen hafta eklediğim resimler ve notlar", now=_NOW)

    assert result.item_types == ["image", "note"]


def test_bugun_resolves_to_start_of_today():
    result = parse_query("bugün eklediğim not", now=_NOW)

    assert result.date_from == datetime(2026, 9, 7)
    assert result.item_types == ["note"]


def test_dun_resolves_to_start_of_yesterday():
    result = parse_query("dün aldığım ekran görüntüsü", now=_NOW)

    assert result.date_from == datetime(2026, 9, 6)
    assert result.item_types == ["screenshot"]


def test_bu_ay_resolves_to_the_1st_of_this_month():
    result = parse_query("bu ay kaydettiğim linkler", now=_NOW)

    assert result.date_from == datetime(2026, 9, 1)
    assert result.item_types == ["url"]


def test_no_filter_words_leaves_the_query_untouched():
    result = parse_query("Docker container ile image arasındaki fark", now=_NOW)

    assert result.item_types is None
    assert result.date_from is None
    assert result.cleaned_query == "Docker container ile image arasındaki fark"


def test_a_query_that_is_only_filter_words_falls_back_to_the_original_text():
    result = parse_query("geçen ay pdfler", now=_NOW)

    assert result.item_types == ["pdf"]
    assert result.date_from is not None
    # Stripping both filter phrases would leave nothing to embed — the
    # original text is a better search input than an empty string.
    assert result.cleaned_query == "geçen ay pdfler"


def test_is_case_insensitive():
    result = parse_query("GEÇEN HAFTA EKLEDİĞİM NOTLAR", now=_NOW)

    assert result.item_types == ["note"]
    assert result.date_from == datetime(2026, 8, 31)
