**LifeSearch — gereksinim karşılaştırması ve eksik özellikler raporu**

Tarih: **13 Eylül 2026**  
İncelenen proje: `/Users/ilkgulseraydundar/Projects/LifeSearch`  
İncelenen commit: **87847d2** — 13 Eylül 2026. İnceleme başında çalışma ağacı temizdi.  
Gereksinim kaynağı: Kullanıcının paylaştığı 71 maddelik LifeSearch metni; karşılaştırma mevcut uygulama kaynakları, SQL migrasyonları ve testleri üzerinden yapıldı.

Proje önceki incelemeye göre belirgin ilerlemiş: temel içerik akışları, AI, offline katman ve ileri arama özelliklerinin çoğunun kod karşılığı var. **Buna rağmen “bütün gereksinimler tamamlandı” veya “MVP kabulü geçti” sonucu çıkarılamıyor.** En önemli kalan sorunlar hesap değişiminde veri izolasyonu, private içeriklerin farklı ekranlardan erişimi ve AI işlerinin bütün çıktılarında güncel sürüm güvencesi.

71 ana madde için sınıflandırma: **37 Tam, 33 Kısmi, 1 Doğrulanmadı.** Bu sayım bir tamamlanma yüzdesi değildir: doküman aynı özelliği hem ayrıntı maddelerinde hem fazlarda tekrar ediyor. Tamamen yapılmamış alt özellikler aşağıda ayrıca listelendi; ana maddelerin çoğu birden fazla alt özellik içeriyor.

“Tam”, ilgili maddenin temel kod kapsamının mevcut olduğunu ifade eder; gerçek Supabase/AI ortamında sorunsuz çalıştığına dair genel bir garanti değildir. “Kısmi”, eksik bir alt akış veya gösterilebilir bir davranış hatası olduğunu; “Doğrulanmadı”, kabul sonucuna dair yeterli çalışma kanıtı bulunmadığını ifade eder. İleri aşama ve opsiyonel istekler ayrıca işaretlendi; cihaz üzerinde neural embedding, MVP eksikliği olarak değerlendirilmedi.

**Çalıştırılan doğrulamalar**

| Kontrol | Sonuç | Sınır |
|---|---|---|
| Backend `pytest -q -p no:cacheprovider` | **185 geçti**, 6 uyarı | Gerçek AI/Supabase çağrısı yapılmadan mevcut test takımı. |
| Backend `ruff check --no-cache .` | **Geçti** | Kaynak kod kalite kontrolü. |
| Flutter `flutter analyze --no-pub` | **Sorun yok** | Güncel mobil kaynağın geçici kopyasında. |
| Flutter `flutter test --no-pub --reporter expanded` | **217 geçti** | Mevcut unit/widget testleri; cihaz integration_test dahil değil. |
| Denetim için eklenen 3 odaklı regresyon kontrolü | **3 başarısız; bulgular yeniden üretildi** | Yalnız geçici kopyaya eklendi; aşağıdaki P1-01/P1-02 sorunlarını gösteriyor. |
| Türkçe sorgu ayrıştırıcısı | **sesli not → note hatası yeniden üretildi** | Gerçek parser fonksiyonu; dış servis yok. |
| Canlı Supabase migrasyon/RLS, gerçek AI, cihaz kabul akışı | **Çalıştırılmadı** | Kod varlığı ile canlı kurulum birbirinden ayrı değerlendirildi. |

Mevcut test takımındaki toplam **402 başarılı test**, ek denetim kontrollerinin ortaya çıkardığı hataları kapsamıyor. Backend uyarıları ağırlıkla PyMuPDF/SWIG deprecation kayıtları ve Gemini SDK istemcisi kapanışında await edilmeyen coroutine uyarısı; test sonucu başarısız değil.

Flutter doğrulamaları `/private/tmp/lifesearch-audit-20260913-tkg2e18v/mobile` kopyasında, `.env.example` ile yapıldı. Uygulama kaynakları değiştirilmedi. Ek kontrollerin [kodunu](audit-evidence/2026-09-13/audit_repro_test.dart) ve [hata çıktısını](audit-evidence/2026-09-13/repro-results.log) rapor eki olarak inceleyebilirsin. Bu kontroller gerçek controller/provider mantığını çalıştırıyor; ağ sınırlarında projenin mevcut fake repository’lerini kullanıyor.

**Önceki incelemeye göre giderilen veya belirgin iyileştirilen noktalar**

| Önceki eksik | Güncel durum | Kanıt |
|---|---|---|
| Not upsert için `item_contents.item_id` benzersizliği eksik | **Giderildi:** 0012 migrasyonu duplicate temizliği ve UNIQUE ekliyor. Canlı DB’ye uygulanmış olması ayrıca gerekli. | [0012][unique] |
| Kuyruk ve arama geçmişi kullanıcıya bağlı değil | **Temel sorun giderildi:** user_id, migration backfill, kullanıcı bazlı okuma ve kuyruk boşaltma var. İşlem içi oturum açıkları aşağıda sürüyor. | [Yerel DB][db], [sync][sync] |
| Home/Library eski hesap stream’ine bağlı kalabiliyor | **İyileştirildi:** auth değişimini izleyen currentUserId bağımlılığı var. Search/Chat aynı düzeltmeyi almamış. | [Item provider](../mobile/lib/features/item/presentation/providers/item_providers.dart) |
| Hesap silmede anahtar kontrolünden önce dosya siliniyor | **Eksik anahtar senaryosu giderildi:** ön kontrol dosya silmeden önce. Ağ/Storage/Admin kısmi başarısızlıkları için yine telafi/temizlik gerekebilir. | [Account service][account] |
| Chunk yenilemede duplicate/race | **Önemli ölçüde giderildi:** UNIQUE ve iş kimlikli atomik RPC. Diğer çıktı ve durum yazımları henüz aynı kapsamda değil. | [0015][atomic] |
| Tags/entities eski job tarafından silinebiliyor | **Kod düzeyinde giderildi:** 0016 güncel işe bağlı atomik RPC’leri ekliyor. SQL’nin gerçek eşzamanlılık testi eksik. | [0016][tags] |
| AI tetikleme hatası sessizce kayboluyor | **Giderildi:** trigger_ai kuyruğu ve tekrar deneme var. | [Sync service][sync] |
| İş tamamlandığında ekran yenilenmiyor | **İyileştirildi:** sınırlı polling, canlı item akışı; completion sonrası tags/entities invalidate. Uzun işler hâlâ yaklaşık bir dakikadan sonra otomatik izlenmiyor. | [Detay][detail], [not][note] |
| Arama/RAG kaynak kartı eksik Item açıyor | **Yerel kayıt varsa giderildi:** tam item ile ekran güncelleniyor. Yeni cihaz/henüz senkronize olmamış kayıtta ağdan çözümleme yok. | [Detay][detail] |
| Notta silme/favori/private/retry kontrolleri yok | **Giderildi:** not editörüne eklenmiş. | [Not ekranı][note] |
| Yalnız PDF belge desteği var | **Giderildi:** DOCX/TXT dosya seçimi ve çıkarımı eklenmiş. | [Capture][capture], [pipeline][pipeline] |
| Taranmış PDF için OCR yok | **Kısmen giderildi:** metinsiz PDF’ye OCR var; karma PDF ve 30 sayfa sınırı sürüyor. | [Pipeline][pipeline] |
| URL güvenliği ve kontrolsüz indirme | **İyileştirildi:** public IP, redirect, içerik tipi ve 5 MB sınırı var. DNS çözümleme/bağlantı arasındaki açık sürüyor. | [URL service][url] |
| Paragraf geçişinde overlap kayboluyor | **Giderildi:** flush öncesi overlap alınıyor. | [Chunker][chunker] |
| Geçen ay/hafta filtreleri yanlış pencere kullanıyor | **Giderildi:** takvim başlangıcı ve önceki dönemin bitişi hesaplanıyor. sesli not tür ayrımı ayrı hata. | [Parser][parser] |
| Geç gelen arama sonucu yeni sorguyu eziyor | **Normal arama/clear akışında giderildi:** generation kontrolü var. Auth değişimi bu generation’ı sıfırlamıyor. | [Search controller][search_state] |
| SDK DEBUG kayıtları içerik/token açığa çıkarabilir | **İyileştirildi:** OpenAI/httpx/httpcore log seviyeleri sınırlandırılmış. | [Logging][logging] |

Ayrıca Gemini ve yerel AI provider, LLM reranking, daha gelişmiş yerel TF-IDF arama, öğe bazında private işareti, analytics, native Google/Apple giriş kodu ve macOS/web hedefleri mevcut. Bunların platform/kurulum sınırları ana matriste açıklandı.

**Öncelikli kalan hatalar ve tamamlanma koşulları**

**P1-01 — Hesap değişiminde arama/sohbet verisi ve bazı yerel sorgular izole değil.**

`SearchController` ve `ChatController` auth değişimini izlemiyor; global provider durumları logout ile temizlenmiyor. Gerçek provider kontrollerinde A hesabında üretilen arama sonucu ve iki sohbet mesajı, oturum B’ye geçtikten sonra bellekte kaldı. Uygulamanın tek ProviderScope’u korunduğundan ekranı kapatmak bunları kendiliğinden temizlemiyor. Private reveal bayrağının da hesap değişimiyle sıfırlanması yok. Ayrıca koleksiyon detay sorgusu yalnız collection_id ile filtreliyor; koleksiyonun ve item’ın current user sahipliğini yerel sorguda doğrulamıyor. Önceki hesabın bilinen koleksiyon ID’siyle detay rotası ayrı bir erişim yolu oluşturuyor. [Search state][search_state], [Chat state][chat_state], [koleksiyon sorgusu][collection_query].

Tamamlanma koşulu: tüm kullanıcıya ait provider state’i kullanıcı kimliğine bağlı olsun; logout/switch anında sonuçlar, sohbet, filtreler ve reveal durumu temizlensin; geç gelen eski istekler atılsın; yerel detay/üyelik sorguları current user ile sınırlandırılsın. İki hesap arasında geçiş testi arama, sohbet, koleksiyon ve devam eden isteği kapsasın.

**P1-02 — Private işareti bütün erişim yollarında korunmuyor.**

Ana listelerde ve yerel kaydı bulunan arama sonuçlarında gizleme var. Ancak RAG backend’i private kaydı retrieval’dan çıkarmıyor ve chat katmanında biyometrik açma kontrolü yok. Koleksiyon detayları private filtre uygulamıyor. ItemByIdLoader/doğrudan detay rotası da private item açmadan önce doğrulama istemiyor; açık detay ekranı, bütün uygulama kilidi kapalıysa arka plandan dönüşte görünmeye devam edebiliyor. `_hidePrivateResults` yalnız yerelde bilinen private ID’leri çıkarıyor: henüz senkronize olmamış private kayıt, arama sonucunda snippet ile gösterilebiliyor. Son durum odaklı testte yeniden üretildi. Bu bulgu, başka kullanıcının Supabase RLS’sinin aşılması değil; aynı hesabın cihazındaki private erişim sözleşmesinin eksik uygulanmasıdır. [Gizlilik filtresi][privacy], [RAG][rag], [router][router], [koleksiyon][collection_query].

Tamamlanma koşulu: private erişim kararını tek yerde uygula; detay, koleksiyon, duplicate/related, search ve chat bunu kullansın. Açılmamış private kayıtlar LLM bağlamına girmesin. Kaydın private durumu bilinmiyorsa içerik gösterilmeden doğrulansın. Ekran açıkken yeniden kilitlenme de test edilsin.

**P1-03 — Kuyruk kullanıcıya bağlı, fakat işlem boyunca oturum sabit değil.**

Kuyruk her entry öncesi kullanıcı kontrol ediyor; remote servisler ise her alt çağrıda canlı oturumu okuyor. Örneğin dosya yüklenirken kullanıcı değişirse storage yolu eski kullanıcıyla, sonraki item upsert yeni kullanıcıyla oluşturulabiliyor. Pull akışlarında da bütün await sınırları boyunca aynı kullanıcı/token garantisi yok. Yerel item yazma ve kuyruğa ekleme ayrı await’ler: arada uygulama kapanması kuyruksuz bir yerel değişiklik bırakabilir. Sonraki pull yalnız pending queue ID’lerini koruduğu için böyle bir kaydın kaybolma/ezilme riski var. [Sync][sync], [upload][upload], [offline repository][items].

Tamamlanma koşulu: işlem başında user/token/session generation sabitle; kullanıcı değişince eski işlemin devamını kes. Yerel mutation + enqueue aynı Drift transaction’ında olsun. Aynı item’a bağlı işlemlerde başarısız önceki yazı ile sonraki yazının sırası ve yeniden denemede eski verinin yeniyi ezmesi test edilsin.

**P1-04 — Atomik RPC’ler bütün AI çıktısını kapsamıyor.**

Chunk, tag ve entity RPC’leri eski işi reddediyor. Buna karşılık `replace_item_content`, başlık/açıklama/EXIF, duplicate flag ve item status yazımları job_id’ye bağlı değil. Yeni iş tamamlandıktan sonra eski iş hata verirse item `failed` yapılabiliyor; eski görsel analizi yeni açıklamayı ezebiliyor. Ayrı RPC’ler tek bir işlem neslinin bütün çıktıları için transaction sağlamıyor. Yeni iş başlaması, RPC’nin “en yeni iş” sorgusuyla aynı kilit protokolünde değil. [Pipeline status][job_status], [content repository][content], [0015][atomic], [0016][tags].

Tamamlanma koşulu: item üzerinde processing generation/job sahipliğini bütün yazılara uygula; eski işin başarı/hata durumu güncel item’a yazılamasın. İş başlatma ve sonuç yayınlama aynı sürüm protokolünü kullansın. A eski/B yeni işleri ters sırada bitiren gerçek PostgreSQL concurrency testi yapılsın.

**P1-05 — Background iş kabulü ve kurtarma hâlâ sınırlı.**

`202 accepted` verildikten sonra iş FastAPI BackgroundTasks içinde yaratılıyor; kalıcı bir tüketici yok. `create_job` ana try/finally bloğundan önce, dolayısıyla ilk DB hatası normal failed/status akışına girmiyor. Başlangıç taraması yalnız `processing` işleri failed yapıyor; `pending` işler ve hiç yazılamamış işler kapsam dışı. Kurtarma service-role anahtarı ve tek backend instance varsayımına bağlı. Progress pratikte 0/100; mobil polling 5 saniye × 12 denemeyle sınırlı. 30 sayfalık OCR gibi uzun bir işin sonucu açık ekrana kendiliğinden ulaşmayabilir. [Pipeline][pipeline], [recovery][recovery], [sync][sync].

Tamamlanma koşulu: accepted dönmeden kalıcı iş kaydı oluşsun; ilk hata da izlenebilsin; pending/processing işler için lease/timeout ve yeniden deneme stratejisi tanımlansın. Uzun işlerde ara ilerleme ve tamamlanma bildirimi olsun. Kalıcı worker/queue bu gereksinimleri karşılamanın bir yolu; belirli bir ürün zorunlu değil.

**P1-06 — URL fetch için DNS rebinding açığı açık bırakılmış.**

URL ve redirect kontrolleri gelişmiş olsa da güvenlik kontrolündeki DNS cevabı ile httpx bağlantısındaki ikinci DNS cevabı birbirine sabitlenmiyor. Bu sınır kaynak dosyada da açıkça belirtilmiş; çalışan bir saldırı bu denetimde denenmedi. [URL service][url]. Tamamlanma koşulu: doğrulanan IP’ye bağlanan transport veya aynı sınırı garantileyen dış ağ erişim politikası ve buna yönelik test.

**P1-07 — Madde 66 için gerçek kabul kanıtı yok.**

Mevcut integration_test gerçek ekran/router katmanını çalıştırıyor, fakat auth/repository/backend sınırları fake. Login → Add Note → Search Note → Open Result zincirinin tamamı yok; PDF/screenshot/gerçek RAG eklenince gereken kabul akışı da yok. HTTP MockTransport testleri SQL RPC çağrısının şeklini kontrol ediyor; SQL transaction/RLS davranışını çalıştırmıyor. [Integration suite][integration], [CI][ci].

Tamamlanma koşulu: temiz test ortamında 0001–0016 migrasyonlarını uygula; iki gerçek test kullanıcısıyla RLS/Storage izolasyonunu kontrol et; dokümandaki PDF+screenshot+not ve Riverpod sorulu senaryoyu gerçek AI ile çalıştır; kaynak dosyalarını mobilde aç; yeniden başlatma/offline→online ve iş retry adımlarını kaydet.

**Kapsamı eksik veya tamamlanması gereken ürün özellikleri**

| Öncelik / alan | Şu anda eksik veya sınırlı olan | Tamamlanması gereken |
|---|---|---|
| P2-01 · Hybrid / alaka | Keyword eşleşmesi 0 olan chunk’a bile RRF keyword sırası katkısı var. Başlık/tag/entity FTS’ye dahil değil. Alakasız içerik için eşik yok; LLM reranker adayları yeniden sıralıyor, ilgisizleri reddetmesi istenmiyor. | Gerçek keyword aday kümesini ayır; metadata aramasını ekle; arama/RAG için alaka kabul eşiği ve örnek sorgu değerlendirmesi yap. |
| P2-02 · Doğal dil | `sesli not` ve `sesli notlar` → `note`, cleaned query `sesli`. Takvim UTC; kullanıcının yerel gün sınırı ayrıca taşınmıyor. | Uzun ve özel tür ifadelerini önce eşleştir; ses/PDF/not birleşimlerini test et; timezone kararını açıklaştır. |
| P2-03 · RAG bağlamı | Önceki mesajlar backend’e gönderilmiyor. Aynı belgeden sadece en iyi tek chunk; numaralı atıflar cevap sonrası doğrulanmıyor. | Çok turlu soruyu bağlama göre yeniden yaz veya history gönder; aynı belgeden ilgili birden çok parçayı al; kaynak indekslerini doğrula. |
| P2-04 · PDF bütünlüğü | Bir sayfada metin varsa diğer taranmış sayfalara OCR uygulanmıyor. 30 sayfa üzeri tarama sessizce kısmi indeksleniyor. | Sayfa başına çıkarım/OCR; limit varsa kullanıcıya kısmi işleme durumu ve tamamlanabilir devam akışı. |
| P2-05 · Çıkarılmış metin / metadata | PDF/DOCX/TXT raw_text item_contents’a yazılmıyor. summary/language alanları boş; category üretimi/şeması yok. | Türlerden bağımsız içerik saklama ve metadata üretme adımı ekle; detayda kullanılan alanları bağla. |
| P2-06 · Screenshot | Picker daima image kaydediyor. Screenshot SQL ve backend desteği olmasına rağmen normal kullanıcı akışı bu türü üretmiyor. | Kullanıcı seçimi veya güvenilir sınıflandırma; screenshot filtresi için gerçek kayıt testi. |
| P2-07 · Offline arama | Tag cache yok. OCR/PDF/transkript yerel cache ve aramada yok. TF-IDF eşanlam/paraphrase çözmez. | Önce MVP’de istenen etiketleri cache/search’e ekle; indirilen metinlerin yerel indeksini genişlet. Cihaz embedding modeli sonraki araştırma. |
| P2-08 · Export / Settings | JSON export dosyaları, koleksiyon/üyelikleri, entities, OCR/AI alanlarının tamamını ve private bilgisini içermiyor. Sorgular sayfalamasız; çok kayıtlı arşivde sunucu satır limitine takılabilir. AI Settings sadece durum metni. | Export kapsamını açık sözleşme yap ve eksik metadata/ilişkileri ekle; pagination; gerekiyorsa dosya arşivi. Gerçek AI ayar kontrolleri veya ekran adını doğru kapsamla eşleştir. |
| P2-09 · Detay açma / hata | Henüz cache’te olmayan kaynak için tam item’ı uzaktan çözümleme yok. Signed URL yükleme hatası bazı akışlarda görünür retry durumuna dönmüyor. | Repository üzerinden güvenli fetch-by-id/cache; dosya bağlantısı için loading/error/retry. |
| P2-10 · Dokümantasyon / demo | README test sayısı, açık hata listesi, Realtime şeması ve `/rag/ask` yolu eski; gerçek yol `/ai/ask`. Demo GIF/video yok. | README’yi güncel davranış ve 402 mevcut testle eşleştir; canlı kabul demosunu ekle. |
| P3 · Entity türleri — ileri aşama | Product/Price/Website/Technology yok; mevcut person/place/organization/date yalnız ilk 2000 karakter üzerinden çıkarılıyor. | Şema/provider/parser/UI türlerini genişlet; uzun belgelerde kapsam politikasını belirle. |
| P3 · Library / tema | Türe göre sıralama yok; tema tercihi kalıcı değil. | Type sort ekle; tema seçimini sakla. Üç tema modunun kendisi zaten var. |
| P3 · Chunk / source metadata — geliştirme | `metadata={}`; page_number/section, embedding provider/model/version bilgisi yok. | Sayfa/bölüm izini taşı. Sağlayıcı değişiminde eski vektörlerin yeniden indekslenmesini yönet; eşit boyut farklı modelleri aynı anlamsal uzaya getirmez. |
| P3 · Platformlar — sonraki aşama | Windows hedefi yok; web dosya/görsel/kamera/ses ve Google/Apple giriş akışları tamamlanmamış. macOS kamera yok. | Platforma uygun upload/auth/capture ve gerçek cihaz kabulü. Linux orijinal hedef listesinde yok, eksik sayılmadı. |
| P3 · Ölçek / ölçüm — üretim iyileştirmesi | Sync tam arşiv çekiyor; not başına ayrı içerik isteği var. Hybrid bütün kullanıcı chunk’larını rank ediyor. Gerçek gecikme/arama kalitesi ölçümü yok. | Büyük arşiv benchmark’ı, artımlı sync, batch içerik çekme ve sorgu planı optimizasyonu. |

Bu tabloda “olmayan” ile “kısmen olan” aynı şey değildir: reranking, entity extraction, OCR, private mode ve export artık vardır; tamamlanması gereken sınırları belirtilmiştir. Windows ve dört yeni entity türü ileri aşamaya aittir. Tam neural offline semantic search belgedeki açık ifadeye göre MVP zorunluluğu değildir.

**71 maddenin tamamı: istenen / mevcut / eksik karşılaştırması**

| No | Gereksinim | Durum | Mevcut durum ve eksik | Ana kod kanıtı |
|---:|---|---|---|---|
| 1 | Proje özeti / multimodal kişisel arama | **Kısmi** | Yedi içerik türünü işleyen backend ve arama uygulaması var. Screenshot ayrımı, belge metninin saklanması ve güvenilirlik açıkları sürüyor. | [Kod][pipeline] |
| 2 | Üretime yakın uygulama hedefi | **Kısmi** | Modüler uygulama, offline katman, AI ve CI mevcut; hesap/gizlilik izolasyonu ve gerçek kabul testi tamamlanmadan üretime hazır denemez. | [Kod][sync] |
| 3 | Hedef platformlar | **Kısmi** | Android/iOS ve macOS/web hedefleri var. Windows yok. Web dosya/görsel/kamera/ses ekleme akışlarını kapatıyor; macOS kamera kapalı. | [Kod][platform] |
| 4 | Flutter teknoloji yığını | **Tam** | Dart, Flutter, Riverpod, go_router, Dio, Drift, secure_storage, picker, camera, freezed/json_serializable kullanılıyor. En güncel sürüm iddiası ayrıca doğrulanmadı. | [Kod][pubspec] |
| 5 | FastAPI ve AIProvider soyutlaması | **Tam** | Metin, embedding, görsel ve ses arayüzleri; OpenAI, Gemini ve yerel Ollama/faster-whisper uygulamaları var. Gerçek sağlayıcı çağrıları bu denetimde yapılmadı. | [Kod][ai] |
| 6 | Supabase altyapısı / kimlik doğrulama | **Tam** | E-posta kayıt/giriş/çıkış/oturum; PostgreSQL, Storage, pgvector entegrasyonu var. İleri aşamadaki Google/Apple için native kod ve kurulum dokümanı da mevcut. | [Kod][auth] |
| 7 | Genel sistem mimarisi | **Tam** | Flutter + yerel Drift + Supabase + FastAPI + sağlayıcı ayrımı uygulanmış. Docker içindeki sade PostgreSQL, tam yerel Supabase kurulumu değildir. | [Kod][db] |
| 8 | Item veri modeli | **Kısmi** | Temel alanlar, EXIF konum/zamanı, dosya boyutu, favorite/private var. Şemadaki source üretim akışlarında doldurulmuyor; updated_at yerel/domain modele taşınmıyor. | [Kod][schema] |
| 9 | Content tablosu | **Kısmi** | raw_text/ocr_text/ai_description/summary/language şeması var. summary/language üretilmiyor; PDF/DOCX/TXT metni chunk olarak yazılıyor, item_contents kaydı olarak saklanmıyor. | [Kod][content] |
| 10 | Chunk tablosu | **Tam** | item_id, content, index, vector(1536), metadata ve benzersiz item/index kısıtı mevcut. Metadata alanı şu anda boş; sayfa/bölüm bilgisi ek geliştirme. | [Kod][chunks] |
| 11 | Tags ve item_tags | **Tam** | Otomatik etiket üretimi, ilişki tabloları, detay gösterimi ve güncel işe bağlı atomik değiştirme var. Çevrimdışı etiket erişimi madde 33’te eksik. | [Kod][tags] |
| 12 | AI Processing Jobs | **Kısmi** | Durum/hata/zaman/progress alanları, background işleme ve açılışta yarım iş tespiti var. Ara ilerleme, kalıcı tüketici ve tam eşzamanlılık güvencesi yok. | [Kod][recovery] |
| 13 | İçerik ekleme menüsü | **Tam** | Mobilde not, görsel, PDF/DOCX/TXT, kamera, ses ve link seçenekleri bağlı. Platform istisnaları madde 3’te. | [Kod][capture] |
| 14 | Fotoğraf / screenshot zekâsı | **Kısmi** | Vision ile OCR, başlık, açıklama, etiket, EXIF ve embedding var. Galeriden seçilen her görsel image oluyor; screenshot filtresine doğru kayıt düşmüyor. | [Kod][capture] |
| 15 | PDF işleme | **Kısmi** | Metin çıkarma ve taranmış PDF için OCR eklendi. Karma PDF’nin görsel sayfaları atlanabiliyor; OCR ilk 30 sayfayla sınırlı, kullanıcıya eksik indeksleme bildirilmeden completed oluyor. | [Kod][pipeline] |
| 16 | Not sistemi | **Tam** | Yerel oluşturma/düzenleme, Supabase içerik upsert, senkron sonrası AI tetikleme ve yeniden işleme var. İnternet yokken embedding doğal olarak erteleniyor. | [Kod][items] |
| 17 | URL kaydetme / çıkarım | **Tam** | Başlık, meta description, article/main metni ve nav/script vb. temizliği uygulanmış. JavaScript ile oluşan sayfalar için tarayıcı çalıştırma yok; URL güvenlik sınırı ayrıca listelendi. | [Kod][url] |
| 18 | Ses kaydı ve işleme | **Tam** | Kayıt, yükleme, transkripsiyon, başlık/etiket/entity ve embedding akışı var. Cihaz mikrofonu ve gerçek STT kalitesi bu denetimde denenmedi. | [Kod][pipeline] |
| 19 | Semantic Search | **Tam** | Sorgu embedding’i, pgvector erişimi, öğe başına en iyi parça ve sıralı sonuçlar mevcut. Alaka kalitesi/yanlış pozitifler için madde 20 ve bulgu P2-01 geçerli. | [Kod][search] |
| 20 | Hybrid Search | **Kısmi** | Semantic + FTS + RRF + LLM reranking var. FTS yalnız chunk metnini arıyor; başlık/etiket/entity metadata araması yok. Sıfır keyword eşleşmeleri de RRF katkısı alıyor. | [Kod][hybrid] |
| 21 | Arama filtreleri | **Tam** | Tür, tarih başlangıç/bitiş ve özel tarih aralığı UI/API/SQL zincirinde var. Doğal dil ayrıştırma hatası ayrı madde 22’de. | [Kod][filters] |
| 22 | Doğal dille filtreleme | **Kısmi** | Tür ve Türkçe takvim ifadeleri ayrıştırılıyor; geçen ay/hafta/yıl sınırları düzelmiş. sesli not/sesli notlar yanlışlıkla note türüne çevriliyor. Yapılandırılmış topic alanı yok. | [Kod][parser] |
| 23 | RAG sohbet | **Kısmi** | Arama → kaynak bağlamı → cevap akışı var. Önceki konuşma gönderilmiyor; öğe başına tek chunk kullanılıyor. Gizli içerik erişimi ve hesap değişimi açıkları var. | [Kod][rag] |
| 24 | Kaynak gösterimi | **Kısmi** | Numaralı kaynaklar, snippet ve tıklanabilir kartlar var. Yerel önbelleği hazır öğelerde tam detay yükleniyor; senkronize olmamış kaynak için uzaktan tam öğe çözümleme eksik. Atıflar ayrıca doğrulanmıyor. | [Kod][detail] |
| 25 | Home ekranı | **Tam** | Arama girişi, son eklenenler, tür/sayı özetleri, hızlı ekleme ve loading/empty durumları var. | [Kod][home] |
| 26 | Library | **Kısmi** | Liste/grid, yeni/eski/isim sıralama ve favori görünümü var; istenen türe göre sıralama yok. | [Kod][sort] |
| 27 | Collections | **Tam** | Oluşturma, yeniden adlandırma, silme, çoklu koleksiyon üyeliği ve offline kuyruk var. Koleksiyon detayındaki sahiplik/gizlilik açıkları madde 34/48 kapsamına giriyor. | [Kod][collections] |
| 28 | Smart Collections — ileri aşama | **Tam** | Vektör benzerliği ile kümeler, AI ile isim önerisi ve öneriden koleksiyon oluşturma var. Sürekli kendi kendini güncelleyen kural motoru gereksinimde zorunlu değildi. | [Kod][smart] |
| 29 | Favorites | **Tam** | Notlar dahil tüm içeriklerde favoriye alma/çıkarma, yerel durum ve senkron mevcut. | [Kod][items] |
| 30 | Search History | **Tam** | Drift üzerinde kullanıcıya bağlı geçmiş kaydı ve listeleme var. Eski arama sonuçlarının bellekte kalması ayrı bir hesap izolasyonu sorunu. | [Kod][history] |
| 31 | Offline-first yaklaşımı | **Tam** | Öğe metadata, notlar, favoriler, koleksiyonlar, geçmiş ve senkron durumu yerelde tutuluyor. Tüm dosyaların çevrimdışı indirilmesi veya cihaz embedding modeli MVP zorunluluğu değil. | [Kod][db] |
| 32 | Sync Queue | **Kısmi** | Kalıcı kullanıcı bazlı kuyruk, retry sayacı/hata ve AI tetikleme tekrarları var. İşlem içi oturum sabitleme, atomik local-write/enqueue ve sürüm bazlı çakışma çözümü tamamlanmamış. | [Kod][sync] |
| 33 | Offline arama | **Kısmi** | TF-IDF ile başlık/açıklama/not/link metninde kelime araması var. Etiketler yerel DB’ye senkronize edilmiyor. OCR/PDF/transkript de yerel arama kapsamında değil. | [Kod][offline] |
| 34 | Kullanıcı verisinin güvenliği | **Kısmi** | RLS ve JWT doğrulama var; fakat istemcide eski arama/sohbet durumu ve koleksiyon detay sorgusu tam kullanıcı izolasyonu sağlamıyor. İki hesaplı canlı RLS testi yapılmadı. | [Kod][privacy] |
| 35 | Storage security | **Tam** | Özel bucket, kullanıcı dizinine bağlı SQL politikaları ve süreli signed URL kullanımı var. Canlı bucket politikalarının uygulanmış olduğu bu denetimde doğrulanmadı. | [Kod][storage] |
| 36 | Secret management | **Tam** | İzlenen dosyalarda gerçek .env yerine .env.example var; sağlayıcı/service-role anahtarları backend konfigürasyonunda. Git geçmişinin tamamına yönelik gizli bilgi taraması yapılmadı. | [Kod][config] |
| 37 | Flutter feature-first mimari | **Tam** | Feature bazında data/domain/presentation; ortak core/database/network/sync katmanları mevcut. | [Kod][items] |
| 38 | UI → controller → repository veri akışı | **Kısmi** | Dio/Supabase erişimi data katmanında. Bazı ekranlarda mutation/optimistic rollback ve akış koordinasyonu widget içinde; katı controller ayrımı her özellikte tutarlı değil. | [Kod][detail] |
| 39 | Repository pattern | **Tam** | Auth, item, search, collections, chat için domain sözleşmesi ve uygulamaları var; testlerde fake/override kullanılabiliyor. | [Kod][repo] |
| 40 | FastAPI modüler yapı | **Tam** | api/core/repositories/schemas/services ayrımı mevcut. workers klasörü var fakat kalıcı worker uygulaması yok; bu eksik madde 12’de. | [Kod][main] |
| 41 | Ortak AI pipeline | **Kısmi** | Normalize → chunk → embed → duplicate/tag/entity zinciri var. Genel summary/category üretimi ve bütün çıktıların aynı güncel iş sürümüne bağlanması eksik. | [Kod][pipeline] |
| 42 | Chunking | **Tam** | Paragraf temelli bölme, uzun metni parçalama ve overlap uygulanmış; önceki overlap kaybı düzelmiş. İsteğe bağlı page_number/section metadata henüz üretilmiyor. | [Kod][chunker] |
| 43 | Search result scoring | **Tam** | API sonuçlarında cosine similarity var. Bu skor RRF/LLM son sırasının normalize relevance skoru değildir; arayüzde yüzde olarak yorumlanması yanıltıcı olabilir. | [Kod][search] |
| 44 | AI Auto-Metadata | **Kısmi** | Görsel başlık/açıklama, ses başlığı, URL metadata, etiketler ve entity var. Genel özet/kategori üretimi yok; PDF/not için ortak otomatik metadata adımı tamamlanmamış. | [Kod][content] |
| 45 | Entity extraction — ileri aşama | **Kısmi** | person/place/organization/date destekleniyor. Product, Price, Website, Technology türleri yok; entity üzerinden ayrı arama/filtre akışı da yok. | [Kod][entities] |
| 46 | Duplicate detection — ileri aşama | **Tam** | Benzer içerik işaretleme, mevcut öğeye gitme ve uyarıyı yok sayma var. Yaklaşık embedding benzerliği kullanılıyor; gerçek arşivde eşik kalitesi ayrıca ölçülmeli. | [Kod][duplicate] |
| 47 | Related items | **Tam** | Vektör tabanlı benzer içerikler ve detaydan gezinme var. Kaynak öğenin ilk chunk’ı temsili kabul ediliyor; uzun belgelerde kalite sınırı. | [Kod][related] |
| 48 | Privacy Mode — ileri aşama | **Kısmi** | Private bayrağı, biyometri/cihaz PIN’i ve ana listeleri gizleme var. Koleksiyon, doğrudan detay, RAG ve önbelleğe gelmemiş sonuçlarda tek bir tutarlı erişim kapısı yok. | [Kod][privacy] |
| 49 | Settings | **Kısmi** | Hesap, storage, sync, theme, privacy, export ve delete account ekranları var. AI Settings yalnız durum metni; export eksik kapsamlı ve sayfalamasız. | [Kod][settings] |
| 50 | Light / Dark / System | **Tam** | Üç tema modu uygulanmış. Seçim yalnız bellekte, uygulama yeniden açıldığında sistem temasına dönüyor; kalıcılık ek iyileştirme. | [Kod][theme] |
| 51 | Analytics — opsiyonel | **Tam** | Toplam/tür/ay dağılımı ve en sık etiketler ekranı var. Etiket analizi çevrimiçi veri gerektiriyor. | [Kod][analytics] |
| 52 | Error handling / retry | **Kısmi** | Loading/error durumları, yerel dosya kopyası, senkron kuyruğu ve AI Tekrar Dene var. İlk job oluşturma, bazı signed URL/yan işlem hataları ve uzun iş takibi hâlâ eksik. | [Kod][sync] |
| 53 | Structured logging | **Tam** | JSON kayıt, request/user/job/item kimlikleri, süre ve hata alanları var; OpenAI/httpx/httpcore DEBUG çıktıları baskılanmış. Her sağlayıcının hata metnine yönelik redaksiyon ayrıca sertleştirilebilir. | [Kod][logging] |
| 54 | Unit / widget / integration testleri | **Kısmi** | 185 backend ve 217 Flutter testi geçiyor. Cihaz integration_test sınırları fake; gerçek login → note → search → open ve Supabase RLS/SQL eşzamanlılık kabul testi yok. | [Kod][integration] |
| 55 | CI/CD | **Tam** | GitHub Actions içinde backend ruff/pytest, Flutter codegen/analyze/test var. Son uzaktaki CI çalışması ve release artifact bu denetimde incelenmedi; istenen kontrol işleri mevcut. | [Kod][ci] |
| 56 | README | **Kısmi** | Tanıtım, ekran görüntüleri, mimari, kurulum/test/roadmap var. Test sayısı 234 diye eski; kapanan hataları açık sayıyor; /rag/ask ve Realtime çizimi güncel değil. Demo GIF/video yok. | [Kod][readme] |
| 57 | Phase 1 — temel iskelet | **Tam** | Monorepo, tema, router, Supabase auth ve ana ekran iskeleti uygulanmış. | [Kod][router] |
| 58 | Phase 2 — basic content | **Tam** | Not CRUD, dosya ekleme, liste/detay ve favori akışları var. Son sürüm not silme/favori/private/retry kontrollerini de içeriyor. | [Kod][note] |
| 59 | Phase 3 — local database | **Kısmi** | Drift/cache/kuyruk/offline düzenleme var; madde 32/34’teki atomiklik ve oturum sınırları nedeniyle tam güvenilir senkron kabulü yapılamıyor. | [Kod][sync] |
| 60 | Phase 4 — AI processing | **Tam** | Not/PDF çıkarım, normalize/chunk/embedding, Supabase yazımı ve iş durumlarının temel akışı mevcut. Üretim dayanıklılığı ve PDF kenar durumları madde 12/15’te. | [Kod][pipeline] |
| 61 | Phase 5 — semantic search | **Tam** | Query embedding, SQL RPC, API ve Flutter arama ekranı bağlı; boş/loading/error durumları var. Gerçek veriyle kalite kabulü ayrı. | [Kod][search] |
| 62 | Phase 6 — image intelligence | **Kısmi** | Kamera/galeri, Vision OCR, açıklama ve embedding var; screenshot türü otomatik/doğrudan seçilemiyor. | [Kod][capture] |
| 63 | Phase 7 — RAG chat | **Kısmi** | Cevap ve kaynak UI/API zinciri var; çok turlu bağlam, gizli kaynak sınırı ve gerçek kabul senaryosu eksik. | [Kod][rag] |
| 64 | Phase 8 — audio + URL | **Tam** | Ses kayıt/transkript ve URL metin çıkarımının backend/mobil entegrasyonları var. | [Kod][pipeline] |
| 65 | Phase 9 — advanced search | **Kısmi** | Hybrid, reranking, related, duplicate ve smart collections var. Metadata araması, doğru tüm doğal dil tipleri ve alaka elemesi tamamlanmamış. | [Kod][hybrid] |
| 66 | MVP kabul senaryosu | **Doğrulanmadı** | Gerçek hesapla PDF + screenshot + not → Flutter state management araması → Bunlara göre Riverpod… RAG cevabı ve açılan kaynaklar zinciri bu denetimde çalıştırılmadı. | [Kod][integration] |
| 67 | UI/UX ilkeleri | **Kısmi** | Tema, kartlar, liste/grid, durum bileşenleri ve ekran görüntüleri var. Türkçe/İngilizce metinler karışık; güncel cihaz erişilebilirlik/performans/görsel kabul testi yok. | [Kod][home] |
| 68 | CV açıklaması | **Kısmi** | Flutter/FastAPI/Supabase/pgvector/RAG/offline teknik iddialarının kod karşılığı var. Üretim güvenilirliği ve uçtan uca doğrulanmış multimodal demo henüz kanıtlanmış değil. | [Kod][readme] |
| 69 | Mülakat teknik gösterimi | **Kısmi** | Mimari, pipeline, RLS, kuyruk ve testler gösterilebilir. Gerçek çok kullanıcılı demo, arama kalitesi ölçümü ve bütünlüklü kabul kanıtı eksik. | [Kod][roadmap] |
| 70 | Geliştirme kuralları | **Kısmi** | Fazlar, migrasyonlar, private bucket, env ayrımı, repository ve testler var. Tüm yazıların idempotent/eşzamanlı güvenliği, widget sorumlulukları ve güncel README tamamlanmamış. | [Kod][atomic] |
| 71 | İlk görev / planlama çıktıları | **Tam** | Gereksinim dokümanı, monorepo, şema migrasyonları, bağımlılıklar, env örnekleri, Docker ve faz görev listeleri mevcut. Tarihsel planlama maddesi olarak karşılanmış. | [Kod][roadmap] |

**Önerilen uygulama sırası**

1. **Hesap ve private erişim izolasyonu:** P1-01/P1-02; eklenen üç kontrolün düzeltilmiş kodda geçmesini sağla, koleksiyon ve RAG erişim testlerini ekle.
2. **Senkron ve iş bütünlüğü:** P1-03/P1-04/P1-05; local transaction, sabit oturum, güncel iş sürümü ve kalıcı iş kabulünü tamamla. URL dış erişim açığını kapat.
3. **MVP içerik/arama boşlukları:** screenshot türü, sayfa bazlı PDF OCR, raw_text saklama, metadata/etiket arama ve doğal dil tür hatası.
4. **Gerçek kabul doğrulaması:** iki hesap, migrasyon/RLS/Storage, PDF+screenshot+not, semantic search, Riverpod RAG ve açılan kaynakları tek senaryoda kaydet.
5. **Ürün ve sunum tamamlama:** export, AI Settings, type sort, kalıcı tema, README/demo. Yeni platform ve ileri entity kapsamını sonraki sürüme ayır.

Başarı ölçütü yalnızca daha çok test değil: ilgili hatayı gösteren testin düzelmesi, SQL/RLS’nin gerçek ortamda doğrulanması ve dokümandaki kullanıcı senaryosunun tamamlanmasıdır. Raporda hiçbir canlı servis kurulumunun uygulanmış olduğu veya gerçek AI kalitesinin doğrulandığı varsayılmadı.

[pipeline]: /Users/ilkgulseraydundar/Projects/LifeSearch/backend/app/services/processing_pipeline.py:72
[sync]: /Users/ilkgulseraydundar/Projects/LifeSearch/mobile/lib/core/sync/sync_service.dart:188
[platform]: /Users/ilkgulseraydundar/Projects/LifeSearch/docs/desktop-web-setup.md:1
[pubspec]: /Users/ilkgulseraydundar/Projects/LifeSearch/mobile/pubspec.yaml:1
[ai]: /Users/ilkgulseraydundar/Projects/LifeSearch/backend/app/services/ai_provider.py:24
[auth]: /Users/ilkgulseraydundar/Projects/LifeSearch/mobile/lib/features/auth/data/repositories/supabase_auth_repository.dart:1
[db]: /Users/ilkgulseraydundar/Projects/LifeSearch/mobile/lib/core/database/app_database.dart:1
[schema]: /Users/ilkgulseraydundar/Projects/LifeSearch/infra/supabase/migrations/0001_init.sql:1
[content]: /Users/ilkgulseraydundar/Projects/LifeSearch/backend/app/repositories/items_repository.py:154
[chunks]: /Users/ilkgulseraydundar/Projects/LifeSearch/infra/supabase/migrations/0013_chunks_unique.sql:1
[tags]: /Users/ilkgulseraydundar/Projects/LifeSearch/infra/supabase/migrations/0016_replace_tags_entities_atomic.sql:1
[recovery]: /Users/ilkgulseraydundar/Projects/LifeSearch/backend/app/services/job_recovery.py:1
[capture]: /Users/ilkgulseraydundar/Projects/LifeSearch/mobile/lib/features/capture/presentation/widgets/capture_sheet.dart:205
[items]: /Users/ilkgulseraydundar/Projects/LifeSearch/mobile/lib/features/item/data/repositories/offline_item_repository.dart:1
[url]: /Users/ilkgulseraydundar/Projects/LifeSearch/backend/app/services/url_service.py:20
[search]: /Users/ilkgulseraydundar/Projects/LifeSearch/backend/app/services/search_service.py:1
[hybrid]: /Users/ilkgulseraydundar/Projects/LifeSearch/infra/supabase/migrations/0006_hybrid_and_related.sql:22
[filters]: /Users/ilkgulseraydundar/Projects/LifeSearch/mobile/lib/features/search/presentation/screens/search_tab.dart:1
[parser]: /Users/ilkgulseraydundar/Projects/LifeSearch/backend/app/services/query_parser.py:19
[rag]: /Users/ilkgulseraydundar/Projects/LifeSearch/backend/app/services/rag_service.py:33
[detail]: /Users/ilkgulseraydundar/Projects/LifeSearch/mobile/lib/features/item/presentation/screens/item_detail_screen.dart:35
[home]: /Users/ilkgulseraydundar/Projects/LifeSearch/mobile/lib/features/home/presentation/screens/home_screen.dart:1
[sort]: /Users/ilkgulseraydundar/Projects/LifeSearch/mobile/lib/features/library/domain/library_sort.dart:3
[collections]: /Users/ilkgulseraydundar/Projects/LifeSearch/mobile/lib/features/collections/data/repositories/offline_collection_repository.dart:1
[smart]: /Users/ilkgulseraydundar/Projects/LifeSearch/backend/app/services/collection_suggestion_service.py:1
[history]: /Users/ilkgulseraydundar/Projects/LifeSearch/mobile/lib/features/search/data/local/recent_searches_data_source.dart:1
[offline]: /Users/ilkgulseraydundar/Projects/LifeSearch/mobile/lib/features/search/data/local/local_search_data_source.dart:81
[privacy]: /Users/ilkgulseraydundar/Projects/LifeSearch/mobile/lib/features/search/presentation/providers/search_providers.dart:41
[storage]: /Users/ilkgulseraydundar/Projects/LifeSearch/infra/supabase/migrations/0002_storage.sql:1
[config]: /Users/ilkgulseraydundar/Projects/LifeSearch/backend/app/core/config.py:1
[repo]: /Users/ilkgulseraydundar/Projects/LifeSearch/mobile/lib/features/item/domain/repositories/item_repository.dart:1
[main]: /Users/ilkgulseraydundar/Projects/LifeSearch/backend/app/main.py:1
[chunker]: /Users/ilkgulseraydundar/Projects/LifeSearch/backend/app/services/chunking_service.py:1
[entities]: /Users/ilkgulseraydundar/Projects/LifeSearch/backend/app/services/entity_extraction_service.py:1
[duplicate]: /Users/ilkgulseraydundar/Projects/LifeSearch/infra/supabase/migrations/0007_duplicate_detection.sql:1
[related]: /Users/ilkgulseraydundar/Projects/LifeSearch/infra/supabase/migrations/0006_hybrid_and_related.sql:87
[settings]: /Users/ilkgulseraydundar/Projects/LifeSearch/mobile/lib/features/settings/presentation/screens/settings_screen.dart:75
[theme]: /Users/ilkgulseraydundar/Projects/LifeSearch/mobile/lib/features/settings/presentation/providers/theme_mode_provider.dart:1
[analytics]: /Users/ilkgulseraydundar/Projects/LifeSearch/mobile/lib/features/analytics/presentation/screens/analytics_screen.dart:1
[logging]: /Users/ilkgulseraydundar/Projects/LifeSearch/backend/app/core/logging.py:1
[integration]: /Users/ilkgulseraydundar/Projects/LifeSearch/mobile/integration_test/app_test.dart:1
[ci]: /Users/ilkgulseraydundar/Projects/LifeSearch/.github/workflows/ci.yml:1
[readme]: /Users/ilkgulseraydundar/Projects/LifeSearch/README.md:1
[router]: /Users/ilkgulseraydundar/Projects/LifeSearch/mobile/lib/app/router/app_router.dart:1
[note]: /Users/ilkgulseraydundar/Projects/LifeSearch/mobile/lib/features/item/presentation/screens/note_editor_screen.dart:1
[roadmap]: /Users/ilkgulseraydundar/Projects/LifeSearch/docs/roadmap.md:1
[atomic]: /Users/ilkgulseraydundar/Projects/LifeSearch/infra/supabase/migrations/0015_replace_chunks_atomic.sql:1
[search_state]: /Users/ilkgulseraydundar/Projects/LifeSearch/mobile/lib/features/search/presentation/providers/search_providers.dart:116
[chat_state]: /Users/ilkgulseraydundar/Projects/LifeSearch/mobile/lib/features/ai_chat/presentation/providers/ai_chat_providers.dart:26
[collection_query]: /Users/ilkgulseraydundar/Projects/LifeSearch/mobile/lib/features/collections/data/local/collection_local_data_source.dart:122
[export]: /Users/ilkgulseraydundar/Projects/LifeSearch/mobile/lib/features/settings/data/export_service.dart:30
[export_shape]: /Users/ilkgulseraydundar/Projects/LifeSearch/mobile/lib/features/settings/data/export_payload.dart:1
[job_status]: /Users/ilkgulseraydundar/Projects/LifeSearch/backend/app/services/processing_pipeline.py:207
[upload]: /Users/ilkgulseraydundar/Projects/LifeSearch/mobile/lib/features/item/data/remote/remote_item_data_source.dart:172
[account]: /Users/ilkgulseraydundar/Projects/LifeSearch/backend/app/services/account_service.py:22
[unique]: /Users/ilkgulseraydundar/Projects/LifeSearch/infra/supabase/migrations/0012_item_contents_unique.sql:1
