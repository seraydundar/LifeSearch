-- P3 (docs/requirements-audit-2026-09-13.md): replace_chunks_for_job()
-- (0015_replace_chunks_atomic.sql) upserted content/embedding/metadata
-- only — chunks.embedding_provider/embedding_model (0021_chunk_embedding_
-- provenance.sql) never got written by it, so every chunk stayed
-- permanently untagged no matter what processing_pipeline.py sent.
-- Same signature, same advisory-lock/job-gating body otherwise — see
-- that migration's own comment for why both of those exist.
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
  perform pg_advisory_xact_lock(hashtext(p_item_id::text));

  select id into v_latest_job_id
  from processing_jobs
  where item_id = p_item_id
  order by created_at desc
  limit 1;

  if v_latest_job_id is not null and v_latest_job_id <> p_job_id then
    return;
  end if;

  insert into chunks (
    item_id, chunk_index, content, embedding, metadata,
    embedding_provider, embedding_model
  )
  select
    p_item_id,
    (elem->>'chunk_index')::integer,
    elem->>'content',
    (elem->>'embedding')::vector,
    coalesce(elem->'metadata', '{}'::jsonb),
    elem->>'embedding_provider',
    elem->>'embedding_model'
  from jsonb_array_elements(p_chunks) as elem
  on conflict (item_id, chunk_index) do update
    set content = excluded.content,
        embedding = excluded.embedding,
        metadata = excluded.metadata,
        embedding_provider = excluded.embedding_provider,
        embedding_model = excluded.embedding_model;

  delete from chunks
  where item_id = p_item_id
    and chunk_index >= jsonb_array_length(p_chunks);
end;
$$;
