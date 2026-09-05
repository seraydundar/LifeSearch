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
