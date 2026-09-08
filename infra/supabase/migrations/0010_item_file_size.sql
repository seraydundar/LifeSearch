-- Storage usage in Settings (requirements doc, section 49-52) needs to
-- know how many bytes each uploaded file is. Rather than recomputing
-- this by recursively listing every item's Storage folder (one API call
-- per item), it's recorded once at upload time — the client already
-- knows the file's size before it uploads.
alter table items add column if not exists file_size_bytes bigint;
