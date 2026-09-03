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
| **5** | Semantic Search: query → embedding → pgvector → top-K chunk → items | Evet |
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

Faz 1-4 tamamlandı. Auth, offline-first not/görsel/PDF CRUD (Drift + sync
queue), ve şimdi de FastAPI backend'de gerçek bir AI pipeline: not/PDF
oluşturulup senkronize olduğunda `SyncService` backend'in
`/ai/process-item` uç noktasını tetikliyor, backend kullanıcının kendi
Supabase JWT'siyle (RLS altında, admin key olmadan) içeriği çekip
normalize ediyor, chunk'lıyor, embedding üretip `chunks` tablosuna
(pgvector) yazıyor, `items.processing_status` ve `processing_jobs`
satırını güncelliyor.

Canlıda doğrulandı: gerçek bir kullanıcı token'ıyla uçtan uca test edildi
— auth doğrulama, background task, job tracking, ve (OPENAI_API_KEY
olmadan) zarif hata yönetimi hepsi çalışıyor. Gerçek embedding üretimi
için `backend/.env`'e bir OpenAI key girilmesi gerekiyor.

Sıradaki adım: **Faz 5 — Semantic Search** (ana ekrandaki arama kutusunu
query embedding + pgvector similarity'e bağlamak).
