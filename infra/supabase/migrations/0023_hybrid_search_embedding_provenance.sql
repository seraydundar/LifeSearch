-- P3 (docs/requirements-audit-2026-09-13.md): search must never compare
-- a query embedding against a chunk vector from a *different* provider/
-- model's embedding space — the cosine similarity would be meaningless,
-- not just "less accurate". Adds two optional filter params; when the
-- caller passes both (search_service.semantic_search now always does —
-- see search_repository.py), a chunk whose own embedding_provider/model
-- is set but doesn't match the currently configured one is excluded.
--
-- A chunk with a *null* embedding_provider (every chunk embedded before
-- 0021_chunk_embedding_provenance.sql existed) is never excluded by
-- this — see that migration's own comment for why null means "trust
-- it", not "unknown, therefore stale". A caller that omits both filter
-- params (passes null for both) gets the old, unfiltered behavior —
-- this is additive, not a breaking change to the function's contract.
drop function if exists match_chunks_hybrid(vector, text, int, text[], timestamptz, timestamptz, int, boolean);

create function match_chunks_hybrid(
  query_embedding vector(1536),
  query_text text,
  match_count int default 20,
  filter_types text[] default null,
  filter_after timestamptz default null,
  filter_before timestamptz default null,
  rrf_k int default 60,
  include_private boolean default false,
  filter_embedding_provider text default null,
  filter_embedding_model text default null
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
      greatest(
        coalesce(ts_rank(c.content_tsv, plainto_tsquery('simple', query_text)), 0),
        coalesce(
          ts_rank(to_tsvector('simple', coalesce(i.title, '')), plainto_tsquery('simple', query_text)),
          0
        )
      ) as keyword_rank
    from chunks c
    join items i on i.id = c.item_id
    where i.user_id = auth.uid()
      and (include_private or i.private = false)
      and (filter_types is null or i.type = any(filter_types))
      and (filter_after is null or i.created_at >= filter_after)
      and (filter_before is null or i.created_at <= filter_before)
      and (
        filter_embedding_provider is null
        or c.embedding_provider is null
        or (
          c.embedding_provider = filter_embedding_provider
          and c.embedding_model = filter_embedding_model
        )
      )
  ),
  ranked as (
    select
      candidates.*,
      row_number() over (order by similarity desc) as semantic_rank,
      case when keyword_rank > 0
        then row_number() over (partition by (keyword_rank > 0) order by keyword_rank desc)
      end as keyword_rank_pos
    from candidates
  )
  select
    chunk_id, item_id, item_type, item_title, item_created_at, content, chunk_index,
    similarity, keyword_rank,
    (1.0 / (rrf_k + semantic_rank)) + coalesce(1.0 / (rrf_k + keyword_rank_pos), 0) as score
  from ranked
  order by score desc
  limit match_count;
$$;

grant execute on function match_chunks_hybrid(
  vector, text, int, text[], timestamptz, timestamptz, int, boolean, text, text
) to authenticated;
