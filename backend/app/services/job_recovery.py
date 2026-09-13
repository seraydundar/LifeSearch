"""Recovers `processing_jobs` orphaned by a server crash/restart
(requirements doc, section 12; Faz 10b, madde 2 — see docs/roadmap.md).

`process_item()` (see `processing_pipeline.py`) always keeps a job's
`status` and its item's `processing_status` in lockstep at 'processing'
for as long as it runs, and always moves both to 'completed'/'failed' in
its own `try`/`except` before returning. Since FastAPI's `BackgroundTasks`
don't survive the process itself dying, the *only* way a job can still
be sitting at 'processing' is if the process running it was killed before
it got there — a deploy restart, an OOM kill, a crash. Nothing else will
ever finish that job: the item would show "İşleniyor..." forever, with no
way for the user to retry (the mobile "Tekrar Dene" button only appears
once `processing_status` is 'failed' — see `ItemDetailScreen`).

Also sweeps `pending` jobs, not just `processing` (P1-05, docs/
requirements-audit-2026-09-13.md): `api/ai/routes.py`'s `/process-item`
now creates the `processing_jobs` row (at `pending`) *before* returning
"202 accepted", specifically so a process death in the gap between that
response and `BackgroundTasks` actually starting the job leaves a
recoverable row instead of nothing at all. Without also sweeping
`pending` here, that row would sit forever, `mark_job_started()` never
having run (the exact original gap this fix closes).

Call `recover_orphaned_jobs()` once at startup, before any request is
served — that timing is what makes every `processing_jobs` row already
at `pending`/`processing` at that moment provably orphaned, since a
fresh process couldn't have created or started one yet.

**Single-instance assumption**: this treats "processing at my own
startup" as proof of "orphaned", which only holds when there's exactly
one backend instance. A multi-replica deployment restarting one instance
while another is genuinely still mid-job would need a lease/lock instead
of this timing argument — out of scope while this project runs as one
instance (see docker-compose.yml).
"""

import logging
from typing import Any, Protocol

logger = logging.getLogger(__name__)

_ORPHANED_ERROR = "Sunucu yeniden başlatıldığı sırada kesildi."


class _JobRecoveryRepo(Protocol):
    async def find_jobs_by_status(self, statuses: list[str]) -> list[dict[str, Any]]: ...
    async def mark_job_failed(self, job_id: str, error: str) -> None: ...
    async def update_item_status(self, item_id: str, job_id: str, status: str) -> None: ...


async def recover_orphaned_jobs(repo: _JobRecoveryRepo) -> int:
    """Returns how many jobs were recovered. `repo` must be authenticated
    with the service_role key (see `find_jobs_by_status`'s docstring) —
    the jobs being swept belong to arbitrary users, not whoever restarted
    the server.
    """
    stuck_jobs = await repo.find_jobs_by_status(["pending", "processing"])
    for job in stuck_jobs:
        # `update_item_status` is job-gated (P1-04, docs/requirements-audit-
        # 2026-09-13.md) — passing this job's own id keeps that working:
        # a job stuck at 'processing' is, by this sweep's own single-
        # instance assumption (see module docstring), still the item's
        # latest job, so this always applies rather than silently no-op'ing.
        await repo.mark_job_failed(job["id"], _ORPHANED_ERROR)
        await repo.update_item_status(job["item_id"], job["id"], "failed")

    if stuck_jobs:
        logger.warning("recovered orphaned AI jobs at startup", extra={"count": len(stuck_jobs)})
    return len(stuck_jobs)
