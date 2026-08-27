"""items endpoints.

Not wired into the app yet — this module is scaffolding for a later phase.
See docs/requirements.md for what belongs here.
"""

from fastapi import APIRouter

router = APIRouter(prefix="/items", tags=["items"])
