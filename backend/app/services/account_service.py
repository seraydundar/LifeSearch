"""Orchestrates account deletion (requirements doc, section 49-52):
delete the user's Storage files (best-effort), then delete their
`auth.users` row, which cascades to remove everything else. Kept
separate from `AccountRepository` so the ordering/error-handling here is
testable with a fake — same pattern as `processing_pipeline.py`'s
best-effort helpers (`_check_for_duplicate`, `_attach_tags`).
"""

import logging
from typing import Protocol

logger = logging.getLogger(__name__)


class _AccountRepo(Protocol):
    async def delete_own_files(self, user_id: str) -> None: ...
    async def delete_auth_user(self, user_id: str) -> None: ...


async def delete_account(user_id: str, repo: _AccountRepo) -> None:
    """Whatever `repo.delete_auth_user` raises (including
    `AccountDeletionUnavailable`) propagates straight to the caller —
    this never partially deletes an account over that. A Storage
    failure, by contrast, is logged and ignored: an orphaned file with
    no owner left is a far smaller problem than a user who asked to be
    deleted and wasn't.
    """
    try:
        await repo.delete_own_files(user_id)
    except Exception as error:
        logger.warning(
            "account file cleanup failed", extra={"user_id": user_id, "error": str(error)}
        )

    await repo.delete_auth_user(user_id)
