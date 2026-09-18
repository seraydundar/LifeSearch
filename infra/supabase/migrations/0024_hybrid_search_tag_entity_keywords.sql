-- P2-01 (docs/requirements-audit-2026-09-13.md): match_chunks_hybrid's
-- keyword_rank only ever looked at a chunk's own content and its item's
-- title (0019_hybrid_search_relevance.sql) — a query matching an item's
-- *tag* or *entity* name (e.g. searching "docker" for an item tagged
-- "docker" but whose text never spells the word out) got no keyword
-- credit for it at all. 0019's own comment left this out on purpose:
-- "Item-level tag/entity keyword matching is a further, separately-
-- scoped improvement — not built here." This is that improvement.
--
-- item_keywords aggregates each item's tag + entity names into one
-- string once (not per chunk), same idea as joining `items.title` in
-- 0019. No `user_id = auth.uid()` filter needed here: item_tags/
-- item_entities only ever link to their own item, and attach_tags/
-- attach_entities (0016_replace_tags_entities_atomic.sql) always upsert
-- tags/entities under the same user_id as the item itself — a tag or
-- entity from a different user can't end up attached to this item.
--
-- keyword_rank's greatest(...) gets a third term for this, on the same
-- to_tsvector('simple')/ts_rank scale as the content and title terms —
-- greatest, not summed, for the same reason 0019 used greatest for
-- title: these are independent sources of the same relevance signal,
-- not separate signals to add together.
drop function if exists match_chunks_hybrid(vector, text, int, text[], timestamptz, timestamptz, int, boolean, text, text);

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
  with item_keywords as (
    select item_id, string_agg(name, ' ') as names
    from (
      select it.item_id, t.name
      from item_tags it
      join tags t on t.id = it.tag_id
      union all
      select ie.item_id, e.name
      from item_entities ie
      join entities e on e.id = ie.entity_id
    ) names
    group by item_id
  ),
  candidates as (
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
        ),
        coalesce(
          ts_rank(to_tsvector('simple', coalesce(ik.names, '')), plainto_tsquery('simple', query_text)),
          0
        )
      ) as keyword_rank
    from chunks c
    join items i on i.id = c.item_id
    left join item_keywords ik on ik.item_id = i.id
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
