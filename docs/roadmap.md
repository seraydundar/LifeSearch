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
- **`item_contents.item_id` üzerinde UNIQUE yoktu ✅ (Faz 10a, migration
  yazıldı)** — bkz. aşağıdaki alt bölüm.
- **Search/Ask AI/Related Items'tan açılan item'lar dosya gösteremiyordu
  ✅ (Faz 10a, madde 3, düzeltildi)** — bkz. aşağıdaki alt bölüm.

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

#### Faz 10a, madde 2: `item_contents` UNIQUE constraint ✅

`infra/supabase/migrations/0012_item_contents_unique.sql` eklendi —
`item_id` üzerinde `item_contents_item_id_key` unique constraint'i,
mobil `createNote()`'un `onConflict: 'item_id'` ile beklediği tam şey.
0001_init.sql'deki düz (unique olmayan) index kaldırıldı; constraint
kendi index'ini zaten oluşturduğu için ikisini birden tutmak gereksiz
yer kaplardı. Constraint eklenmeden önce bir dedup adımı var
(`item_id` başına en yeni `created_at`'i tutup gerisini siliyor) —
canlı bir tabloda zaten var olabilecek bir şeye karşı sigorta, bu bug'ın
kendisi hiç başarılı bir insert üretmediği için (Postgres constraint
olmadan `ON CONFLICT` isteğini komple reddediyordu) aslında hiç
tetiklenmemiş olması bekleniyor.

**Doğrulama**: bu makinede `SUPABASE_SERVICE_ROLE_KEY`/DB şifresi
olmadığı için canlı projeye uygulanamadı (bu, kullanıcının kendisinin
yapması gereken bir adım — Supabase Dashboard'un SQL editörü veya
`supabase db push`). Bunun yerine, geçici bir `postgres:16` Docker
container'ında `item_contents`'in gerçek şeklini kurup iki satırlık bir
"sahte duplicate" ekleyip migration'ı gerçekten çalıştırdım: dedup
(2 satır → 1), index değişimi ve constraint ekleme hepsi doğru çalıştı;
ardından PostgREST'in `.upsert(onConflict: 'item_id')`'inin ürettiği
tam `INSERT ... ON CONFLICT (item_id) DO UPDATE ...` sorgusunu elle
çalıştırdım — artık hatasız çalışıyor (constraint'ten önce "no unique or
exclusion constraint matching" hatasıyla patlıyordu).

**Kalan adım**: bu migration dosyasının canlı Supabase projesine
uygulanması — kullanıcı tarafında.

#### Faz 10a, madde 3: Search/Ask AI/Related Items'tan açılan item'lar ✅

`ItemByIdLoader` (Faz 9 sonrası turu) bu sorunu çözmüyordu çünkü yalnızca
`extra` *hiç yokken* (gerçek deep link) devreye giriyor — burada `extra`
her zaman dolu, sadece eksik (search/RAG/related item'lar
`storagePath`/`sourceUrl`/gerçek `favorite`/`createdAt` içermeyen budanmış
bir `Item` inşa edip geçiriyor).

- **`ItemDetailScreen._loadFullItem()`**: `initState()`'ta, alınan `item`
  ne olursa olsun `findById(item.id)` ile local Drift'ten tam kaydı
  çekip `_item`'ın üzerine yazıyor. Library'den tıklanan (zaten tam)
  bir item için bu bir no-op'a yakın — `findById` ucuz bir local lookup,
  iki durumu ayırt etmeye çalışmak (kural 4) gereksiz karmaşıklık
  olurdu. Tam kayıt gelince `storagePath` yeni öğrenildiyse
  `_loadSignedUrl()`'i, `duplicateOfItemId` yeni öğrenildiyse
  `_loadDuplicateTarget()`'i tekrar tetikliyor — ilk çağrı zaten aynı
  sonuca ulaştıysa (Library'den tıklanan normal durum) gereksiz bir
  ekstra ağ isteği atmadan.
- **Bilinçli sınır**: `findById` yalnızca local cache'i okuyor, ağa hiç
  gitmiyor — bir item başka bir cihazda az önce oluşturulup bu cihaza
  henüz senkronize olmadıysa (gerçek ama nadir bir durum), ekran "bulunamadı"
  duvarına düşmek yerine sessizce elindeki budanmış `Item`'ı göstermeye
  devam ediyor — kırık bir "Dosyayı Aç" düğmesi, "az önce arama
  sonucunda gördüğün şey artık yok" demekten daha az şaşırtıcı.
- **`NoteEditorScreen`'e dokunulmadı**: notlar için budanmış `Item`
  zaten yalnızca `id`/`title` kullanıyor (ikisi de stand-in'de var —
  bkz. `search_tab.dart`'ın `_openResult`'ı), `storagePath` gibi
  görünür bir alan yok — bugün gözlemlenebilir bir hata olmadan
  spekülatif "ileride lazım olur" kodu eklemek kural 4'e aykırı olurdu.

Mobile: `flutter analyze` temiz, 124 → **127** test (+3, yeni
`item_detail_screen_test.dart` — bu ekranın ilk kez kendi test dosyası:
Library'den tıklanan tam item'ın değişmediğini, budanmış bir stand-in'in
gerçek kayıtla değiştiğini — favori yıldızı ve "Dosyayı Aç" düğmesi dahil
— ve senkronize olmamış bir id'nin çökmeden zarifçe eski haliyle kaldığını
doğruluyor). Ayrıca canlı simülatörde uygulama gerçekten çalıştırılıp
(gerçek bir Supabase hesabıyla, Home ekranı doğru veri gösterdi) backend'in
de (`127.0.0.1:8000`) ayakta ve auth/health/docs uçlarının doğru
davrandığı doğrulandı — bu spesifik senaryo (arama sonucundan dosya açma)
gerçek bir OpenAI key olmadığı için canlı uçtan uca denenemedi, widget
testleriyle kapsandı.

#### Faz 10a, madde 4: Hesap silme — dosyalar önce silinmesin ✅

`delete_account()` `repo.delete_own_files()`'ı `repo.delete_auth_user()`'dan
önce çağırıyordu; ikincisi `service_role` key yoksa
`AccountDeletionUnavailable` fırlatıyordu ama bu kontrol yalnızca
`delete_auth_user()`'ın içindeydi — yani dosyalar zaten silinmiş
oluyordu, hesap silinemeden.

- **`AccountRepository.ensure_deletion_available()`**: I/O yapmayan, salt
  aynı config kontrolünü yapan yeni bir metot — `delete_account()`'ın en
  başında, hiçbir yıkıcı adım başlamadan önce çağrılıyor.
  `delete_auth_user()`'ın kendi içindeki kontrol de duruyor (savunma
  derinliği), ama artık asıl koruma en baştaki bu çağrı.
- Regresyon testi: `test_an_unavailable_backend_never_touches_files` —
  key yokken hem `files_deleted_for` hem `auth_deleted_for`'ın boş
  kaldığını doğruluyor. Var olan
  `test_propagates_account_deletion_unavailable_without_pretending_to_succeed`
  testi bu sırayı hiç kontrol etmiyordu (yalnızca exception'ın
  yayıldığını doğruluyordu) — bug tam da bu boşluktan geçiyordu.

Backend: 87 → **88** test (yerelde doğrulanan kapsamda). `ruff check`
temiz.

#### Faz 10a, madde 5: Debug log seviyesi içerik sızdırıyor ✅

Bu madde "Önerilen sıra"da Faz 10a'nın (P0) bir parçası olarak
yazılmıştı ama fiilen atlanmış kalmıştı — kod hâlâ orijinal haliyle
duruyordu. `configure_logging(debug=True)` yalnızca **root** logger'ı
`DEBUG`'a çekiyordu; Python'ın logging hiyerarşisinde kendi seviyesini
hiç ayarlamamış (bir kütüphanenin normal, iyi huylu davranışı) her
üçüncü parti logger da bunu miras alıyor. `openai` SDK'sı `DEBUG`
seviyesinde tam istek/yanıt gövdesini (prompt, embedding girdisi)
loglayıyor; `httpx`/`httpcore` — burada yalnızca OpenAI istemcisi değil,
her repository'nin Supabase'e giderken doğrudan kullandığı kütüphane —
`DEBUG` seviyesinde istek header'larını, `Authorization` bearer token'ı
dahil, loglayabiliyor. `settings.debug`'ın varsayılanı `True` olduğu
için bu, üretimde de varsayılan davranıştı.

- **`configure_logging()`**: artık `openai`/`httpx`/`httpcore`
  logger'larını açıkça `WARNING`'e sabitliyor — bir logger'ın **kendi**
  seviyesi her zaman bir ata'nın seviyesine kazanır, yani root ne
  olursa olsun bunlar asla `DEBUG`'a çıkamıyor. Uygulamanın kendi kodu
  hiçbir yerde `logger.debug(...)` çağırmadığı için (kontrol edildi),
  `debug` bayrağının bugüne kadarki tek gözlemlenebilir etkisi tam da
  bu sızıntıydı — kaybedilen bir şey yok.
- Regresyon testi yalnızca seviyeyi değil, gerçek bir `logger.debug(...)`
  çağrısını "içerik" taşıyan bir `extra` ile simüle edip bunun log
  buffer'ına hiç yazılmadığını doğruluyor — seviye kontrolünün kağıt
  üzerinde doğru ama fiilen etkisiz olduğu bir senaryoyu (örn. formatter
  seviyeyi görmezden gelirse) da yakalar.

Backend: `ruff check` temiz, testler 162 → **168** (yeni
`test_logging.py` testleri — `openai`/`httpx`/`httpcore`'un `debug=True`
iken bile `DEBUG` seviyesine hiç ulaşamadığını, ve bu logger'lardan
birine yapılan "içerik" taşıyan bir çağrının log buffer'ında hiç
görünmediğini doğruluyor).

#### Faz 10a, madde 11: Android `INTERNET` izni ✅

Ana `AndroidManifest.xml`'de `CAMERA`/`RECORD_AUDIO`/`USE_BIOMETRIC`
vardı ama `INTERNET` yalnızca Flutter'ın kendi debug/profile
boilerplate'inde ("hot reload için gerekli" yorumuyla) duruyordu — bir
**release APK'sı ağa hiç çıkamıyordu**, yani login/sync/search dahil
uygulamanın tamamı sessizce çalışmazdı. Hiç release build alınmamıştı.

- `<uses-permission android:name="android.permission.INTERNET"/>` ana
  manifest'e taşındı — artık debug/profile/release'in hepsine miras
  kalıyor (Android manifest merge kuralı: ana manifestteki bildirimler,
  varyant-özel bir manifest açıkça kaldırmadığı sürece her varyanta
  geçer).
- **Doğrulama — gerçek bir release APK'sı derlendi**: `flutter build apk
  --release`. İlk deneme bu düzeltmeyle ilgisiz bir Android SDK
  sorunuyla (`flutter_secure_storage`'ın SDK 37 istemesi, `compileSdk`'nin
  36 olması) 58s'de başarısız oldu; Flutter SDK Platform 37'yi otomatik
  kurdu, ikinci deneme 117s'de başarıyla `app-release.apk` (64.4MB)
  üretti. Sonucu varsaymak yerine `aapt dump permissions` ile gerçek
  APK'nın manifest'ini okudum —
  `uses-permission: name='android.permission.INTERNET'` orada, diğer
  tüm izinlerin (CAMERA, RECORD_AUDIO, USE_BIOMETRIC, ...) yanında.
- `android/.kotlin/` (bu build'in bıraktığı bir Gradle/Kotlin
  incremental-compilation cache'i, Flutter'ın kendi `.gitignore`
  şablonunda eksikti — yalnızca bu build'e özgü değil, herhangi bir
  Android build'i bunu bırakırdı) `mobile/.gitignore`'a eklendi.

Backend `ruff check`/testleri bu maddeden etkilenmedi (tamamen mobil,
kod değişikliği yok — yalnızca manifest + gitignore).

#### Faz 10b, madde 1: AI tetikleme hatası — kalıcı retry + "Tekrar Dene" ✅

`AiProcessingTrigger.triggerProcessing()` `/ai/process-item` isteği
başarısız olduğunda (backend kapalı, ağ yok, 5xx) hatayı yutuyordu —
item sonsuza kadar `pending`'de kalıyordu, hiçbir kayıt/retry/kullanıcı
bildirimi yoktu. Backend'in kendi pipeline hatası (kötü API key, bozuk
PDF) zaten `processing_status`'u `failed`'e çekiyordu, ama o durumda da
mobilde yeniden deneme yolu yoktu.

- **`AiProcessingTrigger.triggerProcessing()`**: artık `Future<bool>`
  döndürüyor — istek backend'e ulaştıysa `true`, ulaşamadıysa `false`.
  `BACKEND_URL` hiç ayarlanmamışsa (AI özelliği o kurulumda zaten yok)
  `true` sayılıyor — bu bir hata değil, denenecek bir şey yok.
- **`SyncService._triggerAi()`**: tetikleme başarısız olursa, mevcut
  `sync_queue` altyapısını yeniden kullanan bir `trigger_ai` girdisi
  kuyruğa ekliyor — bu girdi diğer her queue kaydı gibi kalıcı (uygulama
  yeniden başlasa da kaybolmuyor) ve her `syncNow()` çağrısında normal
  `retryCount`/`lastError` muhasebesiyle yeniden deneniyor.
  `_markSynced`/`_markFailed` bu op için no-op — ne bir item'ın ne bir
  koleksiyonun local satırı bu op'a ait, o yüzden syncStatus'a
  dokunmuyor (asıl item verisi zaten senkronize olmuştu, sadece AI
  tetiklemesi başarısızdı).
- **`ItemRepository.retryProcessing()`** (yeni): item detayında
  kullanıcının kendi isteğiyle tetiklediği yeniden deneme. Local
  `processingStatus`'u optimistik olarak `pending`'e çekiyor, aynı
  `trigger_ai` kuyruk girdisini ekliyor ve `syncSoon()` çağırıyor —
  backend pipeline'ın kendisinin başarısız olduğu (`failed`) durumla
  tetiklemenin backend'e hiç ulaşmadığı durumu aynı yolla ele alıyor.
- **`ItemDetailScreen`**: işleme durumu `completed` değilken gösterilen
  chip'in yanında, durum `failed` ise bir "Tekrar Dene" düğmesi
  beliriyor (`_toggleFavorite`/`_dismissDuplicate` ile aynı optimistik
  güncelle/geri al deseni).

**Bilinçli sınır**: bu, madde 6'nın üç parçasından yalnızca birini
kapatıyor — "tetikleme hatası sessizce kayboluyor" artık doğru değil,
ama backend'in kendi `BackgroundTasks` restart sonrası job kurtarmaması
ve mobilde AI sonucu için Realtime/polling'in hâlâ olmaması (bir
sonraki başarılı `syncNow()`'a kadar `completed`/`failed` durumu
otomatik yansımıyor) ayrı, çözülmemiş kalıyor — bkz. aşağıdaki
"Önerilen sıra".

Mobile: `flutter analyze` temiz, 127 → **132** test (+3
`sync_service_test.dart` — tetikleme başarısız olduğunda `trigger_ai`
kuyruğa ekleniyor, kuyruktaki bir `trigger_ai` tekrar başarısız olursa
`retryCount` artıyor, başarılı olursa kuyruktan siliniyor; +2
`item_detail_screen_test.dart` — `failed` bir item'da "Tekrar Dene"
görünüyor ve tıklanınca `retryProcessing()`'i çağırıp durumu
optimistik günceller, `pending`/`completed` bir item'da düğme hiç
görünmüyor).

#### Faz 10b, madde 2: job restart-kurtarma + mobil polling ✅

Madde 6'nın kalan iki parçası: backend `BackgroundTasks` bir job'ı
restart/crash'te kaybediyordu (bir sonraki hiçbir şey onu tamamlamıyordu
— item sonsuza kadar `İşleniyor...` gösteriyordu, `failed` olmadığı için
madde 1'in "Tekrar Dene" düğmesi de hiç çıkmıyordu) ve mobilde
`completed`/`failed` durumu ancak bir sonraki connectivity/auth/yerel-
yazma tetiklemeli senkronizasyona kadar görünmüyordu.

**Backend — `app/services/job_recovery.py` (yeni)**: `process_item()`
bir job'ın `status`'unu ve item'ın `processing_status`'unu her zaman
birlikte `processing`'e çekip kendi `try`/`except`'i içinde birlikte
`completed`/`failed`'e döndürüyor — bir job'ın `processing`'de asılı
kalmasının tek yolu, çalıştığı process'in bitmeden ölmesi (deploy
restart, OOM, crash). Bu yüzden **taze bir process'in başlangıcında**
`processing_jobs`'ta `status = 'processing'` bulunan her satır, kanıtlanmış
şekilde önceki bir çökmeden kalmıştır — bu process henüz hiçbir job
başlatmamıştır.

- `recover_orphaned_jobs(repo)`: bulduğu her asılı job'ı `failed`'e
  çekiyor, ilgili item'ı da `failed`'e çekiyor — madde 1'de eklenen
  "Tekrar Dene" düğmesi artık bu item'larda da çıkıyor.
- `SupabaseRestRepository.find_jobs_by_status()` (yeni): bu sweep tek
  çağıran, keyfi kullanıcıların job'larına bakması gerektiği için
  `service_role` key'i `access_token` olarak geçiyor (RLS'i bypass
  ediyor) — normal bir kullanıcı token'ıyla bu mümkün değil.
  `app/core/config.py`'daki `supabase_service_role_key` yorumu bunu
  yansıtacak şekilde güncellendi.
- `main.py`: FastAPI'nin deprecated `@app.on_event("startup")`'ı yerine
  `lifespan` context manager'ı kullanıldı — sweep bir istek işlenmeden
  önce çalışıyor, `SUPABASE_SERVICE_ROLE_KEY` yoksa (veya Supabase o an
  erişilemezse) sessizce atlanıyor, uygulamanın başlamasını hiç
  engellemiyor.
- **Bilinçli sınır**: "kendi başlangıcımda `processing` = orphaned"
  mantığı yalnızca **tek instance**'lı bir dağıtımda geçerli — birden
  fazla replika varsa biri restart olurken diğeri gerçekten hâlâ o job'ı
  işliyor olabilir. Bu proje şu an `docker-compose.yml` ile tek instance
  çalıştığı için kapsam dışı bırakıldı; çok-instance'lı bir dağıtım
  bunun yerine bir lease/lock mekanizması gerektirir.

**Mobile — `SyncService` polling**: `_scheduleNextPollIfNeeded()`, her
`syncNow()` sonunda imzalı kullanıcının `pending`/`processing` durumunda
hâlâ bir item'ı olup olmadığına bakıyor (`ItemLocalDataSource.
hasUnfinishedProcessing()`, yeni); varsa `pollInterval` sonra (varsayılan
5 saniye) `syncSoon()`'u tetikleyen bir `Timer` kuruyor, yoksa hiçbir şey
yapmıyor — sessiz bir kütüphane asla poll etmiyor. `maxPollAttempts`
(varsayılan 12, yani ~1 dakika) aşıldığında durup bekliyor; bu süre
notlar/URL'ler için saniyeler, PDF/görsel/ses için onlarca saniye süren
gerçek AI işleme sürelerinin fazlasıyla üstünde — o zamana kadar bitmemiş
bir job zaten backend restart'ında yukarıdaki sweep'in ele alacağı
"orphaned" bir job'dır, sonsuza kadar poll etmek pil tüketmekten başka
işe yaramaz. `SyncService.dispose()` (yeni) `syncServiceProvider`'ın
`ref.onDispose`'una bağlandı, kalan bir `Timer`'ı hiç yaşatmıyor.

**Bilinçli sınır**: bu gerçek bir Supabase Realtime kanalı değil, item
detayı açık olmasa (Home/Library'de) da çalışan bir polling — ama yine
de bir polling: madde 6'nın "Realtime/polling yok" boşluğunu dolduruyor,
ancak arka planda uygulama tamamen kapalıyken (process askıya alınmışken)
çalışmıyor — bir sonraki açılış zaten normal `syncSoon()` akışıyla
güncel durumu çekiyor.

Backend: `ruff check` temiz, testler 119 (bir önceki turdaki çalıştırma;
bu makinede macOS'un sistem Python'ıyla gelen `pyexpat` uyumsuzluğu
yüzünden `DYLD_LIBRARY_PATH=<homebrew expat>/lib` gerekiyor, aksi halde
`pypdf` import'unda collection hatası veriyor) → **122** test (+`test_job_recovery.py`,
2 test: hiçbir job asılı değilken no-op, birden fazla asılı job'ın
hepsinin doğru sırayla `failed`'e çekildiği). `main.py`'daki `lifespan`
geçişi hiçbir deprecation warning'i bırakmadı.

Mobile: `flutter analyze` temiz, 132 → **137** test (+3
`sync_service_test.dart`'ın yeni "AI status polling" grubu — hâlâ
`pending` iken tekrar tekrar sync ediyor ve `completed` olunca duruyor,
başlangıçtan itibaren her şey zaten bitmişken hiç poll etmiyor,
`maxPollAttempts`'ı aşınca asılı bir job'ı sonsuza kadar poll etmeyip
duruyor — üçü de gerçek zamanlayıcıyı beklemek zorunda kalmamak için
milisaniyelik bir `pollInterval` enjekte ediyor).

#### Faz 10b, madde 3: chunk/content replace idempotency ✅

`replace_chunks()`/`replace_item_content()` bağımsız bir DELETE'in
ardından bağımsız bir INSERT çalıştırıyordu — iki ayrı HTTP isteği, bir
transaction değil. Aynı item için eşzamanlı iki reprocessing çalışması
(örn. kullanıcı "Tekrar Dene"ye basarken önceki deneme hâlâ sürüyor)
birbirinin DELETE'inden sonra, hiçbiri INSERT'ini bitirmeden ikisi de
INSERT edebiliyordu — her chunk'ı ikiye katlıyordu; hiçbir constraint
bunu engellemiyordu.

- **`infra/supabase/migrations/0013_chunks_unique.sql`** (yeni):
  `chunks_item_id_chunk_index_key`, `(item_id, chunk_index)` üzerinde
  unique constraint — `0012_item_contents_unique.sql` ile aynı desen
  (önce dedup: her `(item_id, chunk_index)` çifti için en yeni
  `created_at`'i tutup gerisini siliyor).
- **`replace_chunks()`**: artık `on_conflict=item_id,chunk_index` +
  `Prefer: resolution=merge-duplicates` ile tek bir UPSERT — iki
  yarışan çalışma "her chunk_index için son yazan kazanır"a yakınsıyor,
  "ikisinin de satırı aynı anda var olması" hiç mümkün değil. Ardından
  gelen DELETE artık yalnızca **yeni chunk sayısının ötesindeki**
  index'leri kırpıyor (`chunk_index >= len(chunks)`) — kaç kere veya
  eşzamanlı çalışsa da güvenli, çünkü sadece satır siliyor, hiç
  yaratmıyor.
- **`replace_item_content()`**: `item_contents_item_id_key` (Faz 10a,
  madde 2'de eklenmişti) zaten tam bu upsert'e izin veriyordu —
  DELETE tamamen kaldırıldı, artık tek bir atomik PostgREST isteği.
- **Doğrulama**: bu makinede `SUPABASE_SERVICE_ROLE_KEY`/DB şifresi
  olmadığı için canlı projeye uygulanamadı (madde 2'deki gibi kullanıcı
  tarafında bir adım). Bunun yerine, projenin kendi
  `docker-compose.yml`'ının kullandığı `pgvector/pgvector:pg16`
  imajıyla geçici bir container'da gerçek `chunks` şeklini kurup iki
  satırlık bir "sahte duplicate" ekleyip migration'ı gerçekten
  çalıştırdım: dedup (2 satır → 1) ve constraint ekleme doğru çalıştı;
  ardından PostgREST'in üreteceği tam upsert+trim sorgu çiftini elle
  çalıştırıp doğru son duruma (yeni içerik, kırpılmış eski index)
  ulaştığını doğruladım.

**Bilinçli sınır**: bu, aynı item için iki reprocessing çalışmasının
"kim son söz sahibi olacak" yarışını çözmüyor (biri diğerinin trim'ini
ezebilir) — o yarış bu kod değişikliğinden önce de vardı ve denetim
raporunun bulduğu asıl kusur değildi. Çözülen, spesifik olarak
"duplicate satır oluşması" — artık constraint bunu yapısal olarak
imkansız kılıyor.

Backend: `ruff check` temiz, testler 122 → **125** test (yeni
`test_items_repository_idempotency.py` — pipeline seviyesindeki fake'ler
bu HTTP-seviyesi kusuru göremeyeceği için `httpx.MockTransport` ile
gerçek `SupabaseRestRepository`'nin attığı isteklerin DELETE+INSERT
değil UPSERT+kırpma olduğunu doğruluyor).

#### Faz 10b, madde 4: URL fetch'te SSRF koruması ✅

`fetch_and_extract()` kaydedilen bir linki hiçbir doğrulama yapmadan
doğrudan çekiyordu — backend'in kendi ağ erişimiyle kullanıcı tarafından
verilen bir URL'e istek atmak, klasik SSRF kurulumu (bir link internal
bir admin paneline, veritabanına, ya da çoğu cloud sağlayıcısında gerçek
credential döndüren metadata endpoint'ine (`169.254.169.254`)
işaret edebilir). Ayrıca `httpx`'in `follow_redirects=True`'sı hiçbir
redirect hedefini kontrol etmiyordu, response boyutu sınırsızdı,
content-type kontrolü yoktu.

- **`_ensure_safe_to_fetch()`** (yeni): scheme `http`/`https` değilse
  reddediyor; host'u çözüp (`_resolve_addresses`, DNS lookup'ı testlerin
  gerçek ağa çıkmadan sahte sonuç verebilmesi için ayrı bir fonksiyona
  çıkarıldı) her adresin `ipaddress.IPv*Address.is_global` olup
  olmadığına bakıyor — bu tek kontrol private (RFC 1918), loopback,
  link-local (metadata adresi dahil), multicast, reserved ve unspecified
  aralıklarının hepsini aynı anda dışlıyor.
- **Redirect'ler artık manuel takip ediliyor** (`follow_redirects=False`
  + döngü, en fazla `_MAX_REDIRECTS=5` adım): her hop, istek gerçekten
  atılmadan önce yukarıdaki kontrolden geçiyor — public görünen bir
  URL'in 302 ile internal bir adrese yönlendirmesi de yakalanıyor.
- **Boyut sınırı**: `_MAX_RESPONSE_BYTES` (5 MB) aşılırsa stream
  kesiliyor — kötü niyetli/bozuk bir sunucunun sınırsız veri
  akıtmasına karşı.
- **Content-type kontrolü**: `text/html` içermeyen bir yanıt (örn. bir
  PDF veya binary dosya) reddediliyor — zaten çıkarılacak bir şey yok,
  metin gibi işlemeye çalışmak anlamsız/riskli.
- **Bilinçli sınır**: bu, host'u bir kere çözüp sonra `httpx`'in
  bağlanmak için tekrar (bağımsız) çözmesine güveniyor — bu iki lookup
  arasında cevabı değiştiren bir DNS-rebinding saldırganı hâlâ
  sızabilir. Bunu tam kapatmak, bu kontrolün zaten çözdüğü IP'ye
  bağlanan (pinleyen) özel bir transport gerektirir — aşağıdaki
  URL/redirect/boyut/content-type kontrollerinden daha büyük bir
  değişiklik, burada yapılmadı, roadmap'te açık bir boşluk olarak not
  edildi.

Backend: `ruff check` temiz, testler 125 → **140** (yeni
`test_url_service_ssrf.py`, 15 test — non-public adresler/scheme'ler
reddediliyor, internal adrese giden bir redirect yakalanıyor, boyut
sınırı ve content-type kontrolü çalışıyor, gerçek bir HTML yanıtı hâlâ
doğru çıkarılıyor, redirect döngüsünde teslim oluyor — hepsi gerçek
DNS/ağ erişimi olmadan: literal IP'ler zaten ağa çıkmadan çözülüyor,
sembolik `public.example.com` host'u testlerde sahte bir sonuca
bağlanıyor).

### Faz 10c — İçerik kapsamı

#### Faz 10c, madde 1: Genel belge desteği (DOCX/TXT) ✅

`ItemType.document` mobil tarafta (renk/ikon/etiket — "Belge",
`Icons.description_outlined`) ve `items` tablosunun `type` check
constraint'inde zaten vardı, ama hiçbir yerden ona ulaşılamıyordu:
"Upload Document" yalnızca `.pdf` seçtiriyordu ve seçileni her zaman
`ItemType.pdf` olarak yüklüyordu; backend'in `SUPPORTED_TYPES`'ında
`document` yoktu, yani biri elle `type: "document"` bir item
oluştursa bile pipeline onu `UnsupportedItemType` ile `failed`'e
çekerdi.

- **`document_service.extract_document_text()`** (yeni): `mime_type`'a
  (yoksa dosya adının uzantısına — bir picker tanımadığı bir uzantı
  için `application/octet-stream` döndürebiliyor) göre `.txt`'yi
  doğrudan decode ediyor, `.docx`'i **`python-docx`/`lxml` bağımlılığı
  eklemeden**, salt standart kütüphaneyle (`zipfile` + `ElementTree`)
  ayrıştırıyor — bir `.docx` zaten bir zip arşivi, gövdesi
  `word/document.xml`'de WordprocessingML; ihtiyaç olan tek şey
  paragrafları gezip her birinin metin run'larını birleştirmek.
  Tanınmayan bir tür (örn. `.xlsx`) veya bozuk bir `.docx` açık bir
  `ValueError` ile reddediliyor — pipeline'ın var olan genel
  `except Exception`'ı bunu diğer her tür-doğrulama hatası gibi
  `failed`'e çeviriyor.
- **`processing_pipeline.py`**: `SUPPORTED_TYPES`'a `"document"`
  eklendi; yeni bir `elif item_type == "document"` dalı dosyayı indirip
  yukarıdaki fonksiyona veriyor — PDF/görsel/ses dallarıyla aynı
  "storage_path yoksa açık hata" deseninde.
- **Mobile — `capture_sheet.dart`**: "Upload Document" artık
  `pdf`/`docx`/`txt` seçtiriyor; seçilen dosyanın türü artık picker
  çağrılmadan önce sabitlenmiş bir `ItemType` değil, seçilen dosyanın
  uzantısından (`_documentItemTypeFor`) sonradan belirleniyor — `.pdf`
  hâlâ `ItemType.pdf` (var olan detay ekranı/ikon davranışını
  koruyor), diğerleri `ItemType.document`. `_guessMimeType`'a
  `docx`/`txt` eklendi; ikon artık genel `Icons.description_outlined`
  (yalnız PDF değil, genel bir belge).
- **Mobile — `SyncService._aiSupportedUploadTypes`**: `'document'`
  eklendi — yoksa bir belge yüklendikten sonra AI pipeline hiç
  tetiklenmezdi (upload'un kendisi başarılı olur, ama işleme hiç
  başlamazdı).

**Bilinçli sınır**: yalnızca `.pdf`/`.docx`/`.txt` — DOC (eski
binary Word formatı), ODT, RTF gibi diğer ofis formatları kapsam
dışı; denetim raporu özellikle "DOCX/TXT" diyordu, daha fazlası
istenmedi.

Backend: `ruff check` temiz, testler 140 → **151** (yeni
`test_document_service.py` testleri — `.txt`'yi mime_type'a/uzantıya
göre okuyor, gerçek bir sahte `.docx` zip'ini ayrıştırıp paragrafları
birleştiriyor, boş paragrafları atlıyor, bozuk bir `.docx`'i ve
tanınmayan bir türü reddediyor; yeni `test_processing_pipeline.py`
testleri — bir `.txt` item'ı uçtan uca işliyor, storage_path'siz ve
tanınmayan document type'lı item'lar açıkça `failed` oluyor). Mobile:
`flutter analyze` temiz, 135 test hâlâ geçiyor (bu değişiklik yeni bir
mobil test eklemedi — `FilePicker`'ın kendisi bir platform kanalı
olduğu için, kod tabanının başka hiçbir capture akışının da yapmadığı
gibi, bunu mock'lamak için yeni bir test altyapısı kurmak bu
düzeltmenin kapsamının dışında tutuldu; `flutter analyze`'ın
`_documentItemTypeFor`/`_guessMimeType` üzerindeki tip kontrolü ve
mevcut 135 testin hâlâ geçmesi tek doğrulama).

#### Faz 10c, madde 2: doğal dil tarih filtreleri artık takvim aralığı ✅

`query_parser.py` her "geçen X"/"bu X" ifadesi için yalnızca bir alt
sınır (`date_from`) üretiyordu, hiç üst sınır (`date_to`) yoktu. İki
farklı sorun buradan çıkıyordu: "geçen ay" takvim ayı yerine
`today - timedelta(days=30)` (kayan 30 gün) olarak hesaplanıyordu —
31 günlük bir ay için yanlış, Şubat gibi 28 günlük bir ay için daha da
yanlış; "dün" ise üst sınırı olmadığı için gerçekte "dünden itibaren
her şey" anlamına geliyordu, bugünü de kapsayarak.

- **`_date_range_for_phrase()`** (yeniden yazıldı — eski adı
  `_date_from_phrase`, tek bir `datetime` döndürüyordu): artık her ifade
  için `(date_from, date_to)` çifti döndürüyor. "bu X" ifadeleri (bu
  hafta/ay/yıl) hâlâ üst sınırsız — henüz sürüyorlar, gelecekte
  tarihli bir item olamayacağı için buna gerek yok. "geçen X" ifadeleri
  artık **kapalı** bir aralık: "geçen ay" gerçek önceki takvim ayının
  1'inden son gününe (`_last_instant_before` ile bir sonraki ayın
  başından bir mikrosaniye öncesine — hybrid RPC'nin
  `created_at <= filter_before` karşılaştırması dahil olduğu için, tam
  gece yarısı sınırında yanlışlıkla bir sonraki döneme sızmaması için),
  "dün" tam olarak dünün 00:00:00.000000'ından 23:59:59.999999'una,
  "geçen hafta"/"geçen yıl" de aynı desende kapalı aralıklara çekildi.
- **`ParsedQuery`**'e `date_to` alanı eklendi.
- **`api/search/routes.py`**: `date_to = body.date_to or parsed.date_to`
  eklendi — önceden her zaman `body.date_to` kullanılıyordu, yani
  istemci kendi `date_to`'sunu göndermediğinde parser'ın ürettiği üst
  sınır sessizce atılıyordu (bu satır olmadan, `date_from` düzeltmesi
  tek başına "dün"ü hâlâ bugüne kadar açık bırakırdı).

Backend: `ruff check` temiz, testler 151 → **157** (yeniden yazılan
`test_query_parser.py` — "geçen ay"ın gerçek takvim ayı olduğunu hem
31 günlük hem 28 günlük bir ayla hem de yıl sınırını aşan bir örnekle
doğruluyor, "dün"ün `date_to`'sunun kesinlikle bugünden önce kaldığını
doğruluyor, "bu X" ifadelerinin hâlâ üst sınırsız olduğunu, "geçen
hafta"/"geçen yıl"ın da kapalı aralık olduğunu doğruluyor).

**O zaman kapsam dışı bırakılan** (sonradan eklendi): mobilde özel
tarih aralığı seçimi — denetim raporunun bu maddesi özellikle NLP
parser'ın takvim matematiğiydi, mobil UI değil. Kullanıcı bunu da
istedi, bkz. Faz 11, madde 1.

#### Faz 10c, madde 3: taranmış PDF için OCR fallback ✅

`extract_pdf_text()` yalnızca PDF'in gerçek metin katmanını okuyordu
(`pypdf`); taranmış/görüntü tabanlı bir PDF'te (fotoğraflanmış sayfalar,
eski bir tarayıcı çıktısı) bu katman yok ya da boş — pipeline
`normalize_text(raw_text)` boş çıkınca "No extractable text found"
diyerek item'ı doğrudan `failed`'e çekiyordu. Görsellerin zaten aldığı
OCR (vision modelinin `ocr_text` çıktısı) hiç devreye girmiyordu.

- **`document_service.render_pdf_pages_to_images()`** (yeni):
  `pymupdf` (yeni bağımlılık — kendi MuPDF'ini içinde taşıyor, poppler
  gibi bir sistem paketi gerektirmiyor) ile her sayfayı bir PNG'ye
  rasterize ediyor. `max_pages` parametresiyle sınırlanıyor.
- **`processing_pipeline.py`**: PDF dalı, `extract_pdf_text()` boş
  dönerse (`raw_text.strip()` boşsa) artık `_ocr_scanned_pdf()`'i
  çağırıyor — her sayfayı yukarıdaki fonksiyonla görsele çevirip,
  görsellerin zaten aldığı `vision_service.analyze_image()` çağrısına
  veriyor, yalnızca `ocr_text`'i tutuyor (`title`/`description`/`tags`
  bir taranmış sayfa için anlamsız, atılıyor). En fazla
  `_MAX_OCR_PDF_PAGES = 30` sayfa OCR ediliyor — sınırsız sayfalı bir
  taramanın sınırsız (ücretli) vision çağrısı tetiklemesine karşı.
- Metin katmanı **olan** bir PDF için bu dal hiç çalışmıyor — OCR
  yalnızca gerçekten boş çıktığında tetikleniyor, her PDF için ekstra
  bir vision çağrısı yapılmıyor.

**Bilinçli sınırlar**:
- Sayfa başına bir vision çağrısı — görsellerin aldığı aynı çağrı
  yeniden kullanıldığı için `title`/`description`/`tags` de üretiliyor
  ama kullanılmıyor; OCR'a özel, daha ucuz bir provider çağrısı ayrı
  bir `AIProvider` arayüz değişikliği gerektirirdi, burada yapılmadı.
- 30 sayfa sınırı: daha büyük bir taramanın yalnızca ilk 30 sayfası
  OCR ediliyor, geri kalanı sessizce atlanıyor (ne bir uyarı ne bir
  kesme mesajı) — denetim raporu "OCR fallback yok" diyordu, "her
  büyüklükte tarama için sınırsız OCR" istenmedi.

**Doğrulama ortamı notu**: bu makinenin lokal Python kurulumunda
(`platform.mac_ver()`'ın macOS 26.2'de boş döndüğü bir pip/Python
uyumsuzluğu — Faz 10c madde 1'deki `python-docx` kurulum denemesiyle
aynı kök sorun) `pip install pymupdf` normal şekilde çalışmadı; asıl
doğrulama projenin kendi `Dockerfile`'ının temel imajıyla
(`python:3.12-slim`) geçici bir container'da yapıldı — gerçek pip
kurulumu, gerçek `ruff check`, gerçek `pytest`, hiçbiri workaround
gerektirmeden. Bu, gerçek dağıtım ortamını (Docker) zaten kullandığı
için lokal makine kusurundan tamamen bağımsız bir doğrulama. Ayrıca bu
makinenin `.venv`'ine de (pip'in kendisini değil, indirilen wheel'i
doğrudan `site-packages`'a açarak) pymupdf kuruldu — bundan sonraki
lokal `pytest` çalıştırmaları da bu değişikliği kapsıyor.

Backend: `ruff check` temiz (Docker'da ve lokalde), testler 157 →
**162** (Docker'da ve lokalde iki ortamda da doğrulandı — yeni
`test_document_service.py` testleri: `render_pdf_pages_to_images()`
sayfa sayısı kadar PNG döndürüyor, `max_pages`'e uyuyor; yeni
`test_processing_pipeline.py` testleri: gerçek metin katmanı olan bir
PDF OCR'ı hiç tetiklemiyor — sabit OCR metni sonuçta hiç görünmüyor —,
metin katmanı olmayan 2 sayfalık bir PDF'in iki sayfası da OCR
ediliyor).

Doğrulanmayan ama dosya/satır referanslı, inandırıcı bulunan diğer
maddeler (öncelik sırasıyla, denetim raporundan):

4. ~~Hesap silme: dosyalar `service_role` key kontrolünden önce
   siliniyordu~~ ✅ düzeltildi — bkz. yukarıdaki alt bölüm.
5. ~~`configure_logging(debug=True)` root logger'ı DEBUG'a çekiyor;
   kurulu OpenAI SDK'sı bu seviyede istek gövdesini (prompt/embedding
   girdisi) loglayabiliyor~~ ✅ düzeltildi — bkz. yukarıdaki alt bölüm
   (Faz 10a, madde 5).
6. ~~AI job tetikleme hatası tamamen yutuluyor, kalıcı retry/kullanıcıya
   "Tekrar Dene" yok; backend `BackgroundTasks` restart sonrası job
   kurtarmıyor; mobilde işleme sonucu için Realtime/polling yok~~ ✅
   üçü de düzeltildi — bkz. yukarıdaki iki alt bölüm (Faz 10b, madde 1 ve
   madde 2).
7. ~~"Geçen ay" takvim ayı yerine "son 30 gün" olarak yorumlanıyor;
   "dün" bitiş sınırı yok, bugünü de kapsıyor~~ ✅ düzeltildi — bkz.
   yukarıdaki alt bölüm.
8. ~~`replace_chunks`/`replace_item_content` bağımsız DELETE+INSERT —
   aynı item için eşzamanlı iki job iki kez INSERT yapabilir~~ ✅
   düzeltildi — bkz. yukarıdaki alt bölüm.
9. ~~URL fetch'te SSRF koruması yok (private IP/localhost/redirect
   hedefi doğrulaması, boyut sınırı)~~ ✅ düzeltildi — bkz. yukarıdaki
   alt bölüm.
10. ~~Genel belge (DOCX/TXT) desteği yok, `document` tipi backend
    `SUPPORTED_TYPES`'ta değil; taranmış (metin katmanı olmayan) PDF'te
    OCR fallback yok, `extract_pdf_text` metinsiz kalırsa hata
    veriyor~~ ✅ ikisi de düzeltildi — bkz. yukarıdaki iki alt bölüm
    (Faz 10c, madde 1 ve madde 3).
11. ~~Android ana `AndroidManifest.xml`'de `INTERNET` izni yoktu~~ ✅
    düzeltildi — bkz. aşağıdaki alt bölüm.

**Önerilen sıra** (denetim raporundan, projenin kendi faz mantığıyla
uyumlu hale getirildi):

1. **Faz 10a (P0 — MVP'yi bloke eden)** — tamamlandı ✅: ~~hesap
   izolasyonu (sync queue + recent searches, her okuma/yazma imzalı
   kullanıcıya göre filtreleniyor)~~, ~~`item_contents` UNIQUE
   migration'ı~~, ~~search/RAG/related'tan tam item açma~~, ~~hesap
   silme sırası~~, ~~debug log seviyesi~~, ~~Android INTERNET izni~~
   (madde 11'de). **Küçük, çözülmemiş bir nüans**: bu izolasyon filtreleme
   ile sağlandı, "logout'ta local DB'yi temizleme" ile değil — A
   hesabından çıkıldığında A'nın satırları hâlâ cihazın local
   sqlite dosyasında duruyor, sadece B oturumu açıkken artık hiç
   okunmuyor/gösterilmiyor/gönderilmiyor. Fonksiyonel izolasyon için
   yeterli; cihaza fiziksel erişimi olan biri için "veri hâlâ diskte"
   kalıyor.
2. **Faz 10b (P1 — güvenilirlik)** — tamamlandı ✅: ~~AI job retry +
   kullanıcıya "Tekrar Dene"~~, ~~realtime/polling ile otomatik mobil
   güncelleme~~, ~~backend job restart-kurtarma~~, ~~chunk/content
   replace idempotency~~, ~~URL fetch SSRF koruması~~, ~~Android
   INTERNET izni~~ (madde 11'de).
3. **Faz 10c (içerik kapsamı)** — tamamlandı ✅: ~~genel belge
   desteği~~, ~~doğal dil tarih filtrelerinin takvim aralığına
   düzeltilmesi~~, ~~taranmış PDF için OCR fallback~~.
4. **Doğrulama**: gerçek OpenAI + `service_role` key'leriyle, iki ayrı
   hesabı da içeren izole bir ortamda dokümanın 66. bölümündeki MVP
   senaryosunu uçtan uca çalıştırmak — yalnızca o zaman "MVP tamamlandı"
   denebilir.

Google/Apple login, Gemini/local provider, masaüstü/web, tam offline
semantic search, analytics ekranı, item-bazlı Privacy Mode — doküman
zaten bunları "ileri aşama" sayıyor; Faz 10'un kapsamı dışında.

### Faz 11 — İleri aşama özellikleri ✅ (6c'nin Windows/Linux kısmı hariç, bkz. madde 6c)

Faz 10'da bilinçli olarak kapsam dışı bırakılan maddeler — kullanıcı
bunları da eklemek istedi. Büyüklükleri çok farklı (bazıları yarım
günlük mobil özellikler, bazıları haftalarca sürebilecek altyapı
işleri, bazıları Google/Apple/Supabase'de harici kurulum gerektiriyor);
en küçükten en büyüğe doğru sırayla ele alınıyor:

1. ~~Mobilde özel tarih aralığı seçimi~~ ✅ — bkz. aşağıdaki alt bölüm.
2. ~~Item-bazlı Privacy Mode~~ ✅ — bkz. aşağıdaki alt bölüm.
3. ~~Analytics ekranı~~ ✅ — bkz. aşağıdaki alt bölüm.
4. ~~Gemini AI provider~~ ✅ — bkz. aşağıdaki alt bölüm. "local"
   sağlayıcı madde 6'ya bırakıldı (aynı yerel çıkarım altyapısı).
5. ~~Google/Apple login~~ ✅ (kod) — bkz. aşağıdaki alt bölüm. Kurulum
   (Google Cloud Console + Apple Developer + Supabase Dashboard) hâlâ
   kullanıcıda, bkz. `docs/google-apple-login-setup.md`.
6. Tam offline semantic search + local AI provider + masaüstü/web
   istemci (en büyük, en riskli üçü — en sona bırakıldı, kullanıcı
   isteğiyle üçe bölündü, en küçüğünden başlanıyor):
   - a. ~~Local AI provider (backend)~~ ✅ — bkz. aşağıdaki alt bölüm.
   - b. ~~Tam offline semantic search (mobil)~~ ✅ — bkz. aşağıdaki alt
     bölüm.
   - c. ~~Masaüstü/web istemci~~ ✅ (web + macOS) — bkz. aşağıdaki alt
     bölüm. Windows/Linux eklenmedi (bkz. alt bölümdeki gerekçe).

#### Faz 11, madde 1: mobilde özel tarih aralığı seçimi ✅

Search sekmesinin tarih filtresi yalnızca üç sabit preset sunuyordu
(Her zaman/Bugün/Geçen hafta/Geçen ay); kullanıcının kendi başlangıç/
bitiş tarihini seçmesi yoktu — `SearchFilters`'ta `dateTo` alanı da
hiç yoktu, tek bir alt sınır (`dateFrom`) taşıyordu.

- **`SearchFilters`**'a `dateTo` eklendi (freezed, `build_runner`
  yeniden çalıştırıldı).
- **`ApiSearchRepository`**: `date_to` artık backend'in `/search/`
  isteğine ekleniyor — backend zaten `date_to`'yu kabul ediyordu
  (Faz 10c, madde 2), mobil taraf hiç göndermiyordu.
- **`LocalSearchDataSource`**: offline keyword fallback'e de
  `dateTo` (`isSmallerOrEqualValue`) eklendi — online/offline aynı
  filtre semantiğini paylaşıyor.
- **`SearchTab`**: tarih preset menüsüne "Özel aralık…" eklendi —
  seçilince Flutter'ın kendi `showDateRangePicker()`'ı açılıyor.
  Seçilen aralık, bitiş gününün tamamını kapsayacak şekilde
  (`23:59:59.999999`'a kadar) `dateTo`'ya çevriliyor — "20'sine kadar"
  seçildiğinde 20'sinin 23:59'unda oluşturulmuş bir şeyin de dışarıda
  kalmaması için (backend'in kendi "geçen X" mantığıyla aynı
  gerekçe, bkz. query_parser.py). Kullanıcı picker'ı iptal ederse
  (`showDateRangePicker` `null` döner) önceki seçim aynen kalıyor —
  hiçbir şey sıfırlanmıyor. Chip artık seçili özel aralığı
  ("1 Eyl - 5 Eyl" gibi) kendi etiketi yerine gösteriyor.
- **Gerçek bir hata bulundu ve düzeltildi**: `DateTime`'ın 7.
  pozisyonel argümanı `millisecond`, `microsecond` değil —
  `DateTime(y, m, d, 23, 59, 59, 999999)` yazmak "999999 milisaniye"
  (≈16.7 dakika) ekleyip gece yarısını aşıp bir sonraki güne
  taşıyordu, tam olarak önlenmek istenen şeyi yeniden yaratıyordu.
  Doğrusu iki ayrı argüman: `DateTime(y, m, d, 23, 59, 59, 999, 999)`.
  Bunu bir widget testi (gerçek `showDateRangePicker` takvim
  grid'iyle etkileşime giren, mock'lanmamış bir test) yakaladı —
  yalnızca seviyeyi değil gerçek son tarihi doğruladığı için.

Mobile: `flutter analyze` temiz, 135 → **137** test (+2: özel aralık
seçiminin her iki ucu da doğru filtre olarak uyguladığını — gerçek
takvim grid'inde iki güne dokunup "Save"e basarak — ve picker iptal
edilirse önceki seçimin değişmediğini doğruluyor).

#### Faz 11, madde 2: item-bazlı Privacy Mode ✅

Yalnızca biyometrik/PIN'le tüm uygulamayı kilitleyen bir "Privacy"
switch'i vardı (Settings) — tek bir hassas içeriği tüm uygulamayı
kilitlemeye gerek kalmadan gizli tutmanın bir yolu yoktu.

- **Şema**: `items.private` (yeni migration
  `0014_item_private.sql`) ve `LocalItems.private` (Drift şeması
  v7→v8) — `favorite` ile birebir aynı desen. **RLS bu sütuna göre
  hiçbir şey filtrelemiyor**; bu bilinçli bir tercih (aşağıdaki
  "Bilinçli sınır"a bkz.).
- **`ItemDetailScreen`**: kilit ikonlu bir aksiyon — işaretlemek/
  kaldırmak biyometrik onay istemiyor (kendi item'ını favorilemekle
  aynı güven seviyesi); yalnızca zaten private olanları **görmek**
  onay istiyor.
- **`item_providers.dart`**: `itemsProvider` (Home + Library'nin
  paylaştığı tek kaynak) artık `privateItemsRevealedProvider` `false`
  iken `private` item'ları listeden çıkarıyor — iki ekran da tek bir
  yerden "bedavaya" doğru davranışı alıyor.
- **`LibraryScreen`**: kilit/kilit-açık ikonlu bir "reveal" düğmesi —
  basılınca `AppLockService.authenticate()` (mevcut whole-app-lock
  altyapısı, `Settings`'in "Privacy" switch'inin zaten kullandığı)
  çağrılıyor; başarılıysa private item'lar o oturum için görünür
  oluyor. Gizlemek hiç onay istemiyor. `AppLockGate`'in arka plana
  alma dinleyicisi artık bunu da sıfırlıyor — whole-app-lock kapalı
  olsa bile, uygulama arka plana alınınca private item'lar tekrar
  gizleniyor.
- **`SearchController`/`relatedItemsProvider`**: bir `SearchResult`
  yalnızca id/snippet taşıyor, kendi `.private`'ına bakamıyor — local
  cache'teki gerçek `Item` listesiyle çapraz kontrol ediliyor.

**İki gerçek hata bulundu ve düzeltildi** (ikisi de bu turda eklenen
widget testleriyle yakalandı, spekülasyonla değil):
1. İlk tasarım `ref.read(...).valueOrNull` ile senkron okuyordu —
   oturumun ilk aramasında, alttaki stream henüz hiç yayın
   yapmamışken bu `null` dönüyor, yani private bir item'ın sonucu
   filtrelenmeden sızabiliyordu. Düzeltme: `allItemsIncludingPrivateProvider.future`'ı
   `await` etmek — ilk gerçek yayını bekliyor, anlık/boş bir
   snapshot okumuyor.
2. O `await` eklendikten sonra, provider'ın kendisi hata durumuna
   düşerse (örn. imzalı kullanıcı yok) `.future` bu hatayı fırlatıyor
   — `.valueOrNull`'ın sessizce yuttuğunun aksine — bu da tüm aramayı
   başarısız gösteriyordu. Düzeltme: `try/catch` ile, kontrol edilecek
   bir şey yokken tüm aramayı düşürmek yerine sonuçları filtrelenmemiş
   döndürmek.

**Bilinçli sınır** (kapsamlı, açıkça belgelendi): `private` yalnızca
istemci tarafında uygulanıyor — RLS hâlâ her satırı yalnızca sahibine
göre kısıtlıyor, öncekiyle aynı. Backend'in `private` diye bir kavramı
yok, yani:
- **Ask AI (RAG)** bir private item'ın içeriğinden hâlâ alıntı
  yapabilir/cevaba dahil edebilir.
- **Smart Collection önerileri** ve **duplicate-detection banner'ı**
  hâlâ private item'lara referans verebilir.
- Bir item'ın id'sini zaten bilen (örn. eski bir deep link) doğrudan
  `/item/:id`'ye gidip detay ekranını açabilir — Library/Home/Search
  filtrelese de, `ItemByIdLoader`/deep link rotası bu kontrolü
  yapmıyor.

Bunların hepsini kapatmak, backend'in her retrieval RPC'sinin
(hybrid_search, find_related, find_duplicate_candidate, collection
suggestions) `private`'ı bilmesini ve filtrelemesini gerektirir —
burada yapılmadı, gerçek bir sunucu-taraflı erişim kontrolü değil,
"rastgele göz atmadan gizleme" seviyesinde bir özellik olarak
belgelendi.

Backend: yalnızca migration (`0014_item_private.sql`), kod
değişikliği yok. Mobile: `flutter analyze` temiz, testler 137 →
**144** (+7: `LibraryScreen`'de private item'ların varsayılan
gizlendiğini/reveal ile göründüğünü, başarısız kimlik doğrulamanın
gizli tuttuğunu, cihaz desteklemediğinde hata gösterdiğini — 3 test;
item detay ekranında private işaretleme/kaldırmanın onay istemediğini
— 1 test; `SyncService`'te `set_private` push'unu ve pull'da
`private` alanının doğru taşındığını — 2 test; Search'te bir private
item'ın kendi sonucunun gizlenip diğerlerinin kaldığını — 1 test —
doğruluyor).

#### Faz 11, madde 3: Analytics ekranı ✅

Home'da tür başına sayaçlar vardı ("Images: 3" gibi) ama ayrı, arşivi
bütün olarak gösteren bir Analytics ekranı, zaman içindeki büyüme ve
en yaygın etiketler yoktu.

- **`analytics.dart`** (yeni, `mobile/lib/features/analytics/domain/`):
  saf fonksiyonlar — `totalItemCount`/`favoriteCount`/`privateCount`,
  `countsByType`, `itemsPerMonth` (son N ay, boş aylar da sıfırla
  dolduruluyor — bir bar grafiğinin "veri yok" ile "sorulmadı"
  arasında tahmin yapmasına gerek kalmıyor), `topTags` (bir tag
  isim listesini frekansa göre sayıp sıralıyor).
- **Veri kaynağı**: her şey zaten local cache'te (`itemsProvider`) —
  ayrı bir backend endpoint'i yok, uygulamanın her yerindeki
  offline-first sözleşmesiyle aynı. Tek istisna **en yaygın
  etiketler**: tag'ler local'de cache'lenmiyor (`fetchTags`'in kendi
  belgesindeki "bağlantı gerekiyor" sözleşmesi), o yüzden yeni
  `RemoteItemDataSource.fetchAllTagNames()` tüm arşivin (item, tag)
  eşleşmelerini **tek bir istekte** çekiyor — `item_tags_owner` RLS
  politikası zaten `item_id` filtresi olmadan da yalnızca çağıranın
  kendi satırlarını döndürüyor; frekans sayımı istemci tarafında.
- **Ekran**: toplam/favori/depolama stat kutucukları, türe göre
  azalan sıralı bar listesi (mevcut `itemTypeColor`/`itemTypeIcon`/
  `itemTypeLabel` ile — Library/Home/arama sonuçlarının zaten
  kullandığı sabit, hiç döngüye girmeyen renk eşlemesi; her barın
  kendi ikon+etiketi zaten "direct label", ayrı bir legend'a gerek
  yok), son 6 ayın item sayısı için tek renkli (marka rengi) aylık
  bar grafiği, en yaygın etiketler için sayılı chip'ler. Settings'e
  yeni bir "Analytics" satırı (`/analytics`) eklendi.
- **item-bazlı Privacy Mode ile entegrasyon**: ekranın geri kalanı
  `itemsProvider`'ı (zaten private item'ları filtreleyen) kullandığı
  için hiçbir ekstra iş yapmadan private item'lar hiçbir sayıma
  girmiyor. "Private: N" stat kutucuğu yalnızca
  `privateItemsRevealedProvider` `true` iken (aynı reveal kapısından
  geçilmişse) görünüyor — `itemsProvider`'ın zaten filtrelediği
  listeyi saymak hep sıfır verirdi, bu yüzden bu tek sayı özellikle
  filtrelenmemiş ham stream'den okunuyor.

Backend: yalnızca yeni bir salt-okunur sorgu (`fetchAllTagNames`),
şema/migration değişikliği yok. Mobile: `flutter analyze` temiz,
testler 144 → **163** (+19: `analytics.dart`'ın saf fonksiyonları için
11 test — ay bucket'larının yıl sınırını doğru geçtiği, `topTags`'in
doğru sıraladığı dahil; `AnalyticsScreen` için 7 widget testi — boş
arşiv/tür dağılımı/private item'ın varsayılan hiçbir sayıma
girmeyip reveal'da hepsine dahil olması/etiket listesi; Settings'in
yeni "Analytics" satırının doğru sayfaya gittiğini doğrulayan 1
test). Bu turda `Analytics` satırı eklenince Settings'in düz
`ListView(children:)`'ı bir tık uzayıp "Privacy" switch'ini varsayılan
test viewport'unun art alan (cache extent) dışına itti — iki mevcut
Privacy testi bunun için scroll etmiyordu, gerçek bir regresyon olarak
yakalandı ve komşu testlerin zaten kullandığı aynı `drag` deseniyle
düzeltildi.

#### Faz 11, madde 4: Gemini AI provider ✅

`AIProvider` arayüzü zaten "bir sağlayıcıdan diğerine geçmek bir alt
sınıf eklemek demek" diyordu ama `get_ai_provider()`'ın `gemini` dalı
`NotImplementedError` fırlatıyordu.

- **`GeminiProvider`** (yeni, `google-genai` — Google'ın güncel
  birleşik SDK'sı; eski `google-generativeai` paketi artık bakım
  modunda): `generate_text`/`generate_embedding(s)`/`analyze_image`/
  `transcribe_audio`'nun hepsi `OpenAIProvider`'ın attığı JSON şemasıyla
  aynı sözleşmeyi uyguluyor — pipeline hangi sağlayıcıyı kullandığını
  hiç bilmiyor. `transcribe_audio` Whisper gibi ayrı bir ASR endpoint'i
  yerine Gemini'nin ses girdisini doğrudan multimodal bir parça olarak
  alıp transkript isteyen genel `generate_content` çağrısını kullanıyor.
- **Gerçek bir boyut uyuşmazlığı, çözümü ve kanıtı**: `text-embedding-004`
  768 boyutlu vektör üretiyor, ama `chunks.embedding` (OpenAI'nin
  `text-embedding-3-small`'ı için) sabit `vector(1536)` — şema
  değişikliği olmadan bunu düzeltmenin yolu her embedding'i 1536'ya
  sıfırla doldurmak (`_pad_embedding`). Bu rastgele bir "işe yarıyor
  gibi görünüyor" hilesi değil: iki vektöre aynı uzunlukta sıfır kuyruğu
  eklemek ne iç çarpımı ne de normları değiştirdiği için cosine
  similarity **matematiksel olarak tam olarak** değişmiyor — testlerden
  biri tam bu özelliği (rastgele iki vektörün cosine'ının
  pad'lemeden önce/sonra birebir aynı kaldığını) doğruluyor, sadece
  "uzunluk doğru" demiyor. **Bu, farklı sağlayıcıların embedding
  uzaylarını karşılaştırılabilir yapmıyor** — `AI_PROVIDER`'ı canlı
  bir arşivde değiştirmek hâlâ elle tam bir re-embed gerektiriyor,
  bunun için bir migration yok; docstring'de açıkça uyarılıyor.
- **Gerçek bir bağımlılık çakışması bulundu ve çözüldü**:
  `google-genai==2.23.0` `pydantic>=2.12.5` istiyor, ama
  `requirements.txt` `pydantic==2.10.4`'e sabitlenmişti — Docker'da
  `pip install`'ın kendisi bunu `ResolutionImpossible` ile net şekilde
  gösterdi. `fastapi`/`pydantic-settings`/`openai`'ın hiçbiri gerçekte
  `<3.0`'dan daha katı bir üst sınır istemiyordu, yani bu sabitlemeyi
  bu kadar aşağıda tutan tek gerçek kısıt buydu — `pydantic` `2.12.5`'e
  yükseltildi, `pydantic-core`'un eşleşen sürümü (`2.41.5` — `2.12.5`
  başka bir sürümle çalışmayı reddediyor, kendi kontrolü var) hem
  Docker'da hem bu makinenin `.venv`'inde ayrıca doğrulandı.
- **"local" sağlayıcı bu maddeye dahil edilmedi**: gerçek bir yerel
  çıkarım motoru gerektiriyor, o yüzden bilinçli olarak Faz 11 madde
  6'ya bırakıldı; `get_ai_provider()`'ın `local` dalı hâlâ
  `NotImplementedError` fırlatıyor. (Sonradan madde 6, kullanıcı
  isteğiyle üçe bölündü — local provider tek başına madde 6a oldu,
  bkz. aşağıdaki alt bölüm; "offline semantic search"le paylaşılan tek
  şey Ollama'nın kurulu olması, kod tarafında bağımlılık yok.)

**Doğrulama ortamı notu**: yerel `.venv`'e kurulum, önceki turlardaki
gibi (`pymupdf`) aynı `platform.mac_ver()` uyumsuzluğu yüzünden normal
`pip install` ile çalışmadı; wheel'ler indirilip doğrudan
`site-packages`'a açıldı — bu kez `pydantic-core`'un pydantic'in
istediğinden farklı bir sürümü otomatik çekilince gerçek bir
`SystemError` ile karşılaşıldı ve doğru sürüm elle indirilip
düzeltildi. Asıl doğrulama, gerçek bir `pip install -r requirements.txt`
çalıştıran temiz bir Docker container'ında yapıldı.

Backend: `ruff check` temiz (Docker'da ve lokalde), testler 168 →
**174** (+6: `Settings`'e göre Gemini'nin seçildiğini/key olmadan
açık bir hata verdiğini, "local"ın hâlâ `NotImplementedError`
fırlattığını doğrulayan provider-seçim testleri; `_pad_embedding`
için 4 test — kısa bir embedding'i sıfırla doldurma, doğru uzunluğu
değiştirmeme, savunmacı kırpma, ve cosine similarity'nin pad'lemeden
önce/sonra birebir aynı kaldığı).

#### Faz 11, madde 5: Google/Apple login ✅ (kod) — kurulum kullanıcıda

Yalnızca e-posta/şifre ile giriş/kayıt vardı.

- **`NativeOAuthService`** (yeni — `AppLockService`'in `local_auth`'ı
  sardığı gibi, `google_sign_in`/`sign_in_with_apple`'ı sarıyor; bir
  testin gerçek bir platform kanalına hiç dokunmadan sahtesini
  koyabilmesi için): `signInWithGoogle()`/`signInWithApple()` bir ID
  token döndürüyor (kullanıcı native seçiciyi iptal ederse `null` —
  bir hata değil), `AuthRepository.signInWithGoogleIdToken()`/
  `signInWithAppleIdToken()` bunu Supabase'in `signInWithIdToken()`'ına
  veriyor. Supabase hesabı ilk kullanımda otomatik oluşturuyor —
  e-posta/şifre `signUp`'ın zaten yaptığı gibi.
- **`google_sign_in` 7.x'in tamamen yeniden tasarlanmış API'si**: bu
  paket 7.0'da (mevcut sürüm) imperatif `GoogleSignIn().signIn()`'den
  `GoogleSignIn.instance.initialize()` + `.authenticate()` + bir
  `authenticationEvents` stream'ine dayanan çok farklı bir mimariye
  geçti — ID token artık `account.authentication.idToken` üzerinden
  senkron olarak alınıyor (paketin kendi kaynağından doğrulandı, bkz.
  aşağıdaki "Doğrulama" notu). `initialize()` tam olarak bir kez, başka
  hiçbir çağrıdan önce çalışmalı — `main.dart`'a, yalnızca
  `GOOGLE_CLIENT_ID`/`GOOGLE_SERVER_CLIENT_ID` ayarlıyken eklendi.
- **Gerçek bir sürüm kısıtı bulundu**: `sign_in_with_apple`'ın en
  güncel sürümü (8.x) Dart `>=3.11` istiyor, bu proje `^3.10.1`'de —
  `flutter pub get` bunu net şekilde reddetti. `7.0.1`'e sabitlendi
  (Dart SDK yükseltildiğinde tekrar değerlendirilebilir).
- **`LoginScreen`**: Google/Apple düğmeleri yalnızca kendi ön koşulları
  karşılanmışken görünüyor (`googleSignInAvailableProvider`/
  `appleSignInAvailableProvider`) — yapılandırılmamış bir sağlayıcıyı
  bozuk gösteren bir düğme yerine, hiç göstermiyor. Apple yalnızca iOS/
  macOS'ta (`NativeOAuthService.isAppleAvailable`) — Android ayrı bir
  web tabanlı akış gerektirir, kurulmadı.
- **Gerçek bir regresyon bulundu ve düzeltildi**: `Env._optional()`
  (`backendUrl`, ve yeni `googleClientId`/`googleServerClientId`)
  `dotenv.env[...]`'i hiç try/catch'siz çağırıyordu — `dotenv.load()`
  hiç çalışmamışken (çoğu widget testinde olduğu gibi) bu sessizce
  `null` dönmek yerine `NotInitializedError` **fırlatıyordu**.
  `LoginScreen`'in yeni `googleSignInAvailableProvider` okuması, bu
  spesifik `Env` erişimini mock'lanmadan çalıştıran **ilk** test oldu
  ve var olan bir testi (`login_screen_test.dart`'ın "signs in..."
  testi, hiçbir Google/Apple provider'ını override etmiyordu) gerçekten
  kırdı — spekülasyonla değil, gerçek bir test çalıştırmasıyla
  yakalandı. `_optional()` artık `NotInitializedError`'ı "hiçbir şey
  ayarlanmamış" ile aynı şekilde ele alıyor — bu, yalnızca yeni kodu
  değil, `backendUrl`'ün de daha önce hiç ortaya çıkmamış aynı gizli
  kırılganlığını düzeltti.
- **`docs/google-apple-login-setup.md`** (yeni): Google Cloud
  Console'da Web/iOS/Android OAuth client'ları oluşturma, Supabase
  Dashboard'da her iki sağlayıcıyı yapılandırma, Apple Developer'da
  Services ID + Sign in with Apple key oluşturma, `mobile/.env` ve
  Xcode capability adımlarının tam kontrol listesi — hepsi kullanıcının
  kendisinin yapması gereken, bu oturumdan yapılamayan/doğrulanamayan
  adımlar.

**Doğrulanamayan**: gerçek bir Google/Apple giriş turu uçtan uca —
gerçek OAuth kimlik bilgileri, her iki sağlayıcının da gerçekten
yapılandırıldığı bir Supabase projesi, (Apple için) capability'li bir
provisioning profille imzalanmış gerçek bir cihaz/simülatör gerektiriyor,
hiçbiri bu ortamda yok. Yapılabilecek kadarı doğrulandı: `flutter
analyze` temiz; widget testleri `AuthController.signInWithGoogle()`/
`signInWithApple()`'ın her dalını (başarı, kullanıcı iptali, native SDK
hatası) gerçek SDK'lar yerine `FakeNativeOAuthService`'e karşı test
ediyor.

Mobile: `flutter analyze` temiz, testler 163 → **169** (+6: Google/
Apple düğmelerinin ikisi de yokken hiçbiri görünmüyor; Google'a
basmak native picker'dan gelen token'la giriş yapıyor; Apple için
aynısı; Google picker iptal edilirse `AuthRepository` hiç
çağrılmıyor ve hata gösterilmiyor; native bir hata snackbar olarak
çıkıyor, çökmüyor; `Env`'in dotenv yüklenmemişken bile `null` döndüğü
— regresyon düzeltmesinin kendi testi).

#### Faz 11, madde 6a: local AI provider (backend) ✅

Faz 11'in son, en büyük maddesi kullanıcı isteğiyle üçe bölündü —
local AI provider, tam offline semantic search, masaüstü/web istemci
— ve en küçüğünden başlandı. `get_ai_provider()`'ın `local` dalı
`NotImplementedError` fırlatıyordu (bkz. Faz 11 madde 4'ün notu).

- **`LocalProvider`** (yeni, `ai_provider.py`): text/embedding(s)/
  vision **Ollama**'ya (https://ollama.com — ayrı kurulan, HTTP'yle
  konuşulan bir model sunucusu) gidiyor; `transcribe_audio` ise
  Ollama'da ASR endpoint'i olmadığı için **`faster-whisper`**'ı
  (yeni bağımlılık) backend içinde çalıştırıyor. İkisi de bulut
  API'sine hiç istek atmıyor — tamamen çevrimdışı çalışabilen tek
  sağlayıcı bu.
  - `generate_text`/`analyze_image`: Ollama'nın `POST /api/chat`'i,
    `stream: false` ile. Vision, OpenAI/Gemini'nin content-parts
    yapısı yerine mesajın kendi üzerinde base64 string listesi
    (`images`) bekliyor — API dokümanından (resmi `ollama/ollama`
    reposunun `docs/api.md`'si) doğrulandı, tahmin edilmedi.
  - `generate_embeddings`: `POST /api/embed`, `input` tek string
    veya liste kabul ediyor; `nomic-embed-text` 768 boyut üretiyor,
    `GeminiProvider`'ın kullandığı aynı `_pad_embedding()` ile
    1536'ya sıfırla dolduruluyor (aynı matematiksel gerekçe, bkz.
    `GeminiProvider`'ın docstring'i — burada da yalnızca aynı
    sağlayıcının kendi embedding'leri karşılaştırılıyor).
  - `transcribe_audio`: `faster_whisper.WhisperModel` ilk kullanımda
    lazy oluşturuluyor (gereksiz model indirmeden kaçınmak için) ve
    `asyncio.to_thread` üzerinden çalıştırılıyor — CPU-bound,
    senkron bir çağrı event loop'u tıkamasın diye.
  - Ollama'ya bağlanılamazsa (`httpx.ConnectError`) ham bağlantı
    hatası yerine `docs/local-ai-provider-setup.md`'ye yönlendiren
    net bir `RuntimeError` fırlatılıyor.
- **`Settings`**'e `local_ollama_base_url`/`local_text_model`/
  `local_embedding_model`/`local_vision_model`/`local_whisper_model`
  eklendi (`backend/.env.example`'da karşılıkları, açıklamalarıyla).
- **`docs/local-ai-provider-setup.md`** (yeni, `docs/
  google-apple-login-setup.md`'nin yapısını izliyor): Ollama kurulumu,
  hangi modellerin `ollama pull`'lanması gerektiği, sağlayıcılar arası
  geçişte re-embed gerekliliği — hepsi bu oturumdan yapılamayan/
  doğrulanamayan, kullanıcının kendisinin yapması gereken adımlar.

**Doğrulama ortamı notu**: `faster-whisper`'ın kendisi saf Python
wheel'i ama derlenmiş transitive bağımlılıkları (`ctranslate2`,
`onnxruntime`, `av`) var — önce Docker'da (`python:3.12-slim`, gerçek
`pip install -r requirements-dev.txt`) hem tek başına hem projenin
tüm `requirements.txt`'iyle birlikte çakışmasız kurulduğu doğrulandı.
Yerel `.venv`'e kurulum, önceki turlardaki gibi aynı
`platform.mac_ver()` uyumsuzluğuna (bu kez ayrıca pip 26.2'nin kendi
`_prevent_import_hook`'una da) çarptı; `pip download` ile wheel'ler
indirilip doğrudan `site-packages`'a açılarak çözüldü — asıl doğrulama
yine Docker'da. Yerel `pytest` çalıştırması bu oturumla ilgisiz, önceden
var olan ayrı bir ortam sorununa (Homebrew Python'ın `pyexpat`/sistem
`libexpat` sürüm uyuşmazlığı, `pypdf`'i import ederken patlıyor) çarptı;
Docker'da tüm test paketi (bu değişikliklerle) sorunsuz geçtiği için bu
yerel makineye özgü, ilgisiz bir kusur olarak not edildi.

Backend: `ruff check` temiz (Docker'da ve lokalde), testler 174 →
**179** (+5: `Settings`'e göre `LocalProvider`'ın seçildiğini
doğrulayan provider-seçim testi; `TestLocalProviderOllamaCalls` —
`httpx.MockTransport`'la gerçek bir Ollama'ya hiç dokunmadan
`generate_text`'in `/api/chat`'e doğru gövdeyi attığını,
`generate_embeddings`'in `/api/embed`'e attığını ve sonucu 1536'ya
doldurduğunu, boş liste için hiç istek atmadığını, `analyze_image`'ın
görseli base64 `images` alanına koyup JSON yanıtı ayrıştırdığını, ve
Ollama'ya bağlanılamazsa okunabilir bir `RuntimeError` fırlatıldığını
doğruluyor).

#### Faz 11, madde 6b: tam offline semantic search (mobil) ✅

`LocalSearchDataSource` (backend'e ulaşılamayınca devreye giren
keyword fallback, bkz. `OfflineFallbackSearchRepository`) yalnızca düz
substring araması yapıyordu: yalnızca sabit üç preset yerine sıralama
yoktu (her zaman en yeniden en eskiye), ve çok kelimeli bir sorgu
kelimeleri farklı alanlarda ya da farklı sırada geçtiğinde hiç eşleşmiyordu
(tek bir alanda tek bir bitişik substring aranıyordu).

**Mimari kararı kullanıcıya soruldu**: gerçek bir nöral embedding modeli
(GGUF/TFLite, native plugin ile cihazda çalıştırma) mı, yoksa hafif bir
istatistiksel yaklaşım mı — kullanıcı **hafif TF-IDF/cosine ranking**'i
seçti. Gerekçe: nöral seçenek 50-150MB'lık bir model dosyasını uygulamaya
gömüp yeni bir native plugin bağımlılığı eklemeyi gerektiriyordu ve bu
oturumda (gerçek cihaz/simülatör yok) kodun **çalıştığı hiç
doğrulanamazdı** — yalnızca arayüz doğrulanabilirdi, Google/Apple
login'deki "kod tamam, doğrulama kullanıcıda" durumunun bir tekrarı
olurdu. TF-IDF ise sıfır yeni bağımlılık, sıfır model dosyasıyla, bu
oturumda `flutter test` ile uçtan uca gerçekten doğrulanabilen tek
seçenekti.

- **`tfidf_ranker.dart`** (yeni, ~50 satır, sıfır bağımlılık):
  `rankByTfidf()` — sorguyu ve her dokümanı (title + description +
  noteContent + sourceUrl birleştirilmiş) Unicode-aware tokenize edip
  (Türkçe harfler `\w`'nin İngilizce ASCII karşılığından farklı olarak
  kelime sınırı sayılmıyor — `\p{L}`/`\p{N}` kullanıldı), klasik
  TF-IDF ağırlıklandırma (log-scaled term frequency × smoothed idf) ve
  cosine similarity ile sıralıyor. Vokabülerini hiç paylaşmayan bir
  doküman (cosine tam 0) sonuçtan tamamen çıkarılıyor — eski "hiç
  eşleşme yoksa hiç sonuç yok" sözleşmesiyle aynı.
- **Bu, nöral bir embedding DEĞİL** — eşanlamlı/paraphrase yakalamıyor
  ("araba" sorgusu "otomobil" içeren bir dokümanı bulmaz), yalnızca
  paylaşılan kelime kökü (tokenize edildikten sonra) eşleşmesi. Bu
  sınır `tfidf_ranker.dart`'ın kendi docstring'inde ve
  `LocalSearchDataSource`'ınkinde açıkça yazılı.
- **`LocalSearchDataSource`**: artık `q.get()`'le gelen tüm satırları
  `rankByTfidf()`'e veriyor, `similarity` alanına gerçek cosine skorunu
  yazıyor (eskiden sabit `0`'dı). Snippet çıkarımı iki aşamalı: önce
  eski davranış gibi sorgunun tam bitişik substring'ini arıyor; o
  bulunamazsa (çok kelimeli bir sorgunun kelimeleri farklı alanlarda
  geçtiği için) sorgudaki paylaşılan tokenlardan birinin ilk geçtiği
  yere düşüyor — TF-IDF bir eşleşme dediği halde snippet'in boş
  dönmemesi için.
- **Gerçek bir davranış değişikliği, mevcut bir teste çarptı**: eski
  testlerden biri, boşluksuz 400+ karakterlik bitişik bir "kelime"nin
  ortasına gömülü `docker` alt-dizisini arıyordu — düz substring
  arama bunu (kelime sınırı önemsemeden) buluyordu, ama tokenize
  edilmiş TF-IDF bunu bulamaz (tüm 400+ karakter TEK bir token
  sayılıyor, `docker` kendi başına bir token değil). Bu, gerçekte bir
  düzeltme: "xxxdockeryyy" gerçek bir "docker" eşleşmesi değil. Test,
  aynı senaryoyu (uzun bir alanın ortasındaki bir eşleşmenin etrafını
  kırpma) gerçek kelime sınırlarıyla (`'lorem ' * 40 + 'docker' + '
  ipsum' * 40`) yeniden yazıldı.

**Bilinçli sınırlar**:
- Yalnızca zaten Drift'e senkronize edilen alanlar aranıyor — OCR
  metni ve görsellerin/PDF'lerin AI açıklamaları Supabase'in
  `item_contents` tablosunda yaşıyor, cihaza hiç inmiyor (aynı
  önceden var olan sınır, değişmedi).
- Eşanlamlı/paraphrase yakalamıyor (yukarıda açıklandı) — bu maddenin
  "tam" kelimesini tam anlamıyla karşılamıyor, yalnızca eski düz
  substring aramaya göre gerçek bir iyileştirme (kelime sırası/alan
  bağımsız çok kelimeli eşleşme + alaka düzeyine göre sıralama).
- Sorgu her arama çağrısında sıfırdan hesaplanıyor (kalıcı bir
  ters-indeks yok) — bir kullanıcının local cache'i gerçekçi olarak
  yüzlerce-birkaç bin satır olduğu için kabul edilebilir; gerçek bir
  ölçek sorununu çözmeye çalışmıyor.

Mobile: `flutter analyze` temiz, testler 168 → **180** (+12: yeni
`tfidf_ranker_test.dart` — tokenize'ın Türkçe harfleri kelime sınırı
saymadığını, boş sorgu/korpüsün hiçbir şey döndürmediğini, vokabüler
paylaşmayan bir dokümanın tamamen dışarıda kaldığını, çok kelimeli bir
sorgunun kelimeleri farklı alanlara yayılmış bir dokümanı bulduğunu,
sorgu vokabülerinin daha fazlasını içeren bir dokümanın daha yüksek
sıralandığını, nadir bir terimin çok tekrarlanan yaygın bir terimden
daha ağır bastığını, sonuçların skora göre sıralı olduğunu doğruluyor;
`local_search_data_source_test.dart`'a +3: çok kelimeli sorgunun
farklı alanlardaki kelimeleri eşleştirdiğini, daha fazla sorgu terimi
içeren item'ın daha yükseğe sıralandığını, paylaşılan bir kelimenin
artık sıfırdan farklı bir `similarity` aldığını).

#### Faz 11, madde 6c: masaüstü/web istemci ✅ (web + macOS)

Faz 11 madde 6'nın üçe bölünen son parçası. Kullanıcıya kapsam
soruldu: gerçek bir nöral embedding gibi, bu oturumda derlenip/
çalıştırılıp doğrulanabilen platformlar **web** ve **macOS**'tu (bu
makinede Xcode kurulu, gerçek bir macOS cihaz bulundu); Windows/Linux
için gerçek bir makine yok — kod eklense de burada hiç
derlenip/çalıştırılamazdı. Kullanıcı **"Web + macOS masaüstü"**
kapsamını seçti.

- **`flutter create --platforms=web,macos .`**: `web/` ve `macos/`
  scaffold edildi — aynı Dart/Flutter kod tabanı, ayrı bir istemci
  değil. `.metadata`'daki migration listesi bu komutun bir yan etkiyle
  android/ios girdilerini SİLİP macos/web ile değiştirdiğini ortaya
  çıkardı (gerçek bir `flutter create` tuhaflığı) — dördü de geri
  eklendi, yoksa `flutter migrate` ileride android/ios şablon
  dosyalarını artık takip edilmiyor sanabilirdi.
- **Drift'in web'de sqlite'ı WASM'a derlemesi gerekiyor** — tarayıcıda
  gerçek bir dosya sistemi yok. `AppDatabase._openConnection()`'a
  `DriftWebOptions(sqlite3Wasm:, driftWorker:)` eklendi;
  `web/sqlite3.wasm` ve `web/drift_worker.dart.js` drift'in kendi
  GitHub release'inden, **`pubspec.lock`'ın çözümlenmiş drift
  sürümüyle (2.34.4) tam eşleşecek şekilde** indirildi — sürüm
  uyuşmazlığında worker protokolü sessizce bozulabiliyor. Bu olmadan
  uygulama web'de hiç açılmıyordu (`driftDatabase()` web'de `web:`
  parametresi verilmeden `ArgumentError` fırlatıyor).
- **`capture_platform_support.dart`** (yeni, saf fonksiyonlar):
  `Choose Image`/`Upload Document`/`Take Photo`/`Record Audio`'nun
  hepsi `OfflineItemRepository.uploadFile()` üzerinden `dart:io`'nun
  `File`'ını kullanıyor — web'de gerçek bir dosya sistemi yok, bu da
  crash demek. Dördü de web'de devre dışı, "Web'de henüz
  desteklenmiyor" alt metniyle (Google/Apple login'deki "bozuk bir
  düğme göstermek yerine hiç gösterme" deseninin aynısı). `Take Photo`
  macOS'ta da AYRICA devre dışı — `camera` paketinin macOS
  implementasyonu hiç yok (kendi `pubspec.yaml`'ı yalnızca
  android/ios/web tanımlıyor); `Choose Image`/`Upload Document`/
  `Record Audio` macOS'ta normal çalışıyor (`file_picker`/`record`'ın
  gerçek masaüstü backend'leri var).
  - **Testability kararı**: bu kontroller `kIsWeb`/`Platform.isMacOS`'u
    widget içinde doğrudan okumak yerine saf `isWeb`/`isMacOS`
    parametreli fonksiyonlar olarak yazıldı — `flutter test` her zaman
    `kIsWeb == false` ile çalışıyor ve `Platform.isMacOS` testi
    çalıştıran makineye bağlı, o yüzden widget'ın kendisi hiçbir
    platform kombinasyonunu deterministik test edemezdi.
- **`ExportService`/`ExportController`**: `dart:io` `File` + temp
  dizine yazıp paylaşmak yerine, JSON'ı doğrudan bytes'tan
  paylaşacak şekilde (`XFile.fromData`) yeniden yazıldı — bu bir
  "web'de devre dışı" sınırı değil, her platformda aynı şekilde
  çalışan daha basit bir tasarım; `path_provider`/`dart:io` bağımlılığı
  export'tan tamamen kalktı.
- **Gerçek bir hata bulundu, düzeltildi, ve before/after ile
  doğrulandı**: Flutter'ın kendi macOS şablonu
  `com.apple.security.app-sandbox`'ı açıyor ama
  `com.apple.security.network.client`'ı **eklemiyor** — bu olmadan
  App Sandbox altında her giden istek (Supabase, AI backend) sessizce
  engelleniyor (Flutter'ın kendi dokümanında da belgeli, bu projeye
  özgü değil). Düzeltmeden önce derlenip çalıştırılan `.app`, her
  seferinde birkaç saniye içinde bir arka plan ağ çağrısında
  (`google_fonts`'un bir fontu HTTPS üzerinden çekmesi) hata veriyordu;
  entitlement her iki dosyaya da (`DebugProfile.entitlements` VE
  `Release.entitlements` — Flutter'ın kendi tavsiyesi: ikisini de aynı
  tut) eklenip yeniden derlendikten sonra, aynı senaryo iki ayrı
  çalıştırmada da hiç hata vermedi. `codesign -d --entitlements :-`
  ile entitlement'ın gerçekten imzalı binary'ye gömüldüğü doğrulandı.
- **`docs/desktop-web-setup.md`** (yeni): yukarıdakilerin hepsinin
  ayrıntısı, artı Windows/Linux'un neden eklenmediği, drift wasm
  dosyalarının sürüm senkronizasyonu nasıl yapılır, ve web'de Google/
  Apple login'in ihtiyaç duyacağı ekstra (bu oturumda yapılmayan)
  kurulum notları.

**Bilinçli sınırlar**:
- Windows/Linux hiç eklenmedi — bu sandbox'ta ne derlenebilir ne
  çalıştırılabilirdi, kod eklemek "yazıldı ama hiç denenmedi" durumu
  yaratırdı.
- Web'de gerçek bir tarayıcı çalıştırması hiç yapılamadı — bu
  makinede Chrome/Chromium kurulu değil (`flutter doctor` bunu
  doğruluyor). Wasm sqlite kurulumu kod incelemesi + drift'in
  belgelenmiş sözleşmesiyle birebir eşleşme üzerinden doğrulandı,
  gerçek bir tarayıcıda veritabanı açıldığı izlenerek değil.
- macOS uygulamasının gerçek bir kullanıcı akışı (giriş yapıp arama
  yapmak gibi) hiç uçtan uca izlenemedi — bu oturum bir process
  başlatıp loglarını okuyabiliyor, GUI'yi tıklayarak süremiyor. Süreç
  gerçek Supabase kimlik bilgileriyle ~30 saniye boyunca hatasız
  çalıştığı gözlemlendi, gerçek bir kullanıcı akışını tamamladığı değil.
- Web'de Google/Apple login için gereken ekstra kurulum (web'e özgü
  meta tag/redirect URI) eklenmedi — Faz 11 madde 5 zaten "kod var,
  kurulum kullanıcıda" durumundaydı, bu bir platform daha ekliyor.

Mobile: `flutter analyze` temiz, `flutter build web` ve `flutter build
macos` ikisi de gerçekten derlendi (macOS için ayrıca gerçekten
çalıştırılıp gözlemlendi), testler 180 → **189** (+9: yeni
`capture_platform_support_test.dart` — dosya tabanlı yakalamanın
web'de desteklenmediğini, her yerde başka desteklendiğini, kameranın
hem web'de hem macOS'ta desteklenmediğini ama başka bir native
platformda desteklendiğini, web ve macOS için gösterilen gerekçelerin
birbirinden farklı olduğunu, gerçekten desteklenen bir platformda hiç
gerekçe gösterilmediğini doğruluyor).

## Faz 12 — bağımsız yeniden denetim (11 Eylül 2026, HEAD `106264f`)

Codex tabanlı ikinci bir bağımsız denetim, Faz 10/11'in "tamamlandı"
işaretlerinin bir kısmının mevcut davranıştan ileri gittiğini buldu —
özellikle hesap izolasyonu ve item-bazlı Privacy Mode gerçekten
kapanmamıştı. Raporun her maddesi kodda tek tek doğrulandı (bazıları
zaten dokümante edilmiş bilinçli sınırlarla çakışıyordu, çelişki değil;
aşağıdakiler gerçekten yeni bulunan, düzeltilmesi gereken hatalar):

1. ~~Hesap değişince eski hesabın listesi ekranda kalıyor~~ ✅ — bkz.
   aşağıdaki alt bölüm.
2. ~~Sync sırasında hesap değişirse A'nın yazması B'nin hesabına
   düşebiliyor~~ ✅ — bkz. aşağıdaki alt bölüm.
3. ~~`findById`/`fetchNoteContent` kullanıcı filtresiz~~ ✅ — bkz.
   aşağıdaki alt bölüm.
4. ~~B'nin sync'i A'nın yerel koleksiyon üyeliğini silebiliyor~~ ✅ —
   bkz. aşağıdaki alt bölüm.
5. ~~Private: arama hata verince tüm sonuçları gösteriyor + reveal
   kapanınca eski sonuçlar temizlenmiyor~~ ✅ — bkz. aşağıdaki alt bölüm.
6. ~~Polling bütçesi tükenince bir daha hiç çalışmıyor (yeni işler
   dahil)~~ ✅ — bkz. aşağıdaki alt bölüm.
7. ~~`replace_chunks`: eski iş yeni işin chunk'ını silebiliyor~~ ✅ —
   bkz. aşağıdaki alt bölüm.
8. ~~Item detail ekranı işlem tamamlanınca güncellenmiyor~~ ✅ — bkz.
   aşağıdaki alt bölüm.
9. ~~Büyük arşivde sync, gelmeyen kayıtları "silinmiş" sanıp local'den
   siliyor~~ ✅ — bkz. aşağıdaki alt bölüm.
10. ~~Gemini varsayılan modelleri (`text-embedding-004`,
    `gemini-2.0-flash`) gerçekten kapatılmış~~ ✅ — bkz. aşağıdaki alt
    bölüm.
11. ~~Web'de Google sign-in kod seviyesinde çalışamaz~~ ✅ — bkz.
    aşağıdaki alt bölüm.
12. ~~Not ekranında sil/favori/private/retry yok~~ ✅ — bkz. aşağıdaki
    alt bölüm.
13. ~~Arama yarışı — hızlı ardışık aramada eski/yavaş yanıt yeni sonucun
    üstüne yazabiliyor~~ ✅ — bkz. aşağıdaki alt bölüm.

#### Faz 12, madde 1: hesap değişince eski hesabın listesi ekranda kalıyor ✅

`itemRepositoryProvider`/`itemsProvider`/`collectionRepositoryProvider`/
`pendingSyncCountProvider`/`recentSearchesProvider` düz `Provider`/
`StreamProvider`'dı — hiçbiri `authStateChangesProvider`'ı izlemiyordu,
hiçbir yerde `ref.invalidate` edilmiyordu. `OfflineItemRepository.
watchItems()` çağrıldığı anda `_userId`'yi (bir getter, ama STREAM'in
kendisi ilk kurulduğunda bir kere değerlendiriliyor) Drift sorgusuna
gömüyor. Sonuç: aynı oturumda A'dan çıkıp B'ye girince, Home/Library B'ye
geçene kadar A'nın item'larını göstermeye devam ediyordu — köşe durum
değil, hemen her hesap değişiminde tetiklenen bir bug.

- **`currentUserIdProvider`** (yeni, `auth_providers.dart`):
  `authStateChangesProvider`'dan türeyen, savunmacı (Supabase hiç
  initialize edilmemişse `null` — mevcut `_currentUserIdOrNull`
  desenleriyle aynı) tek bir kaynak. Her "kullanıcıya özel" provider bunu
  `ref.watch` ediyor (doğrudan ya da `itemRepositoryProvider`/
  `collectionRepositoryProvider` üzerinden dolaylı) — böylece hesap
  değişince Riverpod bunları GERÇEKTEN yeniden kuruyor, altlarındaki
  Drift stream'lerini de yeni hesaba bağlıyor.
- **`itemRepositoryProvider`**, **`collectionRepositoryProvider`**: en
  başta `ref.watch(currentUserIdProvider)` — değerin kendisi
  kullanılmıyor, yalnızca yeniden kurulma bağımlılığı için. Bu ikisinin
  yeniden kurulması `itemsProvider`/`allItemsIncludingPrivateProvider`/
  `collectionsProvider`/`collectionItemsProvider`'ı da otomatik
  tetikliyor (Riverpod: bir `Provider`'ın çıktısı değişince onu
  `ref.watch` eden her şey de yeniden kurulur).
- **`pendingSyncCountProvider`**, **`recentSearchesProvider`**: aynı hatayı
  ayrı ayrı taşıyorlardı (ilk kurulduklarında hangi hesap aktifse ona
  sonsuza kadar bağlı kalıyorlardı) — ikisi de `currentUserIdProvider`'a
  geçirildi.
- **Regresyon testi, düzeltmeden önce gerçekten kırmızı olduğu
  doğrulanarak yazıldı**: `item_providers_account_switch_test.dart` —
  gerçek bir in-memory Drift DB'de iki hesabın item'ları, gerçek
  `itemRepositoryProvider`/`itemsProvider` zinciri, yalnızca
  `remoteItemDataSourceProvider`'ın "kim giriş yapmış" bilgisi sahte
  (gerçek bir Supabase oturumu bu ortamda kurulamıyor). İlk yazımda test
  yanlışlıkla sahte `RemoteItemDataSource`'un KENDİSİNİ hesap
  değişince yeniden kuruyordu — bu, asıl düzeltmeyi (itemRepositoryProvider'ın
  kendi `ref.watch`'ı) test etmeden de testi yeşil geçiriyordu (fix
  satırı geçici olarak geri alınıp doğrulandı: test hâlâ yeşildi — yanlış
  pozitif). Sahte veri kaynağı production'daki gibi TEK bir sabit
  instance'a çevrilip yalnızca `userId` getter'ının okuduğu değer
  değişecek şekilde düzeltildi; bu haliyle fix geri alınınca test gerçekten
  kırmızı çıktı ("Actual: ['a-item']" beklenen ['b-item'] yerine), fix
  geri konunca yeşile döndü.

**Bilinçli sınır**: bu madde yalnızca OKUMA tarafını (listeler, sayımlar,
son aramalar) düzeltiyor. Sync sırasında bir hesap değişirse A'nın
BEKLEYEN bir YAZMASININ B'nin hesabına gitmesi ayrı bir hata — madde 2'de.

Mobile: `flutter analyze` temiz, testler 189 → **190** (+1,
yukarıdaki regresyon testi — hem gerçekten kırmızı çıktığı hem
düzeltmeyle yeşile döndüğü doğrulanarak yazıldı).

#### Faz 12, madde 2: sync sırasında hesap değişirse A'nın yazması B'ye gidebiliyor ✅

`SyncService.syncNow()` `userId`'yi başında bir kez yakalayıp
`_flushQueue(userId)`'a geçiriyordu, ama `_flushQueue`'nun içindeki her
`_remote.createNote()`/`updateNote()`/... çağrısı kendi `user_id`
alanını `RemoteItemDataSource.userId` getter'ından — yani **o anki
canlı Supabase oturumundan** — dolduruyordu, hiç `userId` parametresini
kullanmadan. A'nın kuyruğu boşaltılırken (birden fazla girdi varsa,
network I/O'nun tamamlanmasını beklerken) hesap B'ye değiştirilirse,
A'nın kalan yazmaları B'nin `user_id`'siyle ve B'nin auth token'ıyla
gönderiliyordu. **RLS bunu yakalamıyor**: `items_owner` policy'si
`auth.uid() = user_id` kontrol ediyor, ama hem `user_id` alanı hem
`auth.uid()` (JWT) aynı racy canlı okumadan geliyor — ikisi birbiriyle
tutarlı (ikisi de B), yalnızca bu girdinin GERÇEKTEN kime ait olduğuyla
tutarsız.

- **`SyncService._flushQueue()`**: döngünün her adımının başında
  `if (_currentUserIdOrNull() != userId) return;` — canlı oturum artık
  bu `syncNow()` çağrısının başladığı hesapla eşleşmiyorsa, kuyruğun
  geri kalanını hiç denemeden tamamen duruyor. Kalan girdiler
  `_queue.recordFailure`/`_markFailed` ile "başarısız" işaretlenmiyor —
  hiç dokunulmadan, olduğu gibi kuyrukta kalıyor (`pendingEntries(userId)`
  zaten A'ya göre filtrelendiği için, A tekrar giriş yapınca normal
  şekilde devam ediyor).
- **Bilinçli olarak kapatılmayan artık kalan (residual) boşluk**
  (`url_service.py`'nin DNS-rebinding notuyla aynı ruhta): bu yalnızca
  KUYRUK GİRDİLERİ ARASINDA koruyor, tek bir isteğin ORTASINDA (kontrol
  geçti, tam istek gönderilirken hesap değişti) değil — bunu tam
  kapatmak, "şu an hangi oturum aktifse ona güven" yerine bu isteğin
  kullanması gereken tam access token'ı sabitlemeyi gerektirir, bu
  fixin kapsamından daha büyük bir değişiklik.
- **Regresyon testi, düzeltmeden önce gerçekten kırmızı çıktığı
  doğrulanarak yazıldı**: `sync_service_test.dart`'a yeni bir test —
  user-1'in kuyruğunda 2 not varken, `remote.userId` mock'u SAYAÇLA
  ilk iki okumada 'user-1', sonrasında 'user-2' dönecek şekilde
  ayarlanıyor (ilk okuma `syncNow()`'ın kendisi, ikincisi ilk kuyruk
  girdisinin guard kontrolü — üçüncü okuma, ikinci girdinin guard'ı,
  artık 'user-2'). Yalnızca ilk not gönderiliyor, ikincisi hiç
  denenmiyor ve kuyrukta user-1'e ait olarak sağlam kalıyor. Fix geçici
  geri alınınca test gerçekten kırmızı çıktı ("Unexpected calls:
  createNote(note-2...)"), geri konunca yeşile döndü.

Mobile: `flutter analyze` temiz, testler 190 → **191** (+1, yukarıdaki
regresyon testi).

#### Faz 12, madde 3: `findById`/`fetchNoteContent` kullanıcı filtresiz ✅

`ItemLocalDataSource.findById(itemId)` yalnızca `t.id.equals(itemId)`
filtreliyordu — `watchAll(userId)`/`allIds(userId)`'ın aksine hiç
`userId` almıyordu. `OfflineItemRepository.findById()`/
`fetchNoteContent()` bunu doğrudan kullanıyordu; ikisi de `ItemByIdLoader`
(deep link, `/item/:id` route restore) ve item detail'in duplicate-hedef
yüklemesi gibi, kullanıcının kendi filtrelenmiş listesinden GEÇMEYEN
yollardan çağrılıyor. Sonuç: B oturumdayken, cihazda hâlâ duran (Faz
10a'nın kendi dokümante ettiği "veri hâlâ diskte" sınırı — sign-out
local DB'yi hiç temizlemiyor) A'nın bir item id'si biliniyorsa (deep
link, bildirim, vs.), A'nın not içeriği B'ye gösterilebiliyordu.

- **`ItemLocalDataSource.findById(String userId, String itemId)`**:
  imza değişti, sorguya `& t.userId.equals(userId)` eklendi — artık
  `watchAll`/`allIds` ile aynı desende, her okuma kullanıcıya bağlı.
  `OfflineItemRepository`'nin iki çağrı yeri (`findById`,
  `fetchNoteContent`) zaten `_userId`'yi biliyordu, tek satırlık geçiş.
  `ItemRepository` arayüzünün kendisi (public `findById(itemId)`)
  değişmedi — çağıranlar (`ItemByIdLoader`, `item_detail_screen.dart`)
  hiç dokunulmadan otomatik düzeldi.
- **`fetchNoteContent`'in remote fallback'ı** (`_remote.fetchNoteContent`,
  ilk sync'ten önceki cold-start yolu) zaten güvenliydi — Supabase'in
  kendi RLS'i (`item_contents_owner`) başka bir hesabın `item_id`'si için
  sunucu tarafında zaten hiçbir şey döndürmüyor.
- **Regresyon testi, düzeltmeden önce gerçekten kırmızı çıktığı
  doğrulanarak yazıldı**: yeni `item_local_data_source_test.dart` —
  gerçek bir in-memory Drift DB'de A'nın item'ı eklenip B olarak
  `findById` çağrılıyor, `null` bekleniyor. Fix geçici geri alınınca
  test gerçekten A'nın satırını (`noteContent: 'secret body'` dahil)
  döndürerek kırmızı çıktı, geri konunca `null`'a döndü.

Mobile: `flutter analyze` temiz, testler 191 → **194** (+3, yukarıdaki
yeni test dosyası — `ItemLocalDataSource`'ın kendi dedike bir testi
daha önce hiç yoktu).

#### Faz 12, madde 4: B'nin sync'i A'nın yerel koleksiyon üyeliğini silebiliyor ✅

`CollectionLocalDataSource.allMemberships()` hiç `userId` almıyordu —
`_db.select(_db.localCollectionItems).get()` ile CİHAZDAKİ TÜM
HESAPLARIN üyelik satırlarını döndürüyordu (`LocalCollectionItems`'ın
kendi `userId` kolonu yok, yalnızca `collectionId`/`itemId`).
`SyncService._pullRemoteCollections(userId)` bunu B'nin sunucudan gelen
üyelik kümesiyle karşılaştırıp eşleşmeyeni "stale" kabul edip
`removeItem` ile siliyordu — A'nın hiç ilgisi olmayan, cihazda hâlâ
duran üyelik satırları, B senkron olduğu anda **kalıcı olarak
siliniyordu**. Bu bir okuma sızıntısı değil, gerçek bir veri kaybıydı.

- **`allMemberships(String userId)`**: artık `LocalCollections`'a
  `innerJoin` ile bağlanıp `LocalCollections.userId = userId` filtresi
  uyguluyor — `LocalCollectionItems`'ın kendi kolonu olmadığı için
  sahiplik bilgisi, `collectionId` üzerinden sahibi bilinen
  `LocalCollections`'tan geliyor (`watchItemsForCollection`'ın zaten
  kullandığı join deseniyle aynı).
- **Regresyon testi, düzeltmeden önce gerçekten kırmızı çıktığı
  doğrulanarak yazıldı**: yeni `collection_local_data_source_test.dart`
  — A ve B'nin ayrı koleksiyon+üyelikleri eklenip her ikisi için ayrı
  ayrı `allMemberships` çağrılıyor, yalnızca kendi üyeliklerini
  görmeleri doğrulanıyor; ayrıca sahibi hiç cache'te olmayan (defensive)
  bir üyeliğin kimseye görünmediği ayrıca test edildi. Fix geçici geri
  alınınca her iki test de gerçekten kırmızı çıktı (B'nin sorgusu A'nın
  satırını da döndürdü; sahipsiz satır boş liste yerine göründü), geri
  konunca ikisi de yeşile döndü.

Mobile: `flutter analyze` temiz, testler 194 → **197** (+3, yukarıdaki
yeni test dosyası — `CollectionLocalDataSource`'ın kendi dedike bir
testi daha önce hiç yoktu).

#### Faz 12, madde 5: Private — arama hata verince açık, reveal kapanınca eski sonuçlar açık kalıyor ✅

İki ayrı gerçek boşluk, ikisi de `search_providers.dart`'ta.

1. **`_hidePrivateResults` fail-open'dı**: `allItemsIncludingPrivateProvider.future`
   hata verirse (gerçek bir Drift arızası, kapatılmış bağlantı, vb.)
   `catch` bloğu sonuçları FİLTRELEMEDEN döndürüyordu — "kontrol
   edilecek bir şey yokken aramayı tamamen düşürmeye değmez" gerekçesi
   asıl olarak yapılandırılmamış bir test fixture'ı (hiç
   `itemRepositoryProvider` override'ı yok) için yazılmıştı, ama her
   GERÇEK hataya da aynı şekilde uygulanıyordu — production'da genuine
   bir hata, private item'ları sessizce sonuç listesine sızdırabilirdi.
2. **Reveal kapanınca ekrandaki sonuçlar temizlenmiyordu**:
   `privateItemsRevealedProvider` `false`'a dönünce (`AppLockGate`'in
   arka plana düşünce sıfırlaması gibi) `itemsProvider` (Home/Library)
   reaktif olarak yeniden filtreleniyor, ama `SearchController.state`
   yalnızca `search()` çağrıldığında hesaplanan tek seferlik bir
   snapshot — reveal açıkken görünen bir private sonuç, ekranda kalmaya
   devam ediyordu, yeni bir arama yapılana kadar.

- **`_hidePrivateResults`**: artık try/catch yok, hata varsa rethrow
  ediyor — `SearchController.search()`'ün zaten sahip olduğu
  `AsyncValue.guard` bunu gerçek bir arama hatasıyla (bkz.
  `search_tab.dart`'ın `error:` dalı) aynı, görünür bir hata durumuna
  çeviriyor; `relatedItemsProvider` da zaten her hatada kendi bölümünü
  gizliyor (`item_detail_screen.dart`) — ikisi de "belki private olan
  bir şeyi sessizce göster" yapmıyor artık.
- **`SearchController.build()`**: `privateItemsRevealedProvider`'ı
  `ref.listen` ediyor — `true`'dan `false`'a düşüşte, halihazırda
  ekranda olan sonuç listesini (yeni bir arama YAPMADAN) aynı
  `_hidePrivateResults`'tan tekrar geçiriyor.
- **Test harness düzeltmesi**: `search_tab_test.dart`'ın `wrap()`
  yardımcısı artık `itemRepo` verilmese bile HER ZAMAN boş bir
  `FakeItemRepository()` ile override ediyor — eskiden override
  edilmeden bırakılıp gerçek (Supabase'siz test ortamında hata veren)
  provider'a düşüyordu, ki bu da tam olarak artık kaldırılan fail-open
  yolunu tetikleyen şeydi. Bu, `search_providers.dart`'ın kendi hiç
  test edilmemiş olmasının (bu maddeye kadar `search_providers.dart`
  için dedike bir test dosyası hiç yoktu) bir sonucuydu.
- **Regresyon testleri, düzeltmeden önce gerçekten kırmızı çıktığı
  doğrulanarak yazıldı**: yeni `search_controller_test.dart` — (1)
  `watchItems()`'ı hata fırlatan bir sahte repository ile aramanın
  gerçekten `AsyncError`'a düştüğünü, (2) reveal açıkken bir private
  sonucun göründüğünü, reveal kapanınca (yeni arama yapılmadan) o
  sonucun listeden kalktığını doğruluyor. Her iki fix de geçici geri
  alınınca ilgili test gerçekten kırmızı çıktı, geri konunca yeşile
  döndü.

Mobile: `flutter analyze` temiz, testler 197 → **199** (+2, yukarıdaki
yeni test dosyası — `search_providers.dart`'ın kendi ilk dedike testi).

#### Faz 12, madde 6: polling bütçesi tükenince bir daha hiç çalışmıyor ✅

`_scheduleNextPollIfNeeded`'de `if (_pollAttemptsLeft <= 0) return;`
kontrolü, bütçeyi işler bitince sıfırlayan kontrolden ÖNCE
çalışıyordu. Bütçe bir kez 0'a inince (12 deneme × 5sn ≈ 1dk), bu
`SyncService` örneği bir daha **hiçbir zaman** — cihaz uygulama içinde
kaldığı sürece, tamamen farklı, çok sonra yüklenen bir item için bile
— timer kurmuyordu; idle kontrolüne hiç ulaşmadığı için bütçe asla
sıfırlanamıyordu. Faz 10b madde 2'nin asıl amacını (işlem sonucunun
otomatik yansıması) fiilen devre dışı bırakan bir regresyondu.

- **`ItemLocalDataSource.unfinishedProcessingIds(userId)`** (yeni —
  eski `hasUnfinishedProcessing`'in yerine): artık yalnızca `bool`
  değil, **hangi item id'lerinin** bekliyor olduğunun kendisini
  döndürüyor.
- **`SyncService._pollingItemIds`** (yeni alan): her poll kontrolünde
  güncellenen, "en son hangi id'ler bekliyordu" kümesi.
- **`_scheduleNextPollIfNeeded`**: artık ÖNCE bekleyen id'leri okuyor;
  hiç yoksa (idle) bütçeyi sıfırlıyor. Doluysa, önceki kümede
  OLMAYAN yeni bir id varsa bütçeyi yine sıfırlıyor — böylece kalıcı
  olarak takılı kalmış eski bir iş, ondan SONRA başlayan yepyeni bir
  işin kendi bütçesini almasını engellemiyor. Yalnızca kümedeki id'ler
  hiç değişmiyorsa (aynı takılı iş, başka hiçbir şey yok) orijinal
  niyet korunuyor: ~1 dakika sonra pes edip pilden tasarruf ediyor.
- **Regresyon testi, düzeltmeden önce gerçekten kırmızı çıktığı
  doğrulanarak yazıldı**: `sync_service_test.dart`'a yeni bir test —
  kalıcı takılı bir item (item-1) `maxPollAttempts: 3` bütçesini tek
  başına tüketiyor (`fetchCount` platoya ulaşıyor, doğrulanıyor); sonra
  yepyeni bir item (item-2) `pending` olarak beliriyor —
  `pollingSync.syncSoon()` çağrılıyor (gerçek bir yeni yükleme
  tetiklerdi) ve polling'in GERÇEKTEN devam ettiği (`fetchCount`
  büyümeye devam ediyor) doğrulanıyor. Fix geçici eski sıralamaya geri
  alınınca test gerçekten kırmızı çıktı (`fetchCount` platoda takılı
  kaldı, item-2'ye rağmen), geri konunca yeşile döndü.

Mobile: `flutter analyze` temiz, testler 199 → **200** (+1, yukarıdaki
regresyon testi).

#### Faz 12, madde 7: `replace_chunks`'ta eski iş yeni işin chunk'ını silebiliyor ✅

Faz 10b madde 3'ün kendi düzeltmesinin arta kalanı. `chunks_item_id_chunk_index_key`
(0013 migration) + UPSERT, iki eşzamanlı işin chunk'ları ÇOĞALTMASINI
önlemişti — ama bu hâlâ İKİ AYRI HTTP isteğiydi (bir UPSERT, sonra ayrı
bir DELETE). Eski, yavaş bir iş 1 chunk üretip; yeni, daha hızlı bir iş
3 chunk üretip önce bitirirse — eski işin gecikmiş DELETE'i
(`chunk_index >= 1`) yeni işin 1 ve 2 numaralı chunk'larını siliyordu.
Duplicate'i önleyen aynı fix, bu SIRA sorununu hiç çözmemişti.

- **`replace_chunks_for_job(p_item_id, p_job_id, p_chunks)`** (yeni
  Postgres fonksiyonu, `0015_replace_chunks_atomic.sql`): tüm işlemi
  TEK bir atomik RPC çağrısına indiriyor —
  1. `pg_advisory_xact_lock(hashtext(item_id))` ile item başına
     serialize ediyor — aynı item için iki eşzamanlı çağrı asla
     birbirinin SELECT/INSERT/DELETE adımlarıyla iç içe geçemiyor.
  2. `processing_jobs`'ta bu item için en güncel job hâlâ `p_job_id`
     mi diye kontrol ediyor — değilse (daha yeni bir iş zaten varsa)
     hiçbir şey yapmadan dönüyor. (1) sayesinde, bu kontrole gelen
     ikinci çağrı, ilkinin yazdıklarını zaten COMMIT edilmiş olarak
     görüyor — hangi iş gerçekten en son başladıysa, hangisi önce
     BİTERSE bitsin, son sözü o söylüyor.
  3. UPSERT + trim, tek transaction içinde.
- **`SupabaseRestRepository.replace_chunks()`**: artık `job_id` alıyor,
  eski iki-istekli (POST+DELETE) kodun yerine tek bir RPC POST'u var.
  `processing_pipeline.py`'daki tek çağrı yeri `job_id`'yi geçiriyor
  (zaten `create_job()`'dan elde ediyordu).
- **Gerçek bir canlı Postgres'e karşı doğrulandı** (bu sınıftaki
  değişiklikler için alışılmışın dışında bir titizlik — genelde SQL
  migration'ları yalnızca kod incelemesiyle doğrulanıyordu): projenin
  kendi `docker-compose.yml`'ındaki `pgvector/pgvector:pg16`
  container'ı ayağa kaldırılıp (`auth.users`'a bağımlı olmayan,
  yalnızca `items`/`chunks`/`processing_jobs`'ı taklit eden minimal bir
  şema ile) fonksiyonun kendisi gerçekten çalıştırıldı: (1) tam bu
  raporun tarif ettiği yarış senaryosu (eski iş [job A, 1 chunk] yeni
  işten [job B, 3 chunk] SONRA çağrılıyor — gerçek zamanlamayı taklit
  ediyor) — sonuç doğru şekilde yalnızca B'nin 3 chunk'ı, A'nın çağrısı
  sessizce no-op; (2) normal yeniden-işleme (aynı job daha az chunk'la
  tekrar çağrılıyor) — doğru şekilde güncelliyor + fazlasını kırpıyor;
  (3) hiç `processing_jobs` satırı olmayan bir item (olması gerekmeyen
  ama savunmacı bir uç durum) — `null` kontrolü doğru çalışıp işlemi
  engellemedi. Test container'ı ve script'leri işlem bitince silindi.
- **Doğrulanmayan**: gerçek eşzamanlı (concurrent, aynı anda) iki HTTP
  isteğiyle canlı bir yarış — yukarıdaki doğrulama sıralı (sequential)
  SQL çağrılarıyla "B sonra A" senaryosunu taklit ediyor, gerçek
  paralel bir yük altında `pg_advisory_xact_lock`'ın kilitlenme/bekleme
  davranışı ayrıca gözlemlenmedi (Postgres'in kendi belgelenmiş
  garantisine güveniliyor).

Backend: `ruff check` temiz (Docker'da), testler 179 (değişmedi — 2 eski
`replace_chunks` testi [POST+DELETE şeklini doğrulayan] artık geçersiz
olduğu için yeni tek-RPC şeklini doğrulayan 2 yeni testle değiştirildi;
`test_processing_pipeline.py`'nin `FakeRepo.replace_chunks`'ı yeni
`job_id` parametresini kabul edecek şekilde güncellendi).

#### Faz 12, madde 8: item detail ekranı işlem tamamlanınca güncellenmiyor ✅

`_loadFullItem()` yalnızca `initState()`'te bir kez çağrılıyordu.
Ekran açıkken arka planda `SyncService` item'ın `processingStatus`'unu
`pending`'den `completed`'a çekse (ya da `storagePath`'i doldursa) bile,
ekran bunu hiç görmüyordu — kullanıcının ekrandan çıkıp geri gelmesi
gerekiyordu.

- **`watchItemByIdProvider(itemId)`** (yeni, `item_providers.dart`):
  `itemByIdProvider`'ın (tek seferlik `Future`) canlı karşılığı — düz
  bir `Provider.autoDispose.family`, `allItemsIncludingPrivateProvider`'ı
  (zaten reaktif Drift stream'i) `ref.watch` edip listede eşleşen id'yi
  döndürüyor. Reveal durumundan bağımsız `allItemsIncludingPrivateProvider`'dan
  türetildi — private bir item'ın kendi detay ekranı, başka yerde reveal
  kapalı olsa bile onu göstermeye devam etmeli.
- **`ItemDetailScreen`**: `initState()`'teki tek seferlik `findById()`
  çağrısı kaldırıldı. Yerine: `initState()`'te `ref.read(watchItemByIdProvider(...))`
  ile senkron bir anlık düzeltme (local cache zaten hazırsa —
  arama/related/duplicate'ten gelen kırpılmış stand-in'i anında
  düzeltiyor); `build()`'de `ref.listen(watchItemByIdProvider(...))` ile
  SÜREKLİ dinleme — bundan sonraki her yerel değişiklikte (ekranın
  kendi optimistic yazmaları dahil — `_toggleFavorite` zaten Drift'e
  doğrudan yazıyor, bu yalnızca ekranda zaten görüneni onaylıyor, görsel
  bir titreme yok — ve şimdi, sunucudan çekilen gerçek bir tamamlanma)
  `_item`'ı güncelliyor.
- **Optimistic revert mantığı korundu**: `_toggleFavorite`/`_togglePrivate`/
  `_retryProcessing`/`_dismissDuplicate` hâlâ kendi `setState` ile anlık
  güncelleyip hata durumunda geri alıyor — bu yalnızca YEREL bir yazma
  başarısız olursa devreye giriyor (nadir), sunucu senkron hatası zaten
  hiç geri almıyordu (Home/Library'nin de yaptığı gibi, kalıcı olarak
  yerel durumu gösterip `syncStatus: 'failed'` ile işaretliyor). İki
  mekanizma (optimistic + reaktif) çakışmıyor: başarı durumunda ikisi de
  aynı son değere yakınsıyor, nadir yerel hata durumunda yalnızca
  optimistic katman geri almış oluyor.
- **Regresyon testi, düzeltmeden önce gerçekten kırmızı çıktığı
  doğrulanarak yazıldı**: `item_detail_screen_test.dart`'a yeni bir
  test — `FakeItemRepository`'ye yeni bir `updateItem()` yardımcı metodu
  eklendi (arka plan senkronunu taklit etmek için — diğer tüm mutasyon
  metotları ekranın KENDİ yazmasını taklit ediyordu, bu ilk kez "başka
  bir yerden gelen" bir değişikliği taklit ediyor); ekran açıkken
  `pending`'den `completed`'a + `storagePath` dolduran bir güncelleme
  simüle edilip "Dosyayı Aç"ın (yeniden navigasyon olmadan) belirdiği
  doğrulanıyor. Fix geçici geri alınınca test gerçekten kırmızı çıktı,
  geri konunca yeşile döndü.

Mobile: `flutter analyze` temiz, testler 200 → **201** (+1, yukarıdaki
regresyon testi).

#### Faz 12, madde 9: büyük arşivde sync, gelmeyen kayıtları "silinmiş" sanıp local'den siliyor ✅

`RemoteItemDataSource.fetchAllRows()`/`RemoteCollectionDataSource.
fetchAllRows()`/`fetchAllItemRows()` hiç sayfalama yapmıyordu — düz bir
`.select()`, PostgREST'in yapılandırılmış satır limitini (genelde 1000)
aşan bir arşivde hata vermeden SESSİZCE kırpıyordu. `SyncService`
"yanıtta yok" = "sunucuda silinmiş" varsayıyor (`_pullRemote`/
`_pullRemoteCollections`'ın stale-row temizleme mantığı) — bu limiti
aşan bir kullanıcı için, sınırın ötesindeki HER ŞEY bir sonraki sync'te
silinmiş sanılıp local cache'ten kalıcı olarak siliniyordu.

- **`fetchAllPages()`** (yeni, `core/network/paginated_fetch.dart`): saf,
  Supabase'den bağımsız bir sayfalama döngüsü — `.range(from, to)`
  çağıran bir callback alıp, dönen sayfa TAMAMEN BOŞ olana kadar
  çağırmaya devam ediyor. Bilinçli olarak "sayfa `pageSize`'dan kısaysa
  dur" YERİNE bunu seçti — kısa bir sayfa, sunucunun kendi yapılandırılmış
  limiti İSTENEN `pageSize`'dan daha düşükse YANLIŞ POZİTİF verir (bu
  durumda her sayfa "kısa" görünür, hiçbiri gerçekte son sayfa
  olmayabilir) — yalnızca gerçekten boş bir sayfa, sunucunun gerçek
  limiti ne olursa olsun güvenilir bir "bitti" sinyali.
- **`RemoteItemDataSource.fetchAllRows()`**, **`RemoteCollectionDataSource.
  fetchAllRows()`/`fetchAllItemRows()`**: üçü de artık `fetchAllPages()`
  üzerinden gidiyor; `created_at`'e (veya `collection_id`/`item_id`'ye)
  ek olarak `id` ikincil sıralama anahtarı eklendi — aynı `created_at`'e
  sahip birden fazla satır varsa (ör. toplu bir içe aktarım) sayfalar
  arası sıralamanın deterministik kalması için (aksi halde sayfa sınırında
  bir satır atlanabilir ya da tekrar edebilirdi).
- **Regresyon testleri, gerçek bir uygulama hatası bulunup düzeltilerek
  yazıldı** (alışılmışın biraz ötesinde): yeni `paginated_fetch_test.dart`
  yazılırken bir testin kendisi (sahte "bir sayfa döndür" callback'i her
  çağrıda AYNI 3 satırı döndürüyordu, hiç boş dönmüyordu) gerçek bir
  SONSUZ DÖNGÜYE yol açtı — `flutter test` gerçekten asılı kaldı (CPU'da
  2+ dakika, hiç ilerlemeyen bir test), süreç öldürülüp test düzeltildi.
  Ayrıca iki testin kendi beklenen çağrı listeleri yanlıştı (sunucu
  limitin altında sayfalarken bile fonksiyonun HER ZAMAN bir "onaylayıcı"
  boş sayfa çağrısı yaptığını hesaba katmıyorlardı) — gerçek çalıştırma
  bunları da yakalayıp düzeltti. Son olarak: fonksiyonun kendisi
  "sayfa `pageSize`'dan kısaysa dur" şekline geçici olarak geri alınıp,
  3 testin gerçekten kırmızı çıktığı (özellikle sunucu-limit-altı senaryosu
  yalnızca 1 çağrıda durup 250 satırdan yalnızca 100'ünü döndürdü)
  doğrulandı, doğru hâline geri döndürüldü.

Mobile: `flutter analyze` temiz, testler 201 → **205** (+4, yukarıdaki
yeni test dosyası — `fetchAllPages`'in kendisi, Supabase'e hiç
dokunmadan, saf bir fonksiyon olarak test ediliyor).

#### Faz 12, madde 10: Gemini varsayılan modelleri gerçekten kapatılmış ✅

Faz 11 madde 4 `text-embedding-004`/`gemini-2.0-flash`'ı varsayılan
yaptığında ikisi de gerçek, çalışan modeldi. Google'ın kendi
changelog'undan doğrulandı: `text-embedding-004` 14 Ocak 2026'da,
`gemini-2.0-flash` 1 Haziran 2026'da kapatılmış — "sadece bir API key
ekle" artık sessizce "kırık" demek, `AI_PROVIDER=gemini` kullanan
hiç kimse varsayılanları değiştirmediyse.

- **Güncel modeller** (Google'ın changelog'undan, fix anında
  doğrulandı — bu sabitlenemez, Google'ın kendi model yaşam döngüsü
  bugünkü kararlı varsayılanı da bir gün kapatacak): metin/vision/ses
  için `gemini-3.8-flash` (kararlı, GA), embedding için
  `gemini-embedding-2` (kararlı GA — `-preview` çok modlu varyantı
  DEĞİL).
- **Embedding boyutu artık dolgu/kırpma değil, doğrudan isteniyor**:
  `gemini-embedding-2` Matryoshka Representation Learning ile
  eğitilmiş — `output_dimensionality` parametresiyle çıktıyı doğrudan
  `chunks.embedding`'in sabit boyutunda (1536) istemek mümkün ve
  Google'ın kendi belgelediği önerilen boyutlardan biri (768/1536/3072),
  model bunu kendi kendine normalize ediyor. Eski `text-embedding-004`
  sabit 768 boyut üretiyordu, `_pad_embedding()` onu 1536'ya sıfırla
  DOLDURMAK zorundaydı — matematiksel olarak güvenli bir işlem
  (docstring'de kanıtlı). Yeni model 3072 (daha BÜYÜK) üretiyor;
  `_pad_embedding()` bunu doğrudan istemeden kullansaydı 1536'ya
  KIRPARDI — bu, sıfırla doldurmayla AYNI matematiksel güvenceye sahip
  değil (gerçek bilgi atılıyor). `output_dimensionality` bu ihtiyacı
  tamamen ortadan kaldırıyor; `_pad_embedding()` savunmacı bir no-op
  olarak kalıyor (gelecekte bu parametreyi desteklemeyen bir model
  gelirse sessizce eski dolgu/kırpma davranışına düşer, sert bir hataya
  değil).
- **Doğrulanmayan**: `gemini-3.8-flash`'ın görsel/ses girdisini
  (`analyze_image`/`transcribe_audio`'nun ikisi de aynı `_text_model`'i
  kullanıyor) gerçekten desteklediği Google'ın belgelerinden ayrı bir
  tabloyla teyit edilemedi — Flash ailesinin her zaman çok modlu olması
  makul bir varsayım ama doğrulanmış bir gerçek değil. Yanlışsa,
  sonuç sessiz bir hata değil, API'den net bir hata olurdu.

Backend: `ruff check` temiz (Docker'da), testler 179 → **181** (+2:
varsayılan modellerin artık kapatılmış olanlar OLMADIĞINI, ve
`generate_embeddings()`'in gerçekten `output_dimensionality=1536`
geçtiğini doğrulayan yeni testler — ikincisi geçici olarak geri alınıp
gerçekten kırmızı çıktığı doğrulanarak yazıldı).

#### Faz 12, madde 11: web'de Google sign-in kod seviyesinde çalışamaz ✅

`googleSignInAvailableProvider` yalnızca `GOOGLE_CLIENT_ID`/
`GOOGLE_SERVER_CLIENT_ID` yapılandırılmış mı diye bakıyordu — platformun
bu akışı GERÇEKTEN destekleyip desteklemediğine hiç bakmıyordu.
`google_sign_in_web`'in kendi kaynağını okudum: `authenticate()`'i
(`NativeOAuthService.signInWithGoogle()`'ın çağırdığı) web'de
`UnimplementedError` fırlatıyor, `renderButton()` kullanmaya
yönlendiriyor — DOM'a Google'ın kendi kontrol ettiği bir buton render
etmeyi gerektiren, bu uygulamanın hiç uygulamadığı, temelden farklı bir
akış. Web'de env değişkenlerini ayarlamak, dokunulduğunda HER ZAMAN
fırlayan bir buton göstermeye yetiyordu.

- **`NativeOAuthService.isGoogleAvailable`** (yeni getter): `!kIsWeb`
  gibi sabit bir platform kontrolü yerine, paketin KENDİ belirttiği
  yeteneği (`GoogleSignIn.instance.supportsAuthenticate()`) soruyor —
  böylece paketin ileride destek eklediği/kaldırdığı herhangi bir
  platformda da otomatik doğru kalıyor, burada eşleşen bir kod
  değişikliği gerekmeden.
- **`googleSignInAvailableProvider`**: artık `configured &&
  isGoogleAvailable` — ikisi birden gerekiyor.
- **Gerçek bir ek risk bulunup düzeltildi**: `isGoogleAvailable`'ı test
  yazarken, `google_sign_in_platform_interface`'in hiçbir gerçek
  implementasyon kayıt olmadığında düştüğü `_PlaceholderImplementation`'ın
  `supportsAuthenticate()`'inin `UnimplementedError` (bir `Exception`
  değil, bir `Error`) FIRLATTIĞI ortaya çıktı — bu, bu paketin hiç
  platform implementasyonu olmayan bir platformda (bugün hedeflenmeyen
  ama `google_sign_in`'in gerçekten desteklemediği Windows/Linux gibi)
  GERÇEK bir çökme riski yaratırdı. `AppLockService.isDeviceSupported()`
  ile aynı desende (`_local_auth` hatasını yutup `false` dönmek)
  savunmacı bir `catch` eklendi — `on Exception` DEĞİL, bilinçli olarak
  çıplak bir `catch`, çünkü `UnimplementedError` bir `Error`.
- **Regresyon testleri, düzeltmeden önce gerçekten kırmızı çıktığı
  doğrulanarak yazıldı**: yeni `native_oauth_service_test.dart` — ilk
  yazımda düz `expect(service.isGoogleAvailable, isA<bool>())` gerçekten
  `UnimplementedError` ile patladı (varsayılmadı, gerçek çalıştırmayla
  bulundu), bu da savunmacı `catch`'in eklenmesine yol açtı. Fix geçici
  geri alınınca test gerçekten aynı hatayla kırmızı çıktı, geri konunca
  yeşile döndü.

Mobile: `flutter analyze` temiz, testler 205 → **206** (+1, yukarıdaki
yeni test dosyası).

### CI düzeltmesi: `test_items_repository_idempotency.py` gerçek `.env`'i sessizce güveniyordu ✅

Kullanıcı GitHub'ın CI bildirimlerinden `main`'in art arda kırmızı
çıktığını fark edip bildirdi (bkz. ekran görüntüsü — CI #42-44).
İncelemede: bu oturumun kendi "Docker'da doğrulama" yöntemi
(`docker run -v "$PWD":/app ...`) **yanlışlıkla bu makinenin gerçek
`backend/.env` dosyasını da container'a mount ediyordu** —
`.gitignore`'da olduğu için git'e hiç girmiyor, ama volume mount dosya
sistemini olduğu gibi kopyalıyor. Bu, `SUPABASE_URL`'in bu makinede
HER ZAMAN gerçek bir değere sahip olması anlamına geliyordu — CI'da ise
`.env` hiç yok, `Settings.supabase_url` boş string'e düşüyor.

- **Gerçek hata**: `SupabaseRestRepository.__init__` (`app/repositories/
  items_repository.py`) `self._base_url`'i `Settings.supabase_url`'den
  (ortam/`.env`'den) alıyor. `test_items_repository_idempotency.py`'nin
  `_repo_with_transport()` yardımcı fonksiyonu bunu HİÇ override
  etmiyordu — bu makinede sessizce gerçek bir Supabase URL'i
  kullanıyordu, CI'da ise boş string kalıyordu. Boş `_base_url` ile
  kurulan istekler (`f"{self._base_url}/rest/v1/..."`) düz `/rest/v1/...`
  gibi GÖRECELİ bir path'e dönüşüyor — httpx'in cookie-jar uyumluluk
  katmanı (`_CookieCompatRequest`, stdlib `urllib.request.Request`
  üzerine kurulu) böyle bir URL'i asla parse edemiyor:
  `ValueError: unknown url type`. Bu, `MockTransport`'un handler'ı hiç
  çalışmadan, httpx'in `_send_single_request` içindeki cookie çıkarma
  adımında (Set-Cookie olsun olmasın HER yanıttan sonra koşulsuz
  çalışıyor) patlıyordu — 3 test etkilendi (2'si bu oturumun Faz 12
  madde 7'de eklediği yeni `replace_chunks` testleri, 1'i Faz 10b madde
  3'ten kalma, bu oturumdan önce yazılmış `replace_item_content` testi).
- **Bu, bu oturumun "Docker'da doğrulama = CI'ya sadık doğrulama"
  varsayımının kendisinde bir boşluk olduğunu ortaya çıkardı** — mount
  edilen dizin, git'in izlemediği yerel dosyaları da (gitignore'lu
  `.env` dahil) sessizce taşıyor. Bundan sonraki Docker doğrulamaları
  için: `.env`'siz bir kopya üzerinde çalışmak (`cp -r /app
  /tmp/clean && rm -f /tmp/clean/.env`) gerçek CI koşulunu taklit
  ediyor; bu turda böyle doğrulandı.
- **Düzeltme**: `_repo_with_transport()` artık `repo._base_url`'i sabit,
  gerçek olmayan bir değere (`"https://example.test"`) pinliyor — hangi
  makinede/ortamda çalıştırılırsa çalıştırılsın artık ortam durumundan
  bağımsız. Testlerin hiçbiri tam URL'e değil yalnızca `.path`/`.params`'a
  bakıyor, yani bu hiçbir gerçek kontrolü zayıflatmıyor.
- **Regresyon, gerçek CI hatası tekrar üretilerek doğrulandı**: fix
  geçici geri alınıp `.env`'siz temiz bir kopyada tam olarak CI'daki
  aynı 3 test aynı hatayla kırmızı çıktığı doğrulandı, geri konunca
  ikisi de (tüm suite + `.env`'siz temiz kopya) yeşile döndü.

Backend: `ruff check` temiz, testler **181/181** — bu kez gerçekten
`.env`'siz, CI'yı taklit eden temiz bir kopyada doğrulandı (yalnızca
gerçek `.env`'i mount eden eski yöntemle değil).

#### Faz 12, madde 12: not ekranında sil/favori/private/retry yok ✅

Notlar da diğer her içerik tipiyle aynı AI pipeline'ından (tag/entity/
embedding) geçiyor ve aynı favori/Private/silme aksiyonlarını
destekliyor, ama `NoteEditorScreen`'de bunlardan HİÇBİRİ yoktu —
yalnızca "koleksiyona ekle" ve "kaydet" vardı. Ayrıca işlem durumu
(pending/processing/failed) hiç gösterilmiyordu, `ItemDetailScreen`'in
aksine.

- **`NoteEditorScreen`**: `ItemDetailScreen` ile birebir aynı desende
  favori/Private toggle'ları (optimistic + hata durumunda geri alma),
  silme (onay diyaloğu + `_isDeleting` durumu), ve işlem durumu
  chip'i + `failed` durumunda "Tekrar Dene" eklendi. Yalnızca
  `_isEditing` (mevcut bir not düzenlenirken) gösteriliyor — yeni,
  henüz kaydedilmemiş bir notun ne id'si ne de işlem durumu var.
- **Faz 12 madde 8'in aynı canlı-güncelleme deseni burada da**:
  `watchItemByIdProvider`'ı `ref.listen` ediyor — arka planda işlem
  tamamlanınca (ya da başka bir cihazdan bir değişiklik gelince) ekran
  açıkken bile güncelleniyor, tıpkı `ItemDetailScreen` gibi.
- **Regresyon testleri, gerçek bir test-altyapısı hatası bulunup
  düzeltilerek yazıldı**: yeni `note_editor_screen_test.dart`
  (`NoteEditorScreen`'in hiç dedike bir testi yoktu) — silme testi ilk
  yazımda düz bir `Navigator.push` ile "No GoRouter found in context"
  hatasıyla gerçekten patladı (`context.pop()` go_router'ın uzantısı,
  Settings'in Delete Account testinin roadmap'te zaten dokümante
  edilmiş aynı gotcha'sı) — `MaterialApp.router` + gerçek bir
  `GoRouter`'a çevrilip düzeltildi.

Mobile: `flutter analyze` temiz, testler 206 → **213** (+7, yukarıdaki
yeni test dosyası).

#### Faz 12, madde 13: arama yarışı ✅

`SearchController.search()`, her çağrıda `state`'i sırasıyla
`AsyncLoading` yapıp sonra ağ/local sorgusunun (+ Faz 12 madde 5'in
private filtresinin) sonucuna set ediyordu — ama iki `search()` çağrısı
üst üste (kullanıcı hızlı yazıp fikrini değiştirdiğinde, ya da eski bir
sorgu ağ gecikmesi yüzünden yavaş kaldığında) çakıştığında, hangisinin
`state`'i EN SON yazacağı çağrıların gerçek dünyadaki (network) bitiş
sırasına bağlıydı — çağrılma sırasına değil. Daha yeni bir arama zaten
sonucunu göstermişken, daha eski/yavaş bir aramanın geç gelen yanıtı
onun üzerine yazabiliyordu; aynı şekilde kullanıcı arama kutusunu
tamamen temizlese (`clear()`) bile, hâlâ uçuşta olan eski bir `search()`
sonunda gelip boşaltılmış listeyi yeniden dolduruyordu.

- **`_searchGeneration` sayacı**: `SearchController`'a eklenen bir
  `int` alan. Her `search()` çağrısı, herhangi bir `await`'ten önce
  kendi jenerasyon numarasını (`++_searchGeneration`) yakalıyor;
  sonucu `state`'e yazmadan hemen önce sayaç hâlâ kendi numarasında mı
  diye kontrol ediyor — değilse (yani araya başka bir `search()` ya da
  bir `clear()` girmişse) kendi (artık bayat) sonucunu sessizce atıyor.
  `clear()` de kendi sayacını artırıyor, böylece hâlâ uçuşta olan eski
  bir `search()`'ün geç yanıtı, az önce temizlenmiş listeyi geri
  doldurmuyor.
- **Regresyon testleri, iki eşzamanlı `search()` çağrısının bitiş
  sırasını gerçekten kontrol ederek yazıldı**: `FakeSearchRepository`'ye
  sorgu başına `Completer` ("gate") ve sorgu başına farklı sonuç seti
  desteği eklendi, böylece test "yavaş" sorguyu önce başlatıp "hızlı"
  sorguyu sonra başlatabiliyor, sonra "hızlı"yı önce, "yavaş"ı ondan
  sonra tamamlanmaya bırakabiliyor — tam olarak üretimde olacağı gibi.
  İki yeni test: (1) yavaş/eski aramanın geç yanıtı, zaten ekranda olan
  hızlı/yeni sonucun üstüne yazmıyor, (2) `clear()` sırasında uçuşta
  olan bir arama, sonradan tamamlanınca boşaltılmış listeyi yeniden
  doldurmuyor. Düzeltme geçici olarak geri alınıp testlerin gerçekten
  kırmızıya düştüğü doğrulandı (ikisi de somut, yanlış sonuçla — "slow-
  result" beklenenin yerine, ve boş liste yerine dolu liste ile —
  başarısız oldu), sonra düzeltme geri konup yeşile döndüğü doğrulandı.

Mobile: `flutter analyze` temiz, testler 213 → **215** (+2, yukarıdaki
yeni testler), tüm suite (215 test) yeşil.

Faz 12'nin 13 maddesinin tamamı tamamlandı.

## Faz 13 — üçüncü bağımsız tarama (13 Eylül 2026)

Faz 12'nin 13 maddesi bitince, dış bir rapor beklemeden aynı disiplinle
kod tabanı bir kez daha tarandı: önceki iki denetimin bulduğu hata
*kalıpları* (reaktivite/staleness, kullanıcı filtresi eksikliği, yarış
koşulu, fail-open/fail-closed, atomik olmayan çok adımlı işlemler)
kodun geri kalanında sistematik olarak arandı.

1. ~~Item detail/not ekranı açıkken işlem tamamlanınca tag/entity'ler
   yenilenmiyor~~ ✅ — bkz. aşağıdaki alt bölüm.
2. ~~`attach_tags`/`attach_entities`'te eski iş yeni işin tag/entity'sini
   silebiliyor~~ ✅ — bkz. aşağıdaki alt bölüm.

#### Faz 13, madde 1: işlem tamamlanınca tag/entity'ler yenilenmiyor ✅

Faz 12 madde 8 ve 12, `ItemDetailScreen`/`NoteEditorScreen`'i arka
planda işlem tamamlandığında (`processingStatus` → `completed`) canlı
güncellenir hâle getirmişti — ama yalnızca `Item`'ın kendi alanları
için. `TagsRow`/`EntitiesRow`'un arkasındaki `itemTagsProvider`/
`itemEntitiesProvider`, item id'sine göre anahtarlanan tek seferlik
(`FutureProvider.autoDispose.family`) provider'lar: ekran ilk açıldığında
(item hâlâ pending/processing iken, genelde "tag yok") bir kere
çekiliyor ve sonucu önbelleğe alıyorlardı; onları yeniden çekmeye
zorlayan hiçbir yer (bir `ref.invalidate` çağrısı) yoktu. Sonuç:
kullanıcı ekranı açık tutarken AI pipeline tag/entity üretimini
tamamlasa bile, ekrandan çıkıp geri girmeden bunlar hiç görünmüyordu —
tam olarak Faz 12 madde 8/12'nin düzelttiği "işlem durumu chip'i
güncellenmiyor" hatasının bir görünmeyen kuzeni.

- **`ItemDetailScreen._applyFreshItem`** ve **`NoteEditorScreen`**'in
  `ref.listen(watchItemByIdProvider(...))` callback'i artık `previous`
  parametresini de kullanıyor: `previous.processingStatus != 'completed'
  && fresh.processingStatus == 'completed'` geçişini yakalayınca
  `itemTagsProvider(id)`/`itemEntitiesProvider(id)`'ı `ref.invalidate`
  ediyor, böylece `TagsRow`/`EntitiesRow` yeniden çekip gerçek sonucu
  gösteriyor. `previous == null` (bu ekranın gördüğü ilk emisyon) hariç
  tutuldu — o bir geçiş değil, ve `initState()`'in kendi düzeltmesi zaten
  `TagsRow`/`EntitiesRow`'un ilk çekişini bedavaya getiriyor.
- **Regresyon testleri, gerçekten kırmızıya düşürülerek doğrulandı**:
  her iki ekranın test dosyasına birer test eklendi — `FakeItemRepository
  .tagsByItemId` işlem tamamlanmadan hemen önce dolduruluyor, sonra
  `repo.updateItem(...completed)` çağrılıyor; düzeltme geçici geri
  alınınca iki test de somut "docker" bulunamadı hatasıyla kırmızıya
  düştü, geri konunca yeşile döndü.

Mobile: `flutter analyze` temiz, testler 215 → **217** (+2, yukarıdaki
yeni testler), tüm suite (217 test) yeşil.

#### Faz 13, madde 2: `attach_tags`/`attach_entities`'te eski iş yeni işin tag/entity'sini silebiliyor ✅

Aynı taramada, Faz 12 madde 7'nin `replace_chunks` için kapattığı hatanın
birebir aynısının `attach_tags`/`attach_entities`'te hâlâ durduğu
bulundu — ikisi de `replace_chunks`'ın eski (0013'teki) hâliyle aynı
şekle sahipti: `tags`/`entities` tablosuna bir UPSERT, ardından
`item_tags`/`item_entities` junction tablosunda bağımsız bir
DELETE+INSERT — üç ayrı HTTP isteği. Aynı item için iki eşzamanlı
reprocessing çalışması (kullanıcı "Tekrar Dene"ye basarken önceki
deneme hâlâ sürüyorsa, ya da backend restart-kurtarma zaten süren bir
işi tekrar tetiklerse — `replace_chunks`'ın orijinal hata gerekçesiyle
birebir aynı senaryo) varsa, eski/yavaş işin gecikmiş DELETE'i, yeni işin
az önce yazdığı tag/entity'leri silip kendi (muhtemelen bayat) setiyle
değiştirebiliyordu.

- **`replace_item_tags_for_job`/`replace_item_entities_for_job`**
  (infra/supabase/migrations/0016_replace_tags_entities_atomic.sql):
  `replace_chunks_for_job` ile birebir aynı üç parçalı çözüm — item
  başına aynı advisory lock (`hashtext(item_id::text)`, chunk'larla aynı
  kilit — aynı item'ın aynı işlem koşusu korunuyor), çağıranın job'ı hâlâ
  o item'ın en yeni `processing_jobs` satırı değilse no-op, ve tek bir
  atomik transaction (tek RPC çağrısı). İki ayrı RPC — tek bir birleşik
  çağrı değil — çünkü pipeline'da tag ve entity ekleme birbirinden
  bağımsız best-effort adımlar (`_attach_tags`/`_attach_entities`, biri
  başarısız olursa diğerini durdurmuyor); birleştirmek birinin hatasını
  diğerinin zaten commit olmuş yazmasını geri alır hâle getirirdi.
- **`SupabaseRestRepository.attach_tags`/`attach_entities`**: artık
  `job_id` alıyor ve tek bir RPC POST'u yapıyor; `processing_pipeline
  .py`'daki çağrı yerleri (`_attach_tags`/`_attach_entities`) zaten
  scope'ta olan `job_id`'yi geçiriyor.
- **Gerçek Postgres üzerinde doğrulandı** (yalnızca HTTP-mock testleriyle
  değil): pgvector/Postgres container'ında minimal bir şema (auth.users
  stub'ı + items/processing_jobs/tags/item_tags/entities/item_entities)
  kurulup 0016 migration'ı yüklendi, sonra gerçek bir SQL script'i job
  A (eski, `created_at` 10 saniye önce) ve job B'yi (yeni) aynı item için
  oluşturup B'yi önce, A'yı sonra çağırdı — B'nin tag/entity'leri (
  `{correct, fresh}` / `{"Fresh Corp"}`) A'nın gecikmiş çağrısından
  sağlam çıktı, A'nın kendi (bayat) seti hiçbir şeyin üstüne yazmadı.
  (İlk deneme aynı transaction içinde iki `processing_jobs` satırı
  ekleyip yanlışlıkla kırmızı çıktı — Postgres bir transaction boyunca
  `now()`'ı sabitliyor, iki INSERT aynı `created_at`'i aldı; gerçek iki
  ayrı istekteki doğal zaman farkını taklit etmek için açık, farklı
  `created_at` değerleriyle düzeltildi.)
- **Regresyon testleri, HTTP seviyesinde de gerçekten kırmızıya
  düşürülerek doğrulandı**: `test_items_repository_idempotency.py`'a
  4 yeni test eklendi (`replace_chunks` testleriyle aynı desende, gerçek
  bir `SupabaseRestRepository` + `httpx.MockTransport`) — düzeltme
  geçici geri alınınca 4'ü de kırmızıya düştü (biri gerçek bir
  `JSONDecodeError` ile, boş mock yanıtı eski kodun `.json()` çağırdığı
  bir yerde patladığı için), geri konunca yeşile döndü.
  `test_processing_pipeline.py`'daki 4 mevcut test de yeni `job_id`
  alanını bekleyecek şekilde güncellendi.

Backend: `ruff check` temiz (`.venv/bin/ruff`), testler 181 → **185**
(+4, yukarıdaki yeni testler) — CI'yı taklit eden temiz bir Docker
kopyasında (`.env`'siz) doğrulandı.

#### Faz 13, madde 3-4: hesap ve private erişim izolasyonu (P1-01/P1-02) ✅

`docs/requirements-audit-2026-09-13.md` denetiminin bulduğu en öncelikli
iki sorun. Faz 13'ün ilk iki maddesi kod içi bir tekrar-tarama iken, bu
ikisi dış denetimin doğrudan işaret ettiği P1 kalemleri — buradan
itibaren fazlar iç tarama yerine denetimin öncelik sırasını (P1 → P2 →
P3) izliyor.

**P1-01 — hesap değişiminde arama/sohbet verisi izole değildi**: tek bir
`ProviderScope` korunduğundan, A hesabında üretilen arama sonucu ve
sohbet mesajları B hesabına geçince bellekte kalıyordu.

- `SearchController`/`ChatController` artık `currentUserIdProvider`'ı
  dinliyor; hesap değişince (signed-out dahil) sonuçları/sohbeti
  temizliyor.
- `privateItemsRevealedProvider` (`AppLockGate`) artık hesap
  değişiminde de sıfırlanıyor — önceden yalnız arka plana atılmada
  sıfırlanıyordu.
- Koleksiyon detay sorgusu (`watchItemsForCollection`) artık yalnız
  `collectionId`'yi değil, koleksiyonun ve item'ların gerçekten
  signed-in user'a ait olduğunu da doğruluyor.

**P1-02 — private izolasyonu tek yerde ve kökte uygulanmıyordu**: RAG
retrieval'ı ve bazı erişim yolları private kaydı filtrelemiyordu.

- Yeni migrasyon: `match_chunks_hybrid`/`related_items` artık private
  item'ları SQL'de varsayılan olarak hariç tutuyor (`include_private`
  parametresi, yalnız reveal açıkken `true`) — backend bu parametreyi
  service/schema/route katmanlarında uçtan uca taşıyor;
  `rag_service` bunu hiç göndermiyor, yani private içerik LLM
  bağlamına asla giremiyor.
- Mobile: `SearchController.search()` ve `relatedItemsProvider` artık
  `privateItemsRevealedProvider`'ı backend'e `includePrivate` olarak
  iletiyor; offline TF-IDF arama ve koleksiyon detayı aynı kuralı
  savunma katmanı olarak ayrıca uyguluyor.
- `ItemByIdLoader` (deep link/route-restore erişim yolu) artık reveal
  kapalıyken private item'ı çözümlemiyor.
- `ItemDetailScreen`/`NoteEditorScreen`: zaten açık olan bir private
  item'ın ekranı artık reveal arka plana geçişte kapanınca kendini
  kilitliyor (`PrivateItemLockedView`) ve "Kilidi Aç" ile tekrar
  biyometrik/PIN doğrulaması istiyor. Kullanıcının kendi item'ını o an
  private yapması ekranı kilitlemiyor (mevcut davranış korundu).

Backend: 188 test yeşil (185 → 188, +3). Flutter: `flutter analyze`
temiz, 237 test yeşil (217 → 237, +20).

## Faz 14 — dış denetimin öncelik sırasını izleyen ikinci tur: senkron ve iş bütünlüğü (P1-03/P1-04/P1-05/P1-06) ✅

`docs/requirements-audit-2026-09-13.md`'nin Faz 2 önceliklerini
(hesap/private izolasyonundan sonraki en yüksek risk grubu) giderir.

**P1-03 — kuyruk kullanıcıya bağlı, ama işlem boyunca oturum sabit
değildi**:

- `RemoteItemDataSource.uploadFile` artık `userId`'yi tek seferde
  sabitliyor — önceden storage path'in ve item upsert'in `user_id`'si
  ayrı ayrı okunuyordu; arada hesap değişirse ikisi farklı kullanıcıyı
  gösterebiliyordu. Artık tutarsızlık RLS reddiyle güvenli şekilde
  başarısız oluyor.
- `ItemLocalDataSource`/`CollectionLocalDataSource`'a `transaction()`
  eklendi; `OfflineItemRepository`/`OfflineCollectionRepository`'deki
  yerel yazma + kuyruğa ekleme çiftleri artık tek Drift
  transaction'ında — uygulama arada kapanırsa artık kuyruksuz bir
  yerel değişiklik kalmıyor (`SyncService._pullRemote` bunu önceden
  "silinmiş" sayıp yerelden de siliyordu).

**P1-04 — atomik RPC'ler bütün AI çıktısını kapsamıyordu**: chunk/tag/
entity RPC'leri eski işi reddediyordu ama başlık/açıklama/EXIF,
duplicate flag ve item status yazımları job'a bağlı değildi.

- Yeni migrasyon: `update_item_status_for_job`,
  `update_item_fields_for_job`, `replace_item_content_for_job`,
  `mark_duplicate_for_job` — chunk/tag/entity RPC'leriyle aynı "en yeni
  iş" kilit protokolü. Artık eski iş tamamlandıktan sonra hata verirse
  item'ı `failed` yapamıyor; eski görsel analizi yeni açıklamayı
  ezemiyor.

**P1-05 — background iş kabulü ve kurtarma sınırlıydı**:

- `create_job` artık `process_item()`'ın içinde değil, `/ai/process-item`
  route handler'ında "202 accepted" dönmeden ÖNCE çağrılıyor —
  `BackgroundTasks` yalnız yanıt gönderildikten sonra çalıştığından,
  arada süreç ölürse artık iz bırakmayan değil, kurtarılabilir bir
  `processing_jobs` satırı kalıyor. `create_job` hatası da artık
  sessizce kaybolmuyor, normal başarısız istek olarak dönüyor (mobil
  taraf zaten `trigger_ai`'ı kuyruğa alıp yeniden deniyor).
- `job_recovery.py` başlangıç taraması artık yalnız `processing`
  değil, `pending` işleri de kapsıyor.

**P1-06 — URL fetch DNS rebinding açığı**:

- `url_service.py` artık güvenlik kontrolünün doğruladığı IP'ye
  doğrudan bağlanıyor (Host/SNI gerçek hostname olarak kalıyor) —
  ikinci, bağımsız bir DNS çözümlemesi kalmadığından rebinding
  saldırısının araya girecek bir penceresi yok.

**Kapsam dışı bırakılanlar** (raporda da belirtildiği gibi ayrı bir ürün
kararı gerektiriyor): tam kalıcı worker/queue, çoklu instance
lease/timeout, uzun işler için ara ilerleme bildirimi.

Backend: 197 test yeşil (191 → 197, +6), `ruff check` temiz. Flutter:
`flutter analyze` temiz, 240 test yeşil (237 → 240, +3).

## Faz 15 — MVP içerik/arama boşlukları (P2-01/P2-02/P2-04/P2-05/P2-06) ✅

`docs/requirements-audit-2026-09-13.md`'nin Faz 3 önceliklerinden bir
kısmını giderir — anahtar gerektirmeyen veya düşük riskli P2 kalemleri.

- **P2-02 (doğal dil ayrıştırma)**: `query_parser.py` tür anahtar
  kelimelerini artık uzundan kısaya doğru deniyor. Eski sözlük
  sırasında "notlar" kısa anahtar kelimesi "sesli notlar" içinde de
  `\b`-sınırlı bir kelime olarak eşleştiğinden, "sesli notlar" hiç
  denenmeden tür yanlışlıkla "note" çıkıyor ve `cleaned_query`'de
  "sesli" öbek hâlinde kalıyordu.
- **P2-05 (çıkarılan metin saklanmıyordu)**: `processing_pipeline.py`
  artık PDF ve document dallarında da `replace_item_content`
  çağırıyor (image/audio/url zaten çağırıyordu).
- **P2-04 (karma PDF'de taranmış sayfalara OCR yoktu)**:
  `document_service.py`'ye `extract_pdf_text_per_page` eklendi;
  `render_pdf_pages_to_images` artık belirli sayfa indeksleri de kabul
  ediyor. Pipeline artık yalnız metni olmayan sayfaları OCR'lıyor —
  önceden bütün belge boşsa OCR çalışıyordu, tek bir taranmış sayfa
  (ör. imzalanıp geri taranmış bir sayfa) metni olan bir PDF içinde
  sessizce kayboluyordu.
- **P2-01 (hybrid arama)**: yeni migrasyon — `match_chunks_hybrid`
  artık `keyword_rank=0` olan chunk'lara RRF keyword teriminde gerçek
  bir sıfır veriyor (önceden fiziksel tarama sırasına göre rastgele
  bir "şanslı" sıra alabiliyorlardı). `keyword_rank` artık chunk
  içeriği VE item başlığının en iyisi (`greatest`) — yalnız chunk
  metnine bakmıyor. Tag/entity'yi FTS'ye dahil etme ayrı, daha büyük
  bir iş olarak bırakıldı.
- **P2-06 (screenshot ayrımı yoktu)**: `capture_sheet.dart`'a ayrı bir
  "Choose Screenshot" seçeneği eklendi; Library'nin screenshot filtresi
  ve backend'in screenshot'a özel vision prompt'u artık bu akıştan da
  gerçekten kullanılabiliyor.

**Kapsam dışı bırakılanlar**: tag/entity'yi FTS'ye dahil etme, 30 sayfa
OCR sınırı aşıldığında kullanıcıya kısmi işleme bildirimi, summary/
language/category üretimi.

Backend: 204 test yeşil (199 → 204, +5), `ruff check` temiz. Flutter:
`flutter analyze` temiz (bu tur için özel widget testi eklenmedi —
FilePicker'ın gerçek native çağrısı test edilebilir bir soyutlama
arkasında değil; mevcut Choose Image/Take Photo/Record Audio akışlarının
hiçbiri de test edilmiyor, aynı ön koşul).

## Faz 16 — kalıcı tema tercihi ve Library'de türe göre sıralama (P3) ✅

`docs/requirements-audit-2026-09-13.md`'nin P3 (ileri aşama/geliştirme)
kalemlerinden ikisini giderir.

- **Tema tercihi artık kalıcı**: yeni `ThemePreferenceService`
  (`AppLockService` ile aynı desen — `flutter_secure_storage`; Drift'te
  henüz genel bir key-value ayarlar tablosu yok).
  `themeModeProvider` `StateProvider`'dan `AsyncNotifierProvider`'a
  taşındı — önceden yalnız bellekte tutuluyordu, uygulama yeniden
  açılınca her zaman sistem temasına dönüyordu.
- **Library'de türe göre sıralama**: `LibrarySort.byType` eklendi — tür
  adına göre alfabetik gruplama, aynı tür içinde en yeni önce. AppBar
  sıralama menüsüne "Türe göre" seçeneği eklendi.

Backend değişmedi. Flutter: `flutter analyze` temiz, 250 test yeşil
(240 → 250, +10).

## Faz 17 — RAG sohbette çok turlu bağlam (P2-03) ✅

`docs/requirements-audit-2026-09-13.md`: "önceki mesajlar backend'e
gönderilmiyor" — bir takip sorusu ("peki onun alternatifi ne?") önceki
soru/cevap hiç yaşanmamış gibi yanıtlanıyordu.

- `AiChatRepository.ask` artık conversation history'yi (yeni soru
  hariç, eskiden yeniye) backend'e gönderiyor; hata baloncukları
  history'ye dahil edilmiyor (bunlar modelin kendi sözü değil,
  uygulamanın fallback metni).
- Backend: `AskRequest.history`, `rag_service.answer_question`'a
  taşınıyor; prompt'a "Önceki konuşma" bölümü olarak ekleniyor —
  retrieval hâlâ yalnız yeni soru metniyle yapılıyor (bağlamı yalnız
  modelin "onun"/"peki o" gibi ifadeleri çözmesi için kullanıyoruz,
  embedding'i bulanıklaştırmıyoruz). En fazla son 10 tur, sunucu
  tarafında sabit.

Backend: 208 test yeşil (204 → 208, +4), `ruff check` temiz. Flutter:
`flutter analyze` temiz, 251 test yeşil (250 → 251, +1).

## P2-10 — README güncellendi ✅

`docs/requirements-audit-2026-09-13.md`'nin belirttiği eski bilgileri
düzeltir:

- Durum notu artık eski (2026-09-10) denetimin çoktan giderilmiş
  sorunlarını değil, güncel 2026-09-13 denetimini ve gerçekten kalan
  açık kalemi (canlı iki hesap Supabase/RLS kabul testi) referans
  alıyor.
- Test sayısı: 208 backend + 251 mobile (eski tek "234" sayısı
  yerine).
- Mimari diyagramda `/rag/ask` → `/ai/ask` (gerçek yol) düzeltildi;
  gerçekte hiç kullanılmayan Supabase Realtime düğümü kaldırıldı,
  yerine gerçek mekanizma (`SyncService`'in pull/poll döngüsü)
  açıklandı; `/collections/` eklendi.

Kod değişmedi (yalnız README).

## Faz 18 — uzak fetch-by-id ve signed URL retry (P2-09) ✅

`docs/requirements-audit-2026-09-13.md`'nin P2-09 kalemini giderir:
henüz bu cihaza hiç senkron olmamış bir item'a arama/RAG/related
sonuçlarından tıklamak yalnızca elde bulunan "trimmed stand-in"i
(id/title/type) gösterebiliyordu; signed URL yüklemesi başarısız
olduğunda da buton sonsuza kadar devre dışı kalıyordu.

**Uzak fetch-by-id**:

- `RemoteItemDataSource.fetchById` eklendi (zaten var olan ama hiç
  kullanılmayan `rowToItem`'ı ilk kez kullanıma sokuyor).
- `ItemToLocalCompanionX` (`local_item_x.dart`) — `Item` →
  `LocalItemsCompanion`, `toDomainItem`'ın tersi; `SyncService
  ._pullRemote`'un alan eşlemesini tekrarlamadan tek bir item'ı yerel
  önbelleğe yazabilmek için.
- `OfflineItemRepository.findById` artık önce yerelde arıyor, bulamazsa
  uzaktan çözüyor ve sonucu yerel önbelleğe yazıyor (bir sonraki bakış
  ve `watchItems`/`watchItemByIdProvider` bunu ağ isteği olmadan
  görüyor). Offline'ken veya gerçek bir hata durumunda sessizce `null`
  dönüyor — `ItemByIdLoader` ve çağıranların zaten sahip olduğu "henüz
  senkron değil" sözleşmesi korunuyor.

**Signed URL retry**: `ItemDetailScreen`'de signed URL alma artık
hatayı yakalıyor ve görünür bir "Tekrar Dene" durumuna dönüyor (görsel
için kart, dosya için buton) — önceden "hâlâ yükleniyor" ile "başarısız
oldu" ayrımı yoktu.

Backend değişmedi. Flutter: `flutter analyze` temiz, 257 test yeşil
(251 → 257, +6).

---

## Şu an neredeyiz (14 Eylül 2026 itibarıyla)

`docs/requirements-audit-2026-09-13.md`'nin önerdiği uygulama sırasının
ilk üç maddesi (hesap/private izolasyonu, senkron/iş bütünlüğü, MVP
içerik/arama boşluklarının büyük kısmı) ve P3'ün iki kalemi kapatıldı.
Son commit `ed9669e` (Faz 18, 2026-09-14). Backend 208, mobile 257 test
yeşil.

**Denetimin önerdiği sırada hâlâ açık olanlar:**

- **P1-07 — gerçek MVP kabul kanıtı yok**: iki gerçek Supabase test
  hesabıyla migrasyon/RLS/Storage izolasyonunun canlı doğrulanması;
  dokümandaki PDF + screenshot + not → "Flutter state management
  hakkında kaydettiğim şeyleri bul" → "Bunlara göre Riverpod neden
  kullanılıyor?" senaryosunun gerçek bir OpenAI key ile uçtan uca
  çalıştırılıp kaydedilmesi. Denetimin önerdiği uygulama sırasında
  4. adım.
- **P2-07 — offline arama hâlâ sınırlı**: etiketler yerel DB'ye
  senkronize edilmiyor (offline'da aranamıyor); OCR/PDF/transkript
  metni de yerel arama kapsamında değil (yalnızca not içeriği/
  açıklama/başlık/link URL'i aranabiliyor).
- **P2-08 — Export/Settings kapsamı eksik**: JSON export koleksiyon/
  üyelik, entity'ler ve OCR/AI alanlarının tamamını içermiyor;
  sorgular sayfalamasız (büyük arşivde sunucu satır limitine
  takılabilir); AI Settings hâlâ salt-okunur bir durum metni.
- **P3'ün geri kalanı**: entity türlerinin genişletilmesi (Product/
  Price/Website/Technology), chunk/source metadata (sayfa/bölüm izi,
  embedding provider/model/version), Windows hedefi ve web/macOS'ta
  eksik kamera/dosya/giriş akışları, büyük arşiv için sync/arama
  ölçek/gecikme ölçümü.

Denetimin önerdiği 5. ve son adım (export/AI Settings/type-sort/kalıcı
tema/README-demo tamamlama) kısmen bitti — type-sort ve kalıcı tema
(Faz 16) ile README (P2-10) kapandı, export/AI Settings (P2-08) hâlâ
açık.

## Faz 19 — offline arama: etiket ve OCR/PDF/transkript metni senkronu (P2-07) ✅

`docs/requirements-audit-2026-09-13.md`'nin P2-07 kalemini giderir: "Tag
cache yok. OCR/PDF/transkript yerel cache ve aramada yok." Backend'e hiç
dokunmadan tamamen mobil tarafta — bu iki alan zaten doğrudan Supabase'e
(RLS'nin kendisi zaten kapsam sınırlıyor) konuşuyor, `items` tablosunun
kendisi gibi.

- **Local Drift şeması v8→v9**: `LocalItems.extractedText` (yeni sütun,
  `item_contents.raw_text`'i yansıtıyor — taranmış bir PDF/screenshot'ın
  OCR metni, bir PDF/DOCX/TXT'nin çıkarılan gövdesi, bir ses transkripti
  veya kazınmış bir web sayfasının makale metni; görsellerde vision
  açıklaması + OCR metninin birleşimi, bkz. `processing_pipeline.py`) ve
  yeni `LocalTags` tablosu (`item_tags`/`tags`'in yansıması, `(itemId,
  name)` birincil anahtarlı — `LocalCollectionItems` gibi kendi
  `userId`'si yok, kapsamlama `LocalItems`'a join ile yapılıyor).
- **`RemoteItemDataSource`**: `fetchAllItemContentRows()` ve
  `fetchAllItemTagRows()` — `fetchAllRows()` ile aynı `fetchAllPages`
  sayfalama deseni (PostgREST'in sessiz satır sınırı kesmesin diye).
- **`SyncService._pullRemote`**: item satırlarını upsert etmeden önce
  `item_contents` toplu çekiliyor ve `extractedText` olarak companion'a
  ekleniyor; item reconciliation'ından sonra (artık kararlı olan
  `localIds` kullanılarak) `item_tags` toplu çekilip
  `ItemLocalDataSource.replaceTags()` ile yerel önbellek sıfırdan
  yeniden yazılıyor. Tag'lerin `noteContent`/diğer alanların aksine hiç
  yerel-düzenleme/`pending` durumu yok (tamamen AI pipeline'ının
  ürettiği salt-okunur veri) — bu yüzden pending-aware bir merge yerine
  bilinçli olarak baştan-sona bir replace.
- **`LocalSearchDataSource`**: TF-IDF metnine artık `extractedText` ve
  (item başına toplu tek sorguyla çekilen) tag adları da dahil;
  `_snippetFor` de `extractedText`'i excerpt kaynaklarına ekledi, yani
  bir eşleşme yalnızca OCR/PDF metninde olsa bile anlamlı bir alıntı
  gösteriliyor, başlığa düşmüyor. Sınıfın kendi docstring'i güncellendi
  — kalan bilinçli sınır artık yalnızca entity'ler ve
  `item_contents.summary` (hiçbiri yerelde yok).

Backend değişmedi. Mobile: `flutter analyze` temiz, testler 257 → **271**
(+14: `sync_service_test.dart`'a 5 — extractedText'in doldurulması/boş
kalması, tag'lerin önbelleğe alınması, sunucuda silinen bir tag'in bir
sonraki pull'da yerelden de düşmesi, item'ı olmayan bir hesap için
tag/content sorgusunun hiç atılmaması; `item_local_data_source_test.dart`'a
3 — `replaceTags`'in taze ekleme/eski tag'i düşürme/kapsam dışı id'ye
dokunmama davranışı; `local_search_data_source_test.dart`'a 4 —
extractedText'te eşleşme, extractedText'ten snippet, salt tag'te eşleşme,
tag+gövde karışık çok kelimeli sorgu, bir item'ın tag'inin başka bir
item'ın sıralamasına sızmaması).

## Şu an neredeyiz (17 Eylül 2026 itibarıyla)

P2-07 kapandı. Denetimin önerdiği sırada hâlâ açık olanlar değişmedi:

- **P1-07** — gerçek MVP kabul kanıtı yok (yukarıdaki 14 Eylül notuyla
  aynı: iki gerçek Supabase test hesabı, gerçek OpenAI key ile uçtan uca
  PDF+screenshot+not → arama → RAG senaryosu hâlâ hiç çalıştırılmadı).
- **P2-08** — Export/Settings kapsamı eksik (koleksiyon/entity/OCR
  alanları export'ta yok, sorgular sayfalamasız, AI Settings salt-okunur).
- **P3'ün geri kalanı** — entity türü genişletme, chunk/source metadata,
  Windows/web/macOS platform boşlukları, ölçek/gecikme benchmark'ı.

Backend 208, mobile 271 test yeşil.

## Faz 20 — Export kapsamının genişletilmesi ve "AI Settings" adının düzeltilmesi (P2-08) ✅

`docs/requirements-audit-2026-09-13.md`'nin P2-08 kalemini giderir: "JSON
export dosyaları, koleksiyon/üyelikleri, entities, OCR/AI alanlarının
tamamını ve private bilgisini içermiyor. Sorgular sayfalamasız... AI
Settings sadece durum metni."

- **`export_payload.dart`/`export_service.dart`**: `export_version` 1'den
  2'ye çıktı — v1'in tek taşıdığı alan (`note_content`, aslında her içerik
  tipinin yazdığı aynı `item_contents.raw_text`'ti, yalnızca notlar için
  doğru isimlendirilmişti) yerine `item_contents`'in beş alanı da
  (`raw_text`, `ocr_text`, `ai_description`, `summary`, `language`),
  entity'ler (tag'lerle aynı join deseni), `private` bayrağı ve —
  tamamen eksik olan— koleksiyonlar (`item_ids` üyelik listesiyle
  birlikte, `RemoteCollectionDataSource`'la aynı `collections`/
  `collection_items` şekli). Export bir içe-aktarma formatı değil,
  tek yönlü bir paylaş-ve-bitir JSON olduğundan v1'i geriye dönük
  taşımaya gerek yok — temiz bir yeniden isimlendirme.
- **Sayfalama**: `items`, `item_contents`, `item_tags`, `item_entities`,
  `collections`, `collection_items` sorgularının hepsi artık
  `fetchAllPages` (Faz 12, madde 9'la aynı yardımcı) ile — büyük bir
  arşiv artık PostgREST'in sessiz satır sınırına takılıp export'un
  ilk sayfadan sonrasını sessizce atlamasına yol açmıyor. Dosya arşivi
  (fotoğraf/PDF/ses dosyalarının kendisi) bilinçli olarak kapsam dışı
  bırakıldı — `export_payload.dart`'ın kendi notu bunu zaten açıkça
  söylüyor, bu turda değişmedi.
- **"AI Settings" → "AI Status"**: denetimin sunduğu iki seçenekten
  ("gerçek AI ayar kontrolleri ekle" veya "ekran adını doğru kapsamla
  eşleştir") ikincisi seçildi — AI sağlayıcısı kullanıcı başına değil
  sunucu tarafında (`backend/.env`'nin `AI_PROVIDER`'ı) seçildiğinden,
  burada gerçekten yapılandırılabilecek bir şey yok; satır zaten
  Storage/Sync gibi salt-okunur bir durum bildirimi, adı da artık bunu
  söylüyor.

Backend değişmedi (tamamen mobil — export ve Settings zaten Supabase'e
doğrudan konuşuyordu). Mobile: `flutter analyze` temiz, testler 271 →
**272** (`export_payload_test.dart` v2 şekline göre yeniden yazıldı —
5 test: item_contents'in beş alanı + entity'ler, `private` bayrağının
mevcut/varsayılan hali, koleksiyon+üyelik listesi, alanların hepsi boşken
varsayılanlar, üst düzey metadata/sayaçlar; `settings_screen_test.dart`
etkilenmedi, yalnızca bir test adı güncellendi).

## Şu an neredeyiz (17 Eylül 2026 itibarıyla, güncelleme 2)

P2-08 kapandı. Denetimin önerdiği sırada hâlâ açık olan tek şey:

- **P1-07** — gerçek MVP kabul kanıtı yok: iki gerçek Supabase test
  hesabı ve gerçek bir OpenAI key gerektiriyor, kod tarafında yapılacak
  bir şey kalmadı.
- **P3'ün geri kalanı** (ileri aşama/geliştirme, MVP zorunluluğu değil):
  entity türü genişletme (Product/Price/Website/Technology), chunk/
  source metadata (sayfa/bölüm izi, embedding model/version), Windows/
  web/macOS platform boşlukları, büyük arşiv için ölçek/gecikme
  benchmark'ı.

Backend 208, mobile 272 test yeşil.

## Faz 21 — P1-07: gerçek MVP kabul senaryosu, yerel AI ile (17 Eylül 2026)

Denetimin son kalan öncelikli maddesini kapatır — ama OpenAI key ile
değil: `docs/local-ai-provider-setup.md`'nin belgelediği `AI_PROVIDER=local`
yolu bu makinede gerçekten kuruldu (Ollama + `llama3.2`/`nomic-embed-text`/
`llava`, hepsi bu oturumda indirilip gerçek backend kodu üzerinden —
sahte transport değil — tek tek doğrulandı) ve P1-07'nin gerektirdiği
"gerçek AI" şartını ücretsiz, bulut key'i olmadan karşıladı.

**Ortam notu — ilgisiz bir Homebrew/macOS hatası bulunup düzeltildi**:
Ollama kurulumundan bağımsız, önceden var olan bir sorun: bu makinedeki
Homebrew `python@3.12` (3.12.14) bottle'ı, `pyexpat`'ı macOS 26.2'nin
sistem `libexpat`'ında olmayan bir sembolle (`_XML_SetAllocTrackerActivationThreshold`)
derlenmiş — `pypdf`'in (dolayısıyla `document_service.py`'nin, dolayısıyla
tüm `app.main`'in) import edilmesini `dlopen` hatasıyla çöktürüyordu.
Backend'i `DYLD_LIBRARY_PATH=/opt/homebrew/opt/expat/lib` ile başlatmak
Homebrew'in kendi (güncel) expat'ını öne alıp sorunu çözüyor — bu proje
koduyla ilgisiz, yalnızca bu makinenin `backend/.env`'i dışında bir ortam
notu, kalıcı bir kod değişikliği gerektirmiyor. Ayrıca fark edildi:
arka planda kalıcı bir süreç başlatmak için `nohup ... & disown` yerine
yalnızca `... & disown` kullanmak gerekiyor — bu makinede `nohup` her
nedense `DYLD_*` ortam değişkenlerini siliyor, `disown` tek başına
silmiyor.

**Doğrulama yöntemi**: mobil UI üzerinden tıklama değil — gerçek
Supabase Auth/Postgres/Storage'a ve gerçek backend'e doğrudan HTTP
istekleriyle konuşan tek seferlik bir Python scripti (bu oturuma özel,
depoya commit edilmedi). Sebep: bu makinede `System Events`/Accessibility
izni kısıtlı (`osascript` ile pencere koordinatı okumak "yardımcı
erişime izin verilmiyor" hatası veriyor — Faz 11'in Face ID otomasyonunda
belgelenen aynı sınırın bir başka görünümü), yani simülatöre programatik
dokunuş göndermek bu ortamdan mümkün değildi. Bunun yerine mobil
uygulamanın zaten yaptığı şeyin ta kendisini — aynı Supabase REST/Storage
uçları, aynı `/ai/process-item`/`/search/`/`/ai/ask` endpoint'leri,
aynı RLS/JWT modeli — dışarıdan tetikleyip sonuçlarını denetlemek, arayüz
etkileşimini simüle etmeye çalışmaktan daha güvenilir bir doğrulama.

**Senaryo ve sonuç — 18/18 kontrol geçti**:

1. İki gerçek test hesabı oluşturuldu (`/auth/v1/signup`, e-posta
   doğrulaması bu projede kapalı — anında `access_token` dönüyor).
2. Hesap A'ya doğrudan Supabase'e (mobil'in kendi yaptığı gibi) bir not
   ("Flutter'da state management... Riverpod kullanıyoruz çünkü..."),
   gerçek metin içeren bir PDF (PyMuPDF ile üretildi) ve "RIVERPOD STATE
   MANAGEMENT" yazan gerçek bir screenshot (Pillow ile üretildi) eklendi.
3. Üçü için de `/ai/process-item` çağrıldı — **gerçek Ollama** üzerinden
   embedding + (screenshot için) vision/OCR çalıştı, üçü de
   `processing_status: completed`'e ulaştı.
4. Dokümanın MVP cümlesiyle birebir aynı sorgu — **"Flutter state
   management hakkında kaydettiğim şeyleri bul"** — `/search/`'e
   gönderildi: üç item'ın üçü de sonuçlarda çıktı.
5. **"Bunlara göre Riverpod neden kullanılıyor?"** `/ai/ask`'e soruldu:
   gerçek bir LLM (yerel `llama3.2`) cevabı geldi ("Riverpod kullanılıyor
   çünkü compile-time güvenlik sağlıyor, test edilebilirliği
   InheritedWidget'a göre çok daha kolaylaştırıyor...") ve 3 kaynakla
   (kayıtlı chunk'lar) birlikte.
6. **RLS izolasyonu**: hesap B ile aynı işlemler tekrarlandı — B'nin hiç
   item'ı görünmüyor, A'nın notunu id'siyle doğrudan çekmeye çalışınca da
   boş dönüyor (Postgres RLS, backend/uygulama kodu değil), B'nin aynı
   sorguyla araması da A'nın hiçbir sonucunu getirmiyor.
7. Temizlik: Storage'daki dosyalar, `items` satırları ve iki test hesabı
   da (admin API ile) silindi — canlı projede kalıcı bir iz bırakmadı.

**Kapsam dışı kalan (dürüstçe belirtilmeli)**: bu turda mobil
uygulamanın kendi arayüzünden gerçek bir dokunuşla dosya seçme/kaydetme/
açma denenmedi — yukarıdaki Accessibility kısıtı yüzünden. Simülatörde
uygulama açılıp gerçek bir Supabase oturumuyla render olduğu ekran
görüntüsüyle doğrulandı (ayrı, önceden var olan bir geliştirici
hesabıyla), ama bu turun asıl kanıtı arayüz katmanından değil,
mobilin zaten kullandığı aynı API/RLS/AI zincirinin dışarıdan
tetiklenmesinden geliyor. Denetimin "kaynak dosyalarını mobilde aç"
maddesi tam anlamıyla ancak gerçek bir dokunuşla (kullanıcı elleriyle,
ya da Accessibility izni olan bir makineden) tamamlanabilir.

Kod değişmedi (bu tur tamamen doğrulama). Backend 208, mobile 272 test
hâlâ yeşil, hiçbiri bu turdan etkilenmedi.

## Şu an neredeyiz (17 Eylül 2026 itibarıyla, güncelleme 3)

Denetimin (`docs/requirements-audit-2026-09-13.md`) önerdiği tüm
öncelikli maddeler (P1-01 → P1-07, P2-01 → P2-10) artık kapalı — P1-07
gerçek veriyle, gerçek AI ile, gerçek RLS izolasyonuyla doğrulandı.
Geriye yalnızca **P3'ün ileri-aşama/geliştirme kalemleri** kaldı (MVP
zorunluluğu değil): entity türü genişletme, chunk/source metadata,
Windows/web/macOS platform boşlukları, büyük arşiv için ölçek/gecikme
benchmark'ı — ve mobil arayüzün kendisinden elle bir dokunuş turu
(yukarıdaki kapsam-dışı notu).

## Faz 22 — P3: entity türü genişletme (Product/Price/Website/Technology) ✅

`docs/requirements-audit-2026-09-13.md`'nin P3 kaleminin ilki: entity
extraction yalnızca person/place/organization/date tanıyordu — bir satın
alma veya bir araçtan bahseden bir not, o şeyin kendisini yapılandırılmış
bir entity olarak değil, yalnızca serbest metin bir tag olarak
işaretleyebiliyordu.

- **`0020_entity_types_extend.sql`** (yeni migrasyon): `entities.type`
  check constraint'i `product`/`price`/`website`/`technology` ile
  genişletildi — eski dört değer yeni sekizin bir alt kümesi olduğundan
  düz bir `DROP CONSTRAINT` + `ADD CONSTRAINT`, veri kaybı/dönüşüm yok.
- **`entity_extraction_service.py`**: `_VALID_TYPES` sekize çıktı,
  prompt yeni dört türü de örnekleriyle birlikte istiyor.
- **Mobile**: `EntityType` enum'a dört yeni değer, `EntitiesRow`'un
  tür→ikon eşlemesine karşılıkları (`shopping_bag_outlined`,
  `sell_outlined`, `link_outlined`, `memory_outlined`).
- **Canlı veritabanına uygulanmadı**: bu oturumun Supabase projesine
  doğrudan bağlantısı yalnızca `anon`/`service_role` API key'leri
  üzerinden (PostgREST) — DDL (`ALTER TABLE`) çalıştırmak için gereken
  doğrudan Postgres şifresi veya bir Supabase Management API token'ı
  elde yok. Migrasyon dosyası `apply_migrations.sql`'in izlediği aynı
  yolla (Supabase Dashboard → SQL Editor'a yapıştırıp çalıştırma) elle
  uygulanmalı — bu proje için önceki turlarda da migrasyonların canlıya
  uygulanma şekli hep bu oldu.

Backend: `ruff check` temiz, testler 208 → **209** (+1, dört yeni türü
ayrıştırma testi). Mobile: `flutter analyze` temiz, testler 272 →
**273** (+1, dört yeni tür için chip/ikon testi).

## Faz 23 — P3: chunk'lara sayfa numarası metadata'sı (yalnızca PDF) ✅

`docs/requirements-audit-2026-09-13.md`'nin P3 kaleminin ikincisi:
`chunks.metadata` (jsonb, 0001_init.sql'den beri var) hiç kullanılmıyordu
— hangi chunk'ın kaynak belgenin hangi sayfasından geldiği hiçbir yerde
tutulmuyordu.

- **`chunking_service.chunk_pages()`** (yeni fonksiyon, `chunk_text()`'e
  dokunulmadı): sayfa listesi alıp her sayfayı **bağımsız** chunk'lıyor,
  her chunk'ı 1-tabanlı sayfa numarasıyla etiketliyor. Bilinçli tasarım
  kararı: sayfa sınırları arasında chunk paketlemiyor (iki kısa sayfayı
  `chunk_text()` tek bir chunk'ta paketlerdi) — bunun bedeli bazı kısa
  sayfalı belgelerde biraz daha fazla/küçük chunk, karşılığında bir
  chunk'ın sayfa numarası her zaman **kesin**, konuma dayalı bir
  yaklaşıklık değil. Offset/karakter-pozisyonu eşlemesiyle sayfalar arası
  paketlemeyi korumak da mümkündü ama `chunk_text()`'in overlap mantığının
  ürettiği metni orijinal kaynakta arayıp bulmaya dayanan kırılgan bir
  çözüm olurdu — bu basitlik/doğruluk takası tercih edildi.
- **`processing_pipeline.py`**: yalnızca `pdf` tipi için — tek gerçek
  "sayfa" kavramı olan içerik türü — `_ocr_missing_pdf_pages()`'in dönüşü
  artık birleştirilmiş tek string değil, sayfa başına bir liste (diğer
  çağıran, `item_contents.raw_text`, kendi birleştirmesini kendi yapıyor).
  Not/ses/URL/görsel gibi diğer her tip hâlâ düz `chunk_text()`
  kullanıyor, `metadata` onlarda hep `{}` kalıyor.
- **Canlıda doğrulandı**: gerçek 2 sayfalı bir PDF (PyMuPDF ile üretildi)
  gerçek backend + gerçek yerel Ollama üzerinden işlendi — Supabase'in
  `chunks` tablosunda `chunk_index=0` → `{"page_number": 1}`,
  `chunk_index=1` → `{"page_number": 2}` olarak doğru yazıldığı
  görüldü, sonra test verisi temizlendi.

**Kapsam dışı bırakılan** (P3'ün aynı maddesinin ikinci yarısı, ayrı bir
ürün kararı gerektiriyor): embedding provider/model/version'ın chunk
başına saklanması ve `AI_PROVIDER` değişince eski embedding'lerin
yeniden işlenmesi için bir reindex mekanizması — bunlar "otomatik mi
elle mi tetiklenecek" sorusuna önce bir cevap gerektiriyor.

Backend: `ruff check` temiz, testler 209 → **213** (+4:
`chunk_pages()`'in kendi 4 birim testi; 3 mevcut PDF testi de yeni
sayfa-başına-chunk davranışına ve `page_number` metadata'sına göre
güncellendi). Mobile değişmedi (bu tamamen backend/chunk üretimi).
