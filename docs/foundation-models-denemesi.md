# Apple Foundation Models denemesi (spike, 2026-10-04)

Soru: Apple Foundation Models (macOS 26, cihaz üstü), "kendi Claude anahtarını getir" (BYOK) sürtünmesini kaldıran **sıfır kurulumlu** bir AI sağlayıcısı olabilir mi?

Yöntem: depo koduna dokunulmadı. Ayrı bir SwiftPM paketi (`scratchpad/fm-deneme`, kendi `.build`'i) yazıldı ve **gerçekten çalıştırıldı**. Tüm veriler uydurma (Kuzey Lojistik, Deneme Yangın, Örnek Kafe Zinciri). Ağ izleme yapılmadı; gizlilik bölümü yalnız Apple belgelerine dayanır. Aşağıdaki çıktılar kısaltılmıştır, ama hiçbiri uydurma değildir. Model varsayılan örnekleme (rastgele) ile çalıştı, bu yüzden aynı istem farklı çalıştırmalarda farklı sonuç verebilir.

## 1. Ortam

| Öğe | Değer |
|---|---|
| macOS | 26.3.1 (25D2128) |
| Donanım | Apple M2 Max |
| Sistem dili | tr-TR |
| Command Line Tools | Swift 6.3.3, SDK'da `FoundationModels.framework` **var** |
| Xcode | 26.6 (17F113), SDK 26.5, `DEVELOPER_DIR` ile seçildi |

```
$ ls $(xcrun --show-sdk-path)/System/Library/Frameworks | grep -i Foundation
... FoundationModels.framework ...
```

**Önemli bulgu (derleme):** `@Generable` / `@Guide` makroları **yalnız Xcode araç zinciriyle** derleniyor. Yalnız Command Line Tools ile derlemede şu hata çıkıyor (aynen):

```
error: external macro implementation type 'FoundationModelsMacros.GenerableMacro' could not be found
for macro 'Generable(description:)'; plugin for module 'FoundationModelsMacros' not found
```

Makro kullanmayan yol (`DynamicGenerationSchema` + `GeneratedContent`) ise **Command Line Tools ile derlendi ve çalıştı** (bkz. §4). Depo bugün Xcode'suz CLT ile derlendiği için bu, entegrasyonun dinamik şema yoluyla yapılması gerektiği anlamına geliyor.

## 2. Kullanılabilirlik (`fm-deneme ortam`)

```
availability: available
isAvailable: true
contextSize: 4096
supportsLocale(tr_TR): true
supportedLanguages (23): da-DK, de-DE, en-AU, en-GB, en-US, es-419, es-ES, es-US, fr-CA, fr-FR,
  it-IT, ja-JP, ko-KR, nb-NO, nl-NL, pt-BR, pt-PT, sv-SE, tr-TR, vi-VN, zh-Hans-CN, zh-Hant-HK, zh-Hant-TW
```

- Türkçe **resmî olarak destekleniyor** (`tr-Latn-TR`).
- Kullanılamama nedenleri API'de üç tane: `deviceNotEligible`, `appleIntelligenceNotEnabled`, `modelNotReady`. Bu makinede hiçbiri yaşanmadı. Diğer durumlar burada denenmedi.
- `tokenCount(for:)` API'si **macOS 26.4 ve sonrası** gerektiriyor. Bu makine 26.3.1 olduğu için kullanılamadı. `contextSize` geriye dönük (`@backDeployed`) olduğu için okunabildi.

## 3. Basit Türkçe istem (`fm-deneme basit`)

İstem: "Şu görev listesinden en acil olanı seç ve tek cümleyle nedenini açıkla: (4 uydurma görev, biri gecikmiş iletişim formu)"

```
YANIT (1.88 sn):
En acil görev **Deneme Yangın'ın web sitesindeki kırık iletişim formu**; müşteriler 3 gündür ulaşamıyor
ve gecikmiş olması sebebiyle aciliyet arz ediyor.
```

İstem 2: "Kuzey Lojistik müşterisine, aylık raporun 2 gün gecikeceğini bildiren kibar, 3 cümlelik bir e-posta taslağı yaz."

```
YANIT 2 (1.98 sn):
Sayın Kuzey Lojistik Müşterisi,
Aylık sosyal medya raporumuz için talep ettiğiniz son tarih olan 2026-10-20, 2 gün geç kalınca,
2026-10-22 olarak güncellenmiştir. Bu gecikme için özür dileriz.
Saygılarımızla, \[İsminiz]
```

**Türkçe kalite gözlemi:**
- Seçim ve gerekçe doğru, Türkçe akıcı. Yanıt süresi 1,5–2 sn.
- Serbest metinde dilbilgisi zaman zaman bozuluyor ("2 gün geç kalınca ... güncellenmiştir"). İstenen "3 cümle" tutmadı. Markdown kaçış artıkları kaldı (`\[İsminiz]`).
- Araç yanıtlarındaki özet cümleleri de bozuk olabiliyor ("...önerildiğini ve kullanıcı onayının bekleniyor"). Bazen yanıltıcı oluyor: araç yalnız öneri kaydettiği halde "görev oluşturuldu" ya da "değiştirdim" diyor.
- Kısa sınıflama ve çıkarma işlerinde iyi. Müşteriye gidecek metin yazımında Claude düzeyinde değil.

## 4. Araç çağırma

İki araç bizim `ToolCatalog`'daki karşılıklarıyla aynı alanlara sahip: `gorev_oner(baslik, son_tarih?, oncelik? 0–3)` ve `gorev_guncelle_oner(gorev_id, baslik?, son_tarih?, durum? enum)`. Talimatta "Bugün 2026-10-04 Pazar" ve üç uydurma görev (G-1..G-3) vardı. Her istem yeni bir oturumla çalıştırıldı. Araç `call` içinde yalnız argümanları kaydetti; hiçbir veri değişmedi.

Beklenen değerler: "cuma" = 2026-10-09, "yarın" = 2026-10-05, "G-1'i 3 gün ertele" = 2026-10-23, "önümüzdeki pazartesi" = 2026-10-05.

### 4a. Tipli `@Generable` araçlar, yalnız "bugün" bilgisiyle (2 çalıştırma × 5 istem)

| # | İstem | Çalıştırma 1 | Çalıştırma 2 |
|---|---|---|---|
| 1 | Cuma gününe kadar ... teklif taslağı görevi ekle | **araç çağrılmadı**; metinde "2026-10-05 (Cuma)" yazdı | çağrıldı, son_tarih **2026-10-05** (yanlış) |
| 2 | Yarın toplantı, hazırlık görevi, acil | çağrıldı, oncelik 3 doğru, son_tarih **2026-10-04** (yanlış) | aynı hata |
| 3 | G-1'i 3 gün ertele | doğru (2026-10-23), fazladan `durum: todo` gönderdi | doğru |
| 4 | İletişim formu bitti, tamamla | doğru (G-2, done) | doğru |
| 5 | Adını değiştir + önümüzdeki pazartesiye çek | başlık doğru, son_tarih **2026-10-11** (yanlış) | başlık doğru, son_tarih **2026-10-18** (yanlış) |

Araç çağırma: **9/10**. Doğru araç ve kimlik: **9/10**. Tüm argümanlar doğru: **4/10**. Göreli Türkçe tarihler ("cuma", "yarın", "pazartesi") **6 denemenin 6'sında yanlış** çıktı. Aritmetik ("3 gün ertele") ise doğruydu.

### 4b. Aynı araçlar + talimatta hazır tarih tablosu (`araclar-tablo`, 2 × 5)

Talimata şu satır eklendi: "cuma=2026-10-09; yarın=2026-10-05; önümüzdeki pazartesi=2026-10-05 ...". Bu tabloyu uygulama hesaplayıp verir.

| # | Sonuç (2 çalıştırmada da aynı) |
|---|---|
| 1 | doğru, son_tarih 2026-10-09 |
| 2 | doğru, 2026-10-05, oncelik 3 |
| 3 | doğru, 2026-10-23 (ama iki seferde de fazladan değişmemiş `durum: todo` gönderdi) |
| 4 | doğru |
| 5 | doğru, başlık + 2026-10-05 |

Araç çağırma **10/10**, anlamca doğru **10/10**, "yalnız değişen alan" kuralına tam uyum **8/10**. Sonuç: **göreli tarihleri model değil uygulama çözmeli.** Uygulama ya bu tabloyu talimata koymalı ya da araç "cuma" gibi bir ifadeyi kabul edip tarihi kendisi hesaplamalı. Ayrıca değişmeyen alanlar uygulama tarafında ayıklanmalı.

### 4c. Dinamik şema: bizim JSON Schema → `DynamicGenerationSchema` (`fm-deneme dinamik`, 1 × 5, tablosuz)

Derleyiciyle doğrulanan API: `DynamicGenerationSchema(name:description:properties:)`, `DynamicGenerationSchema(name:anyOf: [String])` (enum karşılığı), `DynamicGenerationSchema(arrayOf:)`, `DynamicGenerationSchema(type: Int.self)`, `DynamicGenerationSchema.Property(name:description:schema:isOptional:)`, `GenerationSchema(root:dependencies:) throws`. Aracın tanımı `typealias Arguments = GeneratedContent` ve `let parameters: GenerationSchema` ile yapılıyor; argüman `arguments.jsonString` olarak alınıyor. Yazılan yaklaşık 30 satırlık çevirici, `ToolCatalog`'daki `gorev_oner` ve `gorev_guncelle_oner` şemalarını (birebir JSON kopyası) hatasız çevirdi.

| # | Çağrı (aynen) | Değerlendirme |
|---|---|---|
| D1 | `gorev_oner({"son_tarih": "2026-10-05", "baslik": "Kuzey Lojistik İçin Teklif Taslağı Hazırlama"})` | tarih yanlış |
| D2 | `gorev_oner({"son_tarih": "2026-10-04", "oncelik": 1, ...})` | tarih yanlış, "acil" → 1 (yanlış) |
| D3 | `gorev_guncelle_oner({"gorev_id": "G-1", "son_tarih": "2026-10-23"})` | doğru |
| D4 | `gorev_guncelle_oner({"durum": "done", "gorev_id": "G-2"})` | doğru |
| D5 | `gorev_guncelle_oner({"gorev_id": "G-3", "son_tarih": "2026-10-18"})` | başlık **atlandı**, tarih yanlış; yine de metinde "adını değiştirdim" dedi |

Araç çağırma 5/5, tam doğru 2/5. Hatalar 4a ile aynı türden. Dinamik yol, tipli yoldan belirgin biçimde kötü görünmüyor (örneklem küçük). Bu yolda tarih tablosu denenmedi.

Ek gözlemler:
- `minimum`/`maximum` kısıtları çeviricide eşlenmedi. `GenerationGuide` ile eşlenebilir, ama bu denenmedi.
- `GenerationSchema` `Codable`. Kodlanmış hali bir JSON Schema lehçesi: `title` ve `x-order` alanlarını içeriyor. Bizim ham JSON Schema'mız doğrudan çözülemedi (aynen): `keyNotFound(CodingKeys(stringValue: "x-order", ...))`. `title` ve `x-order` eklenince çözme **başarılı** oldu. Ancak bu biçim belgelenmemiş; ona dayanmak yerine `DynamicGenerationSchema` çevirici önerilir.
- Command Line Tools ile, makrosuz tek araçlık bir sürüm de denendi: `ÇAĞRI: {"baslik": "Bülten taslağı", "son_tarih": "2026-10-09"}`, yani doğru (talimatta cuma tarihi verilmişti).

## 5. Bağlam sınırı

- Belgeye göre (Apple TN3193): "Apple's on-device foundation model has a context window of 4096 tokens per language model session." API de aynısını söylüyor: `contextSize: 4096`. Bu sınır talimat, araç şemaları, geçmiş ve yanıtın **toplamı** içindir.
- **2.500 karakterlik** marka bağlamı (`baglam`): 1,46 sn, doğru iki madde.
- **12.000 karakterlik**, kendini tekrarlayan düzyazı bağlam: 4,80 sn, doğru yanıt (tekrar eden metin verimli belirteçlere ayrılıyor).
- **Çeşitli (tekrarsız) bağlam** (`baglam2`; tarih, tutar ve ad içeren notlar), başta bir "kod adı" iğnesiyle:

```
6.000 karakter  → 3.92 sn, YANIT: TURUNCU-ATMACA-47 (doğru)
9.000 karakter  → HATA: exceededContextWindowSize: Content contains 4334 tokens, which exceeds the maximum allowed context size of 4096.
12.000 karakter → HATA: ... 5784 tokens ...
16.000 karakter → HATA: ... 7722 tokens ...
```

  Model sessizce kırpmıyor, açık bir hata (`exceededContextWindowSize`) fırlatıyor. Ölçülen oran gerçekçi Türkçe iş notlarında **yaklaşık 2,1 karakter/belirteç**. Bu, Apple'ın Latin alfabeli diller için verdiği "3–4 karakter" ortalamasının altında. Pratik tavan, talimat dahil yaklaşık **6–8 bin karakter** Türkçe bağlam.
- **Araç şemalarının maliyeti** (`aracmaliyet`): aynı 9.000 karakterlik istem araçsız 4489, iki tipli araçla 4885 belirteç tuttu. Yani **araç başına yaklaşık 200 belirteç**. Bugünkü `brandTools` 12 araç; hepsi verilirse yaklaşık 2.400 belirteç, yani pencerenin yarıdan fazlası. Apple sağlayıcısına 2–4 araçlık bir alt küme verilmeli.

## 6. Gizlilik ve App Store

- **Cihaz dışı:** Apple'ın Apple Intelligence gizlilik metni: "In many cases, Apple Intelligence models run entirely on device so that a task can be completed without data leaving your device." WWDC25 haber metni çerçeve için şunu söylüyor: "...available when they're offline, that protect their privacy, using AI inference that is free of cost". SDK 26.5 arayüzünde Private Cloud Compute ya da sunucu modeli seçen bir API **yok** (`grep -i cloud` boş döndü). `SystemLanguageModel.default` cihaz üstü model. Belgelerde "Foundation Models framework isteği asla cihazdan çıkmaz" diyen tek, açık bir cümle bulunamadı. Güncel çevrimiçi belge sayfası "on-device and Private Cloud Compute models" ifadesini kullanıyor; bu, bu SDK'da olmayan daha yeni bir sürüme işaret ediyor olabilir. **Ağ izlemesi yapılmadı, çevrimdışı çalışma bu denemede ölçülmedi.**
- **5.1.2(i)** (resmî metin, aynen): "You must clearly disclose where personal data will be shared with third parties, including with third-party AI, and obtain explicit permission before doing so." Apple'ın kendi cihaz üstü modelinin "üçüncü taraf AI" sayılıp sayılmadığına dair resmî bir metin **bulunamadı (doğrulanamadı)**. Yoruma göre veri cihazdan ve uygulamadan çıkmadığı için "paylaşım" yok. Yine de izin ekranında "içerik bu Mac'te Apple'ın modeliyle işlenir" diye açıkça yazmak güvenli yol.

## 7. Önerilen arayüz (taslak, depoya yazılmadı)

```swift
public struct AIProviderCapabilities: Sendable {
    public var supportsTools: Bool
    public var maxToolsPerTurn: Int?          // Apple: ~2–4 (araç başı ~200 belirteç)
    public var contextTokens: Int?            // Apple: 4096 (toplam), Anthropic: büyük
    public var onDevice: Bool                 // Apple: true → izin metni farklı
    public var needsAPIKey: Bool              // Apple: false
}

public enum AIProviderAvailability: Sendable, Equatable {
    case available
    case unavailable(reason: String)          // deviceNotEligible / appleIntelligenceNotEnabled / modelNotReady
}

public protocol AIProvider: Sendable {
    var id: String { get }                    // "anthropic" | "apple" | "codex"
    var capabilities: AIProviderCapabilities { get }
    func availability() async -> AIProviderAvailability
    /// Bugünkü AIEvent akışıyla aynı. Araç çağrıları `onToolCall` üzerinden ChatEngine'e döner;
    /// ChatEngine bugünkü gibi marka kimliğini ve risk kademesini doğrular, öneri onay kartına düşer.
    func stream(system: String,
                history: [AIMessage],
                tools: [ToolSpec],
                onToolCall: @escaping @Sendable (_ name: String, _ input: JSONValue) async -> ToolResult)
        -> AsyncStream<AIEvent>
}

// FoundationModelsProvider uygulama notları (denemeden çıkanlar):
// - ToolSpec.schema (JSONValue) → DynamicGenerationSchema çevirici; makro yok (CLT ile derlenir).
// - Her ToolSpec için `struct FMTool: Tool { typealias Arguments = GeneratedContent }`;
//   call() → JSONValue.parse(arguments.jsonString) → onToolCall.
// - Talimata uygulamanın hesapladığı tarih tablosu eklenir; değişmemiş alanlar ayıklanır.
// - Geçmiş: Transcript(entries:) ya da son N mesaj; exceededContextWindowSize yakalanıp
//   "bağlam kısaltıldı" uyarısıyla yeniden denenir.
// - streamResponse anlık görüntü (kümülatif içerik) verir; textDelta için fark alınır.
// - #if canImport(FoundationModels) + @available(macOS 26, *) koruması.
```

## 8. Bilinen engeller

1. **4096 belirteçlik toplam pencere.** Türkçede yaklaşık 2 karakter/belirteç ölçüldü. Bugünkü bağlam paketleme ve 12 araç sığmıyor; ayrı ve küçük bir bütçe gerekiyor.
2. **Göreli tarih hesabı güvenilmez** (tablosuz 6/6 yanlış). Uygulama tarafında çözülmesi şart.
3. **Serbest Türkçe metin kalitesi** orta düzeyde. Model yanıltıcı özet de yazabiliyor ("oluşturdum" diyor ama yalnız öneri kaydedilmiş). Onay kartı zaten gerçeği gösterdiği için zararı sınırlı.
4. **Makrolar Xcode istiyor.** CLT'de yalnız dinamik şema yolu çalışıyor (doğrulandı).
5. **Erişim koşulu:** Apple Intelligence destekli cihaz, özelliğin açık olması ve model inmiş olması. Bunlar sağlanmazsa sağlayıcı yok; geri dönüş BYOK olur. Kapalı/indirilmemiş durumlar bu denemede yaşanmadı.
6. `tokenCount` macOS 26.4 gerektiriyor; 26.3'te bütçe ancak tahminle ya da hata mesajıyla bilinebiliyor.
7. Ölçülmeyenler: çevrimdışı çalışma, uzun çok turlu sohbet, `guardrailViolation` sıklığı, eşzamanlı oturum, bellek ve pil etkisi, 12 aracın birden verildiği durum.

## 9. Karar önerisi: **KOŞULLU EVET**

Foundation Models, **anahtarsız ilk deneyim ve kısa, yapılandırılmış işler** için sıfır kurulumlu sağlayıcı olarak eklenmeye değer: görev önerme/güncelleme, en acil işi seçme, kısa özet, sınıflama. Kanıtlar:
- Bu makinede kurulum gerektirmeden `available` döndü ve Türkçe resmî destekli.
- Yanıt süresi 1,5–3 sn.
- Tarih tablosuyla tipli araç çağırma 10/10 doğru.
- Bizim JSON şemalarımız dinamik şemaya çevrilebiliyor ve CLT ile derleniyor.

Ancak Claude BYOK'un **yerine geçemez**. 4096 belirteçlik pencere, orta düzey serbest metin kalitesi ve göreli tarih zaafı nedeniyle rapor derleme, bilgi sayfası güncelleme ve uzun bağlamlı sohbet Claude'da kalmalı. Koşullar:
- (a) Apple sağlayıcısına yalnız küçük bir araç alt kümesi ve küçük bağlam bütçesi verilir.
- (b) Göreli tarihleri uygulama çözer.
- (c) Model kullanılamıyorsa arayüz bunu nedeniyle söyler ve BYOK'a yönlendirir.
- (d) Satış metninde "Claude kalitesinde" ya da "her Mac'te" vaat edilmez; "Apple Intelligence açık Mac'lerde, cihaz üstü" denir.
