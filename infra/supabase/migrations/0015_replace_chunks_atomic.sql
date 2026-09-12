-- Fixes a real residual gap found by an independent re-audit (2026-09-11,
-- see docs/roadmap.md "Faz 12", madde 7): 0013_chunks_unique.sql's UPSERT
-- stopped two concurrent reprocessing runs from *duplicating* chunks, but
-- didn't stop an *older*, slower run's trailing DELETE (trimming
-- chunk_index >= its own, smaller chunk count) from wiping out chunk
-- rows a *newer*, already-finished run had just written. Two separate
-- HTTP requests (an UPSERT, then a DELETE) still let an older job's
-- delayed DELETE land after a newer job's own UPSERT+DELETE pair had
-- already completed — e.g. job A produces 1 chunk, job B (started later)
-- produces 3 and finishes first; A's trailing `chunk_index >= 1` DELETE
-- then lands and wipes B's chunks 1 and 2, leaving only chunk 0.
--
-- `replace_chunks_for_job()` makes the whole replace operation:
--   1. Serialized per item_id via a session-scoped advisory lock, so two
--      concurrent calls for the same item never interleave their
--      SELECT/INSERT/DELETE steps with each other.
--   2. Conditional on the caller's job still being the most recent
--      `processing_jobs` row for this item — a stale, delayed call from
--      an older job becomes a no-op instead of touching anything, once a
--      newer job already exists. Because of (1), by the time a second
--      call for the same item gets to run this check, the first call's
--      writes (if any) are already fully committed — so whichever call
--      corresponds to the truly-latest job always gets the final say,
--      regardless of which one happened to *start* first.
--   3. One atomic transaction (a single RPC call), not two independent
--      HTTP requests a client-side crash/retry could interleave between.
--
-- SECURITY INVOKER (the default — not declared here) — runs as the
-- calling user, so the existing `chunks_owner`/`items_owner`/
-- `processing_jobs` RLS policies apply exactly as they do for a direct
-- REST insert/delete/select; this grants no privilege the caller didn't
-- already have.
create or replace function replace_chunks_for_job(
  p_item_id uuid,
  p_job_id uuid,
  p_chunks jsonb
)
returns void
language plpgsql
as $$
declare
  v_latest_job_id uuid;
begin
  -- Blocks until any other in-flight call for the same item_id commits —
  -- what actually makes step 2 below race-free, not just "usually right".
  perform pg_advisory_xact_lock(hashtext(p_item_id::text));

  select id into v_latest_job_id
  from processing_jobs
  where item_id = p_item_id
  order by created_at desc
  limit 1;

  if v_latest_job_id is not null and v_latest_job_id <> p_job_id then
    -- A newer job already exists for this item — this call is from a
    -- stale run; let the newer job's own call decide this item's final
    -- chunk set instead.
    return;
  end if;

  insert into chunks (item_id, chunk_index, content, embedding, metadata)
  select
    p_item_id,
    (elem->>'chunk_index')::integer,
    elem->>'content',
    (elem->>'embedding')::vector,
    coalesce(elem->'metadata', '{}'::jsonb)
  from jsonb_array_elements(p_chunks) as elem
  on conflict (item_id, chunk_index) do update
    set content = excluded.content,
        embedding = excluded.embedding,
        metadata = excluded.metadata;

  delete from chunks
  where item_id = p_item_id
    and chunk_index >= jsonb_array_length(p_chunks);
end;
$$;
