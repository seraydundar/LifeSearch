-- Fixes a real bug found by an independent audit (2026-09-10, see
-- docs/roadmap.md "Faz 10b", madde 3): `replace_chunks()`
-- (backend/app/repositories/items_repository.py) used to be an
-- independent DELETE followed by an independent INSERT — two separate
-- HTTP requests, not one transaction. Two concurrent reprocessing runs
-- for the same item (e.g. the user hits "Tekrar Dene" while an earlier
-- attempt is still in flight) could each run their DELETE before either
-- ran its INSERT, then both INSERTs land — doubling every chunk, with
-- no constraint to stop it.
--
-- A unique constraint on (item_id, chunk_index) lets `replace_chunks()`
-- become a single atomic UPSERT instead: two racing runs converge on
-- "last writer per chunk_index wins", never "both writers' rows exist
-- at once". De-duplicating first, same as 0012_item_contents_unique.sql,
-- is insurance against whatever might already be in a live table —
-- keeping each (item_id, chunk_index) pair's most recently created row.
delete from chunks a
using chunks b
where a.item_id = b.item_id
  and a.chunk_index = b.chunk_index
  and a.created_at < b.created_at;

alter table chunks
  add constraint chunks_item_id_chunk_index_key unique (item_id, chunk_index);
