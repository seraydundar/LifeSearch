-- P2-01 (docs/requirements-audit-2026-09-13.md): two real relevance gaps
-- in match_chunks_hybrid, left over from 0006_hybrid_and_related.sql:
--
--   1. Every candidate chunk got a `keyword_rank_pos` via a plain
--      `row_number() over (order by keyword_rank desc)`, including
--      chunks with a keyword_rank of exactly 0 (no keyword match at
--      all). Ties among every zero-match row got resolved by whatever
--      arbitrary physical order Postgres happened to scan them in, so a
--      chunk with literally no keyword relevance could still land at a
--      decent rank position purely by luck and pick up real RRF score
--      from a signal it never actually matched on.
--   2. `keyword_rank` only ever looked at `chunks.content` — a query
--      matching an item's *title* (but not any chunk's body text
--      verbatim) got no keyword-search credit for it at all, even
--      though title is exactly the kind of short, information-dense
--      text keyword search is best at.
--
-- Fix for (1): only chunks with `keyword_rank > 0` get a `keyword_rank_pos`
-- at all (computed in its own partition, so the excluded zero-match rows
-- can't shift anyone else's numbering) — everyone else's keyword-side RRF
-- term is `coalesce(..., 0)`, an honest zero contribution instead of a
-- lucky tie-break rank.
--
-- Fix for (2): `keyword_rank` is now the *better* of a chunk's own
-- content match and its item's title match (`greatest(...)`, not summed
-- — the two scores live on the same ts_rank scale but come from
-- differently-sized documents, and summing would let a long chunk's
-- content match and its title match double-count for the same
-- underlying relevance). Item-level tag/entity keyword matching is a
-- further, separately-scoped improvement — not built here.
drop function if exists match_chunks_hybrid(vector, text, int, text[], timestamptz, timestamptz, int, boolean);

create function match_chunks_hybrid(
  query_embedding vector(1536),
  query_text text,
  match_count int default 20,
  filter_types text[] default null,
  filter_after timestamptz default null,
  filter_before timestamptz default null,
  rrf_k int default 60,
  include_private boolean default false
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
  vector, text, int, text[], timestamptz, timestamptz, int, boolean
) to authenticated;
