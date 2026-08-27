# LifeSearch — Faz Planı

Kaynak: `docs/requirements.md` bölüm 57-66. Her faz bir öncekinin üzerine
inşa edilir; bir fazı bitirmeden bir sonrakine geçilmez (bkz. "Önemli
Geliştirme Kuralları").

| Faz | Kapsam | Backend var mı? |
|---|---|---|
| **1** | Flutter proje iskeleti, tema, Riverpod, go_router, Supabase bağlantısı, Login/Register/Logout, bottom nav, Home/Library/Settings kabukları | Hayır |
| **2** | Not oluşturma/düzenleme/silme, image/PDF upload, item list/detail, favorites | Hayır (Supabase doğrudan) |
| **3** | Drift ile local DB (items, notes, favorites, recent searches), sync_status + pending operations + retry | Hayır |
| **4** | FastAPI backend kurulur. İlk pipeline: Note/PDF → text → chunking → embedding → pgvector | **Evet — burada başlar** |
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

Altyapı kuruldu (bu oturumda): monorepo iskeleti, Flutter feature-first
mimarisi + Phase 1 bağımlılıkları, FastAPI backend iskeleti (`/health`
uçtan uca çalışıyor), Supabase şeması taslağı (`infra/supabase/migrations`),
docker-compose. **Henüz hiçbir ürün özelliği kodlanmadı.**

Sıradaki adım: **Faz 1** — bkz. görev listesi için sohbetteki plan mesajı.
