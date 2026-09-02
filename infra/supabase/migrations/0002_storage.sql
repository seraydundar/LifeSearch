-- Private storage bucket for user-uploaded files (images, PDFs, audio...).
-- Objects are keyed as `{user_id}/{item_id}/{filename}` so RLS can scope
-- access per-user from the path alone (see requirements doc, section 35:
-- "Storage bucket private. Dosya erişimleri signed URL veya authenticated
-- erişim ile gerçekleştirilmelidir.").

insert into storage.buckets (id, name, public)
values ('item-files', 'item-files', false)
on conflict (id) do nothing;

create policy "item-files: users insert into their own folder"
on storage.objects for insert
with check (bucket_id = 'item-files' and auth.uid()::text = (storage.foldername(name))[1]);

create policy "item-files: users read their own folder"
on storage.objects for select
using (bucket_id = 'item-files' and auth.uid()::text = (storage.foldername(name))[1]);

create policy "item-files: users update their own folder"
on storage.objects for update
using (bucket_id = 'item-files' and auth.uid()::text = (storage.foldername(name))[1]);

create policy "item-files: users delete their own folder"
on storage.objects for delete
using (bucket_id = 'item-files' and auth.uid()::text = (storage.foldername(name))[1]);
