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
# Mirrors entities.type's check constraint in
# infra/supabase/migrations/0011_entities.sql — kept here too (rather than
# imported from the services layer, which repositories don't depend on)
# so a bad type never reaches Postgres and is silently dropped instead.
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
        # One shared client for this repository's lifetime instead of a
        # fresh TCP+TLS handshake per method call. `process_item()` alone
        # makes 15-20 calls against a single item (get_item, download_file,
        # replace_item_content, replace_chunks, attach_tags,
        # attach_entities, job/status updates, ...) — those used to each
        # open and close their own connection. `headers` set here apply to
        # every request by default; a call site only needs to pass what
        # differs (Content-Type, Prefer) — httpx merges per-request headers
        # on top of the client's, it doesn't replace them.
        self._client = httpx.AsyncClient(headers=self._headers, timeout=15.0)

    async def aclose(self) -> None:
        """Call once this repository is done being used — see
        `processing_pipeline.process_item()`'s `finally` block, its only
        caller today. Safe to await even if nothing was ever requested.
        """
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

    async def replace_chunks(self, item_id: str, chunks: list[dict[str, Any]]) -> None:
        """Idempotent by design (requirements doc, rule 17) — but not via
        an independent DELETE followed by an independent INSERT anymore.
        That used to be two separate HTTP requests, not one transaction:
        two concurrent reprocessing runs for the same item (e.g. the user
        hits "Tekrar Dene" while an earlier attempt is still in flight)
        could each run their DELETE before either ran its INSERT, then
        both INSERTs land — doubling every chunk.

        `chunks_item_id_chunk_index_key` (see
        infra/supabase/migrations/0013_chunks_unique.sql) makes an UPSERT
        possible instead: two racing runs converge on "last writer per
        chunk_index wins", never "both writers' rows exist at once". The
        trailing DELETE only trims indices *past* the new chunk count —
        safe to run any number of times, or concurrently with another
        run's, since it only ever removes rows, never creates any.
        """
        if chunks:
            upsert_response = await self._client.post(
                f"{self._base_url}/rest/v1/chunks",
                params={"on_conflict": "item_id,chunk_index"},
                headers={
                    "Content-Type": "application/json",
                    "Prefer": "resolution=merge-duplicates,return=minimal",
                },
                json=chunks,
                timeout=30.0,  # a full item's worth of chunks in one request
            )
            upsert_response.raise_for_status()

        trim_response = await self._client.delete(
            f"{self._base_url}/rest/v1/chunks",
            params={"item_id": f"eq.{item_id}", "chunk_index": f"gte.{len(chunks)}"},
        )
        trim_response.raise_for_status()

    async def update_item_metadata(
        self,
        item_id: str,
        *,
        title: str | None = None,
        description: str | None = None,
        latitude: float | None = None,
        longitude: float | None = None,
        captured_at: datetime | None = None,
    ) -> None:
        """AI-generated title/description for an image (requirements doc,
        section 14's Dell-monitor example) — only overwrites the fields
        that are actually given. `latitude`/`longitude`/`captured_at`
        come from EXIF instead (section 8-12), not the AI provider —
        see `services/exif_service.py`.
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
        response = await self._client.patch(
            f"{self._base_url}/rest/v1/items",
            params={"id": f"eq.{item_id}"},
            headers={"Content-Type": "application/json"},
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
        """Idempotent via a single atomic UPSERT on `item_id`, not the old
        independent DELETE-then-INSERT pair — two concurrent reprocessing
        runs for the same item used to be able to interleave those into
        two live rows (or a moment with zero). `item_contents_item_id_key`
        (see infra/supabase/migrations/0012_item_contents_unique.sql)
        makes this one PostgREST request instead of two. Notes write
        their body once at creation instead and never call this.
        """
        response = await self._client.post(
            f"{self._base_url}/rest/v1/item_contents",
            params={"on_conflict": "item_id"},
            headers={
                "Content-Type": "application/json",
                "Prefer": "resolution=merge-duplicates,return=minimal",
            },
            json={
                "item_id": item_id,
                "raw_text": raw_text,
                "ocr_text": ocr_text,
                "ai_description": ai_description,
            },
        )
        response.raise_for_status()

    async def attach_tags(self, item_id: str, user_id: str, tag_names: list[str]) -> None:
        """Idempotent by design, same replace pattern as `replace_chunks` —
        reprocessing an item replaces its tag set rather than accumulating
        duplicates from every run.
        """
        names = [n for n in dict.fromkeys(t.strip().lower() for t in tag_names) if n]

        if names:
            # Upsert-by-name so re-tagging with an already-existing tag
            # reuses its row instead of violating the (user_id, name)
            # unique constraint.
            upsert_response = await self._client.post(
                f"{self._base_url}/rest/v1/tags",
                params={"on_conflict": "user_id,name"},
                headers={
                    "Content-Type": "application/json",
                    "Prefer": "resolution=merge-duplicates,return=representation",
                },
                json=[{"user_id": user_id, "name": name} for name in names],
            )
            upsert_response.raise_for_status()
            tag_ids = [row["id"] for row in upsert_response.json()]
        else:
            tag_ids = []

        delete_response = await self._client.delete(
            f"{self._base_url}/rest/v1/item_tags",
            params={"item_id": f"eq.{item_id}"},
        )
        delete_response.raise_for_status()

        if not tag_ids:
            return
        insert_response = await self._client.post(
            f"{self._base_url}/rest/v1/item_tags",
            headers={"Content-Type": "application/json", "Prefer": "return=minimal"},
            json=[{"item_id": item_id, "tag_id": tag_id} for tag_id in tag_ids],
        )
        insert_response.raise_for_status()

    async def attach_entities(
        self, item_id: str, user_id: str, entities: list[dict[str, str]]
    ) -> None:
        """Idempotent, same replace pattern as `attach_tags` — reprocessing
        an item replaces its entity set rather than accumulating
        duplicates from every run.
        """
        deduped: dict[tuple[str, str], str] = {}
        for entity in entities:
            name = str(entity.get("name", "")).strip()
            entity_type = str(entity.get("type", "")).strip().lower()
            if not name or entity_type not in _VALID_ENTITY_TYPES:
                continue
            deduped.setdefault((name.lower(), entity_type), name)
        rows = [{"name": name, "type": t} for (_, t), name in deduped.items()]

        if rows:
            # Upsert-by-(name, type) so re-extracting an already-known
            # entity reuses its row instead of violating the
            # (user_id, name, type) unique constraint.
            upsert_response = await self._client.post(
                f"{self._base_url}/rest/v1/entities",
                params={"on_conflict": "user_id,name,type"},
                headers={
                    "Content-Type": "application/json",
                    "Prefer": "resolution=merge-duplicates,return=representation",
                },
                json=[{"user_id": user_id, **row} for row in rows],
            )
            upsert_response.raise_for_status()
            entity_ids = [row["id"] for row in upsert_response.json()]
        else:
            entity_ids = []

        delete_response = await self._client.delete(
            f"{self._base_url}/rest/v1/item_entities",
            params={"item_id": f"eq.{item_id}"},
        )
        delete_response.raise_for_status()

        if not entity_ids:
            return
        insert_response = await self._client.post(
            f"{self._base_url}/rest/v1/item_entities",
            headers={"Content-Type": "application/json", "Prefer": "return=minimal"},
            json=[{"item_id": item_id, "entity_id": eid} for eid in entity_ids],
        )
        insert_response.raise_for_status()

    async def mark_duplicate(
        self, item_id: str, duplicate_of_item_id: str, similarity: float
    ) -> None:
        """Flags a possible duplicate found during processing (requirements
        doc, section 46) — never blocks or merges anything, just records
        the best candidate for the client to show a dismissible banner for.
        """
        response = await self._client.patch(
            f"{self._base_url}/rest/v1/items",
            params={"id": f"eq.{item_id}"},
            headers={"Content-Type": "application/json"},
            json={
                "duplicate_of_item_id": duplicate_of_item_id,
                "duplicate_similarity": similarity,
                "duplicate_dismissed": False,
            },
        )
        response.raise_for_status()

    async def update_item_status(self, item_id: str, status: str) -> None:
        response = await self._client.patch(
            f"{self._base_url}/rest/v1/items",
            params={"id": f"eq.{item_id}"},
            headers={"Content-Type": "application/json"},
            json={"processing_status": status},
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

    async def find_jobs_by_status(self, status: str) -> list[dict[str, Any]]:
        """Used by `job_recovery.py`'s startup sweep — that's the one
        caller with a legitimate reason to look across every user's jobs
        at once, so it constructs this repository with the service_role
        key as its `access_token` (bypasses RLS) rather than a normal
        user's.
        """
        response = await self._client.get(
            f"{self._base_url}/rest/v1/processing_jobs",
            params={"status": f"eq.{status}", "select": "id,item_id"},
        )
        response.raise_for_status()
        return response.json()
