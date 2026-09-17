import logging
from datetime import datetime
from io import BytesIO

import pymupdf
import pytest
from PIL import ExifTags, Image

from app.services.ai_provider import AIProvider
from app.services.processing_pipeline import process_item


def _blank_pdf(num_pages: int = 1) -> bytes:
    """No text layer at all — the OCR-fallback case (a scanned/
    image-only PDF)."""
    document = pymupdf.open()
    for _ in range(num_pages):
        document.new_page()
    return document.tobytes()


def _text_pdf(text: str) -> bytes:
    """Has a real text layer — `extract_pdf_text()` should find it, so
    OCR must never be triggered for this one.
    """
    document = pymupdf.open()
    page = document.new_page()
    page.insert_text((72, 72), text)
    return document.tobytes()


def _mixed_pdf(*, text_pages: list[str], blank_page_count: int) -> bytes:
    """A PDF with a real text layer on some pages and none at all on
    others (P2-04, docs/requirements-audit-2026-09-13.md) — a signed
    page scanned back into an otherwise text-based document is the
    common real-world shape of this. Text pages come first, purely for
    this helper's own simplicity — `_ocr_missing_pdf_pages` doesn't care
    about page order, only which specific pages come back empty.
    """
    document = pymupdf.open()
    for text in text_pages:
        page = document.new_page()
        page.insert_text((72, 72), text)
    for _ in range(blank_page_count):
        document.new_page()
    return document.tobytes()


def _jpeg_with_exif(*, lat: float, lon: float, when: str) -> bytes:
    image = Image.new("RGB", (4, 4), color="red")
    exif = image.getexif()
    exif[ExifTags.Base.DateTimeOriginal] = when
    exif[ExifTags.IFD.GPSInfo] = {
        ExifTags.GPS.GPSLatitudeRef: "N" if lat >= 0 else "S",
        ExifTags.GPS.GPSLatitude: (abs(lat), 0.0, 0.0),
        ExifTags.GPS.GPSLongitudeRef: "E" if lon >= 0 else "W",
        ExifTags.GPS.GPSLongitude: (abs(lon), 0.0, 0.0),
    }
    buffer = BytesIO()
    image.save(buffer, format="JPEG", exif=exif.tobytes())
    return buffer.getvalue()


class FakeProvider(AIProvider):
    """Returns a fixed-size fake embedding per chunk instead of calling
    a real API — lets the pipeline's plumbing be tested without a key.
    """

    async def generate_text(self, prompt, *, system=None):
        return "fake answer"

    async def generate_embedding(self, text):
        return [0.1, 0.2, 0.3]

    async def generate_embeddings(self, texts):
        return [[0.1, 0.2, 0.3] for _ in texts]

    async def analyze_image(self, image_bytes, mime_type):
        return {
            "title": "Dell G2724D Monitor",
            "description": "A screenshot of an online shopping page for a gaming monitor.",
            "ocr_text": "Dell G2724D 27 inch 165Hz",
            "tags": ["dell", "monitor", "gaming"],
        }

    async def transcribe_audio(self, audio_bytes, mime_type):
        return "Prag'a gittiğimde Cafe Louvre'a uğramayı unutma."


class FakeRepo:
    def __init__(self, item: dict, note_content: str = "", image_bytes: bytes = b"fake-bytes"):
        self.item = item
        self.note_content = note_content
        self.image_bytes = image_bytes
        self.status_history: list[str] = []
        self.status_job_ids: list[str] = []
        self.job_updates: list[dict] = []
        self.inserted_chunks: list[dict] | None = None
        self.metadata_updates: list[dict] = []
        self.content_updates: list[dict] = []
        self.duplicate_marks: list[dict] = []
        self.tag_calls: list[dict] = []
        self.tag_error: Exception | None = None
        self.entity_calls: list[dict] = []
        self.entity_error: Exception | None = None
        self._job_id = "job-1"
        self.closed = False

    async def aclose(self):
        self.closed = True

    async def create_job(self, item_id, job_type):
        return self._job_id

    async def mark_job_started(self, job_id):
        self.job_updates.append({"status": "processing"})

    async def mark_job_completed(self, job_id):
        self.job_updates.append({"status": "completed"})

    async def mark_job_failed(self, job_id, error):
        self.job_updates.append({"status": "failed", "error": error})

    async def update_item_status(self, item_id, job_id, status):
        self.status_history.append(status)
        self.status_job_ids.append(job_id)

    async def get_item(self, item_id):
        return self.item

    async def get_note_content(self, item_id):
        return self.note_content

    async def download_file(self, storage_path):
        return self.image_bytes

    async def replace_chunks(self, item_id, job_id, chunks):
        self.inserted_chunks = chunks

    async def update_item_metadata(
        self,
        item_id,
        job_id,
        *,
        title=None,
        description=None,
        latitude=None,
        longitude=None,
        captured_at=None,
    ):
        self.metadata_updates.append({
            "job_id": job_id,
            "title": title,
            "description": description,
            "latitude": latitude,
            "longitude": longitude,
            "captured_at": captured_at,
        })

    async def replace_item_content(
        self, item_id, job_id, *, raw_text=None, ocr_text=None, ai_description=None
    ):
        self.content_updates.append({
            "job_id": job_id,
            "raw_text": raw_text,
            "ocr_text": ocr_text,
            "ai_description": ai_description,
        })

    async def mark_duplicate(self, item_id, job_id, duplicate_of_item_id, similarity):
        self.duplicate_marks.append({
            "item_id": item_id,
            "job_id": job_id,
            "duplicate_of_item_id": duplicate_of_item_id,
            "similarity": similarity,
        })

    async def attach_tags(self, item_id, job_id, user_id, tag_names):
        if self.tag_error is not None:
            raise self.tag_error
        self.tag_calls.append(
            {"item_id": item_id, "job_id": job_id, "user_id": user_id, "tag_names": tag_names}
        )

    async def attach_entities(self, item_id, job_id, user_id, entities):
        if self.entity_error is not None:
            raise self.entity_error
        self.entity_calls.append(
            {"item_id": item_id, "job_id": job_id, "user_id": user_id, "entities": entities}
        )


class FakeSearchRepo:
    """Stands in for `SearchRepository` in the duplicate-check step."""

    def __init__(self, candidate: dict | None = None, error: Exception | None = None):
        self.candidate = candidate
        self.error = error
        self.calls: list[str] = []

    async def find_duplicate_candidate(self, item_id, *, similarity_threshold=0.93):
        self.calls.append(item_id)
        if self.error is not None:
            raise self.error
        return self.candidate


@pytest.mark.asyncio
async def test_processes_a_note_end_to_end():
    repo = FakeRepo(
        item={"id": "item-1", "type": "note"},
        note_content="Docker container ile image arasındaki fark budur.",
    )

    await process_item("item-1", "job-1", repo, lambda: FakeProvider())

    assert repo.status_history == ["processing", "completed"]
    assert repo.job_updates[-1]["status"] == "completed"
    assert repo.inserted_chunks is not None
    assert len(repo.inserted_chunks) == 1
    assert repo.inserted_chunks[0]["chunk_index"] == 0
    assert repo.inserted_chunks[0]["embedding"] == "[0.1,0.2,0.3]"
    # P3 (docs/requirements-audit-2026-09-13.md): only PDFs have a page
    # concept — every other content type's chunks carry no page_number.
    assert repo.inserted_chunks[0]["metadata"] == {}


@pytest.mark.asyncio
async def test_unsupported_type_marks_the_item_failed_not_crashes():
    repo = FakeRepo(item={"id": "item-2", "type": "carrier_pigeon"})

    await process_item("item-2", "job-1", repo, lambda: FakeProvider())  # must not raise

    assert repo.status_history == ["processing", "failed"]
    assert repo.job_updates[-1]["status"] == "failed"
    assert repo.inserted_chunks is None


@pytest.mark.asyncio
async def test_empty_note_content_is_reported_as_a_failure():
    repo = FakeRepo(item={"id": "item-3", "type": "note"}, note_content="   ")

    await process_item("item-3", "job-1", repo, lambda: FakeProvider())

    assert repo.status_history[-1] == "failed"
    assert "no extractable text" in repo.job_updates[-1]["error"].lower()


@pytest.mark.asyncio
async def test_a_pdf_with_a_real_text_layer_never_triggers_ocr():
    repo = FakeRepo(
        item={
            "id": "item-pdf-1",
            "type": "pdf",
            "storage_path": "u1/item-pdf-1/doc.pdf",
        },
        image_bytes=_text_pdf("Docker Compose notlarım burada."),
    )

    await process_item("item-pdf-1", "job-1", repo, lambda: FakeProvider())

    assert repo.status_history == ["processing", "completed"]
    combined = repo.inserted_chunks[0]["content"]
    assert "Docker Compose" in combined
    # FakeProvider.analyze_image()'s fixed OCR text never shows up —
    # indirect proof that OCR fallback was never triggered.
    assert "Dell G2724D" not in combined
    # P3 (docs/requirements-audit-2026-09-13.md): a single-page PDF's one
    # chunk is tagged with that page.
    assert repo.inserted_chunks[0]["metadata"] == {"page_number": 1}
    # P2-05 (docs/requirements-audit-2026-09-13.md): a PDF's extracted
    # text used to never reach `item_contents` at all — only its chunks.
    assert len(repo.content_updates) == 1
    assert repo.content_updates[0]["job_id"] == "job-1"
    assert "Docker Compose" in repo.content_updates[0]["raw_text"]


@pytest.mark.asyncio
async def test_a_scanned_pdf_with_no_text_layer_falls_back_to_ocr():
    repo = FakeRepo(
        item={
            "id": "item-pdf-2",
            "type": "pdf",
            "storage_path": "u1/item-pdf-2/scan.pdf",
        },
        image_bytes=_blank_pdf(num_pages=2),
    )

    await process_item("item-pdf-2", "job-1", repo, lambda: FakeProvider())

    assert repo.status_history == ["processing", "completed"]
    # P3 (docs/requirements-audit-2026-09-13.md): chunking is per page now
    # (see chunk_pages()'s docstring for why), so two short OCR'd pages
    # become two chunks, not one — each carrying its own page_number.
    assert len(repo.inserted_chunks) == 2
    combined = "\n\n".join(c["content"] for c in repo.inserted_chunks)
    assert combined.count("Dell G2724D 27 inch 165Hz") == 2
    assert [c["metadata"]["page_number"] for c in repo.inserted_chunks] == [1, 2]
    # P2-05: the OCR'd text is saved to item_contents too, not just chunked.
    assert repo.content_updates[0]["raw_text"].count("Dell G2724D 27 inch 165Hz") == 2


@pytest.mark.asyncio
async def test_a_pdf_with_some_scanned_pages_ocrs_only_those_pages():
    """P2-04 (docs/requirements-audit-2026-09-13.md): the actual bug —
    a PDF where *most* pages have a real text layer but one or two are
    scanned images used to get zero OCR at all, since the old check only
    ran OCR when the *entire* document came back empty.
    """
    repo = FakeRepo(
        item={
            "id": "item-pdf-3",
            "type": "pdf",
            "storage_path": "u1/item-pdf-3/mixed.pdf",
        },
        image_bytes=_mixed_pdf(
            text_pages=["Docker Compose notlarım burada."], blank_page_count=1
        ),
    )

    await process_item("item-pdf-3", "job-1", repo, lambda: FakeProvider())

    assert repo.status_history == ["processing", "completed"]
    # P3: one chunk per page — the real text page (1) and the OCR'd
    # scanned page (2), each correctly attributed.
    assert len(repo.inserted_chunks) == 2
    combined = "\n\n".join(c["content"] for c in repo.inserted_chunks)
    # The real text page's own content is untouched...
    assert "Docker Compose" in combined
    # ...and the scanned page is OCR'd instead of being silently dropped.
    assert "Dell G2724D 27 inch 165Hz" in combined
    assert [c["metadata"]["page_number"] for c in repo.inserted_chunks] == [1, 2]
    # Both end up in item_contents too, not just the chunks.
    saved = repo.content_updates[0]["raw_text"]
    assert "Docker Compose" in saved
    assert "Dell G2724D 27 inch 165Hz" in saved


@pytest.mark.asyncio
async def test_processes_an_image_end_to_end():
    repo = FakeRepo(
        item={
            "id": "item-5",
            "type": "screenshot",
            "storage_path": "u1/item-5/shot.png",
            "mime_type": "image/png",
        },
    )

    await process_item("item-5", "job-1", repo, lambda: FakeProvider())

    assert repo.status_history == ["processing", "completed"]
    # AI-generated title/description overwrite the filename placeholder.
    # `image_bytes` here is fake (not a real JPEG), so EXIF fields are None
    # — that path is covered separately in test_exif_service.py and the
    # dedicated pipeline test below.
    assert repo.metadata_updates == [
        {
            "job_id": "job-1",
            "title": "Dell G2724D Monitor",
            "description": "A screenshot of an online shopping page for a gaming monitor.",
            "latitude": None,
            "longitude": None,
            "captured_at": None,
        }
    ]
    assert repo.content_updates[0]["ocr_text"] == "Dell G2724D 27 inch 165Hz"
    assert repo.content_updates[0]["ai_description"] == repo.metadata_updates[0]["description"]
    # Both the description and the OCR'd text end up in what gets embedded.
    assert repo.inserted_chunks is not None
    combined = repo.inserted_chunks[0]["content"]
    assert "gaming monitor" in combined
    assert "Dell G2724D" in combined


@pytest.mark.asyncio
async def test_image_without_a_storage_path_fails_clearly():
    repo = FakeRepo(item={"id": "item-6", "type": "image"})  # no storage_path

    await process_item("item-6", "job-1", repo, lambda: FakeProvider())

    assert repo.status_history[-1] == "failed"
    assert "no storage_path" in repo.job_updates[-1]["error"].lower()


@pytest.mark.asyncio
async def test_processes_a_text_document_end_to_end():
    repo = FakeRepo(
        item={
            "id": "item-doc-1",
            "type": "document",
            "storage_path": "u1/item-doc-1/notes.txt",
            "mime_type": "text/plain",
            "original_filename": "notes.txt",
        },
        image_bytes="Docker Compose ile birden fazla container'ı tanımlarsın.".encode(),
    )

    await process_item("item-doc-1", "job-1", repo, lambda: FakeProvider())

    assert repo.status_history == ["processing", "completed"]
    assert repo.inserted_chunks is not None
    assert "Docker Compose" in repo.inserted_chunks[0]["content"]
    # P2-05 (docs/requirements-audit-2026-09-13.md): a document's
    # extracted text used to never reach `item_contents` — only its
    # chunks.
    assert repo.content_updates == [
        {
            "job_id": "job-1",
            "raw_text": "Docker Compose ile birden fazla container'ı tanımlarsın.",
            "ocr_text": None,
            "ai_description": None,
        }
    ]


@pytest.mark.asyncio
async def test_document_without_a_storage_path_fails_clearly():
    repo = FakeRepo(item={"id": "item-doc-2", "type": "document"})  # no storage_path

    await process_item("item-doc-2", "job-1", repo, lambda: FakeProvider())

    assert repo.status_history[-1] == "failed"
    assert "no storage_path" in repo.job_updates[-1]["error"].lower()


@pytest.mark.asyncio
async def test_an_unrecognized_document_type_fails_clearly():
    repo = FakeRepo(
        item={
            "id": "item-doc-3",
            "type": "document",
            "storage_path": "u1/item-doc-3/report.xlsx",
            "mime_type": "application/vnd.ms-excel",
            "original_filename": "report.xlsx",
        },
    )

    await process_item("item-doc-3", "job-1", repo, lambda: FakeProvider())

    assert repo.status_history[-1] == "failed"
    assert "unsupported document type" in repo.job_updates[-1]["error"].lower()


@pytest.mark.asyncio
async def test_processes_an_audio_note_end_to_end():
    repo = FakeRepo(
        item={
            "id": "item-7",
            "type": "audio",
            "storage_path": "u1/item-7/note.m4a",
            "mime_type": "audio/m4a",
        },
    )

    await process_item("item-7", "job-1", repo, lambda: FakeProvider())

    assert repo.status_history == ["processing", "completed"]
    # The transcript becomes both the title source and the embedded text.
    assert repo.metadata_updates[0]["title"] == "fake answer"  # FakeProvider.generate_text()
    assert repo.content_updates[0]["raw_text"] == "Prag'a gittiğimde Cafe Louvre'a uğramayı unutma."
    assert repo.inserted_chunks is not None
    assert "Cafe Louvre" in repo.inserted_chunks[0]["content"]


@pytest.mark.asyncio
async def test_audio_without_a_storage_path_fails_clearly():
    repo = FakeRepo(item={"id": "item-8", "type": "audio"})

    await process_item("item-8", "job-1", repo, lambda: FakeProvider())

    assert repo.status_history[-1] == "failed"
    assert "no storage_path" in repo.job_updates[-1]["error"].lower()


@pytest.mark.asyncio
async def test_processes_a_url_item_end_to_end(monkeypatch):
    async def fake_fetch_and_extract(url):
        assert url == "https://example.com/docker-compose-guide"
        return {
            "title": "Docker Compose Guide",
            "description": "How to run multi-container apps.",
            "text": "Docker Compose lets you define and run multi-container Docker applications.",
        }

    monkeypatch.setattr(
        "app.services.processing_pipeline.fetch_and_extract", fake_fetch_and_extract
    )
    repo = FakeRepo(
        item={
            "id": "item-9",
            "type": "url",
            "source_url": "https://example.com/docker-compose-guide",
        },
    )

    await process_item("item-9", "job-1", repo, lambda: FakeProvider())

    assert repo.status_history == ["processing", "completed"]
    assert repo.metadata_updates == [
        {
            "job_id": "job-1",
            "title": "Docker Compose Guide",
            "description": "How to run multi-container apps.",
            "latitude": None,
            "longitude": None,
            "captured_at": None,
        }
    ]
    assert repo.content_updates[0]["raw_text"] == (
        "Docker Compose lets you define and run multi-container Docker applications."
    )
    assert repo.inserted_chunks is not None


@pytest.mark.asyncio
async def test_url_item_without_a_source_url_fails_clearly():
    repo = FakeRepo(item={"id": "item-10", "type": "url"})

    await process_item("item-10", "job-1", repo, lambda: FakeProvider())

    assert repo.status_history[-1] == "failed"
    assert "no source_url" in repo.job_updates[-1]["error"].lower()


@pytest.mark.asyncio
async def test_a_broken_provider_factory_fails_the_item_not_the_request():
    """Regression test: a missing API key (or any other AI_PROVIDER
    config error) must be reported the same way as any other pipeline
    failure — not raised straight out of `process_item`, which would
    surface as an unhandled 500 on the endpoint that kicked it off.
    """
    repo = FakeRepo(item={"id": "item-4", "type": "note"}, note_content="hello")

    def broken_factory():
        raise RuntimeError("OPENAI_API_KEY is not set")

    await process_item("item-4", "job-1", repo, broken_factory)  # must not raise

    assert repo.status_history == ["processing", "failed"]
    assert "OPENAI_API_KEY" in repo.job_updates[-1]["error"]


@pytest.mark.asyncio
async def test_marks_the_item_as_a_duplicate_when_a_near_identical_one_exists():
    repo = FakeRepo(
        item={"id": "item-11", "type": "note"},
        note_content="Docker container ile image arasındaki fark budur.",
    )
    search_repo = FakeSearchRepo(
        candidate={"item_id": "item-1", "item_type": "note", "similarity": 0.97}
    )

    await process_item("item-11", "job-1", repo, lambda: FakeProvider(), lambda: search_repo)

    assert search_repo.calls == ["item-11"]
    assert repo.duplicate_marks == [
        {
            "item_id": "item-11",
            "job_id": "job-1",
            "duplicate_of_item_id": "item-1",
            "similarity": 0.97,
        }
    ]
    # Still completes normally — duplicate detection only flags, never blocks.
    assert repo.status_history == ["processing", "completed"]


@pytest.mark.asyncio
async def test_no_duplicate_mark_when_nothing_is_similar_enough():
    repo = FakeRepo(
        item={"id": "item-12", "type": "note"}, note_content="Benzersiz bir not."
    )
    search_repo = FakeSearchRepo(candidate=None)

    await process_item("item-12", "job-1", repo, lambda: FakeProvider(), lambda: search_repo)

    assert repo.duplicate_marks == []
    assert repo.status_history == ["processing", "completed"]


@pytest.mark.asyncio
async def test_a_failing_duplicate_check_does_not_fail_the_item():
    """Regression guard for the best-effort contract in
    `_check_for_duplicate`: whatever goes wrong there (RPC down, bad
    response, ...) must never turn a successful processing run into a
    failed one.
    """
    repo = FakeRepo(item={"id": "item-13", "type": "note"}, note_content="hello")
    search_repo = FakeSearchRepo(error=RuntimeError("RPC unavailable"))

    await process_item("item-13", "job-1", repo, lambda: FakeProvider(), lambda: search_repo)

    assert repo.duplicate_marks == []
    assert repo.status_history == ["processing", "completed"]
    assert repo.job_updates[-1]["status"] == "completed"


@pytest.mark.asyncio
async def test_image_tags_come_from_the_vision_analysis_no_extra_call():
    repo = FakeRepo(
        item={
            "id": "item-14",
            "type": "screenshot",
            "storage_path": "u1/item-14/shot.png",
            "mime_type": "image/png",
        },
    )

    await process_item("item-14", "job-1", repo, lambda: FakeProvider(), user_id="user-1")

    assert repo.tag_calls == [
        {
            "item_id": "item-14",
            "job_id": "job-1",
            "user_id": "user-1",
            "tag_names": ["dell", "monitor", "gaming"],
        }
    ]


@pytest.mark.asyncio
async def test_note_tags_come_from_a_text_completion_call():
    repo = FakeRepo(item={"id": "item-15", "type": "note"}, note_content="Docker notes.")

    await process_item("item-15", "job-1", repo, lambda: FakeProvider(), user_id="user-1")

    # FakeProvider.generate_text always returns "fake answer" regardless
    # of the prompt — this only checks the wiring, not real tag quality.
    assert repo.tag_calls == [
        {"item_id": "item-15", "job_id": "job-1", "user_id": "user-1", "tag_names": ["fake answer"]}
    ]


@pytest.mark.asyncio
async def test_no_user_id_means_no_tagging_attempt():
    repo = FakeRepo(item={"id": "item-16", "type": "note"}, note_content="Docker notes.")

    await process_item("item-16", "job-1", repo, lambda: FakeProvider())  # no user_id

    assert repo.tag_calls == []
    assert repo.entity_calls == []
    assert repo.status_history == ["processing", "completed"]


@pytest.mark.asyncio
async def test_a_failing_tag_attach_does_not_fail_the_item():
    repo = FakeRepo(item={"id": "item-17", "type": "note"}, note_content="Docker notes.")
    repo.tag_error = RuntimeError("tags table unavailable")

    await process_item("item-17", "job-1", repo, lambda: FakeProvider(), user_id="user-1")

    assert repo.status_history == ["processing", "completed"]
    assert repo.job_updates[-1]["status"] == "completed"


@pytest.mark.asyncio
async def test_entities_come_from_a_text_completion_call():
    repo = FakeRepo(
        item={"id": "item-19", "type": "note"},
        note_content="Ahmet ile 15 Ocak'ta İstanbul'da buluştuk.",
    )

    class EntityProvider(FakeProvider):
        async def generate_text(self, prompt, *, system=None):
            if "varlık" in prompt:
                return "person: Ahmet\nplace: İstanbul\ndate: 15 Ocak"
            return await super().generate_text(prompt, system=system)

    await process_item("item-19", "job-1", repo, lambda: EntityProvider(), user_id="user-1")

    assert repo.entity_calls == [
        {
            "item_id": "item-19",
            "job_id": "job-1",
            "user_id": "user-1",
            "entities": [
                {"name": "Ahmet", "type": "person"},
                {"name": "İstanbul", "type": "place"},
                {"name": "15 Ocak", "type": "date"},
            ],
        }
    ]


@pytest.mark.asyncio
async def test_images_also_get_entity_extraction_unlike_the_free_vision_tags():
    repo = FakeRepo(
        item={
            "id": "item-20",
            "type": "screenshot",
            "storage_path": "u1/item-20/shot.png",
            "mime_type": "image/png",
        },
    )

    class EntityProvider(FakeProvider):
        async def generate_text(self, prompt, *, system=None):
            if "varlık" in prompt:
                return "organization: Dell"
            return await super().generate_text(prompt, system=system)

    await process_item("item-20", "job-1", repo, lambda: EntityProvider(), user_id="user-1")

    assert repo.entity_calls == [
        {
            "item_id": "item-20",
            "job_id": "job-1",
            "user_id": "user-1",
            "entities": [{"name": "Dell", "type": "organization"}],
        }
    ]


@pytest.mark.asyncio
async def test_a_failing_entity_attach_does_not_fail_the_item():
    repo = FakeRepo(item={"id": "item-21", "type": "note"}, note_content="Docker notes.")
    repo.entity_error = RuntimeError("entities table unavailable")

    await process_item("item-21", "job-1", repo, lambda: FakeProvider(), user_id="user-1")

    assert repo.status_history == ["processing", "completed"]
    assert repo.job_updates[-1]["status"] == "completed"


@pytest.mark.asyncio
async def test_a_successful_run_logs_item_id_job_id_and_a_processing_time(caplog):
    """Requirements doc, section 53: every log line should carry the
    identifiers that let it be traced back to a specific run, plus how
    long it took — never the item's actual content.
    """
    repo = FakeRepo(item={"id": "item-18", "type": "note"}, note_content="Docker notes.")

    with caplog.at_level(logging.INFO, logger="app.services.processing_pipeline"):
        await process_item("item-18", "job-1", repo, lambda: FakeProvider())

    record = next(r for r in caplog.records if r.message == "item processed")
    assert record.item_id == "item-18"
    assert record.job_id == "job-1"
    assert record.processing_time_ms >= 0
    assert not hasattr(record, "note_content")  # never the content itself


@pytest.mark.asyncio
async def test_a_failed_run_logs_the_error_and_a_processing_time(caplog):
    repo = FakeRepo(item={"id": "item-19", "type": "carrier_pigeon"})

    with caplog.at_level(logging.WARNING, logger="app.services.processing_pipeline"):
        await process_item("item-19", "job-1", repo, lambda: FakeProvider())

    record = next(r for r in caplog.records if r.message == "processing failed")
    assert record.item_id == "item-19"
    assert record.job_id == "job-1"
    assert "carrier_pigeon" in record.error
    assert record.processing_time_ms >= 0


@pytest.mark.asyncio
async def test_a_photo_with_gps_exif_gets_its_location_and_capture_time_saved():
    photo = _jpeg_with_exif(lat=39.9334, lon=32.8597, when="2026:03:15 10:30:00")
    repo = FakeRepo(
        item={
            "id": "item-20",
            "type": "image",
            "storage_path": "u1/item-20/photo.jpg",
            "mime_type": "image/jpeg",
        },
        image_bytes=photo,
    )

    await process_item("item-20", "job-1", repo, lambda: FakeProvider())

    update = repo.metadata_updates[0]
    assert update["latitude"] == pytest.approx(39.9334, abs=1e-3)
    assert update["longitude"] == pytest.approx(32.8597, abs=1e-3)
    assert update["captured_at"] == datetime(2026, 3, 15, 10, 30, 0)


@pytest.mark.asyncio
async def test_a_photo_with_no_exif_leaves_location_fields_empty():
    plain_photo = BytesIO()
    Image.new("RGB", (4, 4), color="blue").save(plain_photo, format="JPEG")
    repo = FakeRepo(
        item={
            "id": "item-21",
            "type": "image",
            "storage_path": "u1/item-21/photo.jpg",
            "mime_type": "image/jpeg",
        },
        image_bytes=plain_photo.getvalue(),
    )

    await process_item("item-21", "job-1", repo, lambda: FakeProvider())  # must not raise

    update = repo.metadata_updates[0]
    assert update["latitude"] is None
    assert update["longitude"] is None
    assert update["captured_at"] is None
    assert repo.status_history == ["processing", "completed"]


@pytest.mark.asyncio
async def test_the_repo_is_closed_after_a_successful_run():
    """Regression guard: `SupabaseRestRepository` reuses one HTTP client
    across the whole run instead of opening one per call (see its own
    docstring) — this only pays off if something actually closes it
    afterward. `process_item` owns that, via a `finally` block.
    """
    repo = FakeRepo(item={"id": "item-22", "type": "note"}, note_content="Docker notes.")

    await process_item("item-22", "job-1", repo, lambda: FakeProvider())

    assert repo.closed is True


@pytest.mark.asyncio
async def test_the_repo_is_closed_even_after_a_failure():
    repo = FakeRepo(item={"id": "item-23", "type": "carrier_pigeon"})

    await process_item("item-23", "job-1", repo, lambda: FakeProvider())

    assert repo.status_history[-1] == "failed"
    assert repo.closed is True
