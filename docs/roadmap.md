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
| **8** ✅ | Audio + URL: voice note, speech-to-text, URL extraction/webpage processing | Evet |
| **9** 🟡 | Advanced Search: hybrid search (RRF), metadata filtreleri, related items, duplicate detection, doğal dil filtreleme, Collections (temel) | Evet |

## MVP kabul kriteri (bölüm 66)

Register → Login → PDF ekle → Screenshot ekle → Not oluştur → backend
işler → embedding oluşur → "Flutter state management hakkında
kaydettiğim şeyleri bul" araması ilgili PDF/screenshot/notu getirir →
"Bunlara göre Riverpod neden kullanılıyor?" sorusuna RAG ile kaynaklı
cevap verir. Bu senaryo çalışıyorsa MVP tamamlanmıştır (Faz 7 sonu).

## Şu an neredeyiz

Faz 1-8 tamamlandı. Dokümandaki 7 içerik tipinin (note, image, screenshot,
pdf, audio, url, document) hepsi artık gerçekten eklenebiliyor ve aynı
chunk/embed pipeline'ından geçiyor:

- **Ses**: gerçek mikrofon kaydı (`record` paketi) → Whisper transkripti
  → LLM'den kısa bir başlık ("LLM metadata extraction", bölüm 18) →
  embedding
- **Link**: "Add Link" diyaloğu → backend sayfayı çekip nav/footer/reklam
  temizleyerek asıl makale metnini çıkarıyor (BeautifulSoup), başlık ve
  meta description'ı item'a yazıyor (bölüm 17)
- Local Drift şeması `source_url` kolonuyla v2'ye yükseltildi —
  `MigrationStrategy.onUpgrade` ile mevcut kullanıcı verisi kaybolmadan

Canlıda doğrulandı: backend 37 test, mobile 25 test yeşil; local DB
migration'ı (v1→v2) simülatörde gerçek veri üzerinde (önceden eklenmiş
not + görsel) veri kaybı olmadan çalıştı; app native camera + record
plugin entegrasyonlarıyla birlikte regresyonsuz derlenip çalışıyor.

Bölüm 66'daki MVP senaryosunun kodu Faz 7 sonunda tamamlanmıştı; Faz 8
onun üstüne dokümanın geri kalan içerik tiplerini ekledi. Gerçek OpenAI
key olmadığından embedding/transkript/RAG'ın gerçek kalitesi henüz canlı
görülmedi — pipeline'ın tamamı sahte (fake) provider'larla uçtan uca
test edilmiş durumda.

## Faz 9 — Advanced Search (kısmi 🟡)

Bölüm 21/47'deki beş alt-başlıktan dördü tamamlandı; beşincisi olan
"Smart Collections"ın önkoşulu (düz Collections) de artık var, ama
AI-öneri kısmı henüz yazılmadı — bu yüzden Faz 9 hâlâ kısmi.

- **Hybrid search**: pgvector cosine similarity + Postgres full-text
  search (`tsvector`/`ts_rank`), Reciprocal Rank Fusion (RRF) ile
  birleştiriliyor — `match_chunks_hybrid` RPC'si (`infra/supabase/migrations/0006_hybrid_and_related.sql`).
  Ham skorları `0.7*similarity + 0.3*ts_rank` gibi ağırlıklı toplamak
  yerine RRF seçildi çünkü iki skor karşılaştırılabilir bir ölçekte değil.
- **Metadata filtreleri**: Search sekmesinde tür (Images/Documents/Notes/
  Links/Audio) ve tarih (Bugün/Geçen hafta/Geçen ay) filtreleri — seçim
  değiştiğinde son sorgu aynı filtrelerle otomatik tekrar çalışıyor
  (`SearchController.researchWithCurrentFilters`).
- **Related items**: `related_items` RPC'si (item'ın ilk chunk'ını
  karşılaştırma vektörü olarak kullanan bir `lateral` join) ile item
  detay ekranında "İlgili İçerikler" yatay listesi — sorgu metni
  gerektirmiyor, AI provider key'i olmadan da (503 yerine) çalışıyor.
- **Duplicate detection**: her item işlendikten sonra `find_duplicate_candidate`
  RPC'si (`infra/supabase/migrations/0007_duplicate_detection.sql`) —
  `related_items` ile aynı ilk-chunk-anchor mantığı, ama tek sonuç ve
  yüksek bir eşik (varsayılan 0.93). Eşleşme bulunursa `items` tablosuna
  (`duplicate_of_item_id`, `duplicate_similarity`, `duplicate_dismissed`)
  yazılıyor; item detail'de dismissible bir banner ("Bu içerik zaten
  eklenmiş gibi görünüyor" → Görüntüle/Yoksay) olarak gösteriliyor.
  Kontrol tamamen best-effort: RPC hata verse veya provider key'i eksik
  olsa bile item'ın kendi işlenme durumunu asla etkilemiyor. Local Drift
  şeması bu üç kolonla v3'e yükseltildi.
- **Doğal dil filtreleme**: `query_parser.py` — LLM çağrısı olmadan,
  kural tabanlı bir çıkarım. "geçen ay baktığım PDF'ler" gibi bir sorgu
  önce tür/tarih ifadeleri için taranıyor (Türkçe anahtar kelimeler:
  pdf/resim/not/link/ses/belge/screenshot; bugün/dün/bu hafta/geçen
  hafta/bu ay/geçen ay/bu yıl/geçen yıl), eşleşenler filtreye çevrilip
  sorgu metninden temizleniyor, geri kalan temiz metin ("baktığım")
  embedding'e gidiyor. Search sekmesindeki filtre chip'leri her zaman
  öncelikli — bu yalnızca client hiçbir filtre göndermediğinde devreye
  giriyor, boşlukları dolduruyor.
- **Collections** (temel — Smart Collections'ın önkoşulu): `collections`
  + `collection_items` tabloları (`infra/supabase/migrations/0008_collections.sql`),
  RLS ile sahiplik hem koleksiyon hem item tarafında ayrı ayrı kontrol
  ediliyor (bir kullanıcı başkasının item'ını kendi koleksiyonuna
  ekleyemiyor). Diğer içerik CRUD'ları gibi backend'e uğramadan
  doğrudan Supabase'e konuşuyor (Faz 2'de item'ların başladığı gibi —
  henüz offline değil, bu bilinçli bir sonraki-adım notu). Library'de
  bir koleksiyon şeridi + "Yeni Koleksiyon", item detail/not editöründe
  bir "Koleksiyona Ekle" checkbox sheet'i. `is_smart` kolonu ileride AI
  önerilerinin kullanacağı yer tutucu — hiçbir client bunu `true`
  yazmıyor henüz.

Backend: 50 test yeşil (8 yeni: query_parser). Mobile: `flutter analyze`
temiz, 30 test yeşil (4 yeni: Collections), uygulama simülatörde
(iPhone 17 Pro) regresyonsuz derlenip açılıyor — mevcut not/görsel
verisi korunmuş durumda görüldü, Collections şeridi canlı Supabase
projesine karşı (gerçek realtime subscription ile) doğrulandı. Gerçek
OpenAI key olmadığından hybrid arama, related items ve duplicate
detection'ın gerçek embedding/metin kalitesiyle canlı davranışı henüz
görülmedi (REST seviyesinde sahte ama kontrollü embedding'lerle
doğrulandı); doğal dil filtreleme ve Collections key gerektirmediği
için tam doğrulandı.

Sıradaki adım: **bir OpenAI key ekleyip Faz 4-9'un tamamını gerçek
veriyle uçtan uca görmek** — ya da Smart Collections'ın AI-öneri
kısmını yazmak (var olan item embedding'lerini kümeleyip "Docker ile
ilgili 6 şey buldum, koleksiyon yapayım mı?" gibi bir öneri üretmek).
