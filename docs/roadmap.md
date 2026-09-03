# LifeSearch — Faz Planı

Kaynak: `docs/requirements.md` bölüm 57-66. Her faz bir öncekinin üzerine
inşa edilir; bir fazı bitirmeden bir sonrakine geçilmez (bkz. "Önemli
Geliştirme Kuralları").

| Faz | Kapsam | Backend var mı? |
|---|---|---|
| **1** | Flutter proje iskeleti, tema, Riverpod, go_router, Supabase bağlantısı, Login/Register/Logout, bottom nav, Home/Library/Settings kabukları | Hayır |
| **2** | Not oluşturma/düzenleme/silme, image/PDF upload, item list/detail, favorites | Hayır (Supabase doğrudan) |
| **3** ✅ | Drift ile local DB (items, notes, favorites, recent searches), sync_status + pending operations + retry | Hayır |
| **4** ✅ | FastAPI backend kurulur. İlk pipeline: Note/PDF → text → chunking → embedding → pgvector | **Evet — burada başlar** |
| **5** ✅ | Semantic Search: query → embedding → pgvector → top-K chunk → items | Evet |
| **6** | Image Intelligence: camera, image upload, OCR, image description/embedding | Evet |
| **7** | RAG Chat ("Ask AI"): yalnızca kullanıcının arşivinden, kaynak göstererek cevap | Evet |
| **8** | Audio + URL: voice note, speech-to-text, URL extraction/webpage processing | Evet |
| **9** | Advanced Search: hybrid search, metadata/doğal dil filtreleri, reranking, related items, smart collections, duplicate detection | Evet |

## MVP kabul kriteri (bölüm 66)

Register → Login → PDF ekle → Screenshot ekle → Not oluştur → backend
işler → embedding oluşur → "Flutter state management hakkında
kaydettiğim şeyleri bul" araması ilgili PDF/screenshot/notu getirir →
"Bunlara göre Riverpod neden kullanılıyor?" sorusuna RAG ile kaynaklı
cevap verir. Bu senaryo çalışıyorsa MVP tamamlanmıştır (Faz 7 sonu).

## Şu an neredeyiz

Faz 1-5 tamamlandı. Auth, offline-first not/görsel/PDF CRUD (Drift + sync
queue), FastAPI'de gerçek bir AI pipeline (not/PDF → chunk → embedding →
pgvector), ve şimdi de gerçek semantic search: ayrı bir arama ekranı,
debounce'lu sorgu, backend'in `match_chunks` RPC'si (pgvector cosine
similarity, `auth.uid()` ile RLS-scoped) üzerinden top-K sonuç, ve local
Drift'te tutulan arama geçmişi.

Canlıda doğrulandı: `match_chunks` fonksiyonu gerçek bir kullanıcı
token'ıyla, üretilmiş (fake) embedding'lerle test edildi — sıralama ve
RLS izolasyonu doğru çalışıyor. `/search` endpoint'i de OPENAI_API_KEY
olmadan 503 ile zarif şekilde dönüyor (500 çökme değil). Gerçek anlamsal
sonuçlar için `backend/.env`'e bir OpenAI key girilmesi gerekiyor —
pipeline'ın kendisi hazır ve test edilmiş durumda.

Sıradaki adım: **Faz 6 — Image Intelligence** (kamera, OCR, görsel
açıklama/embedding — "geçen ay baktığım monitör" gibi sorguları
mümkün kılar).
