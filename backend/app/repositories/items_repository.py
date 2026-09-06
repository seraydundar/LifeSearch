"""Talks to Supabase (PostgREST + Storage) over HTTPS, scoped to a single
user's access token — the same one their Flutter app got from Supabase
Auth. Row Level Security, not this class, is what actually keeps one
user's data out of another's queries (requirements doc, rule 14); this
class just forwards the right `Authorization` header on every request.

No service_role key involved. See core/security.py for where the token
comes from.
"""

from datetime import UTC, datetime
from typing import Any

import httpx

from ..core.config import get_settings

_BUCKET = "item-files"


def _now_iso() -> str:
    return datetime.now(UTC).isoformat()


class SupabaseRestRepository:
    def __init__(self, access_token: str) -> None:
        settings = get_settings()
        self._base_url = settings.supabase_url.rstrip("/")
        self._headers = {
            "apikey": settings.supabase_anon_key,
            "Authorization": f"Bearer {access_token}",
        }

    async def get_item(self, item_id: str) -> dict[str, Any]:
        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.get(
                f"{self._base_url}/rest/v1/items",
                params={"id": f"eq.{item_id}", "select": "*"},
                headers=self._headers,
            )
            response.raise_for_status()
            rows = response.json()
            if not rows:
                raise LookupError(f"Item {item_id} not found (or not owned by this user).")
            return rows[0]

    async def get_note_content(self, item_id: str) -> str:
        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.get(
                f"{self._base_url}/rest/v1/item_contents",
                params={"item_id": f"eq.{item_id}", "select": "raw_text"},
                headers=self._headers,
            )
            response.raise_for_status()
            rows = response.json()
            return rows[0]["raw_text"] or "" if rows else ""

    async def download_file(self, storage_path: str) -> bytes:
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.get(
                f"{self._base_url}/storage/v1/object/{_BUCKET}/{storage_path}",
                headers=self._headers,
            )
            response.raise_for_status()
            return response.content

    async def replace_chunks(self, item_id: str, chunks: list[dict[str, Any]]) -> None:
        """Idempotent by design (requirements doc, rule 17): re-processing
        an item deletes its old chunks first, so running the same job
        twice never leaves duplicates behind.
        """
        async with httpx.AsyncClient(timeout=30.0) as client:
            delete_response = await client.delete(
                f"{self._base_url}/rest/v1/chunks",
                params={"item_id": f"eq.{item_id}"},
                headers=self._headers,
            )
            delete_response.raise_for_status()

            if not chunks:
                return
            insert_response = await client.post(
                f"{self._base_url}/rest/v1/chunks",
                headers={
                    **self._headers,
                    "Content-Type": "application/json",
                    "Prefer": "return=minimal",
                },
                json=chunks,
            )
            insert_response.raise_for_status()

    async def update_item_metadata(
        self, item_id: str, *, title: str | None = None, description: str | None = None
    ) -> None:
        """AI-generated title/description for an image (requirements doc,
        section 14's Dell-monitor example) — only overwrites the fields
        that are actually given.
        """
        fields: dict[str, Any] = {}
        if title:
            fields["title"] = title
        if description:
            fields["description"] = description
        if not fields:
            return
        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.patch(
                f"{self._base_url}/rest/v1/items",
                params={"id": f"eq.{item_id}"},
                headers={**self._headers, "Content-Type": "application/json"},
                json=fields,
            )
            response.raise_for_status()

    async def replace_item_content(
        self,
        item_id: str,
        *,
        raw_text: str | None = None,
        ocr_text: str | None = None,
        ai_description: str | None = None,
    ) -> None:
        """Same idempotent replace pattern as `replace_chunks` — re-running
        the pipeline for an item (e.g. after a fix) shouldn't leave two
        `item_contents` rows behind. Notes write their body once at
        creation instead and never call this.
        """
        async with httpx.AsyncClient(timeout=15.0) as client:
            delete_response = await client.delete(
                f"{self._base_url}/rest/v1/item_contents",
                params={"item_id": f"eq.{item_id}"},
                headers=self._headers,
            )
            delete_response.raise_for_status()

            insert_response = await client.post(
                f"{self._base_url}/rest/v1/item_contents",
                headers={
                    **self._headers,
                    "Content-Type": "application/json",
                    "Prefer": "return=minimal",
                },
                json={
                    "item_id": item_id,
                    "raw_text": raw_text,
                    "ocr_text": ocr_text,
                    "ai_description": ai_description,
                },
            )
            insert_response.raise_for_status()

    async def mark_duplicate(
        self, item_id: str, duplicate_of_item_id: str, similarity: float
    ) -> None:
        """Flags a possible duplicate found during processing (requirements
        doc, section 46) — never blocks or merges anything, just records
        the best candidate for the client to show a dismissible banner for.
        """
        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.patch(
                f"{self._base_url}/rest/v1/items",
                params={"id": f"eq.{item_id}"},
                headers={**self._headers, "Content-Type": "application/json"},
                json={
                    "duplicate_of_item_id": duplicate_of_item_id,
                    "duplicate_similarity": similarity,
                    "duplicate_dismissed": False,
                },
            )
            response.raise_for_status()

    async def update_item_status(self, item_id: str, status: str) -> None:
        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.patch(
                f"{self._base_url}/rest/v1/items",
                params={"id": f"eq.{item_id}"},
                headers={**self._headers, "Content-Type": "application/json"},
                json={"processing_status": status},
            )
            response.raise_for_status()

    async def create_job(self, item_id: str, job_type: str) -> str:
        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.post(
                f"{self._base_url}/rest/v1/processing_jobs",
                headers={
                    **self._headers,
                    "Content-Type": "application/json",
                    "Prefer": "return=representation",
                },
                json={"item_id": item_id, "job_type": job_type, "status": "pending"},
            )
            response.raise_for_status()
            return response.json()[0]["id"]

    async def update_job(self, job_id: str, **fields: Any) -> None:
        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.patch(
                f"{self._base_url}/rest/v1/processing_jobs",
                params={"id": f"eq.{job_id}"},
                headers={**self._headers, "Content-Type": "application/json"},
                json=fields,
            )
            response.raise_for_status()

    async def mark_job_started(self, job_id: str) -> None:
        await self.update_job(job_id, status="processing", started_at=_now_iso())

    async def mark_job_completed(self, job_id: str) -> None:
        await self.update_job(job_id, status="completed", progress=100, completed_at=_now_iso())

    async def mark_job_failed(self, job_id: str, error: str) -> None:
        await self.update_job(job_id, status="failed", error_message=error, completed_at=_now_iso())
