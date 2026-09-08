import logging

import pytest

from app.services.ai_provider import AIProvider
from app.services.processing_pipeline import process_item


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
        self.job_updates: list[dict] = []
        self.inserted_chunks: list[dict] | None = None
        self.metadata_updates: list[dict] = []
        self.content_updates: list[dict] = []
        self.duplicate_marks: list[dict] = []
        self.tag_calls: list[dict] = []
        self.tag_error: Exception | None = None
        self._job_id = "job-1"

    async def create_job(self, item_id, job_type):
        return self._job_id

    async def mark_job_started(self, job_id):
        self.job_updates.append({"status": "processing"})

    async def mark_job_completed(self, job_id):
        self.job_updates.append({"status": "completed"})

    async def mark_job_failed(self, job_id, error):
        self.job_updates.append({"status": "failed", "error": error})

    async def update_item_status(self, item_id, status):
        self.status_history.append(status)

    async def get_item(self, item_id):
        return self.item

    async def get_note_content(self, item_id):
        return self.note_content

    async def download_file(self, storage_path):
        return self.image_bytes

    async def replace_chunks(self, item_id, chunks):
        self.inserted_chunks = chunks

    async def update_item_metadata(self, item_id, *, title=None, description=None):
        self.metadata_updates.append({"title": title, "description": description})

    async def replace_item_content(
        self, item_id, *, raw_text=None, ocr_text=None, ai_description=None
    ):
        self.content_updates.append(
            {"raw_text": raw_text, "ocr_text": ocr_text, "ai_description": ai_description}
        )

    async def mark_duplicate(self, item_id, duplicate_of_item_id, similarity):
        self.duplicate_marks.append(
            {"item_id": item_id, "duplicate_of_item_id": duplicate_of_item_id, "similarity": similarity}
        )

    async def attach_tags(self, item_id, user_id, tag_names):
        if self.tag_error is not None:
            raise self.tag_error
        self.tag_calls.append({"item_id": item_id, "user_id": user_id, "tag_names": tag_names})


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

    await process_item("item-1", repo, lambda: FakeProvider())

    assert repo.status_history == ["processing", "completed"]
    assert repo.job_updates[-1]["status"] == "completed"
    assert repo.inserted_chunks is not None
    assert len(repo.inserted_chunks) == 1
    assert repo.inserted_chunks[0]["chunk_index"] == 0
    assert repo.inserted_chunks[0]["embedding"] == "[0.1,0.2,0.3]"


@pytest.mark.asyncio
async def test_unsupported_type_marks_the_item_failed_not_crashes():
    repo = FakeRepo(item={"id": "item-2", "type": "carrier_pigeon"})

    await process_item("item-2", repo, lambda: FakeProvider())  # must not raise

    assert repo.status_history == ["processing", "failed"]
    assert repo.job_updates[-1]["status"] == "failed"
    assert repo.inserted_chunks is None


@pytest.mark.asyncio
async def test_empty_note_content_is_reported_as_a_failure():
    repo = FakeRepo(item={"id": "item-3", "type": "note"}, note_content="   ")

    await process_item("item-3", repo, lambda: FakeProvider())

    assert repo.status_history[-1] == "failed"
    assert "no extractable text" in repo.job_updates[-1]["error"].lower()


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

    await process_item("item-5", repo, lambda: FakeProvider())

    assert repo.status_history == ["processing", "completed"]
    # AI-generated title/description overwrite the filename placeholder.
    assert repo.metadata_updates == [
        {
            "title": "Dell G2724D Monitor",
            "description": "A screenshot of an online shopping page for a gaming monitor.",
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

    await process_item("item-6", repo, lambda: FakeProvider())

    assert repo.status_history[-1] == "failed"
    assert "no storage_path" in repo.job_updates[-1]["error"].lower()


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

    await process_item("item-7", repo, lambda: FakeProvider())

    assert repo.status_history == ["processing", "completed"]
    # The transcript becomes both the title source and the embedded text.
    assert repo.metadata_updates[0]["title"] == "fake answer"  # FakeProvider.generate_text()
    assert repo.content_updates[0]["raw_text"] == "Prag'a gittiğimde Cafe Louvre'a uğramayı unutma."
    assert repo.inserted_chunks is not None
    assert "Cafe Louvre" in repo.inserted_chunks[0]["content"]


@pytest.mark.asyncio
async def test_audio_without_a_storage_path_fails_clearly():
    repo = FakeRepo(item={"id": "item-8", "type": "audio"})

    await process_item("item-8", repo, lambda: FakeProvider())

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

    await process_item("item-9", repo, lambda: FakeProvider())

    assert repo.status_history == ["processing", "completed"]
    assert repo.metadata_updates == [
        {"title": "Docker Compose Guide", "description": "How to run multi-container apps."}
    ]
    assert repo.content_updates[0]["raw_text"] == (
        "Docker Compose lets you define and run multi-container Docker applications."
    )
    assert repo.inserted_chunks is not None


@pytest.mark.asyncio
async def test_url_item_without_a_source_url_fails_clearly():
    repo = FakeRepo(item={"id": "item-10", "type": "url"})

    await process_item("item-10", repo, lambda: FakeProvider())

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

    await process_item("item-4", repo, broken_factory)  # must not raise

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

    await process_item("item-11", repo, lambda: FakeProvider(), lambda: search_repo)

    assert search_repo.calls == ["item-11"]
    assert repo.duplicate_marks == [
        {"item_id": "item-11", "duplicate_of_item_id": "item-1", "similarity": 0.97}
    ]
    # Still completes normally — duplicate detection only flags, never blocks.
    assert repo.status_history == ["processing", "completed"]


@pytest.mark.asyncio
async def test_no_duplicate_mark_when_nothing_is_similar_enough():
    repo = FakeRepo(
        item={"id": "item-12", "type": "note"}, note_content="Benzersiz bir not."
    )
    search_repo = FakeSearchRepo(candidate=None)

    await process_item("item-12", repo, lambda: FakeProvider(), lambda: search_repo)

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

    await process_item("item-13", repo, lambda: FakeProvider(), lambda: search_repo)

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

    await process_item("item-14", repo, lambda: FakeProvider(), user_id="user-1")

    assert repo.tag_calls == [
        {"item_id": "item-14", "user_id": "user-1", "tag_names": ["dell", "monitor", "gaming"]}
    ]


@pytest.mark.asyncio
async def test_note_tags_come_from_a_text_completion_call():
    repo = FakeRepo(item={"id": "item-15", "type": "note"}, note_content="Docker notes.")

    await process_item("item-15", repo, lambda: FakeProvider(), user_id="user-1")

    # FakeProvider.generate_text always returns "fake answer" regardless
    # of the prompt — this only checks the wiring, not real tag quality.
    assert repo.tag_calls == [
        {"item_id": "item-15", "user_id": "user-1", "tag_names": ["fake answer"]}
    ]


@pytest.mark.asyncio
async def test_no_user_id_means_no_tagging_attempt():
    repo = FakeRepo(item={"id": "item-16", "type": "note"}, note_content="Docker notes.")

    await process_item("item-16", repo, lambda: FakeProvider())  # no user_id

    assert repo.tag_calls == []
    assert repo.status_history == ["processing", "completed"]


@pytest.mark.asyncio
async def test_a_failing_tag_attach_does_not_fail_the_item():
    repo = FakeRepo(item={"id": "item-17", "type": "note"}, note_content="Docker notes.")
    repo.tag_error = RuntimeError("tags table unavailable")

    await process_item("item-17", repo, lambda: FakeProvider(), user_id="user-1")

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
        await process_item("item-18", repo, lambda: FakeProvider())

    record = next(r for r in caplog.records if r.message == "item processed")
    assert record.item_id == "item-18"
    assert record.job_id == "job-1"
    assert record.processing_time_ms >= 0
    assert not hasattr(record, "note_content")  # never the content itself


@pytest.mark.asyncio
async def test_a_failed_run_logs_the_error_and_a_processing_time(caplog):
    repo = FakeRepo(item={"id": "item-19", "type": "carrier_pigeon"})

    with caplog.at_level(logging.WARNING, logger="app.services.processing_pipeline"):
        await process_item("item-19", repo, lambda: FakeProvider())

    record = next(r for r in caplog.records if r.message == "processing failed")
    assert record.item_id == "item-19"
    assert record.job_id == "job-1"
    assert "carrier_pigeon" in record.error
    assert record.processing_time_ms >= 0
