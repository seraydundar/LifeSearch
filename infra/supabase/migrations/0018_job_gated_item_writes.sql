-- P1-04 (docs/requirements-audit-2026-09-13.md): 0015/0016 made
-- chunks/tags/entities safe against an older, slower reprocessing run's
-- write landing after a newer run's — but `update_item_status`,
-- `update_item_metadata` (title/description/EXIF), `replace_item_content`
-- (raw_text/ocr_text/ai_description) and `mark_duplicate` were all still
-- plain, ungated REST calls. An old job finishing (or erroring) after a
-- newer job already completed could still flip a `completed` item back
-- to `failed`, or overwrite a newer job's image description/title with
-- an older, already-superseded analysis.
--
-- Same three-part fix as `replace_chunks_for_job`/
-- `replace_item_tags_for_job` (see their own migrations for the full
-- reasoning): serialized per item_id via the same advisory lock, a no-op
-- once a newer `processing_jobs` row exists for this item, one atomic
-- statement per call. Four small RPCs rather than one combined call —
-- `process_item()` calls these at different points with different
-- fields available (e.g. `update_item_status` runs both before *and*
-- after the metadata/content writes), so forcing them into one call
-- would mean re-sending fields that haven't been produced yet.
--
-- SECURITY INVOKER (the default — not declared here) — same RLS as a
-- direct REST update.
create or replace function update_item_status_for_job(
  p_item_id uuid,
  p_job_id uuid,
  p_status text
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
    -- A newer job already exists — e.g. this is an older run's delayed
    -- `failed` landing after a newer run already completed. Let the
    -- newer job's own status stand.
    return;
  end if;

  update items set processing_status = p_status where id = p_item_id;
end;
$$;

grant execute on function update_item_status_for_job(uuid, uuid, text) to authenticated;

-- `p_fields` carries only the keys that are actually being set (mirrors
-- the Python side's existing "only overwrite what's given" contract) —
-- a key that's absent leaves that column untouched, same as before this
-- fix. Only ever items() own AI-generated metadata columns; never
-- `processing_status`/`private`/anything user-controlled.
create or replace function update_item_fields_for_job(
  p_item_id uuid,
  p_job_id uuid,
  p_fields jsonb
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

  update items set
    title = coalesce(p_fields->>'title', title),
    description = coalesce(p_fields->>'description', description),
    latitude = coalesce((p_fields->>'latitude')::double precision, latitude),
    longitude = coalesce((p_fields->>'longitude')::double precision, longitude),
    captured_at = coalesce((p_fields->>'captured_at')::timestamptz, captured_at)
  where id = p_item_id;
end;
$$;

grant execute on function update_item_fields_for_job(uuid, uuid, jsonb) to authenticated;

create or replace function replace_item_content_for_job(
  p_item_id uuid,
  p_job_id uuid,
  p_raw_text text,
  p_ocr_text text,
  p_ai_description text
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

  insert into item_contents (item_id, raw_text, ocr_text, ai_description)
  values (p_item_id, p_raw_text, p_ocr_text, p_ai_description)
  on conflict (item_id) do update
    set raw_text = excluded.raw_text,
        ocr_text = excluded.ocr_text,
        ai_description = excluded.ai_description;
end;
$$;

grant execute on function replace_item_content_for_job(uuid, uuid, text, text, text) to authenticated;

create or replace function mark_duplicate_for_job(
  p_item_id uuid,
  p_job_id uuid,
  p_duplicate_of_item_id uuid,
  p_similarity float
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

  update items set
    duplicate_of_item_id = p_duplicate_of_item_id,
    duplicate_similarity = p_similarity,
    duplicate_dismissed = false
  where id = p_item_id;
end;
$$;

grant execute on function mark_duplicate_for_job(uuid, uuid, uuid, float) to authenticated;
