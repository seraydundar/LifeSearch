"""Recovers processing_jobs stuck at pending/processing from a crash/restart;
must run once at startup before any request is served, since that timing is
what proves such a row is orphaned rather than genuinely in-flight.

Single-instance assumption: a multi-replica deployment would need a
lease/lock instead of this startup-timing argument.
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
    """Returns how many jobs were recovered. `repo` must use the service_role
    key — swept jobs belong to arbitrary users, not whoever restarted the server.
    """
    # Includes "pending" too: /process-item creates the row before returning
    # 202, so a crash in that gap leaves a pending (not just processing) row.
    stuck_jobs = await repo.find_jobs_by_status(["pending", "processing"])
    for job in stuck_jobs:
        # update_item_status is job-gated; the single-instance assumption above
        # guarantees this is still the item's latest job, so it always applies.
        await repo.mark_job_failed(job["id"], _ORPHANED_ERROR)
        await repo.update_item_status(job["item_id"], job["id"], "failed")

    if stuck_jobs:
        logger.warning("recovered orphaned AI jobs at startup", extra={"count": len(stuck_jobs)})
    return len(stuck_jobs)
