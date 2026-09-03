-- Vector similarity search over the current user's own chunks.
-- PostgREST can't express `ORDER BY embedding <=> query_vector` through
-- its table API, so this is exposed as an RPC instead
-- (`POST /rest/v1/rpc/match_chunks`) — see requirements doc, section 19.
--
-- Not `SECURITY DEFINER`: runs as the calling (authenticated) role, so
-- RLS on `chunks`/`items` still applies. `auth.uid()` is read from the
-- caller's own JWT, not a client-supplied parameter — a caller can't ask
-- for another user's matches by passing a different id.
create or replace function match_chunks(
  query_embedding vector(1536),
  match_count int default 20
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
    1 - (c.embedding <=> query_embedding) as similarity
  from chunks c
  join items i on i.id = c.item_id
  where i.user_id = auth.uid()
  order by c.embedding <=> query_embedding
  limit match_count;
$$;

grant execute on function match_chunks(vector, int) to authenticated;
