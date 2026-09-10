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

### Konum (EXIF) ✅

`items.latitude/longitude/captured_at` kolonları Faz 4'ten beri
duruyordu (`infra/supabase/migrations/0001_init.sql`), hiç
kullanılmıyordu — bu dördüncü ve son boşluk, yeni bir Supabase
migrasyonu gerektirmedi, kolonlar zaten canlıydı.

- `exif_service.py` (yeni, Pillow ile): bir fotoğrafın EXIF'inden GPS
  koordinatlarını (derece/dakika/saniye'den ondalığa çevirerek, N/S/E/W
  referanslarına göre işaretleyerek) ve `DateTimeOriginal`'i çıkarır.
  Screenshot'lar, indirilen görseller, konum kapalıyken çekilmiş
  fotoğraflar gibi EXIF'i olmayan/eksik her durumda hata fırlatmadan
  `None` döner — bu isteğe bağlı metadata, pipeline'ı asla düşürmemeli.
- `processing_pipeline.py`: image/screenshot dalında `analyze_image`
  çağrısının yanına tek bir yerel EXIF okuma eklendi (AI provider
  gerektirmiyor), sonucu `update_item_metadata`'nın yeni
  `latitude`/`longitude`/`captured_at` parametreleriyle tek PATCH'te
  yazıyor.
- Mobil: `Item` entity'sine 3 yeni alan, local Drift şeması v3→v4
  (`latitude`, `longitude`, `capturedAt` kolonları — `SyncService` pull
  aşamasında dolduruluyor). Item detail'de "Çekim" tarihi satırı ve
  koordinatları gösteren, dokunulunca Maps'i açan bir "Konum" satırı
  (reverse geocoding yok — ayrı bir API/key gerektirir, ham koordinat
  yeterli).

Backend: 85 test yeşil (7 test_exif_service.py + 2 yeni
processing_pipeline testi — biri gerçek GPS/tarih EXIF'i gömülü bir
JPEG ile, biri EXIF'siz düz bir fotoğrafla). Mobile: `flutter analyze`
temiz, 49 test (değişmedi — location UI'ı için ayrı bir ekran testi
yazılmadı, item_detail_screen.dart'ın hiç kendi test dosyası yok, sadece
alt widget'ları test ediliyor, mevcut kalıpla tutarlı); simülatörde
local DB migration'ı (v3→v4) mevcut veri üzerinde veri kaybı olmadan
çalıştı.

---

Requirements dokümanının 71 maddesi ve Faz 9 sonrası taramada bulunan
dört boşluğun (tags, offline keyword search, structured logging,
konum/EXIF) hepsi artık kod tarafında tamam.

## Dokümanın dışında — mühendislik/ürünleştirme kalemleri

Requirements dokümanının kapsamı bitince, kod tabanı tekrar dokümanın
kendisinin (bölüm 53-56, 49-52) hâlâ karşılanmamış bıraktığı yerler için
tarandı. Öncelik sırasıyla:

### CI/CD ✅

Bölüm 53-56: *"CI/CD: GitHub Actions (flutter analyze, flutter test,
backend lint, pytest)"* — `.github/workflows/` klasörü var ama boştu.

- `.github/workflows/ci.yml`: `main`'e her push/PR'da iki bağımsız job —
  **backend** (`ruff check .` + `pytest`, Python 3.12) ve **mobile**
  (`dart run build_runner build` — freezed/drift üretilen dosyalar
  gitignore'da, her checkout'ta yeniden üretilmesi gerekiyor — sonra
  `flutter analyze` + `flutter test`, Flutter 3.38.3). Bir backend
  değişikliği mobile job'ını beklemiyor, tersi de öyle.
- Workflow'u yazarken `ruff check .` ilk kez CI koşulunda çalıştırıldı ve
  gerçek bir ihlal buldu (`test_processing_pipeline.py`'de 100 karakteri
  aşan bir satır) — düzeltildi.
- README'ye CI badge'i ve `ruff check` komutu eklendi; "early
  scaffolding" diyen aylar önceki durum satırı güncel duruma çekildi.

### Settings ekranı — Export + Storage + AI Settings ✅

Bölüm 49-52: Account/Sync/Theme/Logout vardı; Delete Account (service_role
key gerektiriyor — henüz yok) ve Privacy (biometric/PIN, kendi başına
büyük bir özellik) bilinçli olarak bu turun dışında bırakıldı.

- **Storage**: `items.file_size_bytes` (yeni kolon,
  `infra/supabase/migrations/0010_item_file_size.sql`) — her item'ın
  boyutunu, Storage'ı her item'ın klasörünü tek tek listeyerek yeniden
  hesaplamak yerine, upload anında bir kere kaydediyor (client dosyanın
  boyutunu zaten biliyor). Settings sekmesi bunu var olan `itemsProvider`
  akışından topluyor — ekstra bir sorgu yok, offline'da da çalışıyor. Bu
  alan eklenmeden önce yüklenmiş item'lar için `null` — Storage satırı bu
  durumda "bazı eski öğelerin boyutu bilinmiyor" diyor, sessizce yanlış
  bir toplam göstermek yerine.
- **Export**: `ExportService` (Supabase'e doğrudan) item'ları, not
  içeriklerini ve etiketleri tek bir JSON'a topluyor, OS'un paylaşım
  sayfasına (`share_plus`) veriyor. Yalnızca metin/metadata — fotoğraf/
  PDF/ses dosyalarının kendisi dahil değil, bu JSON'un içinde açıkça
  yazıyor. Şekillendirme mantığı (`export_payload.dart`) Supabase I/O'dan
  ayrı tutuldu ki gerçek bir client olmadan test edilebilsin.
- **AI Settings**: salt-okunur bir bilgi satırı — backend yapılandırılmış
  mı (`apiClientProvider != null`), embedding/arama/Ask AI'ın bu sunucu
  üzerinden çalıştığını açıklıyor.
- Local Drift şeması v4→v5 (`fileSizeBytes` kolonu).

Backend: 85 test (değişmedi — bu üçü tamamen mobil + zaten var olan
Supabase şeması üzerinde). Mobile: `flutter analyze` temiz, 67 test yeşil
(18 yeni: storage_usage, export_payload, ilk kez yazılan
settings_screen_test.dart). Simülatörde canlı doğrulandı — Storage/AI
Settings/Export satırları doğru render oluyor, v4→v5 migration'ı mevcut
veri üzerinde veri kaybı olmadan çalıştı.

### Delete Account ✅

Bölüm 49-52'nin geri kalanı: Settings ekranındaki son madde. `on delete
cascade` sayesinde `auth.users` satırını silmek kullanıcının tüm verisini
(items, notes, collections, ...) otomatik temizliyor; buna ek olarak
Storage'daki dosyalar ayrıca (best-effort) siliniyor.

- Backend — `DELETE /account/`:
  - `AccountRepository.delete_own_files()`: kullanıcının **kendi**
    token'ıyla (mobile'ın tekil item silmede kullandığı aynı RLS izni)
    `storage_path`'i olan item'ları çekip Storage'dan
    `{"prefixes": [...]}` ile toplu siliyor. Bu adım başarısız olsa bile
    (`logger.warning`, kullanıcıya hata dönmüyor) auth silme adımına
    devam ediliyor — kısmi bir Storage temizliği, tüm işlemi
    engellememeli.
  - `AccountRepository.delete_auth_user()`: Supabase Admin Auth API,
    `DELETE {url}/auth/v1/admin/users/{user_id}`, `service_role` key
    ile. Key yapılandırılmamışsa (`backend/.env`'de hâlâ boş —
    OpenAI key'le aynı kategoride, bekleyen bir secret)
    `AccountDeletionUnavailable` fırlatıyor, route bunu `503`'e
    çeviriyor.
  - `account_service.delete_account()`: yukarıdaki iki adımı sırayla
    çağıran, iş mantığını repo'dan ayıran ince bir servis katmanı.
- Mobile — Settings'te "Delete Account" satırı (kırmızı, "Log out"un
  altında): `showDialog` ile "Bu işlem GERİ ALINAMAZ..." onayı istiyor,
  onaylanırsa `AccountService.deleteAccount()` → backend `204` dönerse
  `authControllerProvider.notifier.signOut()` ile yerel session'ı da
  temizliyor (go_router redirect zaten `/login`'e atıyor). Backend
  yapılandırılmamışsa (`apiClientProvider == null`, dev'de sık
  karşılaşılan durum) kullanıcıya "Backend bağlantısı ayarlanmamış"
  hatası gösteriliyor, sessizce başarısız olmuyor.
- **Canlı uçtan uca doğrulanmadı**: `SUPABASE_SERVICE_ROLE_KEY` henüz
  `backend/.env`'de yok, dolayısıyla gerçek bir hesabı gerçekten silme
  yolu hiç çalıştırılmadı — yalnızca mantık (`FakeAccountRepo` ile) test
  edildi. Key eklenince önce tek kullanımlık bir test hesabıyla
  doğrulanmalı.
- İki gerçek Flutter test hatası bulunup düzeltildi: (1) düz
  `ListView(children:)` viewport dışındaki elemanları mount etmiyor,
  `ensureVisible` "No element" veriyordu — `scrollUntilVisible` ile
  çözüldü; (2) onay dialogunun `context.pop()` çağrısı (go_router'ın
  uzantısı, uygulamanın var olan onay-dialog deseni) test harness'inde
  düz `MaterialApp(home:)` yerine `MaterialApp.router(...)` gerektirdi.

Backend: 89 test (85 → 89, +4: dosya temizliği önce çalışıyor mu, dosya
temizliği başarısız olsa da auth silme engellenmiyor mu,
`AccountDeletionUnavailable` doğru mu yayılıyor, başka bir auth hatası
doğru mu yayılıyor). Mobile: `flutter analyze` temiz, 70 test yeşil (67 →
70, +3: onay isteniyor mu, "Vazgeç" silmeyi engelliyor mu, "Hesabı Sil" +
yapılandırılmamış backend doğru hatayı gösteriyor mu). Simülatörde canlı
doğrulandı — satır doğru render oluyor (kırmızı ikon/başlık, "Tüm
verilerini kalıcı olarak sil" alt yazısı, "Log out"un altında).

### Privacy — biometric/PIN kilidi ✅

Settings ekranının son eksik maddesi. `local_auth` paketiyle uygulama
açılışına (ve arka plandan her dönüşte) bir kilit ekranı eklendi;
`flutter_secure_storage` da böylece ilk gerçek kullanımına kavuştu (kilit
açık/kapalı tercihini saklamak için — kendisi hassas bir değer değil,
paketi kullanan ilk özellik bu oldu).

- `AppLockService`: `local_auth`'u sarmalıyor — `authenticate()`
  (`biometricOnly: false`, cihazın kendi PIN/passcode fallback'ine izin
  veriyor — özellik "biometric/PIN kilidi" olarak kapsandığı için, salt
  parmak izi/Face ID değil), `isDeviceSupported()` (cihazda biyometri
  veya passcode yoksa Settings'teki switch'i devre dışı bırakmak için).
  Bir plugin hatası her iki metodda da exception fırlatmak yerine
  güvenli bir varsayılana (false) düşüyor.
- `AppLockGate` (`MaterialApp.router`'ın `builder`'ında, tüm uygulamayı
  sarmalıyor): kilit açıksa ve mevcut oturum henüz doğrulanmamışsa,
  uygulamanın kendisi yerine tam ekran bir kilit ekranı gösteriyor —
  soğuk başlangıçta, ve `WidgetsBindingObserver` ile arka plana her
  düşüşte (`AppLifecycleState.paused`) yeniden. Yalnızca `paused`'a
  tepki veriyor, `inactive`'e değil — paylaşım sayfası veya bildirim
  çekmecesi gibi geçici sistem UI'ları da `inactive` tetikliyor,
  gerçekten arka plana atılmamış bir uygulamayı gereksiz yere
  kilitlememek için.
- `AppLockScreen`: açılır açılmaz otomatik olarak doğrulama istiyor,
  başarısız olursa "Doğrulanamadı — tekrar dene." ile yeniden dene
  butonu gösteriyor.
- Settings'te "Privacy" satırı: cihaz desteklemiyorsa switch devre dışı
  (asla açılamayacak bir switch sunmak yerine). Kilidi AÇMAK önce
  başarılı bir doğrulama istiyor (güvenilmez Face ID'si olan biri
  kendini bir sonraki açılışta dışarıda bırakmasın diye); KAPATMAK
  yeniden doğrulama istemiyor — switch'e ulaşmış olmak zaten mevcut
  oturumun kilitli olmadığı anlamına geliyor.
- Android: `MainActivity` `FlutterFragmentActivity`'ye çevrildi
  (`local_auth`'ın Android tarafı biyometri promptunu bir
  DialogFragment olarak gösteriyor — düz `FlutterActivity` bunu
  ClassCastException ile çökertiyordu), `USE_BIOMETRIC` izni eklendi.
  iOS: `NSFaceIDUsageDescription` eklendi.

Backend değişmedi (bu tamamen mobil bir özellik). Mobile: `flutter
analyze` temiz, 87 test yeşil (70 → 87, +17: `AppLockService` birim
testleri — mocktail ile `LocalAuthentication`/`FlutterSecureStorage`
mock'lanarak — ve `AppLockGate` + Settings'teki switch için widget
testleri, arka plana düşüp yeniden kilitlenme senaryosu dahil).
Simülatörde canlı doğrulandı — Privacy satırı doğru render oluyor,
switch etkileşimli (simülatörün Face ID donanımı `isDeviceSupported()`
için yeterli). Simülatörde Face ID promptunu gerçekten tetiklemek,
Simulator'ün "Features → Face ID → Enrolled" menüsünü tıklamayı
gerektiriyor — bu makinede Accessibility izni olmadığı için
otomatikleştirilemedi; doğrulama akışının kendisi testlerle kapsandı.

### Library — grid görünüm + sıralama ✅

Bölüm 25-33: *"Library (grid/list, sorting)"*. Liste her zaman zaten
vardı; eksik olan grid görünümü ve sıralama seçenekleriydi.

- `LibrarySort` (`newestFirst` — varsayılan, `oldestFirst`,
  `nameAscending`) + saf `sortItems()` fonksiyonu — favoriler filtresinden
  sonra, list/grid'e vermeden önce uygulanıyor. AppBar'daki yeni sıralama
  menüsünden seçiliyor.
- `LibraryViewMode` (`list` — varsayılan, `grid`) — AppBar'daki yeni
  ikonla değiştiriliyor. `themeModeProvider` ile aynı desen: in-memory,
  soğuk başlangıçta her zaman liste.
- `ItemGridTile`: image/screenshot item'lar için gerçek bir thumbnail
  (item detail'in tek görseli için kullandığı aynı signed-URL deseni —
  görünür her karo kendi URL'ini istiyor), diğer tüm tipler için (ve
  signed URL yüklenemezse) tip ikonu + başlık. Favori item'larda sağ
  üstte yıldız rozeti.
- `Item.displayTitle` extension'ı eklendi (`title ?? originalFilename ??
  'Untitled'`) — daha önce dört ayrı yerde tekrarlanan bu mantığı tek
  yerde topluyor; `ItemListTile` de buna geçirildi.

Backend değişmedi (tamamen mobil). Mobile: `flutter analyze` temiz, 87 →
100 test (+13: `sortItems` için 6 birim testi, Library'nin grid/sıralama
kontrolleri için 2 yeni widget testi, `ItemGridTile` için 5 widget testi
— thumbnail, signed-URL hatasında fallback, favori rozeti, not/diğer
tiplere doğru rotaya gitme). Simülatörde canlı doğrulandı — grid görünümü
gerçek Supabase Storage'dan gelen bir thumbnail'i doğru render etti, not
item'ı için fallback ikon + gradient overlay doğru çalıştı.

**Sonradan bulunan bug (kullanıcı gerçek cihazda buldu) ✅ düzeltildi**:
Yeni bir not oluşturunca ("deneme2"), o not grid'de gerçek bir fotoğrafın
thumbnail'iyle görünüyordu; fotoğrafın kendi karosu ise boş kalıyordu.
Kök neden: `GridView.builder`'ın `itemBuilder`'ı `ItemGridTile`'ları key
vermeden oluşturuyordu — "en yeni önce" sıralaması yeni notu index 0'a
taşıyıp fotoğrafı 1'e itince, Flutter key olmadan State nesnelerini
POZİSYONA göre yeniden kullandı; index 0'daki State hâlâ eski sakini
fotoğrafın çözülmüş signed URL'ini tutup göstermeye devam etti, index
1'deki State ise (önceden hiç fetch yapmamış bir karoydu) hiç fetch
yapmadı. Düzeltme: her karoya `key: ValueKey(item.id)` verildi — artık
Flutter karoları pozisyona değil item kimliğine göre takip ediyor.
Regresyon testi eklendi (fix geri alınınca kırmızı olduğu elle
doğrulandı). Mobile: 100 → 101 test. Simülatörde kullanıcının bildirdiği
tam senaryoyla doğrulandı.

### Integration testleri ✅

`integration_test` paketi eklendi. Var olan unit/widget testlerinden
farkı: `test/widget/*` her ekranı kendi başına, sahte (fake)
repository'lerle ve `flutter_test`'in **taklit** render pipeline'ıyla
test ediyor — `integration_test/app_test.dart` ise gerçek `LifeSearchApp`
widget ağacını (gerçek go_router, gerçek ekran geçişleri), gerçek bir
simülatör/cihazda, **gerçek** Skia render pipeline'ıyla çalıştırıyor.
Yalnızca Supabase/backend'e dokunan sınır (auth, item storage,
collections, app-lock) sahte — geri kalan her şey (routing, provider
kompozisyonu, gerçek widget'lar, gerçek gesture'lar) baştan sona
gerçek.

- 5 senaryo: signed-out kullanıcı login ekranına düşüyor mu, bottom nav
  Home/Library/Settings arasında doğru geçiyor mu, Home'dan bir not
  oluşturunca **elle yenilemeden** Library'de görünüyor mu (aşağıdaki
  reaktiflik düzeltmesini de kapsıyor), app-lock kilit ekranını gerçekten
  gösterip başarılı doğrulamada gerçekten açıyor mu.
- **`FakeItemRepository` gerçekten reaktif hale getirildi**: eskiden
  `watchItems()` tek seferlik bir `Stream.value(...)` dönüyordu — bir ekran
  onu izlemeye başladıktan SONRA `createNote`/`uploadFile` gibi bir
  mutasyon olursa asla görünmüyordu (gerçek `OfflineItemRepository`'nin
  canlı Drift stream'i tam tersini yapıyor). `StreamController.broadcast()`
  ile düzeltildi; `setFavorite`/`deleteItem` de artık gerçekten
  mutasyon+bildirim yapıyor. Bu, hem integration testler için gerekliydi
  hem de var olan tüm widget testlerini daha gerçekçi hale getirdi.
- **Gerçek bug bulundu ve düzeltildi**: "+" menüsünün
  `showModalBottomSheet`'i `isScrollControlled: true` vermeden
  açılıyordu — varsayılan olarak ekranın yaklaşık yarısıyla sınırlı.
  Altı seçenek + başlık bu sınırı simülatörde 3.5px aşıyordu
  (`RenderFlex overflowed`) — hiçbir widget testi bu ekranı hiç
  render etmediği için (gerçek boyutlarda hiç çalıştırılmadığı için)
  hiç yakalanmamıştı. `isScrollControlled: true` + içeriği
  `SingleChildScrollView`'e sarmak (küçük ekranlar/büyük sistem yazı
  tipinde ek güvence) ile düzeltildi.
- **CI'da çalışmıyor — bilinçli bir sınır**: gerçek bir cihaz/simülatör
  gerektiriyor; mevcut CI'ın mobile job'ı `ubuntu-latest` üzerinde
  koşuyor. Bunu eklemek `macos-latest`'e geçmeyi (daha yavaş + daha
  pahalı GitHub Actions dakikaları) ve bir simülatör boot etme adımını
  gerektirirdi — şimdilik yerel bir adım olarak kalıyor:
  `flutter test integration_test/app_test.dart -d <device-id>`.

Backend değişmedi. Mobile: `flutter analyze` temiz, 101 unit/widget testi
hâlâ yeşil (reaktif fake ile), + 5 integration testi simülatörde canlı
yeşil (2 geçiş: overflow bulunup düzeltildikten sonra tekrar çalıştırılıp
doğrulandı).

### README derinliği ✅

- **Ekran görüntüleri**: gerçek hesapla (Delete Account'un service_role
  ihtiyacı gibi başka bir yarım-yamalak demo değil), simülatörde canlı
  çekildi — Home, Library (grid), Settings. 3x simülatör çözünürlüğünden
  500px genişliğe küçültüldü (`sips`) — toplam ~460 KB, üç PNG.
- **Mimari diyagramı**: bir Mermaid `flowchart` — Mobile (Screens →
  Repositories → Drift) / Supabase (Auth, Postgres+pgvector, Storage,
  Realtime) / Backend (FastAPI → pipeline → AIProvider) / OpenAI arasındaki
  gerçek veri akışını gösteriyor (kimin kime, hangi kimlikle konuştuğu
  dahil — backend'in `service_role` değil, çağıranın kendi JWT'siyle
  çalıştığı gibi). GitHub markdown'da native render ediliyor; mermaid-cli
  (`npx @mermaid-js/mermaid-cli`) ile syntax hatası olmadığı doğrulandı.
- **Status satırı** güncellendi — artık iki "doküman ötesi" turu da
  (gap-kapatma + ürünleştirme) ve güncel test sayısını (195) yansıtıyor.
- **Tests bölümüne** `integration_test` komutu eklendi.
- **`mobile/README.md`**: `flutter create`'in bıraktığı hiç
  değiştirilmemiş boilerplate'ti (hâlâ "A new Flutter project." diyordu)
  — kök README'ye yönlendiren kısa bir nota çevrildi.

### Collections offline ✅

Diğer her şey Drift + sync queue ile offline çalışırken, Collections
hâlâ doğrudan Supabase'e konuşuyordu (`SupabaseCollectionRepository`,
"no offline cache yet" yorumuyla) — artık `OfflineItemRepository` ile
birebir aynı desende: her okuma local cache'ten, her yazma önce oraya,
sonra sync queue'ya.

- İki yeni Drift tablosu: `LocalCollections`, `LocalCollectionItems`
  (junction) — şema v5→v6. sqlite FK cascade yapmadığı için bir
  koleksiyonu silmek `CollectionLocalDataSource.delete()`'in kendisinin
  önce üyelik satırlarını silmesini gerektiriyor.
- `RemoteCollectionDataSource`: `RemoteItemDataSource` ile aynı desen —
  her yazma çağıranın ürettiği id'yi alıyor (Postgres'in
  `gen_random_uuid()` varsayılanı yerine), böylece kuyruğa alınmış bir
  create'in tekrar denenmesi idempotent oluyor.
- `OfflineCollectionRepository`: `CollectionRepository`'nin
  `OfflineItemRepository`'yle birebir aynı desende offline-first
  implementasyonu.
- **`SyncService`'in kendisi genelleştirildi** — `features/item/data/sync/`
  yerine `core/sync/`'e taşındı, artık hem item'ları hem koleksiyonları
  aynı geçişte pull/push ediyor. Bilinçli mimari karar: tüm mutasyonlar
  TEK bir `sync_queue` tablosunu paylaşıyor (`operationType`'a göre
  ayrışıyor); iki bağımsız `SyncService` çalıştırmak birbirinin
  kuyruğuyla yarışırdı — mevcut kod, tanımadığı bir `operationType`'ı
  yeniden denemek yerine sessizce SİLİYOR, yani ikinci bir servis
  eklemek ilk servisin diğerinin girişlerini sessizce yutmasına yol
  açardı. Provider dairesel bağımlılığı (SyncService her iki feature'ın
  local/remote source'larına ihtiyaç duyuyor, her iki feature'ın
  repository'si de SyncService'e) `core/sync/sync_providers.dart`
  adında nötr bir üçüncü dosyaya taşınarak çözüldü.
- `LocalItem → Item` eşlemesi tekrarlanan private bir metottu
  (`OfflineItemRepository._toItem`); paylaşılan bir `LocalItemX.toDomainItem()`
  extension'ına çıkarıldı — artık koleksiyon içindeki item'ları
  (`LocalCollectionItems` ⋈ `LocalItems`) okurken de aynı kod kullanılıyor.

Backend değişmedi (şema zaten client-supplied id'yi destekliyordu).
Mobile: `flutter analyze` temiz, 101 → 108 test (+7: her yeni
operationType için bir push testi, pending bir rename'i stale pull'un
ezmediğini doğrulayan bir test, stale bir üyelik satırının
düşürülüp yenisinin eklendiğini doğrulayan bir test —
`test/unit/sync_service_test.dart`'a eklendi, var olan pattern'i
izleyerek: repository/data-source seviyesinde ayrı bir test dosyası
yok, item tarafında da hiç olmadığı gibi). Simülatörde canlı
doğrulandı: v5→v6 migration'ı mevcut veri (bir fotoğraf + bir not)
üzerinde veri kaybı olmadan çalıştı, Library'nin Collections şeridi
gerçek Supabase backend'ine karşı hatasız render oldu.

### Entity extraction ✅

Bölüm 44-48'in son maddesi, "ileri aşama" — kişi/yer/kurum/tarih gibi
yapılandırılmış, tipli varlıklar. Tags'in (serbest metin) tamamlayıcısı:
aynı içerik, farklı bir soru sorularak.

- **Şema**: `entities` + `item_entities` — `tags`/`item_tags`'le
  (0001_init.sql) birebir aynı şekil, `type` için bir check constraint
  (`person`/`place`/`organization`/`date`) eklenmiş hâli. Realtime
  publication'a eklenmedi — tags gibi, mobile bunu tek seferlik bir
  sorguyla çekiyor, canlı izlemiyor. Canlı projede uygulandı.
- **`entity_extraction_service.py`**: `tagging_service.py` ile aynı
  "best-effort, provider hatası boş liste döndürür" sözleşmesi. JSON
  yerine satır-satır `'tür: ad'` formatı seçildi — `generate_tags`'in
  virgülle-ayrılmış formatı seçme gerekçesiyle aynı: LLM'in yanıtındaki
  tek bir bozuk karakter tüm JSON parse'ını çökertmez, sadece o satır
  atlanır.
- **Pipeline'a bağlandı**: tag'lerin aksine — image'lar vision call'dan
  "bedava" tag alıyor, ama entity çıkarmıyor — her içerik tipi (image
  dahil) aynı normalize edilmiş metne karşı çalıştırılıyor.
- **Mobile**: `ExtractedEntity` (name+type) domain modeli, `fetchTags`
  ile birebir aynı desende `fetchEntities` (Supabase'e doğrudan,
  item_tags→tags join'iyle aynı şekilde item_entities→entities). Item
  detail ve not editörde `TagsRow`'un hemen altında yeni bir
  `EntitiesRow` — her chip'te türe özel bir ikon (kişi/yer/kurum/tarih),
  dokununca aynı `TagsRow` gibi arama sonuçlarına gidiyor.

Backend: `flutter analyze`/`ruff` temiz, 89 → **98** backend testi
(+9: `entity_extraction_service` için 6 birim testi, pipeline'a entegre
edildiğini doğrulayan 3 test). Mobile: 108 → **111** test (+3,
`entities_row_test.dart`). **Canlı doğrulanamadı**: hem gerçek varlık
üretimi bir OpenAI key'e bağlı (henüz yok — tags'te de aynı durum
vardı), hem de item detail ekranına bu oturumda kullanılan
"initialLocation router hack'i" ile ulaşılamıyor (rota `state.extra`
olarak tam bir `Item` nesnesi bekliyor, gerçek bir tıklama/push
gerektiriyor). Sorgu şekli, production'da zaten kanıtlanmış
`fetchTags`'le birebir aynı olduğu için düşük risk.

### UI cilası — ortak arama kutusu, tip renkleri, Inter fontu ✅

Doküman kapsamında bir boşluk değil (kod tarafında bir önceki oturumdan
yarım kalmış, commit edilmemiş bir değişiklik seti) — bitirilip
doğrulandı ve buraya not düşülüyor.

- **`LifeSearchBar`** (`shared/widgets/`): Home'daki (readOnly teaser) ve
  Search sekmesindeki (canlı alan) arama kutuları artık tek bileşen —
  ikisi de görsel olarak birebir aynı, yalnızca davranışta ayrışıyor.
  Requirements dokümanının 67. bölümündeki "Google Search, but for your
  personal digital life" hissini vermek için düz bir `TextField`'dan
  biraz daha fazla ağırlık taşıyor: yumuşak bir gölge, ve boşken (ve
  focus'ta değilken) dokümanın 1. bölümündeki örnek sorgular arasında
  ~3 saniyede bir dönen bir hint metni. Search sekmesi kendi `suffixIcon`
  (temizle butonu) davranışını üzerine geçiriyor.
- **`itemTypeColor()`** (`item_type_icon.dart`): her içerik tipine sabit
  bir renk — Library grid/list, Home "Recently Added", search sonuçları,
  item detail ve Ask AI'nin kaynak chip'leri artık aynı tipi her yerde
  aynı renkte gösteriyor. Bilinçli olarak markanın indigo'su değil,
  yumuşak/orta tonlu ayrı bir palet (bölüm 67'nin "AI-glow değil, minimal"
  ilkesiyle tutarlı — tam bir renk-kodlama sistemi değil, sadece göz
  ucuyla ayırt etmeyi kolaylaştıran bir ipucu).
- **Home'un "Recently Added" şeridi**: kendi `_RecentCard` widget'ını
  atıp Library'nin `ItemGridTile`'ını yeniden kullanıyor — artık
  image/screenshot'lar için gerçek thumbnail gösteriyor, önceden sadece
  tip ikonu + başlık gösteriyordu. Home'daki teaser artık kullanıcının
  içeri girince gerçekte göreceğiyle eşleşiyor.
- **Inter fontu** (`google_fonts` paketi, `app_theme.dart`): Material 3
  varsayılan temasının üzerine `GoogleFonts.interTextTheme()` ile
  bindiriliyor — colorScheme'den türeyen metin renkleri dahil her
  boyut/ağırlık rolü korunuyor, yalnızca font ailesi değişiyor.
  **Bilinçli bir sınır**: font dosyaları asset olarak bundle edilmedi,
  `google_fonts` ilk açılışta interneti varsa Inter'i indirip
  cihazda cache'liyor; internet yoksa (offline-first bir uygulama için
  gerçek bir senaryo) sessizce sistem fontuna düşüyor — çökmüyor, sadece
  o oturumda Inter görünmüyor. Tam offline garanti isteniyorsa bir
  sonraki adım fontu asset olarak gömüp
  `GoogleFonts.config.allowRuntimeFetching = false` yapmak.

Backend değişmedi (tamamen mobil). Mobile: `flutter analyze` temiz,
mevcut 110 test hâlâ yeşil (bu tur için yeni bir test eklenmedi —
görsel bir cila, davranış değişmedi; `LifeSearchBar`'ın rotasyon
zamanlayıcısı `Timer.periodic` kullandığı için widget testlerinde
`pumpAndSettle` yerine `pump(duration)` gerektirir, mevcut testler bunu
tetiklemeyecek kısalıkta kaldığı için kırılmadı).

### Backend rate limiting ✅

Dokümanın kapsamı dışında ama gerçek bir üretim riski: `/ai/process-item`,
`/ai/ask` ve `/search/` her çağrıda bir OpenAI isteği (embedding/vision/
Whisper/chat) tetikliyor — düz bir CRUD çağrısının aksine bunun hem parası
hem süresi var. Bir client bug'ı (sonsuz retry döngüsü), sızmış bir token
veya "Ask AI"ya art arda basan biri bu backend üzerinden sınırsız bir
OpenAI faturası açtırabilirdi.

- **`core/rate_limit.py`** — `SlidingWindowLimiter`: kullanıcı başına,
  gerçek bir trailing window (sabit bir dakika sınırında sıfırlanan bir
  sayaç değil — aksi halde bir client sınırın iki katını, resetin hemen
  öncesi/sonrasına denk getirerek geçebilirdi). Redis yok, tamamen
  process-içi (kural 4, "gereksiz abstraction oluşturma") — bilinçli bir
  sınır: backend birden fazla instance'a ölçeklenirse her biri kendi
  penceresini ayrı ayrı uygular (`limit * instance_count` gibi bir etkiye
  yol açar). Tek bir deployment için yeterli; yatay ölçeklenmeden önce
  Redis-backed bir versiyona geçilmeli.
- **`rate_limit_dependency(bucket, limiter)`**: `Depends(get_current_user)`
  ile birebir yer değiştirebilen bir FastAPI dependency üretiyor — aynı
  `get_current_user`'ı çağırdığı için FastAPI'nin istek-içi dependency
  cache'i sayesinde auth doğrulaması hâlâ tek sefer çalışıyor, üstüne
  limit aşılınca `Retry-After` header'ıyla 429 fırlatıyor.
  `require_ai_rate_limit` (`/ai/process-item`, `/ai/ask`) ve
  `require_search_rate_limit` (`/search/`) — `Settings.rate_limit_ai_per_minute`
  (varsayılan 10) ve `rate_limit_search_per_minute` (varsayılan 30)'dan
  besleniyor. `/search/related` ve `/collections/suggest` bilinçli olarak
  dışarıda bırakıldı: ilki hiç provider çağırmıyor (zaten depolanmış bir
  chunk embedding'ini karşılaştırma vektörü olarak kullanıyor), ikincisi
  günlük kullanımda nadiren tetiklenen bir Library ekranı aksiyonu —
  ikisi de bu limitin var olma sebebi olan maliyet riskini taşımıyor.
- Testler `time.monotonic`'i inject edilebilir bir `now` parametresiyle
  değiştirdiği için pencere sona erme senaryoları gerçek `sleep` olmadan
  test ediliyor (fake repo/provider desenle aynı yaklaşım).

Backend: 75 test yeşil (68 → 75, +7: limiter için 5 birim testi + gerçek
bir FastAPI route üzerinden 200/429+Retry-After doğrulayan 2 test).
`ruff check` temiz. Mobile değişmedi.

### Reranking ✅

Bölüm 65'in listesindeki, `search_service.py`'nin kendi modül docstring'inde
"ileri aşama" diyerek kapsam dışı bıraktığı madde. RRF (hybrid search RPC'si
+ `_dedupe_best_per_item`) hızlı ve ucuz ama bir chunk'ı sorguyla neden
eşleştiğini hiç "anlamıyor" — sorgunun kelimelerini tesadüfen tekrar eden
kısa bir pasaj, gerçekte daha alakalı ama o kelimeleri birebir tekrarlamayan
uzun bir pasajı salt ts_rank/embedding-mesafesi üzerinden geçebilir.

- **`reranking_service.rerank_matches()`**: LLM'in adayları gerçekten
  okuyup sorguyla en alakalıdan en az alakalıya sıralamasını istiyor —
  ayrı bir cross-encoder modeli eklemek yerine (kural 4, "gereksiz
  abstraction oluşturma") zaten var olan `generate_text`'i yeniden
  kullanıyor. Prompt'a en fazla 30 aday (`_MAX_CANDIDATES`) veriliyor,
  her biri 300 karaktere kırpılıyor — büyük bir `limit` isteyen bir
  client'ın prompt boyutunu/maliyetini patlatmaması için.
- **Parse formatı**: `tagging_service`/`entity_extraction_service`'le aynı
  gerekçeyle JSON değil, virgülle ayrılmış 1-tabanlı numara listesi
  ("3,1,4,2") — modelin yanıtındaki tek bir bozuk karakter tüm sıralamayı
  çöpe atmasın diye. Adayların yarısından azını anan bir yanıt (muhtemelen
  düzyazıya kaçmış bir "yanlış ateşleme") kullanılamaz sayılıp orijinal
  RRF sırasına düşülüyor; kısmi ama kullanılabilir bir sıralamada modelin
  hiç anmadığı adaylar kendi aralarındaki orijinal sırayla sona ekleniyor.
- **Best-effort sözleşmesi**: provider hatası veya parse edilemeyen bir
  yanıt — ikisi de arama sonucunu asla boşaltmıyor, `search_service`'in
  zaten bulduğu sırayla dönüyor.
- **`search_service.semantic_search()`**: dedupe artık doğrudan `limit`'e
  değil, `min(len(matches), limit*2)`'lik daha geniş bir shortlist'e
  düşüyor — reranker'a yeniden sıralamaktan başka bir şey yapamayacağı,
  zaten `limit`'e kırpılmış bir liste vermemek için (aksi halde reranking
  hiçbir zaman RRF'nin dışarıda bıraktığı bir item'ı öne çıkaramazdı; bir
  testte tam olarak bunu doğruluyor). Yeni bir `rerank: bool = True`
  parametresi var — `/ai/ask` (RAG'ın kaynak seçimi) da `semantic_search`'ü
  hiç değişmeden aynı şekilde çağırdığı için reranking'i otomatik olarak
  bedava alıyor.
- **Maliyet/gecikme notu**: bu, her `/search/` ve `/ai/ask` çağrısına bir
  embedding'in üstüne bir `generate_text` çağrısı daha ekliyor — RRF'ye
  kıyasla daha yavaş ve daha pahalı. Bir önceki turda eklenen rate
  limiting (`require_search_rate_limit`, `require_ai_rate_limit`) bu
  maliyeti zaten sınırlıyor; ayrı bir yapılandırma anahtarı eklenmedi
  (kural 4) — devre dışı bırakmak gerekirse `rerank=False` kod
  seviyesinde her zaman mevcut.

Backend: 86 test yeşil (75 → 86, +11: reranking_service için 9 birim
testi + search_service'e reranking'in shortlist'i genişlettiğini ve
`rerank=False`'ın LLM'i hiç çağırmadığını doğrulayan 2 entegrasyon
testi). `ruff check` temiz. Mobile değişmedi.

### Bug fix: chunk overlap hiç çalışmıyordu ✅

Bir kod incelemesi turunda bulundu — doküman kapsamının dışında ama gerçek
bir veri kalitesi hatası. `chunking_service.chunk_text()`'in paragraf-
taşması dalında, `overlap = buffer[-overlap_chars:]` satırı `flush()`
çağrısından *sonra* çalışıyordu — ama `flush()` zaten `buffer`'ı `""`'e
sıfırlıyor, yani `overlap` her zaman boş string'ti. Sonuç: "chunk sınırını
aşan bir kavram her iki chunk'ta da görünsün" diye tasarlanan overlap,
paragraf paketleme yolunda (`_slice_long_paragraph`'ın kendi overlap'i
etkilenmemişti, sadece bu dal) hiç gerçekleşmiyordu — chunk sınırındaki
bağlam sessizce kayboluyor, bu da tam o sınıra denk gelen sorgularda
arama/RAG kalitesini görünmez şekilde düşürüyordu.

Bunu yakalaması gereken test (`test_consecutive_chunks_share_a_small_overlap`)
yanlışlıkla yeşildi: test verisi aynı birkaç kelimeyi ("Sentence", "about",
"topic") her paragrafta tekrarladığı için, "kuyruktaki herhangi bir kelime
bir sonraki chunk'ın *herhangi bir yerinde*" şeklindeki gevşek assertion,
gerçek bir suffix-overlap olmasa da geçiyordu. Fix: overlap'i `flush()`'tan
*önce* hesaplamak (tek satır); test de gevşek "herhangi bir kelime" yerine
`chunks[1].startswith(tail_of_first)` ile sıkılaştırıldı — eski koda karşı
elle doğrulandı (kırmızı çıkıyor).

Backend: 86 test yeşil (değişmedi — yeni bir test eklenmedi, var olanı
güçlendirdi). `ruff check` temiz.

### Performans: items_repository.py artık tek bir HTTP client paylaşıyor ✅

Bir kod incelemesi turunda bulundu. `SupabaseRestRepository`'nin her
metodu kendi `httpx.AsyncClient(...)`'ını açıp kapatıyordu —
`process_item()` tek bir item için (örn. bir görsel) `get_item`,
`download_file`, `update_item_metadata`, `replace_item_content`,
`replace_chunks` (2 çağrı), `attach_tags` (2-3 çağrı), `attach_entities`
(2-3 çağrı), job/status güncellemeleri derken **15-20 ayrı TCP+TLS
handshake** yapıyordu — hepsi aynı Supabase projesine, aynı istek
sırasında.

- `SupabaseRestRepository.__init__`'te artık tek bir `httpx.AsyncClient`
  oluşturuluyor (`headers=self._headers` ile — apikey/Authorization artık
  her çağrıda tekrar tekrar spread edilmiyor, httpx bunları client
  seviyesindeki varsayılanlarla otomatik birleştiriyor). Her metot kendi
  `async with httpx.AsyncClient(...)` bloğu yerine `self._client`'ı
  kullanıyor; sadece farklı olan (Content-Type, Prefer, ya da
  `download_file`/`replace_chunks`'ın 30s'lik timeout override'ı)
  çağrı bazında geçiliyor.
- Yeni `aclose()` — `process_item()`'ın `finally` bloğunda çağrılıyor
  (hem başarılı hem başarısız yoldan sonra), çünkü `repo` bu background
  task'ın tek tüketicisi ve ondan sonra hiçbir yerde tekrar kullanılmıyor.
- **Kapsam bilinçli olarak dar tutuldu** (kural 4): `SearchRepository`/
  `AccountRepository` aynı per-call-client desenini hâlâ kullanıyor — bu
  ikisi tipik bir istekte sadece 1-2 çağrı yapıyor, kazanç
  `SupabaseRestRepository`'ninki kadar büyük değil; ekstra lifecycle
  karmaşıklığına değmiyor.
- **Doğrulama notu**: `document_service.py`'nin (dolayısıyla
  `processing_pipeline.py`'ın) bu makinede önceden belgelenmiş
  pypdf→expat ortam sorunu yüzünden `test_processing_pipeline.py` yerelde
  hâlâ hiç import edilemiyor (CI'ı etkilemiyor). Bunun yerine
  `SupabaseRestRepository`'yi gerçek bir `httpx.MockTransport`'a karşı elle
  çalıştırdım — 6 farklı metottan 9 gerçek HTTP çağrısı, tek bir paylaşılan
  client üzerinden, doğru header/body/timeout'larla doğrulandı, `aclose()`
  sonrası `client.is_closed == True`. `FakeRepo`'ya (test double) yeni bir
  `aclose()` + onu doğrulayan 2 test eklendi.

Backend: 118 test toplamda (+2: repo'nun kapatıldığını doğrulayan 2 yeni
`test_processing_pipeline.py` testi) — bu makinede o dosya pypdf/expat
importu yüzünden hâlâ hiç çalışmıyor, ama diğer 86'sı (değişmeyen sayı)
yerelde yeşil; CI'da (ubuntu-latest, bu sorunu yaşamıyor) 118'i de
çalışacak. `ruff check` temiz.

### Mobile bug fix: `/item/:id` deep link'te crash ediyordu ✅

Bir kod incelemesi turunda bulundu. `app_router.dart`'ta `/item/:id` ve
`/item/:id/note` rotaları `:id` path parametresini hiç okumuyor,
tamamen `state.extra as Item`'a güveniyordu. `extra` yalnızca uygulama
içi bir tıklamadan geliyor (bir önceki ekran zaten elindeki `Item`
nesnesini geçiriyor); bir deep link, push notification, ya da Android/iOS
process-death sonrası route restore'unda `extra` hiç yok — `null as Item`
anında **crash** ediyordu. Bu aynı zamanda projenin kendi test edilebilirlik
sınırıydı: entity extraction turunda item detail ekranına "gerçek bir
tıklama/push gerektiriyor" diye not düşülmüştü — artık gerekmiyor.

- **`ItemByIdLoader`** (`shared/widgets/`): `extra` yoksa, item'ı `:id`'den
  `ItemRepository.findById()` (local Drift cache, zaten duplicate-banner
  için vardı — yeni bir repository metodu gerekmedi) ile çözüyor; çözerken
  bir spinner, bulunamazsa (henüz bu cihazla senkronize olmamışsa) çöküp
  beyaz ekran yerine anlaşılır bir "İçerik bulunamadı" mesajı gösteriyor.
- **Kapsam bilinçli dar tutuldu**: `ItemDetailScreen`/`NoteEditorScreen`'in
  kendisi hiç değişmedi — `extra` varken (normal, uygulama içi navigasyon)
  tamamen eskisi gibi, sıfır ekstra fetch. Fallback yolu sadece router
  seviyesinde.
- `itemByIdProvider`: `findById`'i saran ince bir `FutureProvider.family`.

Mobile: `flutter analyze` temiz, 110 → 113 test (+3:
`item_by_id_loader_test.dart` — spinner, bulunan item builder'a ulaşıyor
mu, bulunamayan id crash yerine anlaşılır mesaj gösteriyor mu). Diğer
110 test de değişmeden yeşil kaldı — `ItemDetailScreen`/`NoteEditorScreen`
dokunulmadığı için mevcut widget testleri etkilenmedi.

### Küçük performans notları: sıralı çağrılar paralelleştirildi ✅

Bir kod incelemesi turunun kalan iki (düşük riskli) bulgusu.

- **`collection_suggestion_service.suggest_collections()`**: küme
  isimlendirme LLM çağrıları `for` içinde sıralıydı — N kümesi olan bir
  kullanıcı N ayrı `generate_text` round trip'i bekliyordu. Artık
  `asyncio.gather` ile birlikte çalışıyor; `gather()` sonucu girdiyle
  aynı sırada döndürdüğü için `clusters`/`names` eşlemesi bozulmuyor.
  Regresyon testi: sahte bir provider'ın aynı anda kaç çağrının "uçuşta"
  olduğunu sayması (`max_active`) — sıralı koda geri dönülürse test
  kırmızı çıkar. Backend: 87 → **88** test (yerelde doğrulanan kapsamda).
- **`sync_service._pullRemote()`**: her not için `fetchNoteContent`
  round trip'i `for` döngüsü içinde sıralıydı (proje zaten bunu "demo
  ölçeğinde sorun değil" diye not etmişti — join'siz tam çözüm hâlâ
  gelecekteki bir adım). `Future.wait` ile tüm notların içeriği tek bir
  eşzamanlı grupta çekiliyor, sonra upsert'ler eskisi gibi sırayla
  yazılıyor. `remoteIds`/stale-id hesaplaması ve pending-satır atlama
  mantığı birebir korundu. Bu yolun daha önce **hiç** birim testi yoktu —
  hem temel doğruluk (`fetchNoteContent` çağrılıp doğru satıra yazılıyor
  mu) hem eşzamanlılık (`max_active >= 2`) için iki yeni test eklendi.
  Mobile: 113 → **115** test.

Backend `ruff check` temiz, mobile `flutter analyze` temiz.

### Faz 10 — Sağlamlaştırma: bağımsız bir denetimde bulunan gerçek boşluklar

Aşağıdaki "sadece iki key eksik" satırı yanlış çıktı. Codex tabanlı
bağımsız bir denetim (10 Eylül 2026, HEAD `c6fac19`) 71 bölümü kodla
satır satır karşılaştırdı ve daha önceki taramaların (bu dosyanın kendi
içindeki "Faz 9 sonrası" ve "kod incelemesi" turları dahil) kaçırdığı,
MVP'yi doğrudan etkileyen sorunlar buldu. Üçü — en ciddisi — doğrulandı:

- **Sync queue hesaba göre ayrılmıyor ✅ (Faz 10a, düzeltildi)** — bkz.
  aşağıdaki alt bölüm.
- **`item_contents.item_id` üzerinde UNIQUE yok, ama mobil kod
  `onConflict: 'item_id'` ile upsert yapıyor**
  ([remote_item_data_source.dart:104](../mobile/lib/features/item/data/remote/remote_item_data_source.dart),
  şema: [0001_init.sql:65](../infra/supabase/migrations/0001_init.sql) —
  yalnızca düz bir index var). Bu repository'deki migration'lardan
  kurulan temiz bir Postgres'te not oluşturma **Postgres hatasıyla
  başarısız olur**; catch bloğu telafi amaçlı `items` satırını da siler.
  Canlı projede elle eklenmiş bir constraint bu asimetriyi gizliyor
  olabilir — migration'ın kendisi eksik.
- **Search/Ask AI/Related Items'tan açılan item'lar dosya
  gösteremiyor**: bu üç ekran, `/item/:id`'ye gerçek `Item` yerine
  `storagePath`/`sourceUrl` içermeyen budanmış bir nesne gönderiyor
  ([search_tab.dart:112](../mobile/lib/features/search/presentation/screens/search_tab.dart),
  [ai_chat_tab.dart:53](../mobile/lib/features/ai_chat/presentation/screens/ai_chat_tab.dart)).
  `ItemDetailScreen._loadSignedUrl()` `storagePath` null ise sessizce
  hiçbir şey yapmıyor — **"Faz 9 sonrası" turunda eklenen
  `ItemByIdLoader` bunu çözmüyor**, çünkü o yalnızca `extra` *hiç
  yokken* (gerçek deep link) devreye giriyor; burada `extra` dolu ama
  eksik. Ayrı, tamamlayıcı bir düzeltme gerekiyor (muhtemel çözüm:
  `ItemDetailScreen`/`NoteEditorScreen`'in `initState()`'ı, gelen
  `item` ne olursa olsun `findById` ile her zaman tam kaydı çekip
  üzerine yazsın — local Drift lookup olduğu için ucuz).

#### Faz 10a, madde 1: Sync queue hesap izolasyonu ✅

`SyncQueueEntries` ve `RecentSearches`'e `userId` kolonu eklendi — artık
`LocalItems`/`LocalCollections`'ın zaten yaptığı gibi, her okuma/yazma
imzalı bir kullanıcıya bağlı.

- **Şema**: `SyncQueueEntries.userId`/`RecentSearches.userId`
  ([sync_queue_entries.dart](../mobile/lib/core/database/tables/sync_queue_entries.dart),
  [recent_searches.dart](../mobile/lib/core/database/tables/recent_searches.dart)) —
  yalnızca migration'ın `ALTER TABLE ADD COLUMN`'ının bir şeyi doldurabilmesi
  için `withDefault('')`; her gerçek insert her zaman açıkça geçiyor.
  Local şema v6→v7.
- **Migration backfill**: yeni sütun `whoever's-signed-in-now` tahmini
  yerine, her queue kaydının **hedeflediği item/collection'ın zaten doğru
  olan `userId`'sinden** dolduruluyor (`AppDatabase.backfillSyncQueueOwnership()`)
  — bir hesap değişimini atlatmış bir kayıt bu tahminle yanlış sahibe
  atanırdı. Hedefi artık local'de bulunmayan bir kayıt kimseye
  atfedilemez, silinir (yanlış hesap altında bir yazmayı riske atmaktansa).
  `recent_searches`'in geri kazanılabilecek bir sahiplik izi yok, o yüzden
  sadece temizleniyor. Backfill mantığı, `ALTER TABLE` adımından ayrı,
  doğrudan test edilebilir bir metoda çıkarıldı (eski şemayı elle sqlite
  DDL'iyle yeniden kurmak yerine, mevcut v7 şemasında `userId: ''`
  satırlar oluşturup backfill'i çağırarak test edildi).
- **`SyncQueueDataSource`/`RecentSearchesDataSource`**: `enqueue()`,
  `pendingEntries()`, `watchPendingCount()`, `watchRecent()`, `record()`,
  `clear()` artık hepsi `userId` alıyor/filtreliyor. `SyncService._flushQueue()`
  artık yalnızca imzalı kullanıcının kendi kayıtlarını işliyor —
  `syncNow()` zaten hesap değişiminde otomatik tetikleniyor
  (`authStateChangesProvider`), yani B hesabı açılır açılmaz B'nin kendi
  (boş) kuyruğu işlenir, A'nınki dokunulmadan kalır.
  `OfflineItemRepository`/`OfflineCollectionRepository`'nin tüm
  `enqueue()` çağrıları zaten sahip oldukları `_userId` getter'ını
  geçiriyor.
- **`pendingSyncCountProvider`/`recentSearchesProvider`**: imzalı
  kullanıcı yoksa (ya da `Supabase.initialize()` hiç çalışmamışsa — bkz.
  `search_providers.dart`'taki `_currentUserIdOrNull()`, bunun neden
  gerçek uygulamada asla olmayan ama bir widget testinde olabilecek bir
  durum olduğu açıklaması) `0`/boş listeye düşüyor, çökmüyor.

**Regresyon testleri**: `sync_service_test.dart`'a A'nın offline notunun
B'nin oturumu açıkken **asla** gönderilmediğini, kuyrukta beklemeye devam
ettiğini ve A geri giriş yaptığında normal şekilde gönderildiğini
doğrulayan bir test eklendi. Yeni `app_database_migration_test.dart`
(4 test) backfill'in item-scoped/collection-scoped/atfedilemeyen
girdileri doğru işlediğini doğruluyor. Yeni
`recent_searches_data_source_test.dart` (4 test) hesap izolasyonunu
doğruluyor — bu turda ayrıca `watchRecent()`'in sıralamasında gerçek bir
küçük hata bulundu (`searchedAt`'in `currentDateAndTime` varsayılanı
saniye hassasiyetinde; aynı saniyede art arda iki arama "en yeni önce"
sırasını bozabiliyordu) ve `id DESC` ikincil sıralamasıyla düzeltildi.

Mobile: `flutter analyze` temiz, 115 → **124** test (+9: 4 migration
backfill + 4 recent-searches izolasyonu + 1 cross-account sync).
`ItemDetailScreen`/`NoteEditorScreen`'e hiç dokunulmadı — bu commit'in
kapsamı sadece kuyruk/arama geçmişi izolasyonu, madde 3 (kısmi Item)
hâlâ ayrı bir düzeltme bekliyor.

Doğrulanmayan ama dosya/satır referanslı, inandırıcı bulunan diğer
maddeler (öncelik sırasıyla, denetim raporundan):

4. Hesap silme: dosyalar `service_role` key kontrolünden **önce**
   siliniyor — key yoksa hesap silinemeden dosyalar gidebilir
   ([account_service.py:20](../backend/app/services/account_service.py)).
5. `configure_logging(debug=True)` root logger'ı DEBUG'a çekiyor; kurulu
   OpenAI SDK'sı bu seviyede istek gövdesini (prompt/embedding girdisi)
   loglayabiliyor — "asla içerik loglama" kuralını uygulamanın kendi
   `logger` çağrıları değil, üçüncü parti SDK'nın log seviyesi de
   belirliyor ([logging.py:72](../backend/app/core/logging.py)).
6. AI job tetikleme hatası tamamen yutuluyor, kalıcı retry/kullanıcıya
   "Tekrar Dene" yok; backend `BackgroundTasks` restart sonrası job
   kurtarmıyor; mobilde işleme sonucu için Realtime/polling yok —
   sync yalnızca connectivity/auth/yerel yazma tetikliyor
   ([ai_processing_trigger.dart:13](../mobile/lib/features/item/data/remote/ai_processing_trigger.dart)).
7. "Geçen ay" takvim ayı yerine "son 30 gün" olarak yorumlanıyor; "dün"
   bitiş sınırı yok, bugünü de kapsıyor
   ([query_parser.py](../backend/app/services/query_parser.py)).
8. `replace_chunks`/`replace_item_content` bağımsız DELETE+INSERT —
   aynı item için eşzamanlı iki job iki kez INSERT yapabilir (unique
   constraint/job-lock yok).
9. URL fetch'te SSRF koruması yok (private IP/localhost/redirect hedefi
   doğrulaması, boyut sınırı) — kaydedilen bir link doğrudan çekiliyor
   ([url_service.py](../backend/app/services/url_service.py)).
10. Genel belge (DOCX/TXT) desteği yok, `document` tipi backend
    `SUPPORTED_TYPES`'ta değil; taranmış (metin katmanı olmayan) PDF'te
    OCR fallback yok, `extract_pdf_text` metinsiz kalırsa hata veriyor.
11. Android ana `AndroidManifest.xml`'de `INTERNET` izni yok — yalnızca
    debug/profile manifestlerinde var; release build'de doğrulanmalı.

**Önerilen sıra** (denetim raporundan, projenin kendi faz mantığıyla
uyumlu hale getirildi):

1. **Faz 10a (P0 — MVP'yi bloke eden)**: hesap izolasyonu (sync queue +
   logout'ta local DB temizliği + recent searches), `item_contents`
   UNIQUE migration'ı, search/RAG/related'tan tam item açma, hesap
   silme sırası, debug log seviyesi.
2. **Faz 10b (P1 — güvenilirlik)**: AI job retry + kullanıcıya "Tekrar
   Dene" + realtime/polling ile otomatik mobil güncelleme, chunk/content
   replace idempotency, URL fetch SSRF koruması, Android INTERNET izni.
3. **Faz 10c (içerik kapsamı)**: genel belge desteği, taranmış PDF için
   OCR fallback, doğal dil tarih filtrelerinin takvim aralığına
   düzeltilmesi.
4. **Doğrulama**: gerçek OpenAI + `service_role` key'leriyle, iki ayrı
   hesabı da içeren izole bir ortamda dokümanın 66. bölümündeki MVP
   senaryosunu uçtan uca çalıştırmak — yalnızca o zaman "MVP tamamlandı"
   denebilir.

Google/Apple login, Gemini/local provider, masaüstü/web, tam offline
semantic search, analytics ekranı, item-bazlı Privacy Mode — doküman
zaten bunları "ileri aşama" sayıyor; Faz 10'un kapsamı dışında.
