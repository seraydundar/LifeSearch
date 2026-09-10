-- Fixes a real bug found by an independent audit (2026-09-10, see
-- docs/roadmap.md "Faz 10a"): `item_contents` only ever had a plain
-- (non-unique) index on `item_id`, but the mobile client's `createNote()`
-- (features/item/data/remote/remote_item_data_source.dart) upserts into
-- it with `onConflict: 'item_id'`. PostgREST translates that into
-- `INSERT ... ON CONFLICT (item_id) DO UPDATE ...`, which Postgres
-- rejects outright ("no unique or exclusion constraint matching the ON
-- CONFLICT specification") without a matching unique constraint — so on
-- any database built purely from these migrations, creating a note fails
-- every time, and the client's catch block then deletes the `items` row
-- it had just created to compensate. A live project could have papered
-- over this with a constraint added by hand outside of version control;
-- the migration itself was simply missing.
--
-- item_contents is conceptually 1:1 with its item already (every writer —
-- this upsert, and the backend's replace_item_content — treats it that
-- way); de-duplicating before adding the constraint is just insurance
-- against whatever might already be in a live table, keeping each item's
-- most recently created row.
delete from item_contents a
using item_contents b
where a.item_id = b.item_id
  and a.created_at < b.created_at;

-- The unique constraint below creates its own index on item_id — the
-- plain one from 0001_init.sql would just be redundant dead weight
-- alongside it.
drop index if exists idx_item_contents_item_id;

alter table item_contents
  add constraint item_contents_item_id_key unique (item_id);
