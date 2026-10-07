# Dev Camp — Mimari/Kodlama görevleri (swift-gelistirici, 2026-10-05)

Kapsam: yalnız ürün. Satış/yayın/mağaza gönderimi yok; sandbox yalnız mimari hazırlık. Kanıtlar kod okuması + mevcut belgeler; bu rapor için hiçbir şey derlenmedi/çalıştırılmadı. **Gün tahminleri tahmindir.**

## Ölçülen başlangıç durumu
- 74 Swift dosyası, 20.872 satır; 255 `@Test`.
- En büyükler: `MarkaDogrula/main.swift` 1206, `BrandSections.swift` 1131, `ChatEngine.swift` 893 (içinde `BrandFolders` 5–230, `ChatEngine` aktörü 247–792, `CodexTurnState` 817+), `CompanyView` 861, `Design` 722, `Models` 694, `TodoView` 688.
- `try?`: 228 adet; MarkaApp'te `try? app.store`/`try? store` 114. En yoğun: `AppModel` 21, `BrandProfileView` 17, `CompanyView` 15, `BrandSections` 15, `ChatEngine` 13.
- Yenileme: `AppModel.swift:253` `DatabaseRegionObservation(tracking: .fullDatabase)` → `databaseChanged()` → `revision += 1` (315). 14 görünüm `let _ = app.revision` ile her yazmada yeniden okur (ör. `TodayView:14`, `TodoView:91`, `BrandSections:198/337/447/690`). Gözlem hatası yutuluyor: `onError: { _ in }` (254).
- ChatEngine iki yol: `runAnthropic` (523–605) ve `#if !MAS runCodex` (608–685), seçim `runTurn` 472/475.
- `ProposalKind` (Models.swift:580): `updateTask` dışında **8** tür kayıt dışı (görev 7 diyordu; plan yazıldıktan sonra `createTeamMember` eklenmiş).
- ⌘K: `CommandPalette.swift:26–46` elle yazılmış `Entry` listesi.
- Performans (debug, M2 Max, `performans-olcumu.md`): eşleşmesiz `searchToday` 141 ms; `tasks(brandId:)` 27 ms; `tasks(nil)` 219 ms; 2.500 görev Codable ≈24 ms / ham `Row` ≈9 ms.
- Foundation Models: tablosuz göreli tarih 6/6 yanlış, tarih tablosuyla 10/10; pencere 4096 belirteç; araç başına ≈200 belirteç; Türkçe ≈2,1 karakter/belirteç.

## Haftalık mimari tema
- **Hafta 1 — Veri akışı ve hata görünürlüğü:** K-04, K-06, K-14, yeşillerin çoğu (zemini temizler, sonraki diff'leri küçültür).
- **Hafta 2 — Sağlayıcı katmanı:** K-01 → K-09 → K-02, K-10, K-15.
- **Hafta 3 — Eylem ve izin modeli:** K-07 → K-05, K-03 (S4–S5), K-12/K-13.

Toplam tahmin ≈ 55 kişi-gün. Tek geliştirici için 3 haftayı aşar. Paralel ajan ya da 🔴 seçimi gerekir.

## 🔴 Boss görevleri

| ID | Başlık | Neden (kanıt) | Kabul ölçütü | Gün | Bağ. | Doğrulama |
|---|---|---|---|---|---|---|
| K-01 | `AIProvider` protokolü + `FakeProvider`; Anthropic ve Codex buna taşınır | `ChatEngine.swift:472–475` sağlayıcıya göre dallanıyor; iki ayrı döngü (523–685). Plan F3 | `runTurn` içinde sağlayıcı `switch`'i 0; sahte sağlayıcıyla en az 6 yeni test (araç döngüsü, başka marka kimliği reddi, iptal); mevcut 255 test değişmeden geçer | 4 | — | `scripts/test.sh`; `swift build -Xswiftc -DMAS` |
| K-02 | Apple Foundation Models sağlayıcısı (dinamik şema, 2–4 araç alt kümesi, tarih tablosu uygulamadan) | Spike: makrolar CLT'de derlenmiyor, `DynamicGenerationSchema` derleniyor; tablosuz 6/6 yanlış; 12 araç ≈2.400 belirteç | `#if canImport(FoundationModels)` + `@available(macOS 26)`; JSON Schema→`DynamicGenerationSchema` çevirici için ≥8 test; araç alt kümesi ≤4; `exceededContextWindowSize` yakalanıp kısaltılmış bağlamla 1 kez yeniden deneme (test); cihaz üstü yolda `URLSession` çağrısı yok (test) | 4 | K-01, K-09, K-10 | Test + spike'taki 5 istemi elle yeniden çalıştırma (gerçek model, hedef ≥9/10) |
| K-03 | Sandbox S4–S5: bookmark saklama + "izin gerekli" arayüzü | `sandbox-gecis-analizi.md:163–164`; MAS'ta hâlâ `defaultRoot` + `AbsolutePathFolderAccess` (185) | Yeni migration (v10) yalnız ekleme yapar; `BookmarkFolderAccess` üret/çöz/bayat testi; `existingFolder` çağıranlarında `try?` 0; marka sekmesinde `izinGerekli` durumu; klasör seçilmeden çekirdek akışlar çalışır | 4 | — | `KlasorErisimTests` genişler; migration testi; gerçek pencere açık+koyu, `l10n.py check` |
| K-04 | Global `revision` yerine ekran başına `ValueObservation` | `AppModel.swift:253,315`; 14 görünüm her yazmada tüm okumaları tekrarlar | `grep "let _ = app.revision"` = 0; görev eklemede yeniden okunan sorgu sayısı sayaçla ölçülür, hedef ≤2 (önce/sonra tabloya yazılır); gözlem hatası `Diagnostics`'e düşer | 5 | K-14 önerilir | Sayaçlı test + gerçek pencerede Bugün/Yapılacaklar/Akış |
| K-05 | Evrensel geri alma günlüğü (`undoLog`) + atomik plan hattı | Plan F2 (§4.2); bugün ⌘Z yalnız `TodoView:333,525,538` ve `BrandSections:664` içinde elle `registerUndo`; plan "v5" diyor ama şema v9'da, yani v10/v11 | Plan ortasında hata → 0 satır değişir (test); geri alma sonrası tablo içeriği bire bir aynı (test); her geri alma `Store.audit` bırakır; elle `registerUndo` çağrısı 0 | 5 | K-07 | `PlanAtomiklikTests`, `GeriAlmaGunluguTests` |
| K-06 | Başlıklar için Türkçe normalleştirilmiş FTS + liste sayfalama | Eşleşmesiz `searchToday` 141 ms (`Today.swift:142`); `tasks(nil)` 219 ms | Yeni sanal tablo + tetikleyici; eski hesapla sonuç eşdeğerliği (ı/İ, aksan) ≥10 sorguda; eşleşmesiz arama hedefi ≤20 ms (tahmin, ölçülerek kesinleşir); `tasks`/`sources` sayfalı API | 4 | — | `MARKA_OLCUM=1 … OlcekOlcumTests`; `OlcekTests` sınırları |
| K-07 | Action Registry: kalan 8 öneri türünü kayda taşı, ⌘K kayıttan türesin | `plani.md:111` "yapılmadı"; `ProposalKind` 8 tür; `CommandPalette.swift:26–46` elle | `Store+Proposals` `applyProposal`/`revertProposal` içindeki `switch p.kind` (297, 406) kayda devredilir; tür başına önizleme+geri alma testi (≥16); ⌘K girdilerinin eylem kısmı `ActionRegistry`'den gelir; marka yalıtım testi her eylemde | 5 | — | `EylemKaydiTests` genişler |

## 🟡 Orta

| ID | Başlık | Neden | Kabul | Gün | Bağ. | Doğrulama |
|---|---|---|---|---|---|---|
| K-08 | `ChatEngine.swift`'i böl: `BrandFolders`, istem kurucu, Codex turu ayrı dosyalara | 893 satır, 4 tip tek dosyada | Davranış aynı; en büyük parça <450 satır; test sayısı aynı | 1,5 | K-01 öncesi | test + MAS derleme |
| K-09 | Türkçe göreli tarih çözücü (`GoreliTarih`) | FM 6/6 yanlış; Claude için de faydalı | "yarın, cuma, önümüzdeki pazartesi, N gün sonra, ay sonu" ≥15 test, sabit "bugün" ile | 2 | — | test |
| K-10 | Sağlayıcı yeteneğine bağlı bağlam bütçesi | `ContextLimits` tek sınır; FM 4096 belirteç, ≈2,1 kr/belirteç | `AIProviderCapabilities.contextTokens`'tan karakter bütçesi; kırpma notu korunur; ≥4 test | 2 | K-01 | test |
| K-11 | Sıcak yollarda elle `init(row:)` | Codable 24 ms / Row 9 ms | `tasks(brandId:)` 27 → ≤15 ms (hedef); eşdeğerlik testi | 2 | — | `OlcekOlcumTests` |
| K-12 | Sandbox S6: "Yedeği dışa aktar / Yedekten yükle" manifest eşleşmesi | `sandbox-gecis-analizi.md:165` | Marka/kaynak/görev sayısı manifestte eşleşir (test); eski alan dokunulmamış | 3 | K-03 | `ReportImportBackupTests` deseni |
| K-13 | Sandbox S7: entitlements + `build-app.sh --sandbox` (ayrı ad) | :166; ad-hoc imzayla sandbox uygulanıp uygulanmadığı doğrulanamadı | `codesign -d --entitlements` yalnız §3 anahtarları; container klasörü oluşur ya da sınır `bilinen-sinirlar.md`'ye yazılır | 2 | K-03 | komut çıktısı |
| K-14 | Uygulama katmanında yazma hatalarını tek yardımcıya taşı (`app.perform`) | MarkaApp'te 114 `try? store` | Yazma yollarında `try?` 0; hata kullanıcıya + `Diagnostics`'e; okuma `try?`'leri K-16 envanterine göre | 2 | K-16 | grep sayısı + test |
| K-15 | Sahte sağlayıcıyla enjeksiyon uçtan uca senaryosu | `bilinen-sinirlar.md` §4: "uçtan uca yazılmadı" | Başka marka kimliğiyle araç çağrısı, onay atlama, ≥5 senaryoda 0 veri değişikliği | 2 | K-01 | test |

## 🟢 Basit

| ID | Başlık | Neden | Kabul | Gün | Bağ. |
|---|---|---|---|---|---|
| K-16 | `try?` envanteri: 228 adedi tek tek etiketle (okuma/yazma/kasıtlı) | yukarıdaki sayım | Tablo `docs/`'ta; kasıtlı olanlar satırında gerekçe yorumu | 1 | — |
| K-17 | Ölü kod: `MarkaCore/Terminal/TerminalSessions.swift` (102 satır) + `TerminalOturumTests` (5) sil — **KULLANICI ONAYI GEREKİR** | `yapilacaklar-20.md`: yalnız testler kullanıyor | `grep TerminalSession` = 0; test 255 → 250 | 0,5 | onay |
| K-18 | `BrandSections.swift` (1131) ve `CompanyView.swift` (861) bölme | en büyük iki görünüm | Her parça <500 satır; davranış aynı | 1 | — |
| K-19 | `Design.swift` (722), `Models.swift` (694), `TodoView.swift` (688) bölme | en büyük 5'in kalanı | Her parça <500 satır; test sayısı aynı | 1 | — |
| K-20 | Sessiz hata günlüğü: `AppModel.swift:254` `onError: { _ in }`, `CodexAppServer.swift:93` `catch {}` | hata kaybı | İkisi `Diagnostics.record` (içeriksiz); grep = 0 | 0,5 | — |
| K-21 | Yapılandırma sabitleri: 39 sihirli `limit: N`/`prefix(N)` | dağınık sınırlar | `AppLimits`'e taşınır; kalan sabit ≤5 | 1 | — |
| K-22 | Özet "Bu hafta biten" iş kaydı bağlı görevleri saymıyor | `yapilacaklar-20.md` bulgusu | Önce kırmızı sonra yeşil test (örnek markada 3) | 0,5 | — |
| K-23 | `tasks(brandId: nil)` sınırsız çağrıyı kaldır (limit zorunlu) | 219 ms | API'de varsayılansız `limit`; çağıran sayısı aynı | 0,5 | — |
| K-24 | `BackupService.swift:28` `nonisolated(unsafe)` uyarısı | MAS derlemesinde tek uyarı | Derleme uyarısı 0 | 0,5 | — |
| K-25 | `scripts/mas-tarama.sh`'i teste bağla | S2 kanıtı yalnız elle | Test yasaklı kalıpta kırmızı olur | 0,5 | — |
| K-26 | Değişmemiş alanları sağlayıcıdan bağımsız ayıkla (`FieldChange`) | FM 8/10 fazladan `durum` | Aynı değer içeren alan öneriye girmez (≥3 test) | 0,5 | — |
| K-27 | Release derlemede ölçüm | Ölçümler yalnız debug | Release medyanları tabloya eklenir | 0,5 | — |

## Notlar
- K-03/K-12/K-13 yalnız mimari hazırlık; gönderim, imza kimliği, S9 beyanı kamp dışı.
- Her görevin bitti kapısı: `scripts/test.sh && scripts/build-app.sh && python3 scripts/l10n.py check`; gerçek veri alanı yerine geçici `MARKA_WORKSPACE`/`MARKA_FOLDERS`.
