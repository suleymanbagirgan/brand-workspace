# Workspace AI — Yapay zekâ çalışma alanı planı (App Store hedefli)

Tarih: 2026-10-03. Durum: **plan**. Bu belgedeki hiçbir madde "yapıldı" sayılmaz; her aşamanın sonunda ölçülebilir kabul ölçütü var ve ölçülmeden aşama kapanmaz.

## 1. Hedef

Kullanıcı Workspace AI'da yapabildiği her şeyi yapay zekâya söyleyebilsin: "Cuma teslimini 3 gün ertele, Kuzey Lojistik'in raporunu taslakla, bu hafta kaç saat çalıştım?" Yapay zekâ işi **planlasın, önizletsin, kullanıcı onaylasın, geri alınabilsin.** Ürün sözü: **gör · onayla · raporla.**

Rakiplerden ayrımız hız değil **güven**: AI veri değiştirmez, öneri üretir. Bu kural ürünün satış cümlesi olacak ve kodda zorunlu kalacak.

## 2. Bugünkü durum (denetim, 2026-10-03)

| Parça | Durum |
|---|---|
| MarkaCore | 8,5k satır, 39 dosya; GRDB şeması v1–v4; ~109 Store fonksiyonu |
| MarkaApp | 8,2k satır, 22 dosya; "Sakin Atölye" tasarım dili, asistan paneli, ⌘K, menü çubuğu, çentik zamanlayıcı |
| Test | 142 test (Swift Testing) |
| Öneri türleri | createTask, completeTask, createWorkLog, wikiRevision, createOutput, createBrandRecord, createNote (7) |
| AI sağlayıcı | Anthropic (Keychain API anahtarı), Codex App Server süreci |
| Bağımlılık | GRDB, SwiftTerm (SwiftTerm artık ölü; terminal kaldırıldı) |
| Sandbox / entitlements | **Yok** (ad-hoc imza) |
| Doğrulanmamış | Canlı AI yanıtı (anahtar yok), çentik fiziksel görünüm, menü çubuğu popover, Pano sürükle-bırak, VoiceOver |

Ana boşluk: AI yalnızca 7 şey önerebiliyor; uygulamada ise onlarca eylem var. Yetenekler arayüzde, AI araçlarında ve ⌘K'de **ayrı ayrı** tanımlı; tek kaynak yok.

## 3. Kararlar (bozulamaz kurallar korunur)

1. **Terminal kalktı → App Store mümkün.** Hedef: Mac App Store, sandbox içinde.
2. **Codex CLI süreci Mac App Store sürümünde yok.** Sandbox içinde rastgele ikili çalıştırmak uygun değil. Codex yalnız doğrudan (App Store dışı) dağıtım yapılırsa kalır. Bunu satış metninde vaat etmeyiz.
3. **Sparkle yok.** MAS'ta güncelleme yalnız Mac App Store'dan.
4. **Birincil sağlayıcı: Anthropic, kullanıcının kendi anahtarı (BYOK).** İkincisi: Apple Foundation Models (macOS 26, cihaz üstü; bu sağlayıcıda içerik üçüncü tarafa gitmez). Her ikisi aynı `AIProvider` protokolü arkasında.
5. **Madde 5.1.2(i):** İçerik üçüncü taraf AI'ya gitmeden önce açık, markaya özel izin ekranı (bugün marka başına izin var; metni "ne gider, kime gider" diye netleştirilecek) ve App Privacy etiketi.
6. **AI hiçbir zaman doğrudan yazmaz.** Yeni "güvenli eylem" kademesi bile yalnız kullanıcının **önceden, eylem türü başına** verdiği izinle ve yine geri alınabilir olur.
7. Abonelik/ödeme, yayın, imzalama: kurucu "sonra" dedi. Plan bunları son aşamaya koyar, ama mimari (sandbox, gizlilik) baştan uyumlu kurulur.

## 4. Mimari

### 4.1 Action Registry (temel taş)

Tek kayıt defteri. Her yetenek bir `AppAction`:

- `id`, `title` (yerelleştirilmiş), `brandScoped: Bool`
- `parameters`: tipli şema (JSON Schema üretilebilir)
- `risk`: `read` | `safeWrite` | `needsApproval` | `forbidden`
- `preview(params) -> ActionPreview` (diff: önce/sonra)
- `apply(params) -> UndoToken`, `undo(UndoToken)`
- `audit` kaydı zorunlu (bugünkü `Store.audit` kuralı)

Aynı kayıttan türer: arayüz düğmeleri, ⌘K, menü çubuğu, App Intents/Kısayollar, AI araç listesi. **Bir eylemi bir kez yazarsın, her yüzeyde çıkar.**

Başlangıç eylem listesi (bugünkü 7'nin üstüne): görev düzenle/sil/tarih-durum-öncelik değiştir, projeye/hedefe bağla, zamanlayıcı başlat/durdur, finans satırı ekle/düzelt, profil bölümü yaz, kişi ekle, hedef güncelle, rapor taslağı oluştur, rapor onayla, görünüm komutları (marka/sekme aç, filtre uygula).

### 4.2 Plan hattı (toplu, atomik, geri alınabilir)

- AI tek öneri yerine **plan** üretir: sıralı eylem listesi + gerekçe + dayanak.
- Onay sayfası planı diff olarak gösterir; kullanıcı kalem kalem seçer.
- Uygulama tek veritabanı işlemi içinde: ya hepsi ya hiçbiri.
- Geri alma günlüğü (`undoLog`): plan tek hareketle geri alınır. Yeni migration `v5`.

### 4.3 Bağlam motoru

- Bugün: FTS ile arama. Eklenecek: cihaz üstü gömme (NLEmbedding / Core ML) ile anlamsal arama; vektörler yerel tabloda, **marka kimliği her sorguda zorunlu**.
- Token bütçeli paketleme: önce profil + açık işler, sonra ilgili dosya/kayıt; kırpma kuralı testli.
- Atıf: her AI cümlesi hangi kayıttan geldiğini gösterir (rapor kuralı: dayanaksız madde yok).

### 4.4 Sağlayıcı soyutlaması

`AIProvider` protokolü: `stream(messages, tools) -> AsyncStream<AIEvent>`; uygulamalar `AnthropicProvider`, `FoundationModelsProvider`, (MAS dışı) `CodexProvider`. Yetenek bildirimi: araç çağırma var mı, bağlam uzunluğu, cihaz üstü mü. Cihaz üstü sağlayıcıda içerik hiç ayrılmaz.

### 4.5 Proaktif ajanlar

Zamanlanmış, **yalnızca öneri üreten** görevler: "Her sabah Özet taslağı", "Cuma öğleden sonra haftalık rapor taslağı", "Geciken işler için hatırlatma önerisi". Çıktı onay kutusuna düşer. Uygulama kapalıyken çalışmaz (arka plan ajanı ayrı karar; vaat edilmez).

### 4.6 Sistem entegrasyonu

App Intents (Siri, Kısayollar, Spotlight), kontrol merkezi/widget (bugünün özeti, zamanlayıcı), menü çubuğu hızlı aksiyon, Odak filtreleri. Hepsi Action Registry'den üretilir.

### 4.7 Güvenlik ve değerlendirme

- **Prompt enjeksiyonu savunması:** dosya/e-posta içeriği "veri" olarak çerçevelenir; içerikten gelen komut hiçbir eylemi tetikleyemez; araç çağrıları şema ve risk kademesine karşı doğrulanır.
- **Kiracı (marka) yalıtımı testleri:** başka markanın kimliğiyle çağrılan her araç reddedilir (bugünkü kural, eylem sayısı arttıkça genişletilmiş test matrisi).
- **Altın istem seti:** 50+ senaryo, sahte sağlayıcıyla (deterministik) ve gerçek sağlayıcıyla (elle) çalışır; "ne yapmalıyım", "raporu hazırla", "bunu sil" (onay ister), "başka markanın verisini göster" (reddeder).
- Eylem başına birim test; plan atomikliği testi; geri alma testi.

### 4.8 Gizlilik ve sandbox

- App Sandbox + entitlements: kullanıcı seçimli dosya erişimi (security-scoped bookmark), ağ istemcisi, Keychain.
- Marka klasörleri kullanıcı onaylı bookmark ile; bugünkü `~/Documents/...` varsayımı kalkar.
- `PrivacyInfo.xcprivacy`, App Privacy etiketleri, veriyi dışa aktar/sil.
- Günlükte içerik yok (bugünkü kural 6 korunur).

## 5. Aşamalar ve kabul ölçütleri

| Aşama | İçerik | Kabul ölçütü (ölçülür) |
|---|---|---|
| **F1 Action Registry** | Kayıt defteri, mevcut 7 eylemin taşınması, 10+ yeni eylem, önizleme/geri alma | Her eylem için test; `scripts/test.sh` temiz; ⌘K ve AI aynı kayıttan; marka yalıtım testi her eylemde |
| **F2 Plan hattı** | Atomik plan, `v5` migration, onay sayfasında diff, plan geri alma | Plan ortasında hata → hiçbir değişiklik; geri alma sonrası veri bire bir aynı (test) |
| **F3 Sağlayıcılar** | `AIProvider` protokolü, Foundation Models, sahte sağlayıcı | Sahte sağlayıcıyla altın istem seti geçer; cihaz üstü yolda ağ çağrısı yok (test) |
| **F4 Bağlam motoru** | Gömme, anlamsal arama, token bütçesi, atıflar | Başka marka verisi hiçbir sorguda dönmez; atıf olmayan AI cümlesi işaretlenir |
| **F5 Güvenlik/değerlendirme** | Enjeksiyon testleri, altın set, red-team senaryoları | Enjeksiyon senaryolarının tamamında eylem tetiklenmez |
| **F6 Sistem entegrasyonu** | App Intents, widget, Spotlight, proaktif taslaklar | Kısayollar'dan tetiklenen eylem yine onay sayfasına düşer |
| **F7 Sandbox ve gizlilik** | Entitlements, bookmark, privacy manifest, dışa aktar/sil | Sandbox'lı derlemede tüm temel akışlar çalışır (gerçek pencere ölçümü) |
| **F8 App Store hazırlığı** | Xcode projesi, imza, StoreKit 2, ekran görüntüleri, yerelleştirme, erişilebilirlik denetimi | Kurucu "yayına hazır" dediğinde; **şimdilik ertelendi** |

Her aşama sonunda: `scripts/test.sh` + `scripts/build-app.sh` + `python3 scripts/l10n.py check` temiz, gerçek pencerede yakalama ile doğrulama, README "Bilinen sınırlar" güncel.

## 6. Başlangıç sırası

1. F1'in ilk dilimi: `AppAction` protokolü + 3 eylem (görev düzenle, tarih değiştir, zamanlayıcı) + AI aracı olarak açma + testler. Küçük başla, mimariyi tek dikey dilimle kanıtla.
   **Durum (2026-10-04): ilk dilim yapıldı.** `Sources/MarkaCore/Actions/AppAction.swift`: `AppAction`/`TaskEditAction`, risk kademesi, `ActionPreview` (alan bazında önce/sonra), `UndoRecord`, `ActionRegistry`; eylemler `task.reschedule` (+ "N gün ertele" yardımcısı), `task.rename`, `task.setStatus` (hepsi `needsApproval`). Yeni öneri türü `updateTask` (onayla eylem kaydından uygulanır, önceki değerler öneriye yazılır, geri alınır; kullanıcı sonradan düzenlediyse geri alma reddedilir). AI aracı `gorev_guncelle_oner` yalnız öneri üretir. Onay sayfası "Son tarih: 12 Eki → 15 Eki" satırını gösterir (MARKA_SNAPSHOT çiziminde görüldü). 18 test (`EylemKaydiTests`).
   **Yapılmadı:** zamanlayıcı eylemi; mevcut 7 öneri türünün kayda taşınması; ⌘K'nin kayıttan türemesi; tarihi kaldırma önerisi (eylem destekler, araç desteklemez). **Doğrulanmadı:** gerçek pencere, canlı yapay zekâ yanıtı (araç gerçek modelle denenmedi).
2. Dilim çalışınca kalan eylemleri taşı.
3. F2.

## 7. Riskler ve dürüst sınırlar

- Canlı AI yanıtı hiç denenmedi (anahtar yok). **Kurucudan Ayarlar'a anahtar girmesi gerekir**; anahtar sohbette paylaşılmaz. Bu olmadan F1–F5'in gerçek-sağlayıcı kısmı doğrulanamaz.
- Foundation Models'in araç çağırma kalitesi bilinmiyor; F3'te ölçülür, kötüyse yalnız özet/sınıflama için kullanılır.
- Sandbox'a geçiş marka klasörü ve dosya erişim akışını değiştirir; F7 en riskli göç.
- Codex ve Sparkle MAS'ta yok; doğrudan dağıtım ayrı bir karar.
- App Store inceleme sonucunu bilemeyiz; yönergelere uyum için gereken parçalar planda, onay garantisi yok.
- Kod hâlâ commit edilmedi (çalışma ağacında ~40 dosya); aşamaya girmeden önce kurucudan commit onayı istenmeli.
