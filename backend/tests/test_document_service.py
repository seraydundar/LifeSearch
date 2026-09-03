from app.services.document_service import normalize_text


def test_normalizes_line_endings():
    assert normalize_text("a\r\nb\rc") == "a\nb\nc"


def test_collapses_repeated_blank_lines_but_keeps_paragraph_breaks():
    text = "Paragraph one.\n\n\n\n\nParagraph two."
    assert normalize_text(text) == "Paragraph one.\n\nParagraph two."


def test_collapses_repeated_spaces_without_touching_newlines():
    text = "Docker   compose    postgres.\n\nAnother   line."
    assert normalize_text(text) == "Docker compose postgres.\n\nAnother line."


def test_strips_trailing_whitespace_on_each_line():
    text = "Line one.   \nLine two.\t\n\nParagraph two."
    assert normalize_text(text) == "Line one.\nLine two.\n\nParagraph two."


def test_strips_leading_and_trailing_whitespace_overall():
    assert normalize_text("\n\n  hello world  \n\n") == "hello world"
