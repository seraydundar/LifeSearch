-- AI-extracted named entities (requirements doc, section 44-48: "entity
-- extraction") — people, places, organizations, and dates the AI pipeline
-- found mentioned in an item's content. Same shape as tags/item_tags
-- (0001_init.sql): a per-user, deduped entity table plus a junction, with
-- `type` distinguishing what kind of entity it is. Not added to the
-- realtime publication — same reasoning as tags: the mobile app fetches
-- an item's entities with a one-shot query when its detail screen opens,
-- it doesn't watch them live.

create table if not exists entities (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  type text not null check (type in ('person', 'place', 'organization', 'date')),
  created_at timestamptz not null default now(),
  unique (user_id, name, type)
);

create index if not exists idx_entities_user_id on entities (user_id);

create table if not exists item_entities (
  item_id uuid not null references items (id) on delete cascade,
  entity_id uuid not null references entities (id) on delete cascade,
  primary key (item_id, entity_id)
);

create index if not exists idx_item_entities_entity_id on item_entities (entity_id);

alter table entities enable row level security;
alter table item_entities enable row level security;

create policy entities_owner on entities
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Same shape as item_tags_owner in 0001_init.sql: only the item's
-- ownership is checked here (not the entity's) — an entity row is only
-- ever readable through `entities`' own RLS anyway, so a stray
-- cross-user entity_id can't leak anything.
create policy item_entities_owner on item_entities
  for all using (
    exists (select 1 from items i where i.id = item_entities.item_id and i.user_id = auth.uid())
  )
  with check (
    exists (select 1 from items i where i.id = item_entities.item_id and i.user_id = auth.uid())
  );
