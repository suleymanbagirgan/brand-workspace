# Performans ve ölçek ölçümü (2026-10-04)

Soru: bir danışmanın bir yılı (5–8 marka, marka başına binlerce görev/kayıt) birikince uygulamanın okuma yolları yetişiyor mu?
Bütün veri **sentetik**: adlar uydurma, metinler sabit bir sözcük listesinden üretiliyor, gerçek kullanıcı verisi yok.

## Veri seti (`Tests/MarkaCoreTests/YogunVeri.swift`)

`YogunVeri.uret(store, olcek:)` sabit tohumla çalışıyor (SplitMix64): her çalıştırmada aynı dağılım çıkıyor. Kayıtlar son 365 güne yayılıyor.

| Tablo | Marka başına | Toplam (8 marka) |
|---|---|---|
| Görev (%60 bitti, %10 iptal, %30 açık; %70'inin son tarihi var) | 2.500 | 20.000 |
| Kaynak (not / dosya / görüşme …; %5'i arşivde; FTS dizini dolu) | 1.500 | 12.000 |
| İş kaydı (%70 doğrulanmış; yarısı biten bir göreve bağlı; 1–2 dosya bağı) | 800 | 6.400 |
| Finans kalemi + süre kaydı | 100 + 500 | 4.800 |
| Marka kaydı (söz, karar, talep, hedef …) | 300 | 2.400 |
| Öneri (%10 bekliyor, yarısı terminalden) | 200 | 1.600 |
| Denetim olayı | 5.000 | 40.000 (+ marka açılışları) |
| Bilgi sayfası (her 10 sayfadan birinde onay bekleyen sürüm) | 30 | 240 |
| Sohbet oturumu (üçte biri yapay zekâ çalışanı rolüyle) | 30 | 240 |
| Stüdyo ekibi (hiyerarşik; 8'i yapay zekâ, 3'ü arşivde) | — | 40 üye |

Markalardan biri Stüdyo (`isOwn`). Toplu satırlar hız için tek işlemde doğrudan yazılıyor. Bu yüzden her biri ayrı denetim olayı bırakmıyor; onların yerine sentetik denetim olayları ekleniyor. Bu yalnız test verisi için böyle; uygulamanın yazma yolları değişmedi.

## Nasıl ölçüldü

- Ölçümler **bu makinede yapıldı**: Apple M2 Max (12 çekirdek, 32 GB), macOS 26.3.1, Swift 6.3.3.
- `MARKA_OLCUM=1 scripts/test.sh --filter OlcekOlcumTests` komutu sorgu medyanlarını, `EXPLAIN QUERY PLAN` çıktısını ve bileşen kırılımını yazdırıyor. CI'da bu test çalışmıyor.
- Her sorgu önce bir kez ısınma için çalıştırılıyor, sonra 5 kez `ContinuousClock` ile ölçülüyor ve medyan alınıyor.
- Derleme `swift test`'in **debug** derlemesi. Release paketin daha hızlı olması beklenir ama **ölçülmedi**.
- Aynı ölçüm hem bellek içi veritabanında (`AppDatabase.inMemory`) hem de geçici klasörde açılan disk veritabanında (`AppDatabase.open`, WAL) yapıldı. İki sonuç arasındaki fark 1 ms'nin altında kaldı (tek istisna: tüm markalarda FTS, 11 → 16 ms). Tabloda bellek içi sonuçlar var.

## Sonuç tablosu (8 marka, medyan ms)

"Önce" sütunu bu çalışmadan önceki kodu, "sonra" sütunu düzeltmelerle birlikte v9 indekslerini gösteriyor.

| Sorgu | Önce | Sonra | Yapılan düzeltme |
|---|---:|---:|---|
| `today()` (Bugün) | 92,1 | 24,4 | Sayımlar SQL'de `GROUP BY` ile yapılıyor, satırlar çözülmüyor. Gecikenlerde süzme SQL'e taşındı (`dueDate < bugün`) ve yalnız 4 sütun okunuyor. |
| `searchToday` (eşleşen sözcük) | 431,7 | 9,5 | Yalnız `id, brandId, title` sütunları okunuyor. `limit` dolunca tarama duruyor (kesme ve sıra aynı). |
| `searchToday` (eşleşmesiz, tam tarama) | ≈431,7 ¹ | 141,1 | Aynı düzeltme. Kalan süre 20.000 başlığın Türkçe normalleştirilmesinden geliyor (bkz. düzeltilmeyenler). |
| `ContextBuilder.brandContext` | 57,3 | 13,2 | Açık görevler SQL'de süzülüyor. Kaynaklardan yalnız ilk 40'ı ve toplam sayı okunuyor, gövdeler çözülmüyor. |
| Tüm markalar bağlamı / Codex-Anthropic "tüm markalar" istemi (N+1) | 317,1 ² | 1,2 | Marka başına görev listesi yerine tek bir `openTaskCounts()` gruplu sayımı. |
| Menü çubuğu paneli: ilk 5 açık görev (her veri değişikliğinde) | 92,6 ² | 3,6 | `tasks(…, limit: 5)`: sıralama ve kesme SQL'de yapılıyor (`displayOrderSQL`). |
| Pano sürükle-bırak, 20 görev (N+1: görev başına marka listesi) | 775,4 ² | 33,3 | Liste bir kez okunuyor, görevler sözlükten bulunuyor. |
| `reportPreview` (ay) | 38,5 | 16,2 | İş kaydı başına dosya bağı ve görev okuma (N+1) toplu sorguya çevrildi. "Sıradaki işler" için yalnız açık görevler okunuyor. |
| `tasks(brandId:)` | 38,5 | 27,4 | SQL `ORDER BY` `displayOrder` ile aynı. Önceden sıralı girdide Swift sıralaması hızlı. |
| `flow(brandId:)` | 11,7 | 10,6 | v9: `workLog(brandId, occurredAt)`, `workTask(brandId, status, completedAt)` |
| `todo(brandId:)` | 10,3 | 11,5 | — (zaten hızlı; fark gürültü düzeyinde) |
| `completedTaskCount` | 0,44 | 0,14 | v9 kapsayan indeks |
| `pendingApprovals` × 8 marka | 3,7 | 3,6 | v9: `aiProposal(brandId, status)`, `wikiRevision(brandId, state)` |
| `reloadBasics`: `brands()` + `pendingApprovalCounts()` | 0,19 + 0,22 | 0,17 + 0,20 | — (zaten tek gruplu sorgu, N+1 yok) |
| FTS `search` (marka / tüm markalar) | 7,1 / 10,5 | 7,2 / 10,8 | — |
| `orgChart` / `brandTeam` / Stüdyo ekibi | 0,7 / 0,4 / 0,8 | 0,7 / 0,4 / 0,8 | — |
| `memberActivity` | 0,50 | 0,50 | v9: `aiSession(memberId)` (plan: tarama yerine indeks) |
| `profile` | 0,06 | 0,06 | — |
| `sources` / `workLogs` / `records(brandId:)` | 13,0 / 9,0 / 2,7 | 13,3 / 9,0 / 2,7 | — |

¹ Eski kod her aramada üç tablonun tamamını çözüp tarıyordu, yani "kampanya" ölçümü zaten tam taramaydı. Eşleşmesiz sorgu ayrıca ölçülmedi.
² Eski yolun birebir kopyası `OlcekOlcumTests.kirilim` içinde ölçüldü (`ESKİ …` satırları).

Ölçüm turları arasındaki oynama ±1–2 ms. 5 ms'nin altındaki farklar gürültü sayılmalı.

## Sorgu planı bulguları (`EXPLAIN QUERY PLAN`)

- Her marka sorgusunda bir indeks zaten kullanılıyordu: GRDB `belongsTo` her tabloya `brandId` indeksi açıyor. Tam tablo taraması yalnız markalar arası iki gruplu sayımda (`aiProposal`, `wikiRevision`), `memberActivity` içinde (`aiSession`) ve `timeEntry` çalışan sayaç aramasında vardı. Sayaç araması kısmi indeksle hızlı.
- 50 ms'yi aşan sorguların hiçbiri indeks eksikliğinden yavaş değildi. Sürenin çoğu **Swift tarafındaydı**: binlerce satırı Codable ile çözmek (2.500 görev ≈ 24 ms; aynı satırları ham `Row` olarak okumak ≈ 9 ms) ve Swift'te süzüp saymak.
- v9 indeksleri sıralama için kurulan geçici B-ağacını kaldırıyor ve aralık aramasını indekse taşıyor. Örnekler: Akış'ta biten görevler `completedAt DESC LIMIT 200`, rapor ve Bugün'de `occurredAt` ve `endedAt` aralıkları, onay sayımı.

## Şema değişikliği: `v9_olcek_indeksleri`

- Migration yalnız `CREATE INDEX IF NOT EXISTS` içeriyor. Eski migration'lara dokunulmadı.
- İndeksler: `workLog_brand_occurred`, `workTask_brand_status_completed`, `aiProposal_brand_status`, `wikiRevision_brand_state`, `brandRecord_brand_kind`, `timeEntry_brand_ended`, `aiSession_member` (liste: `AppDatabase.v9Indexes`).
- Geri almak için `DROP INDEX IF EXISTS <ad>` yeterli. Sorgular indekssiz de doğru çalışır, yalnız yavaşlar.
- Bekleyen migration'dan önce yedek alma kuralı (`Migration-Yedekleri/`) bu migration için de çalışıyor. Bunu `V9IndeksMigrationTests` doğruluyor: indeksler oluşuyor, veri bozulmuyor, yedek eski şemada kalıyor.
- `MigrationYedekTests`'in ilk testi artık v8 ile birlikte v9'u da geri alıyor. Bütün beklentileri aynı kaldı (yedek adında `v7_kendi_sirket` geçiyor ve yedekte `skill` tablosu yok).

## Regresyon testleri (`Tests/MarkaCoreTests/OlcekTests.swift`)

- **Süre sınırları:** Bugün, kenar çubuğu, menü paneli, Yapılacaklar, Akış, görevler, rapor, ekip/profil, asistan bağlamı ve FTS için sınır 500 ms. Eşleşmesiz `searchToday` için sınır 1 sn. Bu sınırlar ölçülen medyanın en az 5 katı. Amaç yalnız 10–100 katlık gerilemeyi yakalamak; testler bilerek gevşek tutuldu, kararsız olmamaları için. Sentetik veri süreç başına bir kez üretiliyor (`YogunVeri.paylasilan`, ≈3,5 sn).
- **Davranış eşdeğerliği:**
  - `today()` sonucu eski satır-satır hesapla bire bir aynı.
  - `searchToday`, eski hesapla 5 sorguda ve farklı sınırlarla aynı sonucu veriyor.
  - SQL görev sırası `displayOrder` ile aynı, `limit` ilk elemanları veriyor.
  - `openTaskCounts` marka başına sayımla eşit.
  - Marka bağlamı ilk 40 kaynağı ve doğru toplam sayısını yazıyor, başka markanın verisi bağlama girmiyor.
  - Rapordaki dosya bağları, iş kaydı başına okumayla aynı.

## Düzeltilmeyenler ve nedeni

- **Eşleşmesiz `searchToday` (141 ms):** Başlıklar Türkçe kurallarla normalleştiriliyor (ı/İ, aksan). Bu yüzden ön süzme SQL `LIKE` ile yapılamıyor; `LIKE` yalnız ASCII'de büyük/küçük harf duyarsız. Kalıcı çözüm, başlıklar için normalleştirilmiş bir FTS dizini (yeni sanal tablo ve tetikleyici). Bu iş kapsam dışı bırakıldı; görev yalnız indeks migration'ı istiyordu. Eşleşen her aramada tarama erken kesiliyor (≈10 ms).
- **`tasks(brandId: nil)` sınırsız (219 ms):** Bütün markaların 20.000 görevini çözüyor. Uygulamada bu çağrının tek yeri menü paneliydi ve artık `limit: 5` kullanıyor.
- **`tasks(brandId:)` (27 ms) ve `sources(brandId:)` (13 ms):** Marka başına bütün listeyi çözüyorlar. Süre 50 ms eşiğinin altında. Bunu daha da düşürmek için Codable yerine elle `init(row:)` yazmak ya da ekranları sayfalamak gerekir. Bu bir davranış ve arayüz değişikliği olur; ayrı bir iş olarak bırakıldı.
- **Arayüzde tekrar eden okumalar** (ör. `TodoView.grouped` ve `BrandSections` her çizimde bütün görev listesini okuyor): Her biri tek sorgu, N+1 değil. Ekran başına önbellek ayrı bir iş.
- Ölçümler debug derlemede yapıldı. Release paketin süreleri ölçülmedi.
