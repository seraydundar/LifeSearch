-- Collections (requirements doc, section 28) — a plain, user-created
-- grouping of items. This is the base feature Smart Collections (section
-- 129, "AI önerisi") needs before it can exist at all; this migration
-- only adds the manual version. `is_smart` is reserved for a later
-- migration that has the pipeline create suggested collections itself —
-- until then every row a client can insert has it false (see RLS below).

create table if not exists collections (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  is_smart boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists idx_collections_user_id on collections (user_id);

create table if not exists collection_items (
  collection_id uuid not null references collections (id) on delete cascade,
  item_id uuid not null references items (id) on delete cascade,
  added_at timestamptz not null default now(),
  primary key (collection_id, item_id)
);

create index if not exists idx_collection_items_item_id on collection_items (item_id);

alter table collections enable row level security;
alter table collection_items enable row level security;

create policy collections_owner on collections
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Checked both ways: the collection must be the caller's (read/write),
-- and — on insert — so must the item, otherwise a user could add
-- someone else's item id into their own collection.
create policy collection_items_owner on collection_items
  for all using (
    exists (
      select 1 from collections c
      where c.id = collection_items.collection_id and c.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from collections c
      where c.id = collection_items.collection_id and c.user_id = auth.uid()
    )
    and exists (
      select 1 from items i
      where i.id = collection_items.item_id and i.user_id = auth.uid()
    )
  );

-- Same reason as 0003_realtime.sql: `.stream()` on either table needs it
-- in the publication or it fails with RealtimeSubscribeException.
alter publication supabase_realtime add table collections;
alter publication supabase_realtime add table collection_items;
