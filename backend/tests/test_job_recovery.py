import pytest

from app.services.job_recovery import recover_orphaned_jobs


class FakeJobRecoveryRepo:
    def __init__(self, stuck_jobs: list[dict] | None = None):
        self.stuck_jobs = stuck_jobs or []
        self.failed_jobs: list[tuple[str, str]] = []
        self.item_statuses: list[tuple[str, str]] = []

    async def find_jobs_by_status(self, status: str) -> list[dict]:
        assert status == "processing"
        return self.stuck_jobs

    async def mark_job_failed(self, job_id: str, error: str) -> None:
        self.failed_jobs.append((job_id, error))

    async def update_item_status(self, item_id: str, status: str) -> None:
        self.item_statuses.append((item_id, status))


@pytest.mark.asyncio
async def test_does_nothing_when_no_jobs_are_stuck():
    repo = FakeJobRecoveryRepo(stuck_jobs=[])

    recovered = await recover_orphaned_jobs(repo)

    assert recovered == 0
    assert repo.failed_jobs == []
    assert repo.item_statuses == []


@pytest.mark.asyncio
async def test_marks_every_stuck_job_and_its_item_as_failed():
    repo = FakeJobRecoveryRepo(stuck_jobs=[
        {"id": "job-1", "item_id": "item-1"},
        {"id": "job-2", "item_id": "item-2"},
    ])

    recovered = await recover_orphaned_jobs(repo)

    assert recovered == 2
    assert [job_id for job_id, _ in repo.failed_jobs] == ["job-1", "job-2"]
    # A real error message, not an empty one — nothing shown to the user
    # ever comes from here directly, but it should still say something
    # meaningful in `processing_jobs.error_message`.
    assert all(error for _, error in repo.failed_jobs)
    assert repo.item_statuses == [("item-1", "failed"), ("item-2", "failed")]
