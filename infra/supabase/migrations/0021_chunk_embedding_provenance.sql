-- P3 (docs/requirements-audit-2026-09-13.md): "chunk/source metadata —
-- embedding provider/model/version bilgisi yok". Tags each chunk with
-- which AI provider/model actually produced its vector, so a later
-- AI_PROVIDER (or embedding_model) switch can tell exactly which chunks
-- now live in a stale, incomparable vector space — see
-- 0022_replace_chunks_atomic_with_provenance.sql (writes these) and
-- 0023_hybrid_search_embedding_provenance.sql (excludes a mismatch from
-- search) and reembedding_service.py (the on-request fix for it).
--
-- Nullable, and left null on every pre-existing row rather than
-- backfilled with a guess: this feature didn't exist before, so there's
-- no reliable record of which provider actually embedded an old chunk.
-- Every consumer of these columns treats null as "trust it" (never
-- flagged stale) rather than "unknown, therefore broken" — a silent
-- migration should never turn a working archive's search up empty.
alter table chunks add column if not exists embedding_provider text;
alter table chunks add column if not exists embedding_model text;
