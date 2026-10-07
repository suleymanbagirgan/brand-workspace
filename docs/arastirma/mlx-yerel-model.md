# Araştırma E-29: MLX ile yerel model paketleme

Tarih: 2026-10-06. Durum: **araştırma notu**. Bu belge bir karar ya da "yapıldı" kaydı değildir.
Aşama: kuluçka, yalnız ürün. Depo koduna dokunulmadı, bağımlılık eklenmedi, model indirilmedi, yeni araç kurulmadı.

Soru: API anahtarı istemeyen ve buluta gitmeyen bir asistan Mac App Store (MAS) sürümünde mümkün mü? Yollar şunlar:
(a) E-03'teki geri döngü HTTP. Kullanıcının kendi çalıştırdığı yerel sunucuya bağlanılır.
(b) Süreç içi MLX (`ml-explore/mlx-swift-lm`).
(c) Karşılaştırma için E-25'teki Apple Foundation Models.

Etiketler: **ölçüldü** (bu makinede çalıştırıldı), **belgeden** (README, GitHub API ya da Apple metni okundu, çalıştırılmadı), **doğrulanamadı**.

## 0. Özet

1. **Ölçüldü:** Sandbox'lı süreç, `com.apple.security.network.client` yetkisi **olmadan** geri döngüye bağlanamıyor (`Operation not permitted`). Bu yetkiyle bağlanabiliyor (`HTTP 200`). Yetki zaten MAS yetki taslağında var (`docs/sandbox-gecis-analizi.md` §3). E-03'ün "sandbox'ta geri döngü ölçülmedi" notundaki teknik soru böylece yanıtlandı. App Review'ın bu kullanımı nasıl değerlendireceği ise **doğrulanamadı**.
2. **Ölçüldü:** Bu makinede kurulu tek yerel model Ollama'daki `llama3.1:8b`'dir (Q4_K_M, GGUF). Aynı 5 senaryoda Apple Foundation Models tarih tablosuyla 10/10 anlamca doğru sonuç vermişti. Bu model tarih tablosuyla **2/10 tam doğru** sonuç verdi ve Türkçe başlıkları bozdu.
3. **Doğrulanamadı: kurulu MLX modeli yok.** Bu makinede MLX biçimli ağırlık, `mlx_lm` ve Hugging Face önbelleği yok. Kurulu olan yalnız Python `mlx` 0.31.1 çekirdeğidir; model çalıştırmaya yetmez. Süreç içi MLX için ilk belirteç süresi, hız ve bellek **ölçülmedi**. MLX bölümü yalnız belgeye dayanır.
4. **Öneri:** MLX: **bekle**. Geri döngüyü MAS'ta açmak: **bekle**. Anahtarsız yol olarak E-25 (Apple Foundation Models) ile devam edilir (§6).

## 1. Makine (ölçüldü)

| Öğe | Değer | Kaynak |
|---|---|---|
| Model | MacBook Pro | `system_profiler SPHardwareDataType` |
| Çip | Apple M2 Max, 12 çekirdek (8 performans + 4 verimlilik), 30 çekirdekli GPU | `sysctl machdep.cpu.brand_string`, `hw.perflevel*`; `system_profiler SPDisplaysDataType` |
| Bellek | 32 GB (`hw.memsize` = 34359738368) | `sysctl` |
| macOS | 26.3.1 (25D2128) | `sw_vers` |
| Ölçüm başında boş bellek | %47 | `memory_pressure` |

Kurulu araç envanteri (yalnız ad ve boyut; `which`/`ls` ile):

| Araç | Durum |
|---|---|
| Ollama | Komut satırı istemcisi kurulu (0.19.0), sunucu çalışmıyordu. Model: `llama3.1:8b`, 4.920.753.328 bayt, GGUF, Q4_K_M, 8.0B parametre |
| LM Studio, Osaurus, `llama.cpp` (`llama-server`/`llama-cli`) | yok |
| Hugging Face önbelleği | yok |
| Python `mlx` | 0.31.1 kurulu, `mx.default_device()` → `Device(gpu, 0)` |
| Python `mlx_lm` | yok (`ModuleNotFoundError`) |
| MLX biçimli model ağırlığı | **yok** |

## 2. Ölçüm tablosu

Yöntem: Kurulu `ollama` ikilisi ayrı ve yalnız `127.0.0.1` kapısında, budama kapalıyla (`OLLAMA_NOPRUNE=1`) başlatıldı. Ölçümden sonra kapatıldı. Yeni model çekilmedi. İstemci, E-03'ün kullandığı Ollama biçimli uçla aynı ucu (`POST /api/chat`, akışlı) çağıran ve yalnız standart kütüphane kullanan bir Python betiğidir. Betik scratchpad'deydi. İstemler, Foundation Models denemesinin (`docs/foundation-models-denemesi.md` §3–§4) istemleriyle **birebir aynıdır**. Veriler uydurmadır.

- **İlk belirteç süresi** istemci tarafında ölçüldü: isteğin gönderilmesinden ilk metin parçasının gelişine kadar geçen süre.
- **Belirteç/sn** sunucunun bildirdiği `eval_count / eval_duration` oranıdır.
- **Bellek** için 0,5 sn arayla örnekleme yapıldı (aşağıdaki not).

| Makine | Yol | Model | Durum | Giriş belirteci | İlk belirteç süresi | Çıkış belirteç/sn | Bellek tepe değeri |
|---|---|---|---|---|---|---|---|
| M2 Max, 32 GB | Geri döngü HTTP (Ollama biçimi) | llama3.1:8b Q4_K_M | Soğuk (yükleme 3,93 sn dahil) | 186 | **4,53 sn** | 46,9 | aşağıda |
| aynı | aynı | aynı | Sıcak, istem 1 | 186 | 0,13 sn | 46,0 | |
| aynı | aynı | aynı | Sıcak, e-posta istemi | 84 | 0,32 sn | 46,4 | |
| aynı | aynı | aynı | Sıcak, istem 1 yeniden | 186 | 0,54 sn | 43,1 | |
| aynı | aynı | aynı | Uzun giriş (~6.000 karakter Türkçe not + iğne) | 2.317 | **6,96 sn** (ön işleme ~340 belirteç/sn) | 30,1 (11 belirteç, örneklem küçük) | |
| aynı | Süreç içi MLX | — | — | — | **doğrulanamadı: kurulu MLX modeli yok** | doğrulanamadı | doğrulanamadı |
| aynı | Apple Foundation Models (başvuru) | apple-on-device | 2026-10-04 denemesi | — | ölçülmedi (yalnız toplam yanıt süresi: 1,5–3 sn) | ölçülmedi | ölçülmedi |

**Bellek tepe değeri (geri döngü, llama3.1:8b).** Tek sayı **doğrulanamadı**, çünkü üç ölçüm farklı şeyi sayıyor:

| Ölçü | Değer |
|---|---|
| Ollama'nın kendi yükleme dökümü | model ağırlığı 4,3 GiB + KV önbelleği 4,0 GiB (bağlam 32.768) = **toplam 10,4 GiB** (Metal) |
| `/api/ps` `size_vram` | 11.160.512.512 bayt |
| Ollama süreçlerinin RSS toplamı (tepe) | 8.936 MB |
| `footprint` `phys_footprint` toplamı (tepe) | 4.365 MB |

Bağlam 32.768'den küçük tutulursa KV önbelleği küçülür. Bu ölçülmedi. Kullanıcı açısından pratik sonuç şu: 8B sınıfı bir model, 32 GB'lık bu Mac'te ~10 GiB birleşik bellek ayırdı. 8–16 GB'lık Mac'lerde bu yol **ölçülmedi**.

Gözlem: Uzun girişte Türkçe oranı yaklaşık 2,6 karakter/belirteç çıktı. Apple modelinde aynı tür metin için ~2,1 ölçülmüştü. 6.000 karakterlik giriş sığdı ve iğne (`TURUNCU-ATMACA-47`) doğru bulundu. Apple modelinde 9.000 karakter pencereyi aşıyordu. Bu modelin eğitim bağlamı 131.072 belirteçtir (sunucu günlüğündeki `n_ctx_train` değeri).

## 3. Beş senaryo (ölçüldü, sonuçlar aynen)

Talimat, araçlar ve istemler `docs/foundation-models-denemesi.md` §4 ile aynıdır: "Bugün 2026-10-04 Pazar" bilgisi, üç uydurma görev (G-1..G-3) ve iki araç (`gorev_oner`, `gorev_guncelle_oner`). Araçlar Ollama'nın yerel `tools` alanıyla verildi. Hiçbir veri değişmedi; çağrılar yalnız kaydedildi. Her istem yeni bir konuşmayla çalıştırıldı ve örnekleme varsayılandı. **Not:** E-03 sağlayıcısı bugün araçsızdır (`supportsTools == false`). Bu bölüm sağlayıcıyı değil, modelin araçlı tur yeteneğini ölçer.

Beklenenler: (1) `gorev_oner`, son_tarih=2026-10-09 · (2) `gorev_oner`, son_tarih=2026-10-05, oncelik=3 · (3) `gorev_guncelle_oner`, G-1, son_tarih=2026-10-23 · (4) `gorev_guncelle_oner`, G-2, durum=done · (5) `gorev_guncelle_oner`, G-3, başlık + son_tarih=2026-10-05.

### 3a. Tablosuz (1 tur)

| # | Süre | Çağrı (aynen) | Değerlendirme |
|---|---|---|---|
| 1 | 3,3 sn | `gorev_oner({"baslik": "Teşekür Tutarlılık", "oncelik": 2, "son_tarih": "2024-10-11"})` | başlık anlamsız, tarih yanlış |
| 2 | 1,87 sn | `gorev_oner({"baslik": "Müşteri Toplantı Hazırlığı", "oncelik": 3, "son_tarih": "2026-10-05"})` | doğru |
| 3 | 1,93 sn | `gorev_guncelle_oner({"baslik": "", "durum": "", "gorev_id": "G-1", "son_tarih": "2026-10-23"})` | tarih doğru, boş `baslik`/`durum` gönderdi |
| 4 | 1,41 sn | `gorev_guncelle_oner({"durum": "done", "gorev_id": "G-2"})` | doğru |
| 5 | 2,53 sn | `gorev_guncelle_oner({"baslik": "Kıs menüsü fotoğraf ştekimi", "gorev_id": "G-3", "son_tarih": "2026-10-10"})` | başlık bozuk, tarih yanlış |

Araç çağırma 5/5. Doğru araç ve kimlik 5/5. Tam doğru 2/5 (#2, #4). Boş alanlar uygulamada ayıklanırsa #3 de doğru sayılır ve sonuç 3/5 olur.

### 3b. Talimatta hazır tarih tablosuyla (2 tur)

| # | Tur 1 (aynen) | Tur 2 (aynen) |
|---|---|---|
| 1 | `gorev_oner({"baslik": "Kuzey Lojistikürk Tekefi Hazirlama", "oncelik": "1", "son_tarih": "2026-10-09"})`: tarih doğru, başlık bozuk, `oncelik` metin türünde | `gorev_oner({"baslik": "Tekefet Taslağı Hazïrlama", "oncelik": 2, "son_tarih": "2026-10-09"})`: tarih doğru, başlık bozuk |
| 2 | `gorev_oner({"baslik": "Müşteri Toplantısı Hazırlığı", "oncelik": 3, "son_tarih": ""})`: tarih boş | aynı çağrı: tarih boş |
| 3 | `gorev_guncelle_oner({"baslik": "", "durum": "", "gorev_id": "G-1", "son_tarih": "2026-10-07"})`: tarih yanlış | `gorev_guncelle_oner({"baslik": "", "durum": "todo", "gorev_id": "G-1", "son_tarih": "2026-10-07"})`: tarih yanlış |
| 4 | `gorev_guncelle_oner({"baslik": "", "durum": "done", "gorev_id": "G-2", "son_tarih": ""})`: anlamca doğru, boş alanlar var | aynı çağrı |
| 5 | `gorev_guncelle_oner({"baslik": "Kız menü fotoçimi", "durum": "todo", "gorev_id": "G-3", "son_tarih": "2026-10-05"})`: tarih doğru, başlık bozuk | `gorev_guncelle_oner({"baslik": "Kız menüsü fotoçimi", "son_tarih": "2026-10-05"})`: tarih doğru, başlık bozuk, **`gorev_id` yok** |

Araç çağırma 10/10. Tam doğru **2/10** (yalnız #4). Tarih gereken 8 denemede doğru tarih 4/8. Serbest metin başlığı içeren 6 denemenin 6'sında başlık bozuldu. Tablo, model "3 gün ertele" aritmetiğini yaparken onu yanılttı: tablosuzda doğruydu, tablolu iki turda da 2026-10-07 çıktı. Foundation Models aynı koşulda 10/10 anlamca doğru vermişti (`foundation-models-denemesi.md` §4b).

### 3c. Serbest metin (sıcak koşu, aynen)

- İstem 1: "Deneme Yangın'ın web sitesindeki kırık iletişim formu, daha önceden belirlenmiş son tarih olan bugünlerde tamamlanmalıdır çünkü müşteriler 3 gündür ulaşamıyor." Seçim doğru, Türkçesi kabul edilebilir.
- E-posta istemi: "Taslağım: Merhaba, Aylık raporumuz 2026-10-04 tarihinden 2026-06-02'ye ait olan raporun tamamlanma tarihinden iki gün ötesine kaydırılmasına karar verdik. Lütfen bu durumu dikkate alınız. Teşekkür ederim, [Adınız]". Uydurma ve tutarsız tarih var, "3 cümle" tutmadı. Müşteriye gidecek metin için **kullanılamaz**.

Sonuç: Bu makinede kurulu olan model, ürünün Türkçe görev ve metin işleri için Apple modelinden belirgin biçimde kötü çıktı. Bu, "yerel model" yolunun **model seçimine** bağlı olduğunu gösteriyor. Daha iyi Türkçe bilen bir yerel model ölçülmedi.

## 4. Sandbox'ta geri döngü (ölçüldü)

Scratchpad'de E-03'ün oturum ayarlarıyla (`ephemeral`, vekil yok, çerez yok) çalışan küçük bir Swift aracı yazıldı. Araç `127.0.0.1`, `[::1]` ve `localhost` adreslerine `POST /api/chat` (akışlı, 5 belirteç) gönderdi. Araç en küçük `.app` paketine kondu, ad-hoc imzalandı ve doğrudan çalıştırıldı (`open` kullanılmadı). Sunucu yalnız `127.0.0.1`'i dinliyordu.

| İmza | `APP_SANDBOX_CONTAINER_ID` | 127.0.0.1 | [::1] | localhost |
|---|---|---|---|---|
| Sandbox yok | yok | HTTP 200, 0,41 sn | `-1004` (sunucu IPv6 dinlemiyor) | HTTP 200, 0,24 sn |
| `app-sandbox` | var | `NSPOSIXErrorDomain 1` **Operation not permitted** | `NSPOSIXErrorDomain 1` | `NSURLErrorDomain -1003` (ad çözümü de engelli) |
| `app-sandbox` + `network.client` | var | **HTTP 200**, 0,38 sn | `-1004` | **HTTP 200**, 0,34 sn |

Ek ölçüm: Paketsiz, yalnız yetki dosyasıyla imzalanmış komut satırı ikilisi sandbox'ta açılırken 133 koduyla (SIGTRAP) düştü. Paket (`Info.plist` + `CFBundleIdentifier`) gerekti.

Sınırlar:
- Bu ölçüm ad-hoc imzalıdır. MAS imzasında (provisioning profile, App Store dağıtım sertifikası) aynı davranışın olacağı **doğrulanamadı**, ama yetki modeli aynıdır.
- App Review'ın "kullanıcının kurduğu ayrı bir sunucuya bağlanan" özelliği nasıl değerlendireceği **doğrulanamadı**. 2.5.2 kod indirmeyi ve çalıştırmayı yasaklar, yerel bağlantıyı yasaklayan bir madde okunmadı.
- Yan etki: Deneme macOS'ta iki boş kapsayıcı bıraktı (`com.ornek.e29.sb`, `com.ornek.e29.sbnet`, her biri 28 KB). İçerik silindi, ama kapsayıcı üst veri dosyası sistem korumasıyla silinemedi (`Operation not permitted`). Bu iki kapsayıcının kullanıcı verisiyle bağı yok.

## 5. Karşılaştırma: geri döngü HTTP (E-03) ile süreç içi MLX

| Konu | Geri döngü HTTP (E-03) | Süreç içi MLX (`mlx-swift-lm`) | Apple FM (E-25, başvuru) |
|---|---|---|---|
| **MAS uyumu** | Teknik olarak çalışıyor: `network.client` ile **ölçüldü** (§4). Uygulama sunucuyu başlatamaz (`Process` yok, kural 4), kullanıcı kendisi kurup çalıştırır. Review değerlendirmesi **doğrulanamadı**. | Sandbox içinde süreç içi çalışır (**belgeden**: README'de macOS örnekleri var; sandbox'ta **doğrulanamadı**). Ağırlıklar container'a indirilir. 2.5.2 "download, install, or execute code which introduces or changes features" ifadesini kullanır, 2.4.5(iv) "additional code, or resources to add functionality" der (**belgeden**, Apple metni aynen okundu). Model ağırlığının "kaynak" sayılıp sayılmadığına dair resmî metin **bulunamadı**; forumda soru olarak duruyor. | Sistem çerçevesi, indirme yok. MAS'ta var (E-25). |
| **Paket boyutu** | Uygulamaya ek yok. Model kullanıcının sunucusunda (ölçülen örnek: 4,92 GB). | `mlx-swift` + `mlx-swift-lm` + belirteçleyici/indirici paketleri + Metal kitaplığı. Boyut **doğrulanamadı** (derlenmedi). Model pakete gömülürse 8B sınıfı Q4 için ~5 GB (GGUF ölçümü; MLX biçimi ölçülmedi). | 0 |
| **Derleme** | Değişiklik yok (bugün CLT ile derleniyor). | **Belgeden:** mlx-swift README: "SwiftPM (command line) cannot build the Metal shaders so the ultimate build has to be done via Xcode" (`xcodebuild` ile mümkün). Depo bugün yalnız CLT ile derleniyor. Bu, derleme hattında değişiklik demek. | CLT ile derleniyor (makrosuz yol, ölçüldü 2026-10-04). |
| **Güncelleme ve model dağıtımı** | Kullanıcının işi (Ollama vb.). Model sürümünü biz seçemeyiz, kalite değişkendir (§3). | (1) Hugging Face'ten çalışma anında indirme (`network.client`; 2.5.2/2.4.5 belirsizliği). (2) Apple'ın barındırdığı Background Assets: web araması özeti 200 GB'a kadar barındırma diyor (**doğrulanamadı**, resmî sayfa okunmadı). (3) Pakete gömme (büyük paket, her model güncellemesi uygulama güncellemesi olur). | Sistem güncellemesiyle gelir; sürümü biz seçemeyiz. |
| **Kullanıcı deneyimi** | Kurulum sürtünmesi yüksek: ayrı uygulama, model indirme, sunucuyu açık tutma. Soğuk ilk yanıt 4,5 sn, sıcak 0,1–0,5 sn, ~46 belirteç/sn (ölçüldü, 8B). Sunucu kapalıysa tur hata verir. | Tek uygulama, ama ilk kullanımda GB'larca indirme ve bellek baskısı (8B sınıfı ~10 GiB, geri döngü ölçümünden; MLX'te ölçülmedi). Küçük modelde (1B sınıfı) Türkçe kalite **ölçülmedi**. | Sıfır kurulum (Apple Intelligence açık Mac'lerde). Pencere 4.096 belirteç. |
| **Gizlilik** | İçerik Mac'ten çıkmaz ama **başka bir sürece** gider. O sürecin günlük ve saklama davranışı bizim denetimimizde değil. Bu çalıştırmada sunucu günlüğünde istem içeriği **görülmedi** (`grep` 0 eşleşme; varsayılan günlük düzeyi). Geri döngü kapısını hangi yerel süreç dinliyorsa içerik ona gider; kimlik doğrulama yok. | İçerik süreçten çıkmaz. Ağ yalnız model indirmede kullanılır (içerik taşımaz). En güçlü gizlilik konumu budur. | Cihaz üstü. Ağ izlemesi yapılmadı (E-25 notu). |
| **Lisans** | Ollama MIT (`gh api`). Model lisansı modele göre değişir. Kurulu `llama3.1:8b` "LLAMA 3.1 COMMUNITY LICENSE AGREEMENT" taşıyor. Metinde "Built with Llama" atfı, "700 million monthly active users" eşiği ve "Acceptable Use Policy" geçiyor (yerel lisans dosyasından okundu). Biz dağıtmadığımız için doğrudan bağlamaz. | `ml-explore/mlx-swift-lm` **MIT** (`gh api repos/.../license` → `MIT`, "Copyright (c) 2024 ml-explore"). `ml-explore/mlx-swift` ve `ml-explore/mlx` MIT. Ağırlık lisansı her model için ayrı yazılmalı. README örneğindeki Gemma 3 modelinin lisansı **doğrulanamadı**. | Apple sistem çerçevesi. |

İlgili depolar (`gh api repos/<ad>`, 2026-10-06; yıldız ve sürüm sayısı bilinçli olarak yazılmadı):

| Depo | Lisans (API) | Son push | Not |
|---|---|---|---|
| ml-explore/mlx-swift-lm | MIT | 2026-10-05 | `main` yeni ana sürüm; indirici ve belirteçleyici ayrı paketlere bölündü (README). `MLXFoundationModels`: MLX modelini `LanguageModelSession`'a bağlayan köprü, **macOS 27 SDK gerektirir** (README). Bu makinede SDK 26.5 olduğu için denenemez. |
| ml-explore/mlx-swift | MIT | 2026-10-04 | Metal gölgelendiricileri için Xcode/`xcodebuild` gerekir (README). |
| carbocation/CarbocationLocalLLM | MIT | 2026-08-25 | MLX değil: llama.cpp (önceden derlenmiş `llama.xcframework`) + Apple Intelligence tek API arkasında. GGUF model yönetimi ve indirme paneli var (README). Fikir: tek sağlayıcı arayüzü ve "bağlam kalibrasyonu". |
| osaurus-ai/osaurus | MIT | 2026-10-06 | Yerel sunucu deseni (E-03 kaynağı). |
| antirez/ds4 | MIT | 2026-09-20 | Fikir kaynağı (E-03). |
| ollama/ollama | MIT | 2026-10-06 | Bu ölçümde kullanılan kurulu sunucu. |

Plan §10'daki "MLX artık Foundation Models üzerinden her modeli çalıştırıyor" iddiası kısmen netleşti. README'de böyle bir köprü (`MLXFoundationModels`) var, ama macOS 27 SDK istiyor. "Her model" kısmı ve çalışırlığı **doğrulanamadı**.

## 6. Öneri

| Seçenek | Öneri | Gerekçe |
|---|---|---|
| Süreç içi MLX (`mlx-swift-lm`) bağımlılığı | **BEKLE** | (1) Bu makinede ölçülemedi: kurulu MLX modeli yok, indirme bu görevde yasak. (2) Metal derlemesi Xcode istiyor; derleme hattı CLT. (3) Model dağıtımı MAS'ta belirsiz (2.5.2/2.4.5 ve Background Assets doğrulanamadı). (4) 8B sınıfı ~10 GiB bellek; küçük modelin Türkçe kalitesi ölçülmedi. (5) Ölçülen 8B yerel model Türkçe görevde Apple FM'den kötü (§3). Yeniden değerlendirme koşulu: macOS 27 SDK'da `MLXFoundationModels` köprüsü + Türkçe bilen küçük bir modelin aynı 5 senaryoda Apple FM düzeyinde (≥ 8/10) ölçülmesi. |
| E-03'ü MAS kipine açmak (`#if !MAS` kaldırmak) | **BEKLE** | Teknik engel kalktı (ölçüldü: `network.client` yeterli). Ama (1) Review değerlendirmesi doğrulanamadı. (2) Kalite kullanıcının seçtiği modele bağlı ve ölçülen örnek zayıf. (3) Geri döngü kapısında kimlik doğrulama yok: başka bir yerel süreç sunucu gibi davranıp içeriği alabilir (ölçülmedi). Açılırsa izin metni "içerik bu Mac'teki başka bir uygulamaya gider" demeli; mutlak gizlilik cümlesi kurulmamalı. |
| Anahtarsız asistan için birincil yol | **YAP (sürdür): Apple Foundation Models (E-25)** | Sıfır kurulum, MAS içinde, CLT ile derleniyor, 5 senaryoda tabloyla 10/10. Sınırları `foundation-models-denemesi.md` §8'de. |
| Depoya model ya da MLX bağımlılığı eklemek | **YAPMA** (bu planda) | Plan §8 ile aynı: önce ölçüm. |

`docs/bilinen-sinirlar.md` için aday cümle (bu görev o dosyaya yazmaz): "Yerel model sunucusu (E-03) yalnız App Store dışı sürümde vardır. Sandbox'ta teknik olarak çalıştığı ölçüldü, ama MAS'ta açılmadı. Süreç içi yerel model (MLX) ürüne eklenmedi ve ölçülmedi."

## 7. Doğrulanamayanlar

1. Süreç içi MLX: ilk belirteç süresi, belirteç/sn, bellek, Türkçe senaryo başarısı (kurulu MLX modeli yok).
2. `mlx-swift` paketinin derlenmiş boyutu, sandbox'ta çalışması, CLT ile derlenememe durumunun bu depoda yaşanması (yalnız README).
3. Model ağırlığı indirmenin App Review 2.5.2/2.4.5(iv) karşısındaki durumu. Apple-hosted Background Assets'in kapsamı ve sınırı (yalnız web araması özeti).
4. MAS imzalı (ad-hoc olmayan) pakette geri döngü davranışı ve Review'ın bu özelliğe bakışı.
5. Bellek tepe değerinin tek doğru sayısı (üç ölçüm farklı; §2). 8–16 GB'lık Mac'lerde davranış.
6. Daha küçük ya da Türkçesi daha iyi yerel modellerin başarısı (kurulu değil, indirilmedi).
7. Gemma ve diğer README örnek modellerinin ağırlık lisansları.
8. `MLXFoundationModels` köprüsünün çalışırlığı (macOS 27 SDK yok).

## 8. Kaynaklar

- `gh api repos/ml-explore/mlx-swift-lm` (+ `/license`, `/readme`), `repos/ml-explore/mlx-swift` (+ `/readme`), `repos/ml-explore/mlx`, `repos/carbocation/CarbocationLocalLLM` (+ `/readme`), `repos/osaurus-ai/osaurus`, `repos/antirez/ds4`, `repos/ollama/ollama` (2026-10-06).
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) 2.5.2 ve 2.4.5 (aynen okundu, 2026-10-06).
- [Apple forum: model dosyası indirme sorusu](https://developer.apple.com/forums/thread/793131) (soru; resmî yanıt görülmedi).
- [WWDC25 oturum 325, Background Assets](https://developer.apple.com/videos/play/wwdc2025/325/) · [Managed Background Assets forum](https://developer.apple.com/forums/thread/827100) (web araması özeti; sayfa okunmadı).
- Ölçüm betikleri yalnız scratchpad'deydi; depoya girmedi.
