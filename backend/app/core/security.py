"""Auth helpers.

The mobile app authenticates against Supabase Auth directly. The backend's
job is to VERIFY the Supabase-issued JWT on incoming requests (never to
issue its own tokens) and to scope every query to the authenticated user's
id, on top of Postgres Row Level Security.

Implemented in Phase 4 once the backend starts receiving authenticated
requests from the app.
"""

from fastapi import Header, HTTPException, status


async def get_current_user_id(authorization: str = Header(default="")) -> str:
    """Placeholder dependency. Will decode + verify the Supabase JWT
    from the Authorization header and return the user's id.
    """
    if not authorization:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing Authorization header",
        )
    raise HTTPException(
        status_code=status.HTTP_501_NOT_IMPLEMENTED,
        detail="JWT verification not implemented yet",
    )
