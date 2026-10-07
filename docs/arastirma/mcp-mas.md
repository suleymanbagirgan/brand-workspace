# Araştırma: Mac App Store sürümünde MCP istemcisi mümkün mü (E-28)

Tarih: 2026-10-06. Durum: **araştırma notu**, karar değil. Depo kodu değişmedi, bağımlılık eklenmedi, kod kopyalanmadı.
Girdiler: `docs/entegrasyon-plani-30.md` (§0, §1, E-28), `docs/sandbox-gecis-analizi.md`, `docs/dagitim-ve-saglayicilar.md`, `docs/oneri-zarfi.md` (E-17), `docs/bilinen-sinirlar.md` §4, MCP belirtimi (modelcontextprotocol.io ve belirtim deposu), Apple App Review Guidelines, Apple Developer Forums (DTS), `gh api` (2026-10-06 UTC).

Etiketler: **ölçüldü** = bu Mac'te çalıştırıp gördüm. **belgeden** = birincil belgeden okudum, çalıştırmadım. **doğrulanamadı** = ne ölçebildim ne birincil belgede net buldum.

## 0. Özet

1. MCP'nin iki standart taşıması var: **stdio** (istemci sunucuyu alt süreç olarak başlatır) ve **Streamable HTTP**. Eski HTTP+SSE kullanımdan kalktı. WebSocket standart değil (belgeden).
2. MAS'ta stdio ile **kullanıcının kurduğu** bir MCP sunucusunu (`npx`, `uvx`, Homebrew ikilisi) çalıştırmak hem sandbox kalıtımı hem de App Review 2.5.2 / 2.4.5 nedeniyle uygun değil. Bu, Codex'i MAS'tan çıkaran gerekçenin aynısı (belgeden).
3. MAS'a en yakın yol, **uzak Streamable HTTP** sunucusuna `network.client` yetkisiyle giden bir istemcidir. Bu aslında `api.anthropic.com` çağrısıyla aynı türden bir ağ çağrısıdır. Ama her bağlayıcı yeni bir "üçüncü taraf" olur. Bu yüzden 5.1.2(i) izin ekranı ve marka × bağlayıcı izni gerekir (belgeden).
4. Bugün MCP'siz bir köprü zaten var: **E-17 öneri zarfı**. Kullanıcının kendi ajanı (kendi MCP sunucularıyla) zarf üretir, kullanıcı içe alır, her öğe bekleyen öneri olur.
5. Öneri: stdio için **yapma**, uygulama içi HTTP MCP istemcisi için **bekle** (koşullar §4'te), zarf köprüsü için **yap** (zaten var; eksik olan arayüz düğmesi).

## 1. Taşıma türleri × App Store sandbox uyumu

| # | Taşıma | Belirtimdeki yeri | MAS uyumu | Gereken yetki | Etiket | Not |
|---|---|---|---|---|---|---|
| T1 | **stdio, kullanıcının kurduğu sunucu** (`npx …`, `uvx …`, `/opt/homebrew/bin/…`) | Standart. "The client launches the MCP server as a subprocess." | **Uygun değil** | yok (verilemez) | belgeden | Sandbox'lı sürecin alt süreci sandbox'ı devralır (Apple DTS: "that child process always inherits its sandbox from the parent"). Kullanıcı ikilisi bu kalıtımla imzalı değildir. Ayrıca 2.5.2 ("may not … download, install, or execute code which introduces or changes features"). `~/.local/bin` aracının çalışmadığı forum bulgusu `dagitim-ve-saglayicilar.md` §1'de var (forum kaynaklı). Kalıtımlı çalışmada kullanıcı ikilisinin ne yapacağı bu oturumda ölçülemedi (§1.1). |
| T2 | **stdio, paket içine gömülü yardımcı ikili** | Standart taşıma, gömülü sunucu | **Kâğıt üzerinde mümkün, değeri düşük** | yardımcı ikilide `app-sandbox` + `inherit` | belgeden | DTS: alt süreç `com.apple.security.app-sandbox` ve `com.apple.security.inherit` ile imzalanmalı, `get-task-allow` ile birlikte çalışmaz. Gömülü sunucu uygulamayla aynı sandbox'ta kalır: uygulamanın yapamadığını yapamaz. Bu durumda MCP yalnız bir iç protokol olur; aynı işi süreç-içi Swift kodu daha sade yapar. 2.4.5(iii): uygulama kapanınca alt süreç sürmemeli. |
| T3 | **Streamable HTTP, uzak sunucu** (`https://…`) | Standart (2025-03-26'dan beri) | **Uygun görünüyor** | `com.apple.security.network.client` | belgeden | Giden HTTPS, Anthropic çağrısıyla aynı yetki. Kimlik doğrulama (OAuth ya da belirteç) gerekir. 5.1.2(i): veri üçüncü tarafa gidiyorsa açık bildirim ve izin. Sandbox'lı bir pakette gerçek koşu **doğrulanamadı** (sandbox'lı paket hiç üretilmedi, `sandbox-gecis-analizi.md` S7). |
| T4 | **Streamable HTTP, yerel sunucu** (`http://127.0.0.1:…`) | Standart. Belirtim yerel sunucunun yalnız 127.0.0.1'e bağlanmasını ve `Origin` doğrulamasını ister (DNS rebinding uyarısı) | **Belirsiz** | `network.client` (yeterliliği belirsiz) | doğrulanamadı | Sandbox'lı istemcinin geri döngüye bağlanabildiği plan §10'da da doğrulanmamış. Forum aramasında "127.0.0.1'e bağlanamadım" diyen başlık da çıktı (thread/743191), net DTS yanıtı okunmadı. Ayrıca sunucuyu kim başlatıyor sorusu T1'e döner: kullanıcının ayrıca çalıştırdığı süreç ürünün denetimi dışında. |
| T5 | **HTTP+SSE (eski, 2024-11-05)** | **Kullanımdan kalktı** (2025-03-26'dan beri "Deprecated", ileride kaldırılabilir) | Ağ açısından T3 ile aynı | `network.client` | belgeden | Yeni iş için hedeflenmez. Geriye uyum yalnız eski sunucu gerekirse. |
| T6 | **WebSocket** | **Standart değil.** SEP-1288 ("WebSocket Transport") GitHub'da kapalı, etiketleri `draft`, `dormant` (kapanış 2026-06-26) | Ağ açısından T3 ile aynı olurdu | `network.client` | belgeden (`gh api`) | Belirtim özel taşımaya izin verir ("MAY implement additional custom transport mechanisms"), ama karşı tarafın da aynı özel taşımayı konuşması gerekir. Hedeflenmez. |
| T7 | **Süreç-içi** (aynı süreçte istemci ve sunucu; swift-sdk'de `InMemoryTransport`) | Belirtim dışı (özel taşıma) | **Uyumlu** (yeni yetki yok) | yok | belgeden (swift-sdk README) | Gerçek bir dış sisteme erişim sağlamaz; bağlayıcının kendisi (ör. takvim) yine Apple çerçevesi (EventKit) ya da ağ çağrısıyla yazılır. MCP katmanı bu durumda gereksiz soyutlamadır. |
| T8 | **Ham TCP/UDP** (swift-sdk `NetworkTransport`, Network.framework) | Belirtim dışı (özel taşıma) | Ağ açısından T3 ile aynı | giden: `network.client`, dinleme: `network.server` | belgeden (swift-sdk README) | Standart sunucularla konuşmaz. Hedeflenmez. |

**Belirtim sürümü notu (belgeden, `gh api` ile belirtim deposu):** depoda `2026-07-28` adlı bir belirtim klasörü var. Orada Streamable HTTP daha sade: `Mcp-Session-Id` oturumu, ayrı GET SSE akışı, sürdürülebilir akış ve sunucunun başlattığı JSON-RPC istekleri bu sürümün parçası değil ("servers do not initiate JSON-RPC requests"). Bu, istemcinin saldırı yüzeyini daraltır. Bu klasörün resmî "yayımlanmış" durumda olduğu ve swift-sdk'nin bu sürümü desteklediği **doğrulanamadı** (swift-sdk'nin son sürümü bu tarihten önce, aşağıda §3).

### 1.1 Ölçüm denemesi (bu Mac, macOS 26.3.1)

Scratchpad'de, depodan ayrı tek dosyalık bir Swift deneme ikilisi derlendi. İkili şunları dener: `/bin/echo`, `/usr/bin/python3`, Homebrew'daki bir kullanıcı ikilisi, kullanıcı klasöründeki bir kabuk betiği, `127.0.0.1` ve `localhost` üzerindeki yerel HTTP sunucusu, `https://example.com`. Üç imza biçimi denendi: sandbox'sız, `app-sandbox` + `network.client`, yalnız `app-sandbox`.

| Deneme | Sonuç | Etiket |
|---|---|---|
| Sandbox'sız ikili | 4 alt sürecin hepsi çalıştı. Yerel HTTP (127.0.0.1 ve localhost) ve uzak HTTPS 200 döndü | ölçüldü (yalnız denetim grubu) |
| Sandbox'lı iki ikili | Hiçbir satır yazmadan **çıkış 133** (SIGTRAP) ile durdu | ölçüldü (sonuç), neden **doğrulanamadı** |
| Aynı ikilileri komut aracının kendi sandbox'ı dışında koşmak | İzin verilmedi, koşulmadı | doğrulanamadı |

Çıkış 133'ün en olası nedeni, denemenin çalıştığı ortamın zaten bir sandbox içinde olması (iç içe sandbox, `CLAUDE.md` Tuzaklar'daki 2026-09-18 ölçümüyle aynı sınıf). Bu bir çıkarımdır. **Sonuç: T1, T3, T4 için sandbox içi davranış bu oturumda ölçülemedi.** Ölçüm için kurucunun normal Terminal'inde (sandbox'sız kabuk) aynı deneme ikilisini koşması ya da S7'deki sandbox'lı paketin üretilmesi gerekir. Deneme yalnız sentetik hedeflere gider. Gerçek veri alanına ve çalışan uygulamaya dokunmaz.

## 2. Marka yalıtımı ve izin akışı taslağı (kod değil, tasarım)

Amaç: bir MCP bağlayıcısı eklenirse bozulamaz kurallar 1, 3, 5, 6 ve 7 bugünkü Anthropic yolu kadar sıkı kalsın. Aşağıdaki adlar yer tutucudur.

### 2.1 Veri modeli

- **Bağlayıcı kaydı** (`McpConnector`, yer tutucu): ad, uç nokta (`https://` zorunlu; T4 yerel adres MAS'ta kapalı), taşıma (yalnız Streamable HTTP), araç listesinin onaylı anlık görüntüsü (ad + açıklama + girdi şeması özeti, SHA-256).
- **Marka × bağlayıcı izni**: `Brand.allowedProviders` deseniyle aynı. Varsayılan **boş = KAPALI**. Bağlayıcı uygulama düzeyinde kurulu olsa bile hiçbir markada açık değildir.
- **Araç düzeyi izin**: bağlayıcı açık olsa da her aracın ayrı anahtarı vardır. Varsayılan: okuma araçları kapalı, yazma ya da gönderme etkili araçlar **her zaman kapalı** (§2.3).
- **Kimlik bilgisi**: Keychain'de marka × bağlayıcı başına ayrı hesap, `app.anthropicKeyAccount` gibi tek bir erişim noktasından. Deneme kopyası (`MARKA_WORKSPACE`) gerçek hesabı paylaşmaz (D1 kuralı). Anahtar aranmaz, taranmaz. Kullanıcı verir.
- Bir migration gerektirir. Plan §0 kural 7 gereği gerekçeli ve dalga başına tek olur. Bu not migration açmaz.

### 2.2 Çağrı akışı (her çağrı)

1. Model bir MCP aracı çağırmak ister (`mcp__<bağlayıcı>__<araç>` biçiminde araç adı).
2. **Çekirdek denetimi** (`ToolExecutor` katmanı, sert sınır):
   - Oturum tek markalı mı? **Tüm markalar oturumunda MCP araçları hiç sunulmaz.**
   - Oturum markasında bu bağlayıcı ve bu araç açık mı? Değilse araç modele hiç tanıtılmaz.
   - Oturum markasında **sağlayıcı izni** de var mı? MCP sonucu modele, yani sağlayıcıya gider. Bu yüzden iki izin birden gerekir: marka × bağlayıcı ve marka × sağlayıcı (kural 6).
   - Argüman çıkış süzgeci: argümanlarda başka markanın kimliği ya da adı varsa çağrı reddedilir. Reddin hata metni içerik taşımaz.
3. **Onay kartı** (öneri olarak, bekleyen): "Bu markanın şu bilgisi şu adrese gidecek" metni, gönderilecek argümanların tam görünümü. Varsayılan her çağrıda sorar. "Bu oturumda bu araca bir daha sorma" seçeneği yalnız okuma araçlarında ve yalnız o oturum için olur. Kurucu kararı (§4).
4. Çağrı yapılır. Zaman aşımı ve boyut sınırı uygulanır (`ContextLimits` deseni).
5. **Sonuç** `ToolResultFrame.wrap(_, tool: "mcp:<bağlayıcı>:<araç>")` ile `<kaynak_icerigi>` çerçevesine girer. Sonuç veridir, talimat değildir. Aynı yumuşak savunma sınırları geçerlidir (`bilinen-sinirlar.md` §4: çerçeve modelin uymasını garanti etmez).
6. Sonuçtan doğan her değişiklik (görev, kayıt, not) **bekleyen öneri** olur (`createProposal`, köken `.external` benzeri yeni bir köken). Doğrudan yazma yoktur.
7. `Store.audit`: bağlayıcı adı, araç adı, süre, başarı. **Argüman ve sonuç içeriği yazılmaz.** Günlük ve tanı raporu marka adı taşımaz (kural 6).

### 2.3 Bilinçle kapalı tutulanlar

- **Sunucunun başlattığı istekler** (eski sürümlerde `sampling`, `elicitation`, `roots`): reddedilir. `sampling`, dış sunucunun bizim modelimizi ve anahtarımızı kullanması demektir. `roots`, dosya yolu sızdırır.
- **Gönderme, silme, ödeme etkili araçlar**: MAS'ta ilk sürümde hiç açılmaz. "Müşteriye bir şey gönderemezsin" kuralı (`ContextBuilder.baseInstructions`) bunu zaten söyler.
- **Araç tanımı değişimi**: sunucunun araç adı, açıklaması ya da şeması onaylı anlık görüntüden farklıysa bağlayıcı o markada kendiliğinden kapanır ve yeniden onay ister. Araç açıklaması da modele giden üçüncü taraf metnidir. Enjeksiyon kanalıdır, çerçeve kuralına tabidir.
- **Bir bağlayıcı, birden çok marka**: aynı uç nokta iki markada açıksa kimlik bilgisi ve oturum ayrı tutulur. Bir markanın çağrısında öbür markanın belirteci kullanılmaz. Sunucu tarafında iki hesabın verisinin ayrıldığı **bizim denetimimizde değildir**: arayüz bunu söyler, mutlak gizlilik cümlesi kurmaz (kural 7).

### 2.4 Yalıtım muhafızı eşlemesi

| İhlal kodu | MCP'deki karşılığı | Taslaktaki önlem |
|---|---|---|
| Y1 kapsamsız sorgu | Bağlayıcı izni markasız okunur | İzin her zaman `brandId` ile okunur, `YalitimOzellikTests` kapsamına girer |
| Y2 araç kimliği | Argümanda başka marka kimliği | Çıkış süzgeci, ret |
| Y3 bağlam karışması | Başka markanın MCP sonucu bağlama girer | Sonuç yalnız çağrıyı yapan oturuma döner; tüm markalar oturumunda MCP yok |
| Y4 süreç yalıtımı | stdio alt süreci başka marka klasörünü okur | MAS'ta stdio yok (T1, T2 kapalı) |
| Y5 sağlayıcı izni | İzinsiz markanın verisi bağlayıcıya ya da sağlayıcıya gider | İki izin birden şartı (§2.2 adım 2) |

### 2.5 MCP'siz alternatif: E-17 öneri zarfı (bugün var)

Kullanıcının kendi ajanı (ör. Claude Code, kendi MCP sunucularıyla, kendi makinesinde ve kendi sorumluluğunda) `oneri-zarfi` şema 2 JSON'u üretir. Kullanıcı bunu dosyadan ya da panodan içe alır. Marka, içe alan ekranın markasıdır. Zarf metni veridir, her öğe bekleyen öneridir. Bu yol:
- MAS'ta yeni yetki istemez, alt süreç başlatmaz, ağa çıkmaz.
- Uygulama verisini dış ajana **göndermez**. Akış tek yönlüdür (içeri). Bu, MCP'nin "uygulama bağlamını araca açma" yönünü karşılamaz. Bu bilinçli bir sınırdır.
- Eksikleri `oneri-zarfi.md` "Yapılmayanlar"da yazılı: arayüzde içe alma düğmesi yok, gerçek bir ajanın zarfı ürettiği denenmedi.

## 3. `modelcontextprotocol/swift-sdk` lisans durumu

Kaynak: `gh api repos/modelcontextprotocol/swift-sdk` ve `…/contents/LICENSE` (2026-10-06 UTC).

| Olgu | Değer | Etiket |
|---|---|---|
| GitHub API lisans alanı | `spdx_id: NOASSERTION` (`key: other`) | ölçüldü (API yanıtı) |
| Güncel LICENSE (216 satır) | Başta geçiş metni, sonra tam Apache-2.0 metni, sonra MIT metni ("Copyright (c) 2024-2025 Model Context Protocol a Series of LF Projects, LLC."), sonda CC-BY-4.0 notu | ölçüldü (dosya okundu) |
| Geçiş metninin özü | "undergoing a licensing transition from the MIT License to the Apache License, Version 2.0". Yeni kod katkıları Apache-2.0. Belge katkıları (belirtim hariç) CC-BY-4.0. Yeniden lisanslama onayı verilmiş katkılar Apache-2.0. Onay vermemiş yazarların eski katkıları **MIT olarak kalır** | ölçüldü (dosya okundu) |
| Geçişi getiren commit | `8eef5fda00`, 2026-01-27, "chore: update licensing to Apache 2.0 for new contributions (#177)". PR açıklaması: MCP'nin Linux Foundation'a katılması, mevcut MIT kodun "grandfathering" ile korunması, üst tartışma `modelcontextprotocol/modelcontextprotocol#1994` | ölçüldü (`gh api`) |
| LICENSE dosyasının geçmişi (dosyaya dokunan 4 commit) | `be1e9583f8` 2025-02-11 "Initial implementation": **Apache-2.0** metni. `8dfc9c7875` 2025-03-27 "Transfer project to @modelcontextprotocol (#28)": **MIT**, "Copyright (c) 2025 Loopwork Limited and contributors". `c95d0c0354` 2025-07-24 "Remove Loopwork copyright from license (#148)": MIT, telif satırı yok. `8eef5fda00` 2026-01-27: bugünkü karma metin | ölçüldü (her sürümün LICENSE'ı okundu) |
| Son sürüm etiketi | `0.12.1`, yayın 2026-05-07 (son push ile aynı an) | ölçüldü (`gh api …/releases`) |
| Hangi dosyanın ya da satırın hangi lisansta olduğu | Depoda dosya bazında bir liste bulunamadı. Hangi yazarların onay verdiği **doğrulanamadı** | doğrulanamadı |
| İlk commit'teki Apache-2.0'dan MIT'e dönüşün hukuki etkisi | Yorum gerektirir. Hukuki görüş değildir | doğrulanamadı |

Pratik okuma (hukuki görüş değil): depo bugün **MIT + Apache-2.0 karması**dır. Kullanılırsa iki lisansın bildirim yükümlülüğü birlikte taşınmalıdır (MIT telif ve izin metni, Apache-2.0 metni ve varsa NOTICE). Depoda NOTICE dosyası olup olmadığına bakılmadı. Bağımlılık zinciri de lisans incelemesi ister: `Package.swift` şu paketleri çeker: `swift-system`, `swift-log`, `mattt/eventsource`, `swift-nio`, `swift-docc-plugin` (`branch: "main"`). Bunların lisansları bu notta **okunmadı**.

## 4. Öneri: yap / yapma / bekle

| Karar | Ne | Neden |
|---|---|---|
| **YAPMA** | MAS sürümünde stdio MCP (T1 kullanıcı sunucusu, T2 gömülü sunucu) | T1: sandbox kalıtımı + App Review 2.5.2 ve 2.4.5(iv). Codex'i MAS'tan çıkaran kısıtın aynısı. T2: uygulamanın yapamadığını yapamaz, yalnız karmaşıklık ekler. Plan §0 kural 4 ("kullanıcının kurulu ikilisi çalıştırılmaz") ile çelişir. |
| **YAPMA** | swift-sdk'yi şimdi bağımlılık olarak eklemek | Plan §0 kural 10 (dış kod yok). Lisans karma ve dosya bazında belirsiz. Bağımlılık zinciri (NIO, `branch: main` ile docc eklentisi) MAS istemcisi için gereğinden büyük. Son sürüm (0.12.1) en yeni belirtim klasöründen önce. |
| **YAP** (zaten var, küçük kalan iş) | E-17 zarfını "MCP'siz köprü" olarak konumlamak. Eksik arayüz düğmesi ("Dosyadan / panodan içe al") ayrı görev olarak sıraya girer | Yeni yetki, yeni ağ, yeni üçüncü taraf yok. Kullanıcı kendi MCP araçlarını kendi ajanında kullanır, sonucu onaylı öneri olarak getirir. Kurallar 1, 3, 6 olduğu gibi kalır. |
| **BEKLE** | Uygulama içi **uzak Streamable HTTP** MCP istemcisi (T3), özgün ve küçük (`URLSession` üzerinde JSON-RPC) | Koşullar: (a) S7 sandbox'lı paket üretilmiş ve T3 gerçekten ölçülmüş olmalı, (b) somut bir bağlayıcı ihtiyacı kurucu tarafından seçilmiş olmalı (takvim ve kişiler için önce Apple'ın kendi çerçeveleri değerlendirilir, MCP gerekmeyebilir), (c) §2 izin akışı ve 5.1.2(i) izin ekranı metni onaylanmış olmalı, (d) hedef belirtim sürümü seçilmiş olmalı (2026-07-28 sadeleşmesi istemciyi küçültür ama durumu doğrulanmadı). |

**Kurucu kararı bekleyenler (bu not seçmez):**
1. MCP istemcisi ürün kapsamına girecek mi, yoksa E-17 zarfı yeterli mi?
2. Girecekse ilk bağlayıcı hangisi, ve Apple çerçevesiyle (EventKit gibi) yapılabiliyorsa MCP yine de gerekli mi?
3. Bağımlılık mı (swift-sdk, karma lisans) yoksa özgün küçük istemci mi? Bu not özgün istemciyi önerir. Bağımlılık seçilirse koşulu: tüm zincirin lisansı okunur, yalnız istemci taşıması derlenir, kurucu yazılı onay verir.
4. Okuma araçlarında "bu oturumda bir daha sorma" seçeneği olsun mu?
5. Doğrudan dağıtım (`#if !MAS`) sürümünde stdio MCP düşünülecek mi? Bu not yalnız MAS'ı inceler. Doğrudan dağıtımda Codex için yazılan seatbelt bedelleri (`bilinen-sinirlar.md` §4) aynen geçerli olur.

## 5. Doğrulanamayanlar

- Sandbox'lı bir sürecin (a) kullanıcı ikilisini alt süreç olarak çalıştırması, (b) `127.0.0.1`'e bağlanması, (c) `network.client` ile uzak HTTPS MCP sunucusuna bağlanması bu oturumda **ölçülemedi** (§1.1, çıkış 133, izin verilmedi).
- Apple'ın resmî App Sandbox belge sayfaları bu oturumda okunmadı. Kalıtım kuralı DTS forum yanıtından (thread/706390), App Review maddeleri resmî yönerge sayfasından okundu.
- `2026-07-28` belirtim klasörünün resmî yayın durumu ve swift-sdk'nin desteklediği belirtim sürümleri.
- swift-sdk'de hangi kodun MIT, hangisinin Apache-2.0 olduğu. NOTICE dosyasının varlığı. Bağımlılıkların lisansları.
- App Review'un MCP istemcili bir uygulamaya nasıl bakacağı. İnceleme sonucu bilinemez.
- Yıldız sayısı bilinçli olarak sorgulanmadı ve yazılmadı.

## 6. Kaynaklar

- MCP belirtimi, taşımalar (2025-06-18): https://modelcontextprotocol.io/specification/2025-06-18/basic/transports
- MCP belirtim deposu, `docs/specification/2026-07-28/basic/transports/` (`gh api repos/modelcontextprotocol/modelcontextprotocol/contents/…`)
- SEP-1288 WebSocket Transport: https://github.com/modelcontextprotocol/modelcontextprotocol/issues/1288
- swift-sdk: https://github.com/modelcontextprotocol/swift-sdk (README "Transports", "Platform Availability"; LICENSE ve geçmişi; PR #177)
- Apple App Review Guidelines (2.4.5, 2.5.2, 5.1.2(i)): https://developer.apple.com/app-store/review/guidelines/
- Apple DTS, alt süreçte sandbox kalıtımı: https://developer.apple.com/forums/thread/706390
- Geri döngü bağlantısı sorunu (forum, DTS yanıtı okunmadı): https://developer.apple.com/forums/thread/743191
