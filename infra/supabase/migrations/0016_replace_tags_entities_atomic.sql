-- Faz 13, madde 2 (üçüncü bağımsız tarama, see docs/roadmap.md): the same
-- bug 0015_replace_chunks_atomic.sql fixed for chunks — an older, slower
-- reprocessing run's DELETE landing after a newer run's INSERT, wiping
-- out what the newer run just wrote — was still present in
-- `attach_tags`/`attach_entities`. Those upserted `tags`/`entities` rows
-- (safe on their own — ON CONFLICT DO UPDATE), then DELETEd all of
-- `item_tags`/`item_entities` for the item, then INSERTed the fresh
-- junction rows: three separate HTTP requests an older job's delayed
-- DELETE could still land in between, after a newer job had already
-- finished writing its own junction rows — leaving the item with the
-- *older* run's (possibly empty, if the older run found nothing) tag/
-- entity set instead of the newer one's.
--
-- Same three-part fix as `replace_chunks_for_job`:
--   1. Serialized per item_id via a session-scoped advisory lock — the
--      *same* lock chunks use (`hashtext(item_id::text)`), since it's
--      the same item's processing run being protected either way, and
--      nothing here runs concurrently with a chunk replace for reasons
--      unrelated to which job is newest.
--   2. Conditional on the caller's job still being the most recent
--      `processing_jobs` row for this item — a stale call from an
--      older job becomes a no-op.
--   3. One atomic transaction per table (a single RPC call each), not
--      three independent HTTP requests a client-side crash/retry could
--      interleave between.
--
-- Two RPCs, not one combined call — tags and entities are independent
-- best-effort steps in processing_pipeline.py (a tagging failure doesn't
-- stop entity extraction, see `_attach_tags`/`_attach_entities`), so
-- combining them would make one's failure roll back the other's already-
-- committed write instead of leaving it in place.
--
-- SECURITY INVOKER (the default — not declared here) — runs as the
-- calling user, so the existing `tags`/`item_tags`/`entities`/
-- `item_entities`/`processing_jobs` RLS policies apply exactly as they do
-- for a direct REST insert/delete/select.
create or replace function replace_item_tags_for_job(
  p_item_id uuid,
  p_job_id uuid,
  p_user_id uuid,
  p_tag_names jsonb -- e.g. '["docker", "postgres"]'::jsonb
)
returns void
language plpgsql
as $$
declare
  v_latest_job_id uuid;
begin
  perform pg_advisory_xact_lock(hashtext(p_item_id::text));

  select id into v_latest_job_id
  from processing_jobs
  where item_id = p_item_id
  order by created_at desc
  limit 1;

  if v_latest_job_id is not null and v_latest_job_id <> p_job_id then
    -- A newer job already exists for this item — let its own call
    -- decide this item's final tag set instead.
    return;
  end if;

  delete from item_tags where item_id = p_item_id;

  if jsonb_array_length(p_tag_names) = 0 then
    return;
  end if;

  with upserted as (
    insert into tags (user_id, name)
    select distinct p_user_id, elem
    from jsonb_array_elements_text(p_tag_names) as elem
    on conflict (user_id, name) do update set name = excluded.name
    returning id
  )
  insert into item_tags (item_id, tag_id)
  select p_item_id, id from upserted;
end;
$$;

create or replace function replace_item_entities_for_job(
  p_item_id uuid,
  p_job_id uuid,
  p_user_id uuid,
  p_entities jsonb -- e.g. '[{"name": "Ankara", "type": "place"}, ...]'::jsonb
)
returns void
language plpgsql
as $$
declare
  v_latest_job_id uuid;
begin
  perform pg_advisory_xact_lock(hashtext(p_item_id::text));

  select id into v_latest_job_id
  from processing_jobs
  where item_id = p_item_id
  order by created_at desc
  limit 1;

  if v_latest_job_id is not null and v_latest_job_id <> p_job_id then
    return;
  end if;

  delete from item_entities where item_id = p_item_id;

  if jsonb_array_length(p_entities) = 0 then
    return;
  end if;

  with upserted as (
    insert into entities (user_id, name, type)
    select distinct p_user_id, elem->>'name', elem->>'type'
    from jsonb_array_elements(p_entities) as elem
    on conflict (user_id, name, type) do update set name = excluded.name
    returning id
  )
  insert into item_entities (item_id, entity_id)
  select p_item_id, id from upserted;
end;
$$;
