"""Account deletion (requirements doc, section 49-52) — a single
irreversible endpoint, gated on `SUPABASE_SERVICE_ROLE_KEY` being
configured (see `AccountRepository` for why that specific key, and
nothing else in this backend, needs it).
"""

from fastapi import APIRouter, Depends, HTTPException, status

from ...core.security import CurrentUser, get_current_user
from ...repositories.account_repository import AccountDeletionUnavailable, AccountRepository
from ...services.account_service import delete_account

router = APIRouter(prefix="/account", tags=["account"])


@router.delete("/", status_code=status.HTTP_204_NO_CONTENT)
async def delete_account_endpoint(user: CurrentUser = Depends(get_current_user)) -> None:
    repo = AccountRepository(user.access_token)
    try:
        await delete_account(user.id, repo)
    except AccountDeletionUnavailable as error:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Account deletion is unavailable: {error}",
        ) from error
