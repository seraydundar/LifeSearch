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
| **9** ✅ | Advanced Search: hybrid search (RRF), metadata filtreleri, related items, duplicate detection, doğal dil filtreleme, Collections + Smart Collections | Evet |

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

## Faz 9 — Advanced Search ✅

Bölüm 21/47/129'daki beş alt-başlığın hepsi tamamlandı.

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
  bir "Koleksiyona Ekle" checkbox sheet'i.
- **Smart Collections** (AI-öneri kısmı): `item_similarity_pairs` RPC'si
  (`infra/supabase/migrations/0009_collection_suggestions.sql`) henüz
  koleksiyona girmemiş item'ları ikili benzerliklerine göre döndürür —
  Python tarafında `collection_suggestion_service.py` bunları union-find
  ile kümelere ayırır (A~B, B~C ise A/B/C tek küme; ikili karşılaştırma
  yeter, hepsini hepsiyle karşılaştırmak gerekmez) ve en az 3 öğeli
  kümeleri öneri olarak döndürür. İsimlendirme AI provider varsa LLM'den
  ("Docker Notları" gibi kısa bir ad), yoksa (veya provider hata verirse)
  tür bazlı bir fallback'ten gelir ("PDF Grubu (3)") — kümeleme hiç key
  gerektirmiyor, sadece isimlendirme daha iyi olur. `POST /collections/suggest`
  endpoint'i, Library'de "Önerilen Koleksiyonlar" kartları (Oluştur →
  `is_smart: true` ile gerçek koleksiyon oluşturur; Yoksay → sadece bu
  oturum için gizler, sunucuya yazılmaz çünkü öneriler her seferinde
  yeniden hesaplanıyor).

Backend: 58 test yeşil (8 query_parser + 8 collection_suggestion_service).
Mobile: `flutter analyze` temiz, 34 test yeşil (4 Collections + 4
suggestion kartı), uygulama simülatörde (iPhone 17 Pro) regresyonsuz
derlenip açılıyor — mevcut not/görsel verisi korunmuş durumda görüldü,
Collections şeridi canlı Supabase projesine karşı (gerçek realtime
subscription ile) doğrulandı; backend kapalıyken suggestion kartı
sessizce hiç render olmuyor (hata banner'ı yok), backend'in
ulaşılamaması bekleneni yaptı. Gerçek OpenAI key olmadığından hybrid
arama, related items, duplicate detection ve Smart Collections
isimlendirmesinin gerçek kalitesi henüz canlı görülmedi (REST
seviyesinde sahte ama kontrollü embedding'lerle doğrulandı); doğal dil
filtreleme, Collections ve Smart Collections'ın kümeleme kısmı key
gerektirmediği için tam doğrulandı.

## Faz 9 sonrası — dokümanı tekrar tarayıp bulunan boşluklar

9 fazın hepsi bittikten sonra `requirements.md`, kod tabanıyla satır satır
karşılaştırılarak tekrar tarandı; dört gerçek boşluk bulundu (tags, offline
keyword search, structured logging, konum/EXIF). İlk ikisi (tags,
key gerektirmeyenler öncelikli) burada işleniyor.

### Tags ✅

Bölüm 8-12: *"tags / item_tags: kullanıcı ve AI tarafından üretilen
etiketler"* — tablolar Faz 4'ten beri RLS'iyle duruyordu ama hiçbir yere
bağlı değildi. Daha da çarpıcısı: vision AI zaten etiket üretiyordu
(`analyze_image()`'ın döndürdüğü `tags` alanı), pipeline bunu çöpe
atıyordu.

- **Görseller**: vision call'dan gelen tag'ler ekstra bir istek olmadan
  kullanılıyor.
- **Diğer tüm tipler** (not/PDF/ses/link): yeni `tagging_service.generate_tags()`
  — normalize edilmiş metni tek bir `generate_text` çağrısına verip
  virgülle ayrılmış en fazla 5 kısa etiket istiyor, provider hata verirse
  boş liste dönüyor (asla pipeline'ı düşürmüyor).
- `items_repository.attach_tags()`: `tags` tablosuna `(user_id, name)`
  üzerinden upsert, `item_tags`'i `replace_chunks` ile aynı idempotent
  desenle değiştiriyor (yeniden işleme eski etiket setini tamamen
  yeniliyor, biriktirmiyor).
- Etiketleme tamamen best-effort — RPC/HTTP hatası item'ın "completed"
  durumunu asla etkilemiyor (duplicate detection'la aynı sözleşme).
- Mobil: `ItemRepository.fetchTags()` (Supabase'e doğrudan join sorgusu,
  henüz cache'lenmiyor), item detail ve not editöründe paylaşılan bir
  `TagsRow` widget'ı — bir etikete dokunmak Search sekmesini o etiketle
  önceden doldurup otomatik çalıştırıyor (`SearchTab.initialQuery`).

Backend: 67 test yeşil (5 tagging_service + 4 processing_pipeline).
Mobile: `flutter analyze` temiz, 38 test yeşil (3 TagsRow + 1
initialQuery). Simülatörde regresyonsuz derlenip açıldı.

### Offline keyword search ✅

Dokümanın "offline-first (... + offline keyword search)" ifadesine
rağmen Search sekmesi hep backend'e gidiyordu; internet/backend
yokken hiç çalışmıyordu.

- `LocalSearchDataSource`: Drift'teki `LocalItems` üzerinde büyük/küçük
  harf duyarsız bir alt-dize araması — sırasıyla not içeriği,
  açıklama, başlık, link URL'i taranıyor; eşleşme etrafında ~60
  karakterlik bir "…eşleşme…" özeti üretiliyor. Tür/tarih filtreleri
  (`SearchFilters`) online aramayla aynı şekilde uygulanıyor.
  OCR metni/AI açıklaması gibi yalnızca Supabase'de duran alanlar
  Drift'e hiç senkronize olmadığı için offline aranamıyor — bu, "telefonda
  o metnin kopyası yok" gerçeğinden gelen sınırlı ama dürüst bir kapsam.
- `OfflineFallbackSearchRepository`: gerçek (semantic/hybrid) aramayı
  sarmalıyor — remote çağrı başarısız olursa (bağlantı yok, backend
  ulaşılamıyor, `BACKEND_URL` hiç ayarlanmamış) local aramaya düşüyor.
  İlk tercih asla local değil, çünkü anahtar kelime eşleşmesi AI
  destekli sonuçtan her zaman daha zayıf. `related()`'ın offline
  karşılığı yok (embedding gerektiriyor), her zaman doğrudan remote'a
  gidiyor.
- Sıralama offline'da anlamlı bir skor olmadığı için (ne embedding ne
  ts_rank) en yeni eklenen önce geliyor.

Backend değişmedi (tamamen mobil tarafında). Mobile: `flutter analyze`
temiz, 49 test yeşil (8 LocalSearchDataSource + 3 OfflineFallbackSearchRepository).
Simülatörde regresyonsuz derlenip açıldı.

### Structured logging ✅

Bölüm 53: *"request_id, user_id, job_id, item_id, processing_time,
error"* — backend'de toplam 2 log satırı vardı, ikisi de sadece hata
durumunda; artık her satır tek bir JSON objesi ve gerektiğinde bu
alanların hepsini taşıyor.

- `core/logging.py`: `_JsonFormatter` her satırı `{timestamp, level,
  logger, message, ...extra}` şeklinde tek satır JSON'a çeviriyor —
  `extra={}` ile geçilmeyen alanlar (ör. `request_id` bir background
  task içinde `None` ise) çıktıya hiç girmiyor, gürültü yaratmıyor.
- `request_id`/`user_id`, her fonksiyon imzasından geçirmek yerine
  `contextvars` ile taşınıyor — her istek kendi asyncio Task'ında
  çalıştığı için (PEP 567) bir isteğin değerleri başka bir isteğe asla
  sızmıyor. `_ContextFilter` bunu handler seviyesinde her log satırına
  damgalıyor (logger seviyesinde değil — `Logger.filter()` yalnızca
  çağrıyı yapan logger'ın kendi filtrelerine bakıyor, root'unkilere
  değil; bu ayrım bir testte yanlış çıkıp düzeltildi).
- `request_logging_middleware`: her istek için tek bir satır
  (method/path/status_code/processing_time_ms), asla body/query içeriği
  — `X-Request-Id` yanıt header'ı olarak da geri dönüyor, mobil taraftan
  gelen bir hata raporu sunucu loglarıyla eşleştirilebilsin diye.
- `core/security.py`: `get_current_user()` doğrulama sonrası
  `user_id_var`'ı set ediyor — o andan sonraki her log satırı (AI
  pipeline'ın içine kadar) bu kullanıcıyı taşıyor.
- `processing_pipeline.py`: "item processed" (item_id, job_id,
  item_type, chunk_count, processing_time_ms) ve zenginleştirilmiş
  "processing failed" satırları; duplicate/tagging best-effort
  satırları da item_id/error alanlarıyla structured hale geldi.

Backend: 76 test yeşil (7 test_logging.py + 2 yeni processing_pipeline
testi — caplog ile gerçek log kayıtlarının alanlarını doğruluyor).
Mobile değişmedi.

### Henüz yapılmayan

- **Konum (location)**: `items.latitude/longitude/captured_at` kolonları
  Faz 4'ten beri duruyor, hiç kullanılmıyor — fotoğraf eklerken EXIF'ten
  okunabilir.

Sıradaki adım: **bir OpenAI key ekleyip Faz 1-9'un tamamını gerçek
veriyle uçtan uca görmek** — ya da yukarıdaki son boşluğa devam
etmek.
