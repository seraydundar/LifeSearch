# LifeSearch — Faz Planı

Kaynak: `docs/requirements.md` bölüm 57-66. Her faz bir öncekinin üzerine
inşa edilir; bir fazı bitirmeden bir sonrakine geçilmez (bkz. "Önemli
Geliştirme Kuralları").

| Faz | Kapsam | Backend var mı? |
|---|---|---|
| **1** ✅ | Flutter proje iskeleti, tema, Riverpod, go_router, Supabase bağlantısı, Login/Register/Logout, bottom nav, Home/Library/Settings kabukları | Hayır |
| **2** ✅ | Not oluşturma/düzenleme/silme, image/PDF upload, item list/detail, favorites | Hayır (Supabase doğrudan) |
| **3** ✅ | Drift ile local DB (items, notes, favorites, recent searches), sync_status + pending operations + retry | Hayır |
| **4** ✅ | FastAPI backend kurulur. İlk pipeline: Note/PDF → text → chunking → embedding → pgvector | **Evet — burada başlar** |
| **5** ✅ | Semantic Search: query → embedding → pgvector → top-K chunk → items | Evet |
| **6** ✅ | Image Intelligence: camera, image upload, OCR, image description/embedding | Evet |
| **7** ✅ | RAG Chat ("Ask AI"): yalnızca kullanıcının arşivinden, kaynak göstererek cevap | Evet |
| **8** | Audio + URL: voice note, speech-to-text, URL extraction/webpage processing | Evet |
| **9** | Advanced Search: hybrid search, metadata/doğal dil filtreleri, reranking, related items, smart collections, duplicate detection | Evet |

## MVP kabul kriteri (bölüm 66)

Register → Login → PDF ekle → Screenshot ekle → Not oluştur → backend
işler → embedding oluşur → "Flutter state management hakkında
kaydettiğim şeyleri bul" araması ilgili PDF/screenshot/notu getirir →
"Bunlara göre Riverpod neden kullanılıyor?" sorusuna RAG ile kaynaklı
cevap verir. Bu senaryo çalışıyorsa MVP tamamlanmıştır (Faz 7 sonu).

## Şu an neredeyiz

Faz 1-7 tamamlandı — dokümanın bölüm 66'da tarif ettiği MVP senaryosunun
kodu baştan sona yazılmış durumda: register → login → PDF/görsel/not
ekle → backend işler → embedding oluşur → semantic search bulur →
Ask AI, kaynak göstererek cevap üretir. `SearchHubScreen` artık
"Search | Ask AI" sekmeleriyle (bölüm 23) her ikisini de barındırıyor;
RAG servisi Faz 5'in `semantic_search`'ünü olduğu gibi yeniden kullanıp
üstüne LLM cevabı ekliyor — retrieval iki kere yazılmadı.

Canlıda doğrulandı: backend uçları (auth, pipeline, search RPC) gerçek
kullanıcı token'ıyla test edildi; mobile uygulama regresyonsuz derlenip
çalışıyor (44 backend + 24 mobile test yeşil). Gerçek OpenAI key
olmadığından embedding/RAG cevaplarının gerçek kalitesi henüz canlı
görülmedi — tüm pipeline sahte (fake) provider'larla uçtan uca test
edilmiş, key eklenince çalışmaya hazır.

Sıradaki adım: **bir OpenAI key ekleyip Faz 4-7'nin tamamını gerçek
veriyle uçtan uca görmek** (MVP demo senaryosu) — ya da doğrudan
**Faz 8 — Audio + URL**'e geçmek.
