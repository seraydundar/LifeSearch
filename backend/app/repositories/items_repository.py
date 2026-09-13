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

    async def replace_chunks(self, item_id: str, job_id: str, chunks: list[dict[str, Any]]) -> None:
        """Idempotent by design (requirements doc, rule 17) — and, since
        Faz 12 madde 7 (denetim düzeltmesi, see docs/roadmap.md), safe
        against two concurrent reprocessing runs for the same item (e.g.
        the user hits "Tekrar Dene" while an earlier attempt is still in
        flight) in a way the previous version wasn't quite:

        `chunks_item_id_chunk_index_key` (see
        infra/supabase/migrations/0013_chunks_unique.sql) turned this from
        an independent DELETE+INSERT into an UPSERT — that stopped two
        racing runs from *duplicating* chunks, but as two separate HTTP
        requests (an UPSERT, then a DELETE trimming indices past the new
        count), an *older*, slower run's delayed DELETE could still land
        after a *newer* run had already finished, wiping out chunks the
        newer run had just written (its own trim only knows its own,
        smaller chunk count from *before* the newer run added more).

        `replace_chunks_for_job()` (infra/supabase/migrations/
        0015_replace_chunks_atomic.sql) closes that: one atomic RPC call
        that upserts *and* trims within a single transaction, serialized
        per item via an advisory lock, and a no-op if `job_id` is no
        longer the most recent `processing_jobs` row for this item — a
        stale call from an older job can't clobber a newer one's output
        no matter how the two races interleave.
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
        """AI-generated title/description for an image (requirements doc,
        section 14's Dell-monitor example) — only overwrites the fields
        that are actually given. `latitude`/`longitude`/`captured_at`
        come from EXIF instead (section 8-12), not the AI provider —
        see `services/exif_service.py`.

        Job-gated (P1-04, docs/requirements-audit-2026-09-13.md, see
        `update_item_fields_for_job` in infra/supabase/migrations/
        0018_job_gated_item_writes.sql), same reasoning as
        `replace_chunks`/`attach_tags`: an older, slower reprocessing
        run's metadata (e.g. a stale image analysis) must never overwrite
        a newer run's, no matter which HTTP request happens to land last.
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
        """Job-gated atomic UPSERT (P1-04, docs/requirements-audit-2026-09-13.md,
        see `replace_item_content_for_job` in infra/supabase/migrations/
        0018_job_gated_item_writes.sql) — was already a single atomic
        UPSERT on `item_id` (not the old independent DELETE-then-INSERT
        pair; see `item_contents_item_id_key`,
        infra/supabase/migrations/0012_item_contents_unique.sql), but
        still had no job-ownership check: an older, slower run's content
        could still land after a newer run's and overwrite it. Notes
        write their body once at creation instead and never call this.
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
        """Idempotent by design (requirements doc, rule 17) — and, since
        Faz 13 madde 2 (üçüncü bağımsız tarama, denetim düzeltmesi, see
        docs/roadmap.md), safe against two concurrent reprocessing runs
        for the same item the same way `replace_chunks` already was
        (Faz 12 madde 7): this used to be an UPSERT (into `tags`) followed
        by an independent DELETE+INSERT (on `item_tags`) — three separate
        HTTP requests an *older*, slower run's delayed DELETE could still
        land in between, after a *newer* run had already finished writing
        its own tags, wiping them back out to whatever (possibly nothing)
        the older run found.

        `replace_item_tags_for_job()` (infra/supabase/migrations/
        0016_replace_tags_entities_atomic.sql) closes that: one atomic RPC
        call, serialized per item via the same advisory lock
        `replace_chunks_for_job` uses, and a no-op if `job_id` is no
        longer the most recent `processing_jobs` row for this item.
        """
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
        """Flags a possible duplicate found during processing (requirements
        doc, section 46) — never blocks or merges anything, just records
        the best candidate for the client to show a dismissible banner for.

        Job-gated (P1-04, docs/requirements-audit-2026-09-13.md, see
        `mark_duplicate_for_job` in infra/supabase/migrations/
        0018_job_gated_item_writes.sql) — same reasoning as
        `update_item_metadata`.
        """
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
        """Job-gated (P1-04, docs/requirements-audit-2026-09-13.md, see
        `update_item_status_for_job` in infra/supabase/migrations/
        0018_job_gated_item_writes.sql) — without this, an older job
        erroring out *after* a newer job already completed successfully
        could still flip the item back to `failed`; a stale, delayed
        `processing`/`completed` write had the same risk in reverse.
        """
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
        """Used by `job_recovery.py`'s startup sweep — that's the one
        caller with a legitimate reason to look across every user's jobs
        at once, so it constructs this repository with the service_role
        key as its `access_token` (bypasses RLS) rather than a normal
        user's.

        Takes multiple statuses (P1-05, docs/requirements-audit-2026-09-13.md)
        — the sweep needs both `pending` and `processing` jobs, not just
        the latter; see that module's docstring.
        """
        response = await self._client.get(
            f"{self._base_url}/rest/v1/processing_jobs",
            params={"status": f"in.({','.join(statuses)})", "select": "id,item_id"},
        )
        response.raise_for_status()
        return response.json()
