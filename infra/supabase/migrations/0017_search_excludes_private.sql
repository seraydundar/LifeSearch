-- Denetim düzeltmesi P1-02 (docs/requirements-audit-2026-09-13.md): private
-- olarak işaretlenmiş bir item'ın chunk'ları match_chunks_hybrid/
-- related_items tarafından hiç filtrelenmiyordu. Private reveal kapalıyken
-- bile backend bu içeriği ağ üzerinden gönderiyordu; istemci tarafı gizleme
-- (`_hidePrivateResults`) yalnızca zaten yerelde bilinen private ID'leri
-- süzebiliyordu — henüz cihaza senkron olmamış bir private kayıt arama
-- sonucunda snippet ile sızabiliyordu. Kökü kapat: private item'lar
-- varsayılan olarak sorgudan hariç; yalnız cihaz reveal açıkken (private
-- biyometri/PIN kontrolünden geçtiğinde) `include_private=true` gönderilir.
-- RAG/chat bu parametreyi hiç göndermez (rag_service.py), dolayısıyla
-- açılmamış private içerik asla LLM bağlamına girmez.
--
-- Yeni bir trailing parametre eklemek Postgres'te "create or replace" ile
-- eski fonksiyonu değiştirmez, yanına belirsiz bir overload ekler — önce
-- eski imzaları düşürüyoruz.
drop function if exists match_chunks_hybrid(vector, text, int, text[], timestamptz, timestamptz, int);
drop function if exists related_items(uuid, int);

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
      coalesce(ts_rank(c.content_tsv, plainto_tsquery('simple', query_text)), 0) as keyword_rank
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
  vector, text, int, text[], timestamptz, timestamptz, int, boolean
) to authenticated;

create function related_items(
  source_item_id uuid,
  match_count int default 6,
  include_private boolean default false
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
    and (include_private or i.private = false)
  order by c.embedding <=> sc.embedding
  limit match_count;
$$;

grant execute on function related_items(uuid, int, boolean) to authenticated;
