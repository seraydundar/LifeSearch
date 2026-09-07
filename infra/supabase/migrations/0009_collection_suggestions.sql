-- Smart Collections, the AI-suggestion half (requirements doc, section
-- 129) — 0008_collections.sql only added the plain, user-made version.
-- This RPC does the one thing that genuinely needs the database: finding
-- which of the user's not-yet-collected items are pairwise similar
-- enough to suggest grouping. Turning those pairs into actual clusters
-- (union-find) and naming each one happens in Python — see
-- backend/app/services/collection_suggestion_service.py — since that's
-- easier to read, test and (for naming) hand to an LLM than to do in SQL.

create or replace function item_similarity_pairs(
  similarity_threshold float default 0.75,
  max_pairs int default 500
)
returns table (
  item_a uuid,
  item_a_title text,
  item_a_type text,
  item_b uuid,
  item_b_title text,
  item_b_type text,
  similarity float
)
language sql
stable
as $$
  with anchors as (
    -- One embedding per item — its first chunk, same anchor heuristic as
    -- related_items/find_duplicate_candidate. Items already in some
    -- collection are excluded: this only ever suggests groupings for
    -- what the user hasn't organized yet.
    select distinct on (c.item_id)
      c.item_id, c.embedding, i.title, i.type
    from chunks c
    join items i on i.id = c.item_id
    where i.user_id = auth.uid()
      and not exists (select 1 from collection_items ci where ci.item_id = c.item_id)
    order by c.item_id, c.chunk_index
  )
  select
    a.item_id, a.title, a.type,
    b.item_id, b.title, b.type,
    1 - (a.embedding <=> b.embedding) as similarity
  from anchors a
  join anchors b on a.item_id < b.item_id
  where 1 - (a.embedding <=> b.embedding) >= similarity_threshold
  order by similarity desc
  limit max_pairs;
$$;

grant execute on function item_similarity_pairs(float, int) to authenticated;
