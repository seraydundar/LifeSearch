-- Phase 9 (partial): Hybrid Search + Related Items. Natural-language
-- filtering, Smart Collections and Duplicate Detection stay out of scope
-- here — the requirements doc itself calls all three "ileri aşama"
-- (section 22, 28, 46), and Smart Collections needs a Collections
-- feature that was never built.

-- A generated, indexed tsvector so keyword ranking doesn't re-tokenize
-- `content` on every query.
alter table chunks add column if not exists content_tsv tsvector
  generated always as (to_tsvector('simple', content)) stored;

create index if not exists idx_chunks_content_tsv on chunks using gin (content_tsv);

-- Semantic + keyword combined (requirements doc, section 20), with
-- optional type/date filters (section 21). Combines the two rankings
-- with Reciprocal Rank Fusion rather than a raw weighted sum of
-- similarity + ts_rank — those two scores live on incomparable scales
-- (cosine similarity vs. text-frequency rank), so summing them directly
-- lets whichever happens to have the bigger numbers dominate. RRF only
-- looks at each candidate's *position* in each ranking, so it stays
-- well-behaved regardless of either score's scale.
create or replace function match_chunks_hybrid(
  query_embedding vector(1536),
  query_text text,
  match_count int default 20,
  filter_types text[] default null,
  filter_after timestamptz default null,
  filter_before timestamptz default null,
  rrf_k int default 60
)
returns table (
  chunk_id uuid,
  item_id uuid,
  item_type text,
  item_title text,
  item_created_at timestamptz,
  content text,
  chunk_index int,
  similarity float,
  keyword_rank float,
  score float
)
language sql
stable
as $$
  with candidates as (
    select
      c.id as chunk_id,
      c.item_id,
      i.type as item_type,
      i.title as item_title,
      i.created_at as item_created_at,
      c.content,
      c.chunk_index,
      1 - (c.embedding <=> query_embedding) as similarity,
      coalesce(ts_rank(c.content_tsv, plainto_tsquery('simple', query_text)), 0) as keyword_rank
    from chunks c
    join items i on i.id = c.item_id
    where i.user_id = auth.uid()
      and (filter_types is null or i.type = any(filter_types))
      and (filter_after is null or i.created_at >= filter_after)
      and (filter_before is null or i.created_at <= filter_before)
  ),
  ranked as (
    select
      candidates.*,
      row_number() over (order by similarity desc) as semantic_rank,
      row_number() over (order by keyword_rank desc) as keyword_rank_pos
    from candidates
  )
  select
    chunk_id, item_id, item_type, item_title, item_created_at, content, chunk_index,
    similarity, keyword_rank,
    (1.0 / (rrf_k + semantic_rank)) + (1.0 / (rrf_k + keyword_rank_pos)) as score
  from ranked
  order by score desc
  limit match_count;
$$;

grant execute on function match_chunks_hybrid(
  vector, text, int, text[], timestamptz, timestamptz, int
) to authenticated;

-- Related items (requirements doc, section 47): similarity against the
-- source item's own first chunk, standing in for "what this item is
-- about" without needing pgvector's avg(vector) support.
create or replace function related_items(
  source_item_id uuid,
  match_count int default 6
)
returns table (
  chunk_id uuid,
  item_id uuid,
  item_type text,
  item_title text,
  content text,
  chunk_index int,
  similarity float
)
language sql
stable
as $$
  select
    c.id as chunk_id,
    c.item_id,
    i.type as item_type,
    i.title as item_title,
    c.content,
    c.chunk_index,
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
  order by c.embedding <=> sc.embedding
  limit match_count;
$$;

grant execute on function related_items(uuid, int) to authenticated;
