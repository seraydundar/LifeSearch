-- URL items need somewhere to remember what they point to (requirements
-- doc, section 17) — every other type either has a storage_path (file)
-- or is self-contained (note). Left null for all other types.
alter table items add column if not exists source_url text;
