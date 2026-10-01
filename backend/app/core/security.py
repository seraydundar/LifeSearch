"""Verifies the Supabase bearer token via GET /auth/v1/user instead of decoding it locally,
so it works across key formats and signing-key rotation. RLS, not this function, scopes data access.
"""

from dataclasses import dataclass

import httpx
from fastapi import Header, HTTPException, status

from .config import get_settings
from .logging import user_id_var


@dataclass(frozen=True, slots=True)
class CurrentUser:
    id: str
    email: str | None
    access_token: str


async def get_current_user(authorization: str = Header(default="")) -> CurrentUser:
    if not authorization.lower().startswith("bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or malformed Authorization header.",
        )
    token = authorization.removeprefix("Bearer ").removeprefix("bearer ").strip()

    settings = get_settings()
    if not settings.supabase_url or not settings.supabase_anon_key:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Backend is missing SUPABASE_URL/SUPABASE_ANON_KEY configuration.",
        )

    async with httpx.AsyncClient(timeout=10.0) as client:
        response = await client.get(
            f"{settings.supabase_url}/auth/v1/user",
            headers={
                "Authorization": f"Bearer {token}",
                "apikey": settings.supabase_anon_key,
            },
        )

    if response.status_code != 200:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired session.",
        )

    body = response.json()
    # Picked up by core/logging.py so the rest of this request's log lines carry the user id.
    user_id_var.set(body["id"])
    return CurrentUser(id=body["id"], email=body.get("email"), access_token=token)
