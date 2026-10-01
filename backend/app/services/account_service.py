"""Orchestrates account deletion: verify it's possible, best-effort delete
Storage files, then delete the `auth.users` row (cascades to everything else).
"""

import logging
from typing import Protocol

logger = logging.getLogger(__name__)


class _AccountRepo(Protocol):
    def ensure_deletion_available(self) -> None: ...
    async def delete_own_files(self, user_id: str) -> None: ...
    async def delete_auth_user(self, user_id: str) -> None: ...


async def delete_account(user_id: str, repo: _AccountRepo) -> None:
    """Checks config up front so a misconfigured backend fails closed instead of
    deleting files without ever completing the deletion; Storage failures are
    logged and ignored, but delete_auth_user errors propagate.
    """
    repo.ensure_deletion_available()

    try:
        await repo.delete_own_files(user_id)
    except Exception as error:
        logger.warning(
            "account file cleanup failed", extra={"user_id": user_id, "error": str(error)}
        )

    await repo.delete_auth_user(user_id)
