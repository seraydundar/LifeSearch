-- Enables Supabase Realtime on `items` so the Flutter app's
-- `ItemRepository.watchItems()` (a `.stream()` subscription) receives
-- live inserts/updates/deletes instead of failing with
-- RealtimeSubscribeException. Tables aren't in the `supabase_realtime`
-- publication by default — they must be added explicitly.
alter publication supabase_realtime add table items;
