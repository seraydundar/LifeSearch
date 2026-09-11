-- Item-level Privacy Mode (Faz 11, madde 2 — see docs/roadmap.md).
-- Until now the only privacy control was a whole-app biometric/PIN lock
-- (Settings' "Privacy" switch) — there was no way to keep a single
-- sensitive item out of casual browsing without locking the entire app.
--
-- `private` is enforced client-side only (see the mobile app's
-- itemsProvider/SearchController) — RLS still scopes every row to its
-- owner regardless of this flag, exactly as before. A signed-in device
-- with `private_items_revealed` set (after a biometric/PIN check) can
-- still see everything; this column is about hiding from a casual
-- glance at Home/Library/Search, not a second access-control layer.
alter table items
  add column private boolean not null default false;
