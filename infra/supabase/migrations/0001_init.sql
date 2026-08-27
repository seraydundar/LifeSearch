-- LifeSearch initial schema.
-- Apply via `supabase db push` (or it auto-runs when the local docker-compose
-- `db` service starts, since this folder is mounted into
-- /docker-entrypoint-initdb.d).
--
-- Scope: the tables Phases 1-4 of the roadmap need (auth, items, extracted
-- content, chunks/embeddings, tags, processing jobs). Collections,
-- duplicate-detection and other later-phase features get their own
-- migration when that phase starts (see docs/requirements.md, rule 18:
-- "Database migration kullan").

create extension if not exists vector;
create extension if not exists pgcrypto; -- gen_random_uuid()

-- ---------------------------------------------------------------------------
-- items: one row per piece of content the user added
-- ---------------------------------------------------------------------------
create table if not exists items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,

  type text not null check (type in ('note', 'image', 'screenshot', 'pdf', 'audio', 'url', 'document')),

  title text,
  description text,

  original_filename text,
  mime_type text,
  storage_path text, -- path inside the private Supabase Storage bucket

  processing_status text not null default 'pending'
    check (processing_status in ('pending', 'processing', 'completed', 'failed')),

  source text, -- e.g. 'camera', 'gallery', 'share_sheet', 'manual'
  favorite boolean not null default false,

  latitude double precision,
  longitude double precision,

  captured_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_items_user_id on items (user_id);
create index if not exists idx_items_type on items (type);
create index if not exists idx_items_created_at on items (created_at desc);

-- ---------------------------------------------------------------------------
-- item_contents: extracted / AI-generated text for an item
-- ---------------------------------------------------------------------------
create table if not exists item_contents (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references items (id) on delete cascade,

  raw_text text,
  ocr_text text,
  ai_description text,
  summary text,
  language text,

  created_at timestamptz not null default now()
);

create index if not exists idx_item_contents_item_id on item_contents (item_id);

-- ---------------------------------------------------------------------------
-- chunks: text chunks + embeddings for semantic search
-- ---------------------------------------------------------------------------
create table if not exists chunks (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references items (id) on delete cascade,

  content text not null,
  chunk_index integer not null,
  embedding vector(1536), -- adjust to match the configured embedding model's dimensions
  metadata jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now()
);

create index if not exists idx_chunks_item_id on chunks (item_id);
-- ivfflat requires ANALYZE after enough rows exist; fine to create empty.
create index if not exists idx_chunks_embedding on chunks
  using ivfflat (embedding vector_cosine_ops) with (lists = 100);

-- ---------------------------------------------------------------------------
-- tags
-- ---------------------------------------------------------------------------
create table if not exists tags (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now(),
  unique (user_id, name)
);

create table if not exists item_tags (
  item_id uuid not null references items (id) on delete cascade,
  tag_id uuid not null references tags (id) on delete cascade,
  primary key (item_id, tag_id)
);

-- ---------------------------------------------------------------------------
-- processing_jobs: async AI pipeline tracking
-- ---------------------------------------------------------------------------
create table if not exists processing_jobs (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references items (id) on delete cascade,

  job_type text not null, -- e.g. 'ocr', 'chunk_and_embed', 'transcribe', 'summarize'
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'completed', 'failed')),
  progress integer not null default 0,
  error_message text,

  created_at timestamptz not null default now(),
  started_at timestamptz,
  completed_at timestamptz
);

create index if not exists idx_processing_jobs_item_id on processing_jobs (item_id);
create index if not exists idx_processing_jobs_status on processing_jobs (status);

-- ---------------------------------------------------------------------------
-- updated_at trigger for items
-- ---------------------------------------------------------------------------
create or replace function set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_items_updated_at on items;
create trigger trg_items_updated_at
  before update on items
  for each row execute function set_updated_at();

-- ---------------------------------------------------------------------------
-- Row Level Security — every user only ever sees their own data.
-- ---------------------------------------------------------------------------
alter table items enable row level security;
alter table item_contents enable row level security;
alter table chunks enable row level security;
alter table tags enable row level security;
alter table item_tags enable row level security;
alter table processing_jobs enable row level security;

create policy items_owner on items
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy item_contents_owner on item_contents
  for all using (exists (select 1 from items i where i.id = item_contents.item_id and i.user_id = auth.uid()))
  with check (exists (select 1 from items i where i.id = item_contents.item_id and i.user_id = auth.uid()));

create policy chunks_owner on chunks
  for all using (exists (select 1 from items i where i.id = chunks.item_id and i.user_id = auth.uid()))
  with check (exists (select 1 from items i where i.id = chunks.item_id and i.user_id = auth.uid()));

create policy tags_owner on tags
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy item_tags_owner on item_tags
  for all using (exists (select 1 from items i where i.id = item_tags.item_id and i.user_id = auth.uid()))
  with check (exists (select 1 from items i where i.id = item_tags.item_id and i.user_id = auth.uid()));

create policy processing_jobs_owner on processing_jobs
  for all using (exists (select 1 from items i where i.id = processing_jobs.item_id and i.user_id = auth.uid()))
  with check (exists (select 1 from items i where i.id = processing_jobs.item_id and i.user_id = auth.uid()));
