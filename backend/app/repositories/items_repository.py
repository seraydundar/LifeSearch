"""Talks to Supabase (PostgREST + Storage) scoped to a single user's access token.
RLS, not this class, keeps one user's data out of another's queries.
"""

from datetime import UTC, datetime
from typing import Any

import httpx

from ..core.config import get_settings

_BUCKET = "item-files"
# Mirrors entities.type's DB check constraint, so a bad type is dropped here, not sent to Postgres.
_VALID_ENTITY_TYPES = {"person", "place", "organization", "date"}


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
        # One shared client (not per-call) to avoid a fresh TCP+TLS handshake each time;
        # per-request headers merge on top of these, they don't replace them.
        self._client = httpx.AsyncClient(headers=self._headers, timeout=15.0)

    async def aclose(self) -> None:
        """Call once done with this repository. Safe to await even if nothing was requested."""
        await self._client.aclose()

    async def get_item(self, item_id: str) -> dict[str, Any]:
        response = await self._client.get(
            f"{self._base_url}/rest/v1/items",
            params={"id": f"eq.{item_id}", "select": "*"},
        )
        response.raise_for_status()
        rows = response.json()
        if not rows:
            raise LookupError(f"Item {item_id} not found (or not owned by this user).")
        return rows[0]

    async def get_note_content(self, item_id: str) -> str:
        response = await self._client.get(
            f"{self._base_url}/rest/v1/item_contents",
            params={"item_id": f"eq.{item_id}", "select": "raw_text"},
        )
        response.raise_for_status()
        rows = response.json()
        return rows[0]["raw_text"] or "" if rows else ""

    async def download_file(self, storage_path: str) -> bytes:
        response = await self._client.get(
            f"{self._base_url}/storage/v1/object/{_BUCKET}/{storage_path}",
            timeout=30.0,  # larger files (PDFs, audio) need more room than the 15s default
        )
        response.raise_for_status()
        return response.content

    async def replace_chunks(self, item_id: str, job_id: str, chunks: list[dict[str, Any]]) -> None:
        """Atomic upsert+trim RPC, job-gated: a no-op if `job_id` isn't the item's
        most recent job, so a stale/delayed run can't clobber a newer run's chunks.
        """
        response = await self._client.post(
            f"{self._base_url}/rest/v1/rpc/replace_chunks_for_job",
            headers={"Content-Type": "application/json"},
            json={"p_item_id": item_id, "p_job_id": job_id, "p_chunks": chunks},
            timeout=30.0,  # a full item's worth of chunks in one request
        )
        response.raise_for_status()

    async def update_item_metadata(
        self,
        item_id: str,
        job_id: str,
        *,
        title: str | None = None,
        description: str | None = None,
        latitude: float | None = None,
        longitude: float | None = None,
        captured_at: datetime | None = None,
    ) -> None:
        """Only overwrites fields actually given. Job-gated like `replace_chunks`, so a
        stale run's metadata can't overwrite a newer run's.
        """
        fields: dict[str, Any] = {}
        if title:
            fields["title"] = title
        if description:
            fields["description"] = description
        if latitude is not None:
            fields["latitude"] = latitude
        if longitude is not None:
            fields["longitude"] = longitude
        if captured_at is not None:
            fields["captured_at"] = captured_at.isoformat()
        if not fields:
            return
        response = await self._client.post(
            f"{self._base_url}/rest/v1/rpc/update_item_fields_for_job",
            headers={"Content-Type": "application/json"},
            json={"p_item_id": item_id, "p_job_id": job_id, "p_fields": fields},
        )
        response.raise_for_status()

    async def replace_item_content(
        self,
        item_id: str,
        job_id: str,
        *,
        raw_text: str | None = None,
        ocr_text: str | None = None,
        ai_description: str | None = None,
    ) -> None:
        """Job-gated atomic upsert, same stale-run protection as `replace_chunks`.
        Notes write their body once at creation and never call this.
        """
        response = await self._client.post(
            f"{self._base_url}/rest/v1/rpc/replace_item_content_for_job",
            headers={"Content-Type": "application/json"},
            json={
                "p_item_id": item_id,
                "p_job_id": job_id,
                "p_raw_text": raw_text,
                "p_ocr_text": ocr_text,
                "p_ai_description": ai_description,
            },
        )
        response.raise_for_status()

    async def attach_tags(
        self, item_id: str, job_id: str, user_id: str, tag_names: list[str]
    ) -> None:
        """Atomic RPC, job-gated the same way as `replace_chunks` — see its docstring."""
        names = [n for n in dict.fromkeys(t.strip().lower() for t in tag_names) if n]
        response = await self._client.post(
            f"{self._base_url}/rest/v1/rpc/replace_item_tags_for_job",
            headers={"Content-Type": "application/json"},
            json={
                "p_item_id": item_id,
                "p_job_id": job_id,
                "p_user_id": user_id,
                "p_tag_names": names,
            },
        )
        response.raise_for_status()

    async def attach_entities(
        self, item_id: str, job_id: str, user_id: str, entities: list[dict[str, str]]
    ) -> None:
        """Same fix, same reasoning as `attach_tags` — see its docstring."""
        deduped: dict[tuple[str, str], str] = {}
        for entity in entities:
            name = str(entity.get("name", "")).strip()
            entity_type = str(entity.get("type", "")).strip().lower()
            if not name or entity_type not in _VALID_ENTITY_TYPES:
                continue
            deduped.setdefault((name.lower(), entity_type), name)
        rows = [{"name": name, "type": t} for (_, t), name in deduped.items()]

        response = await self._client.post(
            f"{self._base_url}/rest/v1/rpc/replace_item_entities_for_job",
            headers={"Content-Type": "application/json"},
            json={
                "p_item_id": item_id,
                "p_job_id": job_id,
                "p_user_id": user_id,
                "p_entities": rows,
            },
        )
        response.raise_for_status()

    async def mark_duplicate(
        self, item_id: str, job_id: str, duplicate_of_item_id: str, similarity: float
    ) -> None:
        """Records a possible-duplicate candidate; never blocks/merges. Job-gated like metadata."""
        response = await self._client.post(
            f"{self._base_url}/rest/v1/rpc/mark_duplicate_for_job",
            headers={"Content-Type": "application/json"},
            json={
                "p_item_id": item_id,
                "p_job_id": job_id,
                "p_duplicate_of_item_id": duplicate_of_item_id,
                "p_similarity": similarity,
            },
        )
        response.raise_for_status()

    async def update_item_status(self, item_id: str, job_id: str, status: str) -> None:
        """Job-gated: a stale job's delayed write could otherwise flip a newer job's result back."""
        response = await self._client.post(
            f"{self._base_url}/rest/v1/rpc/update_item_status_for_job",
            headers={"Content-Type": "application/json"},
            json={"p_item_id": item_id, "p_job_id": job_id, "p_status": status},
        )
        response.raise_for_status()

    async def create_job(self, item_id: str, job_type: str) -> str:
        response = await self._client.post(
            f"{self._base_url}/rest/v1/processing_jobs",
            headers={"Content-Type": "application/json", "Prefer": "return=representation"},
            json={"item_id": item_id, "job_type": job_type, "status": "pending"},
        )
        response.raise_for_status()
        return response.json()[0]["id"]

    async def update_job(self, job_id: str, **fields: Any) -> None:
        response = await self._client.patch(
            f"{self._base_url}/rest/v1/processing_jobs",
            params={"id": f"eq.{job_id}"},
            headers={"Content-Type": "application/json"},
            json=fields,
        )
        response.raise_for_status()

    async def mark_job_started(self, job_id: str) -> None:
        await self.update_job(job_id, status="processing", started_at=_now_iso())

    async def mark_job_completed(self, job_id: str) -> None:
        await self.update_job(job_id, status="completed", progress=100, completed_at=_now_iso())

    async def mark_job_failed(self, job_id: str, error: str) -> None:
        await self.update_job(job_id, status="failed", error_message=error, completed_at=_now_iso())

    async def find_jobs_by_status(self, statuses: list[str]) -> list[dict[str, Any]]:
        """Used by job_recovery.py's sweep, built with the service_role key to see all jobs."""
        response = await self._client.get(
            f"{self._base_url}/rest/v1/processing_jobs",
            params={"status": f"in.({','.join(statuses)})", "select": "id,item_id"},
        )
        response.raise_for_status()
        return response.json()

    async def find_stale_chunk_item_ids(
        self, current_provider: str, current_embedding_model: str
    ) -> list[str]:
        """Deduped item ids with a chunk embedded by a different provider/model than now in use.
        A null embedding_provider (pre-dates this feature) is never stale.
        """
        response = await self._client.get(
            f"{self._base_url}/rest/v1/chunks",
            params={
                "select": "item_id",
                "embedding_provider": "not.is.null",
                "or": (
                    f"(embedding_provider.neq.{current_provider},"
                    f"embedding_model.neq.{current_embedding_model})"
                ),
            },
        )
        response.raise_for_status()
        return sorted({row["item_id"] for row in response.json()})

    async def get_chunks_for_item(self, item_id: str) -> list[dict[str, Any]]:
        """All of an item's chunks, oldest index first."""
        response = await self._client.get(
            f"{self._base_url}/rest/v1/chunks",
            params={
                "item_id": f"eq.{item_id}",
                "select": "chunk_index,content,metadata",
                "order": "chunk_index",
            },
        )
        response.raise_for_status()
        return response.json()
