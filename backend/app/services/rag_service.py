"""Retrieval-Augmented Generation.

Embeds the user's question, retrieves top-K relevant chunks via
search_service, and asks the LLM to answer using only those chunks —
always returning the source items alongside the answer. Scaffolding
only — implemented starting Phase 7 (RAG Chat).
"""
