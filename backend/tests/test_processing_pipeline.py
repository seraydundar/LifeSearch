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


class FakeRepo:
    def __init__(self, item: dict, note_content: str = ""):
        self.item = item
        self.note_content = note_content
        self.status_history: list[str] = []
        self.job_updates: list[dict] = []
        self.inserted_chunks: list[dict] | None = None
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
        raise AssertionError("not a pdf item, shouldn't be called")

    async def replace_chunks(self, item_id, chunks):
        self.inserted_chunks = chunks


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
    repo = FakeRepo(item={"id": "item-2", "type": "audio"})

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
