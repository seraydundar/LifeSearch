import pytest

from app.repositories.account_repository import AccountDeletionUnavailable
from app.services.account_service import delete_account


class FakeAccountRepo:
    def __init__(
        self,
        *,
        available: bool = True,
        files_error: Exception | None = None,
        auth_error: Exception | None = None,
    ):
        self.available = available
        self.files_error = files_error
        self.auth_error = auth_error
        self.files_deleted_for: list[str] = []
        self.auth_deleted_for: list[str] = []

    def ensure_deletion_available(self) -> None:
        if not self.available:
            raise AccountDeletionUnavailable("no service_role key")

    async def delete_own_files(self, user_id: str) -> None:
        self.files_deleted_for.append(user_id)
        if self.files_error is not None:
            raise self.files_error

    async def delete_auth_user(self, user_id: str) -> None:
        self.auth_deleted_for.append(user_id)
        if self.auth_error is not None:
            raise self.auth_error


@pytest.mark.asyncio
async def test_deletes_files_then_the_auth_user():
    repo = FakeAccountRepo()

    await delete_account("user-1", repo)

    assert repo.files_deleted_for == ["user-1"]
    assert repo.auth_deleted_for == ["user-1"]


@pytest.mark.asyncio
async def test_a_failing_file_cleanup_does_not_block_deleting_the_account():
    """An orphaned file with no owner left is a far smaller problem than
    a user who asked to be deleted and wasn't.
    """
    repo = FakeAccountRepo(files_error=RuntimeError("storage down"))

    await delete_account("user-1", repo)  # must not raise

    assert repo.auth_deleted_for == ["user-1"]


@pytest.mark.asyncio
async def test_propagates_account_deletion_unavailable_without_pretending_to_succeed():
    repo = FakeAccountRepo(auth_error=AccountDeletionUnavailable("no service_role key"))

    with pytest.raises(AccountDeletionUnavailable):
        await delete_account("user-1", repo)


@pytest.mark.asyncio
async def test_a_different_auth_deletion_error_also_propagates():
    repo = FakeAccountRepo(auth_error=RuntimeError("network blip"))

    with pytest.raises(RuntimeError):
        await delete_account("user-1", repo)


@pytest.mark.asyncio
async def test_an_unavailable_backend_never_touches_files():
    """Regression guard: this used to check availability inside
    delete_auth_user, which only runs *after* delete_own_files — a
    misconfigured backend would delete a user's files on every attempt
    and never actually finish deleting the account. Availability is now
    checked first, before anything destructive starts.
    """
    repo = FakeAccountRepo(available=False)

    with pytest.raises(AccountDeletionUnavailable):
        await delete_account("user-1", repo)

    assert repo.files_deleted_for == []
    assert repo.auth_deleted_for == []
