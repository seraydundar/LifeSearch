# LifeSearch — Multimodal Personal AI Search Engine

> Bu doküman projenin ana gereksinim dokümanıdır. Kod içindeki yorumlar ve
> mimari kararlar bu belgeye referans verir. Faz planı için
> [`roadmap.md`](./roadmap.md) dosyasına bakın.

## 1. Proje Özeti

LifeSearch, kullanıcının günlük hayatında biriktirdiği dijital içerikleri tek
bir yerde saklamasına ve bu içerikler arasında doğal dil kullanarak arama
yapmasına olanak sağlayan, Flutter tabanlı multimodal bir kişisel AI arama
motorudur.

Kullanıcı uygulamaya: Fotoğraf, Screenshot, PDF, Not, Belge, Ses kaydı, Web
bağlantısı ekleyebilir. LifeSearch eklenen içerikleri analiz eder,
anlamlandırır, indeksler ve embedding'lerini oluşturur.

Kullanıcı daha sonra klasik dosya adı veya anahtar kelime araması yapmak
yerine doğal dil sorguları gerçekleştirebilir — örn. "Geçen ay baktığım
siyah monitörü bul.", "Docker hakkında kaydettiğim not neydi?".

LifeSearch yalnızca kelime eşleşmesi yapmayacak; sorgunun anlamını
anlayarak **semantik arama** gerçekleştirecektir.

## 2. Projenin Ana Hedefi

- Flutter ile production seviyesinde mobil geliştirme
- Clean/modüler uygulama mimarisi, state management
- REST API entegrasyonu, authentication
- PostgreSQL, local database, offline-first yaklaşımı
- Dosya yükleme, kamera, OCR, Speech-to-Text
- LLM kullanımı, embedding modelleri, vector database
- Semantic search, hybrid search, RAG, multimodal AI
- Background processing, güvenlik
- Unit / integration testleri, CI/CD

Proje yalnızca bir AI API'sine istek atan basit bir chatbot olarak
geliştirilmeyecektir.

## 3. Hedef Platformlar

İlk hedef: Android + iOS (Flutter). İlerleyen aşamada macOS/Windows/Web
eklenebilir. MVP öncelikli olarak Android üzerinde test edilir, kod tabanı
iOS desteğini engellemez.

## 4. Mobil Teknoloji Stack'i

- Dil: Dart, Framework: Flutter (latest stable)
- State Management: Riverpod
- Navigation: go_router
- HTTP Client: Dio
- Local Database: Drift / SQLite
- Secure Storage: flutter_secure_storage
- Dosya seçimi: file_picker, Kamera: camera
- Serialization: freezed, json_serializable

## 5. Backend

Python + FastAPI. Backend yalnızca CRUD API sağlamaz — özellikle AI
işlemleri backend üzerinden gerçekleştirilir: dosya işleme, PDF parsing,
OCR, metadata extraction, chunking, embedding, vector/hybrid search, RAG,
LLM entegrasyonu, görsel analizi, URL işleme, ses transcription, background
AI processing.

Backend mimarisi AI provider'dan bağımsız tasarlanır:

```
AIProvider
├── generateText()
├── generateEmbedding()
├── analyzeImage()
└── transcribeAudio()
```

İleride `OpenAIProvider`, `GeminiProvider`, `LocalModelProvider` gibi farklı
implementasyonlar eklenebilir. API key'ler kesinlikle Flutter içinde
bulunmaz.

## 6. Cloud Altyapısı — Supabase

- **Authentication**: email/password login, register, logout, session
  management. İleride Google/Apple login.
- **PostgreSQL**: ana veritabanı.
- **Storage**: fotoğraf/PDF/ses/belge private bucket içinde, public erişim
  yok.
- **pgvector**: embedding'ler PostgreSQL içinde saklanır, semantic search
  bunun üzerinden çalışır.

## 7. Genel Sistem Mimarisi

```
Flutter App (Riverpod, Drift, Dio)
        │  Authentication
        ▼
    Supabase (Auth, PostgreSQL, Storage, pgvector)
        │
        ▼
  FastAPI AI Service (OCR, Chunking, Embeddings, LLM, RAG, Vision)
        │  AI Providers
        ▼
   LLM API / Embeddings / Vision AI
```

## 8-12. Veri Modeli (özet)

- **items**: kullanıcının eklediği her içerik (`type`: note/image/screenshot
  /pdf/audio/url/document), işleme durumu, konum, favorite vb.
- **item_contents**: AI tarafından çıkarılan/metinselleştirilen içerik
  (raw_text, ocr_text, ai_description, summary, language).
- **chunks**: uzun içeriklerin parçaları + `embedding` (pgvector) +
  metadata (page_number, section, chunk_index...).
- **tags** / **item_tags**: kullanıcı ve AI tarafından üretilen etiketler.
- **processing_jobs**: async AI pipeline takibi (pending/processing/
  completed/failed, progress, error_message).

Tam SQL şeması: [`infra/supabase/migrations/0001_init.sql`](../infra/supabase/migrations/0001_init.sql).

## 13-24. Ürün Özellikleri (özet)

İçerik ekleme (foto/screenshot/PDF/not/ses/link), her içerik tipi için AI
pipeline'ı (OCR → Vision AI → metadata → description → embedding),
semantic search, hybrid search (semantic + keyword + metadata filtre),
doğal dil filtreleme, RAG tabanlı "Ask AI" sohbeti (mutlaka kaynak
göstererek).

## 25-33. UI ve Offline (özet)

Home screen (arama kutusu + recently added + library özeti), Library
(grid/list, sorting), Collections, Smart Collections (AI önerisi),
Favorites, Search History, offline-first (Drift ile local cache + sync
queue + offline keyword search).

## 34-36. Güvenlik

- Supabase RLS: her kullanıcı yalnızca kendi item/chunk/tag/collection/file
  verisine erişir.
- Storage bucket private, signed URL / authenticated erişim.
- Secret management: LLM/embedding API key ve Supabase service role key
  yalnızca backend env variable'larında — asla Flutter içinde değil.

## 37-39. Flutter Mimarisi

Feature-first modüler mimari (`lib/app`, `lib/core`, `lib/features/*`,
`lib/shared`). Data flow: `Screen → Riverpod Controller → Repository →
{Local Source (Drift) | Remote Source (API/Supabase)}`. UI asla doğrudan
Supabase/Dio çağrısı yapmaz.

## 40-43. Backend Mimarisi

`backend/app/{api,core,services,repositories,models,schemas,workers}`.
Tüm içerik türleri ortak pipeline'dan geçer: `INPUT → CONTENT EXTRACTION →
NORMALIZED TEXT → METADATA → CHUNKS → EMBEDDINGS → VECTOR DB`. Bu sayede
arama katmanı içeriğin orijinal türünü bilmek zorunda değildir.

## 44-48. Gelişmiş AI Özellikleri (ileri faz)

AI auto-metadata, entity extraction, duplicate detection, related items
(vector similarity), privacy mode (biometric/PIN korumalı item'lar).

## 49-52. Ayarlar / Tema / Hata Yönetimi

Settings ekranı (Account, AI Settings, Storage, Sync, Theme, Privacy,
Export, Delete Account), Light/Dark/System tema, network ve AI hataları
için retry destekli error handling — dosya/kayıt asla kaybolmaz.

## 53-56. Logging / Test / CI-CD / README

Structured logging (request_id, user_id, job_id, item_id,
processing_time, error) — **kişisel içerikler asla loglanmaz**. Flutter:
unit + widget + integration testleri. Backend: pytest (search, auth,
chunking, permissions, document processing). CI/CD: GitHub Actions
(`flutter analyze`, `flutter test`, backend lint, `pytest`).

## 57-66. Faz Planı

Bkz. [`roadmap.md`](./roadmap.md).

## 67. UI/UX Prensibi

Modern, minimal, premium, hızlı, AI-first. Notion / Linear / Arc / Raycast
esintili sade tasarım. Ana ürün hissi: *"Google Search, but for your
personal digital life."*

## 70. Önemli Geliştirme Kuralları

1. Tüm projeyi tek seferde üretmeye çalışma — fazlar halinde geliştir.
2. Önce çalışan basit versiyonu oluştur, sonra iyileştir.
3. Gereksiz abstraction oluşturma.
4. UI içinde business logic bulundurma; Supabase çağrılarını widget
   içinden yapma.
5. AI provider API key'lerini Flutter içinde saklama.
6. Repository pattern kullan, kodları test edilebilir yaz.
7. Her önemli özellik için error ve loading state oluştur.
8. Null safety kurallarına uy. Public dosya bucket kullanma.
9. PostgreSQL RLS politikalarını unutma; kullanıcı verisini başka
   kullanıcıların sorgularında kullanma.
10. AI işlemlerinin başarısız olabileceğini varsay; dosya işlemeyi
    idempotent tasarla (aynı job tekrar çalışınca duplicate oluşmasın).
11. Database migration kullan. `.env` dosyalarını commit etme. README'yi
    güncel tut.
