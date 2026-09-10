"""Orchestrates account deletion (requirements doc, section 49-52):
verify deletion is actually possible, delete the user's Storage files
(best-effort), then delete their `auth.users` row, which cascades to
remove everything else. Kept separate from `AccountRepository` so the
ordering/error-handling here is testable with a fake — same pattern as
`processing_pipeline.py`'s best-effort helpers (`_check_for_duplicate`,
`_attach_tags`).
"""

import logging
from typing import Protocol

logger = logging.getLogger(__name__)


class _AccountRepo(Protocol):
    def ensure_deletion_available(self) -> None: ...
    async def delete_own_files(self, user_id: str) -> None: ...
    async def delete_auth_user(self, user_id: str) -> None: ...


async def delete_account(user_id: str, repo: _AccountRepo) -> None:
    """`ensure_deletion_available` runs first and does no I/O of its own —
    it exists so a missing `SUPABASE_SERVICE_ROLE_KEY` is caught *before*
    `delete_own_files` ever runs, not after. `delete_auth_user` already
    raises the same `AccountDeletionUnavailable` if the key is missing,
    but only after the files are already gone — checking up front means a
    misconfigured backend fails closed (nothing touched) instead of
    deleting a user's files on every attempt without ever finishing the
    job that was supposed to justify it.

    Once past that, whatever `repo.delete_auth_user` raises still
    propagates straight to the caller — this never partially deletes an
    account over that. A Storage failure, by contrast, is logged and
    ignored: an orphaned file with no owner left is a far smaller problem
    than a user who asked to be deleted and wasn't.
    """
    repo.ensure_deletion_available()

    try:
        await repo.delete_own_files(user_id)
    except Exception as error:
        logger.warning(
            "account file cleanup failed", extra={"user_id": user_id, "error": str(error)}
        )

    await repo.delete_auth_user(user_id)
