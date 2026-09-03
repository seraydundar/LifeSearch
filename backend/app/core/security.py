"""Auth: verifying the Supabase-issued JWT on incoming requests.

The mobile app authenticates against Supabase Auth directly; the backend
never issues its own tokens. It verifies the bearer token by asking
Supabase itself who it belongs to (GET /auth/v1/user) rather than
decoding the JWT locally — this works regardless of whether the project
uses legacy JWT-format keys or the newer opaque publishable/secret keys,
and stays correct if Supabase rotates its signing key.

Every downstream call (Postgres via PostgREST, Storage) reuses this same
user token, so Row Level Security — not this function — is what actually
scopes a request to its own data (requirements doc, rule 14: "Kullanıcının
verilerini başka kullanıcıların sorgularında kullanma").
"""

from dataclasses import dataclass

import httpx
from fastapi import Header, HTTPException, status

from .config import get_settings


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
    return CurrentUser(id=body["id"], email=body.get("email"), access_token=token)
