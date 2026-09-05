from app.services.url_service import extract_from_html

_PAGE = """
<html>
<head>
  <title>Docker Compose Guide</title>
  <meta name="description" content="How to run multi-container apps.">
</head>
<body>
  <nav>Home | Blog | About</nav>
  <header>Site Header</header>
  <article>
    <h1>Docker Compose Guide</h1>
    <p>Docker Compose lets you define multi-container applications.</p>
  </article>
  <aside>Related posts</aside>
  <footer>Copyright 2026</footer>
  <script>console.log('tracking pixel');</script>
</body>
</html>
"""


def test_extracts_title_and_description():
    result = extract_from_html(_PAGE)
    assert result["title"] == "Docker Compose Guide"
    assert result["description"] == "How to run multi-container apps."


def test_extracts_article_text_only():
    result = extract_from_html(_PAGE)
    assert "Docker Compose lets you define multi-container applications." in result["text"]


def test_strips_navigation_ads_and_chrome():
    result = extract_from_html(_PAGE)
    text = result["text"]
    assert "Home | Blog | About" not in text
    assert "Site Header" not in text
    assert "Related posts" not in text
    assert "Copyright 2026" not in text
    assert "tracking pixel" not in text


def test_falls_back_to_body_when_there_is_no_article_or_main_tag():
    html = "<html><head><title>Plain page</title></head><body><p>Just some text.</p></body></html>"
    result = extract_from_html(html)
    assert "Just some text." in result["text"]


def test_missing_title_and_description_are_empty_strings_not_errors():
    result = extract_from_html("<html><body><p>No head at all.</p></body></html>")
    assert result["title"] == ""
    assert result["description"] == ""
