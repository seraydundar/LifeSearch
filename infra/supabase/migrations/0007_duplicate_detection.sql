-- Duplicate Detection (requirements doc, section 46) — the third of the
-- three "ileri aşama" sub-topics left out of Phase 9's first pass
-- (0006_hybrid_and_related.sql). Deliberately simple: no separate table,
-- just three columns on `items` recording the single best duplicate
-- candidate found at processing time. A user can always add near-
-- identical content on purpose (re-scanning the same document, say), so
-- this only ever *flags*, never blocks or auto-merges.

alter table items add column if not exists duplicate_of_item_id uuid references items(id) on delete set null;
alter table items add column if not exists duplicate_similarity float;
alter table items add column if not exists duplicate_dismissed boolean not null default false;

-- Same first-chunk-as-anchor heuristic as `related_items`, but restricted
-- to genuinely near-identical content (default threshold 0.93) and
-- returning at most one match — the pipeline only needs to know "is
-- there already something basically like this", not a ranked list.
create or replace function find_duplicate_candidate(
  source_item_id uuid,
  similarity_threshold float default 0.93
)
returns table (
  item_id uuid,
  item_type text,
  item_title text,
  similarity float
)
language sql
stable
as $$
  select
    c.item_id,
    i.type as item_type,
    i.title as item_title,
    1 - (c.embedding <=> sc.embedding) as similarity
  from chunks c
  join items i on i.id = c.item_id
  cross join lateral (
    select embedding from chunks
    where item_id = source_item_id
    order by chunk_index
    limit 1
  ) sc
  where i.user_id = auth.uid()
    and c.item_id != source_item_id
    and c.chunk_index = 0
    and 1 - (c.embedding <=> sc.embedding) >= similarity_threshold
  order by c.embedding <=> sc.embedding
  limit 1;
$$;

grant execute on function find_duplicate_candidate(uuid, float) to authenticated;
