"""Text -> vector embeddings, provider-agnostic.

Wraps AIProvider.generate_embedding() so callers never talk to a specific
embedding API directly. Scaffolding only — implemented starting Phase 4.
"""
