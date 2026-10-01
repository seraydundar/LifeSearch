"""Deletes a user's account: own-token file deletion first, then a service_role
auth.users delete (cascades everything else). Availability must be checked before
step 1, or a missing key leaves files deleted but the account intact on every retry.
"""

from typing import Any

import httpx

from ..core.config import get_settings

_BUCKET = "item-files"


class AccountDeletionUnavailable(Exception):
    """SUPABASE_SERVICE_ROLE_KEY isn't configured."""


class AccountRepository:
    def __init__(self, access_token: str) -> None:
        settings = get_settings()
        self._base_url = settings.supabase_url.rstrip("/")
        self._service_role_key = settings.supabase_service_role_key
        self._user_headers = {
            "apikey": settings.supabase_anon_key,
            "Authorization": f"Bearer {access_token}",
        }

    def ensure_deletion_available(self) -> None:
        """Same check as `delete_auth_user`, surfaced to run before anything destructive starts."""
        if not self._service_role_key:
            raise AccountDeletionUnavailable("SUPABASE_SERVICE_ROLE_KEY is not configured.")

    async def delete_own_files(self, user_id: str) -> None:
        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.get(
                f"{self._base_url}/rest/v1/items",
                params={
                    "user_id": f"eq.{user_id}",
                    "storage_path": "not.is.null",
                    "select": "storage_path",
                },
                headers=self._user_headers,
            )
            response.raise_for_status()
            rows: list[dict[str, Any]] = response.json()
            paths = [row["storage_path"] for row in rows if row.get("storage_path")]
            if not paths:
                return

            delete_response = await client.request(
                "DELETE",
                f"{self._base_url}/storage/v1/object/{_BUCKET}",
                headers={**self._user_headers, "Content-Type": "application/json"},
                json={"prefixes": paths},
            )
            delete_response.raise_for_status()

    async def delete_auth_user(self, user_id: str) -> None:
        if not self._service_role_key:
            raise AccountDeletionUnavailable("SUPABASE_SERVICE_ROLE_KEY is not configured.")

        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.delete(
                f"{self._base_url}/auth/v1/admin/users/{user_id}",
                headers={
                    "apikey": self._service_role_key,
                    "Authorization": f"Bearer {self._service_role_key}",
                },
            )
            response.raise_for_status()
