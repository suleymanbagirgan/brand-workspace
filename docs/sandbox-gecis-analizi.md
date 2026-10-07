# App Sandbox geçiş analizi (F7 ön çalışması)

Tarih: 2026-10-04. Durum: **analiz, geliştirme amaçlı**. Yayın kararı değildir. Salt okuma: kod okundu, hiçbir şey derlenmedi, çalıştırılmadı, sandbox'lı bir paket üretilmedi. Bu yüzden "sandbox'ta ne olur" sütunları **kod okumasından çıkarım**dır; ölçüm değildir. Ölçülmesi gerekenler "doğrulanamadı" diye işaretlidir. Apple'ın resmî belge sayfaları (developer.apple.com) bu oturumda içerik olarak okunamadı (sayfa yalnız başlık döndürdü); entitlement adları ve davranışlar Apple belgesinden **doğrulanamadı**, yazarın genel bilgisine ve forum arama sonuçlarına dayanır.

Bağlam: `docs/ai-calisma-alani-plani.md` §3 madde 1-2 ve §4.8 (App Store hedefi, Codex MAS dışı, bookmark'lı marka klasörleri), F7 ("en riskli göç", `:120`); `docs/pazar/urun-degerlendirme.md` engel #1 ve #2 (sandbox yok, mimari uymuyor).

## 0. Özet bulgu

1. Tüm kodda sandbox ile çakışan **dört küme** var: (A) marka klasörleri (sabit yol + mutlak yol saklama + dosya tarama/yazma), (B) Codex süreci ve `sandbox-exec` yalıtımı, (C) içe aktarım yolları (`~`, iCloud), (D) eski veri alanından göç. Ağ, Keychain, menü çubuğu, çentik paneli, QuickLook, PDFKit, panolar için **ek kod gerekmiyor** gibi görünüyor (doğrulanamadı; ölçülecek).
2. En sinsi çakışma: `BrandFolders.defaultRoot` (`ChatEngine.swift:11-13`) `.documentDirectory` kullanıyor. Sandbox'ta bu çağrı hata vermeden **container içindeki** `Documents` klasörünü döndürmesi beklenir (doğrulanamadı). Uygulama sessizce çalışır ama marka klasörleri kullanıcının göremediği bir yerde oluşur. Kullanıcıya hata göstermez; veri "kaybolmuş" görünür.
3. Kod boyutu: `BrandSandbox.swift` içindeki `SandboxProfile.canonical` (`:129`) Codex'e özgü değil; `FileImportGuard` (`Store+Sources.swift`) ve `SuggestionInbox` marka yalıtımı için de kullanıyor. Codex'i çıkarırken bu dosya **silinemez**; `canonical` ayrı bir yardımcıya taşınmalı.
4. Marka yalıtımı (bozulamaz kural 1) Codex çıkınca zayıflamaz: Anthropic yolu dosya sistemine dokunmuyor, yalnız `Store` araçlarıyla çalışıyor (`runCodex` dışında `folders` kullanan sohbet yolu bulunmadı; `ChatEngine.swift:559-560` yalnız `runCodex` içinde). Marka klasörü yalıtımı (başka markanın klasörünü okuma) yalnız Codex/terminal için gerekiyordu.
5. SwiftPM + `build-app.sh` ile sandbox'lı imzalı paket **büyük olasılıkla mümkün** ama App Store gönderimi için Xcode gerekip gerekmediği **doğrulanamadı** (bkz. §4).

## 1. Çakışma envanteri

Boyut: S (saat), M (gün), L (birkaç gün, tasarım gerektirir). "MAS'tan çıkar": Mac App Store sürümünden kaldırılacak mı.

### (a) Dosya sistemi

| # | Yer (dosya:satır) | Sandbox'ta ne olur | Gereken | Boyut | MAS'tan çıkar |
|---|---|---|---|---|---|
| a1 | `ChatEngine.swift:11-13` `defaultRoot` = `.documentDirectory/Marka Çalışma Alanı` | Container içi `Documents`'a gider (doğrulanamadı); kullanıcı klasörü bulamaz. | MAS derlemesinde `defaultRoot` kaldırılır; kök kullanıcı seçimi ile gelir (bookmark). | M | Hayır (davranış değişir) |
| a2 | `ChatEngine.swift:24-52` `folder(for:)`: `store.setting("folder.<id>")` mutlak yol, `createDirectory(.../ciktilar)` | Kayıtlı yol erişim verilmemiş bir yer ise `createDirectory` reddedilir (hata fırlar). Yeni marka klasörü adayı `fileExists` ile aranıyor; erişim yoksa hep "yok" çıkar, çakışma denetimi yanılır. | Mutlak yol yerine bookmark. `FolderAccess` soyutlaması; erişim yoksa özel hata `izinGerekli(ipucuYol)`. | L | Hayır |
| a3 | `ChatEngine.swift:55-58` `existingFolder`: `fileExists` | Erişimsiz yolda sessizce `nil` döner; arayüz "klasör yok" sanır. | Aynı `FolderAccess`; "yok" ile "izin yok" ayrılır. | S | Hayır |
| a4 | `ChatEngine.swift:62-82` `writeContextFile` (BAGLAM.md), `:66` `oneriler/` oluşturma, `:91-108` `writeAgentPointers` (CLAUDE.md, AGENTS.md; `lstat`, `text.write`) | Erişim verilmiş klasörde çalışır. Verilmemişse yazma reddedilir; `try?` olanlar (`:66`, `:107`) **sessizce** başarısız olur. | Erişim kapsamı (`startAccessing…`) içinde çağır; sessiz `try?` yerine "izin gerekli" durumu. `lstat`/`O_NOFOLLOW` yardımcıları kapsam içinde çalışır (doğrulanamadı). | M | Hayır; ama işlev anlamı değişir (aşağıya bak) |
| a5 | `AppModel.scanNewFiles` (`AppModel.swift:310-314`) → `importableFiles` (`ChatEngine.swift:192-`) → `snapshot` (`:160-`, `FileManager.enumerator`, `resourceValues`) | Arka plan görevinde (`Task.detached`) numaralandırma; erişim kapsamı o iş parçacığında açık değilse boş döner ya da hata. Kapsam başlatma/bitirme **eşleşmeli** (sızıntı). | `FolderAccess.withAccess(brand) { ... }` sarmalayıcısı; `Task.detached` içinde çağrılır. `BrandView.swift:84` `.task(id:)` iptalinde kapsam kapanmalı. | M | Hayır |
| a6 | `SuggestionInbox.scan` (`SuggestionInbox.swift:249-`, `:264` `contentsOfDirectory`, `:381-` `moveToProcessed`: `mkdir`, `rename`); çağıranlar `BrandView.swift:76,81` (zamanlı yoklama, `settle: 1.5`), `SnapshotRunner.swift:23` | `oneriler/*.json` okunur ve `islenmis/` altına taşınır: **okuma-yazma** gerekir. Zamanlı yoklama süresince kapsam açık tutulmalı. | Aynı `withAccess`; yoklama sırasında kapsamı uzun tutma yerine her turda aç-kapa. | M | Hayır |
| a7 | `Store+Sources.swift` `FileVault` (`store(fileURL:)`, `Files/` altına `0o444`) | `Files/` veri alanında (container); sorun yok. Dışarıdan gelen dosya yalnız seçim paneli ya da sürükle-bırak URL'siyle okunur. | Yok. | - | Hayır |
| a8 | `Store+Sources.swift` `FileImportGuard` (`realpath`, `lstat`, `O_NOFOLLOW`) | Erişim verilmiş yollarda çalışır. | `SandboxProfile.canonical` bağımlılığı ayrılır (bkz. §0 madde 3). | S | Hayır |
| a9 | `SettingsView.swift:246-250,268-272` Konum bölümü: `foldersRoot` oluşturma, `NSWorkspace.activateFileViewerSelecting([workspaceURL, foldersRoot])` | `createDirectory(foldersRoot)` erişimsiz yolda başarısız (`try?` ile yutulur). Finder'da gösterme izin verilmiş URL'lerde çalışır beklenir (doğrulanamadı). Veri yolu container içi yol gösterir. | Marka klasörü kökü için "Klasör seç / değiştir" düğmesi; `try?` kaldırılır. | S | Hayır |
| a10 | `BackupService.swift` (`workspace/Yedekler`, `copyTree` `linkItem`, `restore`, `exportBrand`) | Veri alanı (container) içinde sorunsuz. `exportBrand(to:)` kullanıcı seçimli klasöre yazar: `NSOpenPanel` URL'si ile izin gelir, `…user-selected.read-write` gerekir. | Entitlement. | S | Hayır |
| a11 | `AppDatabase.swift:19-35` (`workspace.sqlite`, WAL, `Migration-Yedekleri`), `WorkspaceLock.swift` (`flock`), `Diagnostics.swift:163` | Hepsi veri alanında; container içi. | Yok. | - | Hayır |
| a12 | `ReportsView.swift:264-` `NSSavePanel` + `data.write(to: url)`; `recordShare(filePath: url.path)` | Kaydetme paneli izin verir (`…user-selected.read-write`). `filePath` yalnız kayıt olarak saklanır; sorun yok. | Entitlement. | S | Hayır |
| a13 | `ReportsView.swift:286-300` Mail taslağı: PDF `workspaceURL/Gecici` altına yazılır, `NSSharingService(.composeEmail)` ile URL verilir | Yazma container içinde çalışır. Mail'in container içindeki dosyayı eke alıp alamayacağı **doğrulanamadı**. | Gerçek pencerede ölçülür; olmazsa geçici kopya panelle seçilen klasöre ya da `NSItemProvider` verisiyle. | M | Hayır |
| a14 | `JoiTodoImporter.swift:70-76` `candidateDirectories`: `~/Library/Mobile Documents/com~apple~CloudDocs/joi-todo`, `~/.joi-todo`; çağıran `OnboardingView.swift:117` | Erişimsiz; ev dizini container'a yönlenir ve yollar yok sayılır (doğrulanamadı). Otomatik bulma çalışmaz. İçe aktarım **panelle seçilen** klasörde çalışır (`OnboardingView.swift:132`, `showsHiddenFiles`). | MAS'ta otomatik bulma kaldırılır; yalnız panel. Daha iyi: bu kişisel eski aktarıcı MAS'tan tümden çıkar. | S | **Evet önerilir** (kişisel eski veri) |
| a15 | `JoiTodoImporter.swift:186-197` anlık görüntü kopyası | Hedef `snapshotDirectory` veri alanı içinde ise sorun yok. | Yok. | - | - |
| a16 | `NSOpenPanel` kullanımları: `BrandSections.swift:597` (dosya ekle), `CompanyView.swift:621` (SKILL.md), `BrandView.swift:151` (marka dışa aktar, klasör), `OnboardingView.swift:132` (Joi klasörü) | Panel sandbox'ta **Powerbox** ile çalışır; seçilen URL'lere oturum boyunca erişim gelir (doğrulanamadı). Kod çoğunlukla değişmez. | `…files.user-selected.read-write` (dışa aktarma ve kaydetme yazar). | S | Hayır |
| a17 | `FlowView.swift:276-283` `FileDrop` (`dropDestination(for: URL.self)`) | Finder'dan bırakılan dosyaya erişim genellikle gelir (doğrulanamadı); gerçek pencerede denenmeli. | Ölçüm. | S | Hayır |
| a18 | `BrandSections.swift:610`, `DetailPanel.swift:472` `NSWorkspace.shared.open(fileURL)`: veri alanındaki `Files/` dosyası başka uygulamada açılır | Container içi dosyanın başka uygulamada açılması **doğrulanamadı** (izin/karantina). | Ölçülür; olmazsa geçici kopya (kullanıcı seçimli ya da sistem açma uzantısı). | M | Hayır |
| a19 | `BrandSections.swift:1095` `QLThumbnailGenerator` (`Files/` dosyası) | İşlem içi üretim, uygulamanın okuyabildiği dosya; sorun beklenmez (doğrulanamadı). | Ölçüm. | S | Hayır |
| a20 | `AppModel.swift:177` `applicationSupportDirectory`, ortam `MARKA_WORKSPACE`, `MARKA_FOLDERS`, `MARKA_SNAPSHOT` (`:180,205`, `SnapshotRunner.swift:16-18`) | Sandbox'ta `applicationSupportDirectory` container içine gider (veri alanı sorunsuz). `MARKA_*` ortam değişkenleri Finder/Launch Services ile açılışta set edilmez; ayrıca container dışı yol erişimsiz olur. Ekran yakalama aracı (`MARKA_SNAPSHOT`) sandbox'lı pakette dışarıya PNG yazamaz. | Geliştirme araçları sandbox'sız geliştirme paketiyle kalır; MAS derlemesinde ortam değişkenleri `#if !MAS` ile kapatılır. | S | Hayır (geliştirme dışı) |

**Anlam değişikliği (a4):** `BAGLAM.md`, `CLAUDE.md`, `AGENTS.md` ve `oneriler/` marka klasörünün **dış araçlar** (kullanıcının kendi Terminal'inde çalıştırdığı Claude Code, Codex CLI) için var. Uygulamada terminal kalktı ve MAS'ta Codex yok; dolayısıyla MAS'ta bu özellik "isteğe bağlı bir çalışma klasörü" olur. Öneri: MAS'ta **klasör izni verilmeden de tüm çekirdek çalışsın** (veri alanı container'da). Klasör özelliği kullanıcı bir kök seçince açılsın.

### (b) Süreç başlatma

| # | Yer | Sandbox'ta ne olur | Gereken | Boyut | MAS'tan çıkar |
|---|---|---|---|---|---|
| b1 | `CodexAppServer.swift:70-95` `locateBinary`: `~/.local/bin/codex`, `/opt/homebrew/bin`, `/usr/local/bin`, `~/.npm-global`; `Process()` ile `/bin/zsh -ilc "command -v codex"` | Sandbox içinde kullanıcının kurulu ikilisi bulunamaz ya da çalıştırılamaz; kabuk ayrıca erişimsiz. `docs/dagitim-ve-saglayicilar.md:10` Apple forum bağlantılarıyla aynı sonucu yazıyor (forum kaynaklı, resmî belge değil). | `#if !MAS` ile derlemeden çıkar. | M | **Evet** |
| b2 | `CodexAppServer.swift:117-150` `Process()`; `sandbox-exec -p <profil> codex app-server` | `/usr/bin/sandbox-exec` sandbox'lı uygulama içinde işe yaramaz: iç içe `sandbox-exec` çalışmıyor (`CLAUDE.md` Tuzaklar: `sandbox_apply: Operation not permitted`, 2026-09-18'de ölçüldü; bu ölçüm sandbox'sız uygulama içindi, sandbox'lı uygulama içinde ayrıca doğrulanamadı). Mevcut kod `SandboxRunner.verify` başarısız olunca Codex'i **başlatmaz** (güvenli kapanış). | Çıkar. | M | **Evet** |
| b3 | `BrandSandbox.swift:288-310` `SandboxRunner` (`Process`, `sandbox-exec`), profil üretimi (`:1-283`: `BrandIsolation`, `SandboxProfile`) | Aynı. Yalnız `SandboxProfile.canonical` (`:129`) çekirdekte kullanılıyor (a8). | Dosya `#if !MAS`; `canonical` yardımcıya taşınır. Test dosyası `IsolationTests` kimi testler profil metnini sınıyor: MAS dışı hedefte kalır. | M | **Evet** (profil kısmı) |
| b4 | `ChildEnvironment.swift:6-15` | Yalnız Codex'in alt sürecinin ortamı. | Birlikte çıkar. | S | **Evet** |
| b5 | `ChatEngine.swift` `codexServer(for:)` (`:264-`), `runCodex` (`:547-`), `codexServers` (`:235`); `AppModel.swift:226-231` (`controlIsolation`, `CodexAppServer(controlOnly:)`); `SettingsView.swift:210-225` ChatGPT girişi; `ReportsView.swift:335` Codex ile rapor özeti; `AIChat.swift:73-75` sağlayıcı listesi | Hepsi b1-b3'e bağlı. Çıkarınca sağlayıcı seçimi yalnız Anthropic kalır. | `AIProvider` soyutlaması (F3) ile uyumlu: `CodexProvider` yalnız `#if !MAS`. | L | **Evet** |

SwiftTerm artık bağımlılık değil (`Package.swift` yalnız GRDB; plan §2 "terminal kaldırıldı"). `Terminal/TerminalSessions.swift` saf mantık, süreç başlatmaz.

### (c) Ağ

| # | Yer | Sandbox'ta ne olur | Gereken | Boyut | MAS'tan çıkar |
|---|---|---|---|---|---|
| c1 | `AnthropicClient.swift:15` `https://api.anthropic.com`, `URLSession.shared`; `ChatEngine.swift:242-248` | Giden ağ entitlement'sız engellenir. | `com.apple.security.network.client` | S | Hayır |
| c2 | `SettingsView`/Link kaynağı `NSWorkspace.shared.open(URL)` (`BrandSections.swift:611`, `DetailPanel.swift:464` `Link`) | Tarayıcıda açma sandbox'ta çalışır (doğrulanamadı; genel beklenti). | Yok. | - | Hayır |

Gelen bağlantı (server) yok: `network.server` gerekmez. Başka ağ kullanımı bulunmadı (`grep URLSession` yalnız Anthropic ve Codex giriş URL'si).

### (d) Keychain

| # | Yer | Sandbox'ta ne olur | Gereken | Boyut | MAS'tan çıkar |
|---|---|---|---|---|---|
| d1 | `AIBasics.swift:96-122` `SecItemAdd/CopyMatching/Delete`, `kSecClassGenericPassword`, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` | Sandbox'lı uygulama kendi kayıtlarına erişir; ek entitlement genellikle gerekmez (doğrulanamadı). `kSecAttrAccessible…` özniteliğinin macOS'ta dosya tabanlı anahtar zincirinde etkisi ve "data protection keychain" gerekliliği doğrulanamadı. Sandbox'sız sürümün yazdığı anahtarı sandbox'lı sürüm **okuyamayabilir** (farklı erişim denetimi): kullanıcı anahtarı yeniden girer. | Ölçüm; göç notu: "API anahtarı yeniden girilecek". | S | Hayır |
| d2 | `PreferenceStore` (`WorkspacePreferences.swift`, `UserDefaults(suiteName:)` yalnız deneme/anlık kapsamda) | `UserDefaults.standard` container'daki tercih dosyasına gider; eski tercihler **taşınmaz** (S: yeniden varsayılan). | Göç notu. | S | Hayır |

### (e) Diğer

| # | Yer | Sandbox'ta ne olur | Gereken | Boyut | MAS'tan çıkar |
|---|---|---|---|---|---|
| e1 | `MarkaApp.swift:44` `MenuBarExtra` | Sandbox'tan etkilenmez beklenir. | Yok. | - | Hayır |
| e2 | `NotchTimer.swift:31-32` `NSPanel`, seviye `.statusBar` | Sandbox'tan etkilenmez beklenir; MAS incelemesi için "fiziksel çentik yok" davranışı ayrı konu. | Yok. | - | Hayır |
| e3 | Bildirim (`UNUserNotification`), Apple Events (`NSAppleScript`), Spotlight (`CSSearchableIndex`, `NSMetadataQuery`) | Kodda **kullanılmıyor** (grep bulgusu yok). F6'da App Intents eklenirse ayrıca değerlendirilir. | Yok. | - | - |
| e4 | `NSPasteboard` (`BrandProfileView.swift:375`, `CompanyView.swift:666`, `SettingsView.swift:361`) | Sandbox'ta çalışır. | Yok. | - | Hayır |
| e5 | `NSSharingService(.composeEmail)` (`ReportsView.swift:292`) | Çalışması beklenir; ek dosya için bkz. a13. | - | - | Hayır |
| e6 | `PDFKit` (`Store+Sources.swift:5`), `CoreText` (`ReportPDF.swift`) | İşlem içi; sorun yok. | Yok. | - | Hayır |
| e7 | `signal(SIGPIPE, SIG_IGN)` (`CodexAppServer.swift`) | Yalnız Codex'te. | Birlikte çıkar. | - | **Evet** |
| e8 | Paket: `LSMinimumSystemVersion 14.0`, yalnız arm64, ad-hoc imza, `codesign --force --deep` (`scripts/build-app.sh:60-64`), Info.plist betikte üretiliyor | Sandbox, entitlements ve gönderim imzası yok. | Bkz. §4. | L | - |

## 2. Önerilen mimari

### 2.1 İki alan

**Veri alanı (container, sorunsuz).** SQLite (`workspace.sqlite`), `Files/`, `Yedekler/`, `Migration-Yedekleri/`, `Gecici/`, `Diagnostics`, kilit dosyası: hepsi `applicationSupportDirectory` altında. Sandbox'ta bu yol kendiliğinden container'a döner (`AppModel.swift:177`); **kod değişikliği gerekmez**. Yalnızca "yol gösterme" metinleri (Ayarlar › Konum) container yolunu gösterir ve Finder'da gösterme çalışır mı ölçülür.

**Marka klasörleri (kullanıcı seçimli bookmark).** Yeni küçük soyutlama `FolderAccess` (çekirdekte, protokol; testte sahte uygulama):

- `grantRoot(url)`: kullanıcının `NSOpenPanel` (klasör, `canCreateDirectories`) ile seçtiği **kök** için security-scoped bookmark üretir ve saklar.
- `grantBrandFolder(brandId, url)`: kök dışında kalan tek tek marka klasörleri için (bugün `folder.<id>` kök dışına taşınmış olabilir; `BrandIsolation.savedBrandFolders` bunu zaten öngörüyor).
- `withAccess(brandId) { dir in … }`: bookmark'ı çözer, `startAccessingSecurityScopedResource`, bloğu çalıştırır, `defer` ile `stop…`. `scanNewFiles`, `SuggestionInbox.scan`, `writeContextFile`, `importableFiles`, dışa aktarım hep bunun içinde çalışır.
- Durumlar: `hazir(url)`, `izinGerekli(ipucuYol)` (kayıt var ama bookmark yok ya da bayat), `secilmedi` (hiç klasör istenmedi).

Saklama: bookmark verisi veritabanında (`setting` anahtarları ya da yeni tablo; yeni migration, geri alınabilir). Bookmark yolu o makineye ve uygulamaya bağlıdır; yedekten başka Mac'e geri yüklenince geçersiz sayılır ve **yeniden izin istenir** (hata değil, normal durum). Bookmark'ın uygulama ve sürüm kimliğine bağlılığı Apple belgesinden **doğrulanamadı**.

Tasarım kuralları:
1. **Klasör izni olmadan uygulama tam çalışır.** Marka klasörü özelliği (BAGLAM.md, `oneriler/`, "klasörden içe al") kullanıcı kök seçince açılır. Seçilmediyse arayüz tek satırlık "Marka klasörü seç" çağrısı gösterir; hata penceresi çıkmaz.
2. Tek kök, tek izin: kullanıcı bir kez `Marka Çalışma Alanı` kökünü seçer; alt klasörler bu kök kapsamında kalır. Kök dışı özel yollar için marka başına ayrı izin.
3. `try?` ile yutulan klasör işlemleri (`ChatEngine.swift:66,107`, `SettingsView.swift:268`) kapsam dışı hatayı **gösterecek** biçimde değişir ("yapmadığımızı vaat etmeyiz").
4. Marka yalıtımı kuralı korunur: `FileImportGuard` kapsamı (`confineTo`) aynı kalır; `canonical` yardımcıya taşınır (b3).
5. Derleme anahtarı `MAS` (SwiftPM: `-Xswiftc -DMAS`, ya da `Package.swift` içinde `swiftSettings: [.define("MAS")]`): `CodexAppServer`, `BrandSandbox` profili, `ChildEnvironment`, ortam değişkenli geliştirme kancaları ve Joi otomatik bulma yalnız `#if !MAS`. Doğrudan dağıtım sürümü sandbox'sız, bugünkü davranışla kalır; iki sürüm tek kod tabanından çıkar.

### 2.2 Mevcut kullanıcının eski veri ve klasör göçü

Eski sürüm (sandbox'sız): veri `~/Library/Application Support/MarkaCalismaAlani`, marka klasörleri `~/Documents/Marka Çalışma Alanı/<Marka>`, DB'de `folder.<id>` mutlak yol.

Sandbox'lı yeni sürüm bu eski konumları **okuyamaz** (`…user-selected` verilmeden). Container'a otomatik taşıma mekanizmasının (Apple'ın sandbox'a geçişte container taşıma belirtimi) kapsamı **doğrulanamadı**; ona güvenilmez. Önerilen, kendi sınadığımız yol:

1. **Eski sürüme küçük bir güncelleme** (sandbox'sız, doğrudan sürümde): Ayarlar › Yedekler'e "Yedeği dışa aktar…" (kullanıcı seçimli klasöre; `createBackup(destination:)` parametresi zaten var, `BackupService.swift:33`; arayüz yok). Yedek = SQLite + `Files/` + manifest.
2. **Yeni sürüme** "Yedekten yükle…" (dosyadan): `NSOpenPanel` ile yedek klasörü seç, mevcut `BackupService.restore`/`validate` yeniden kullanılır (`validate` daha yeni migration'lı yedeği reddediyor; aynı güvence). Geri yükleme öncesi yedek mantığı (`pre-restore`) korunur. Bugün geri yükleme **yalnız** `workspace/Yedekler` listesinden çalışıyor (`SettingsView.swift:375-382`); dosyadan yükleme yeni arayüz.
3. **Marka klasörleri:** geri yüklenen DB'deki `folder.<id>` yolları eski gerçek yolları taşır. İlk kullanımda durum `izinGerekli(ipucuYol)`: panel önceden eski kök klasöre yönlendirilmiş açılır (`NSOpenPanel.directoryURL`; gerçek ev dizini için `getpwuid` gerekebilir çünkü sandbox'ta `NSHomeDirectory` container'ı gösterir; doğrulanamadı), kullanıcı kökü onaylar, kök altındaki tüm marka yolları tek izinle çözülür. Kök dışındaki yollar marka başına ayrıca sorulur. Dosyalar **taşınmaz**, yerinde kalır (veri kaybı riski yok).
4. API anahtarı ve tercihler taşınmaz: "anahtarı yeniden gir" notu ilk açılış ekranında.
5. Geri alma: eski sürüm ve eski veri alanı dokunulmadan kalır; yeni sürüm yalnız kopyayı kullanır. Hiçbir adım eski veriyi silmez.

Mevcut tek kullanıcı kurucu ve beta katılımcıları; kullanıcı sayısı küçük olduğundan yukarıdaki elle göç kabul edilebilir görünür (ölçülmedi).

## 3. Entitlements taslağı (dosya değil, metin)

`Resources/MarkaCalismaAlani-MAS.entitlements` olarak ileride yazılabilecek taslak. `application-identifier` ve `team-identifier` değerleri **provisioning profile'dan** gelir; yer tutucudur, gerçek takım kimliği bu depoya yazılmaz.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <!-- Zorunlu: Mac App Store -->
  <key>com.apple.security.app-sandbox</key><true/>

  <!-- Anthropic HTTPS (api.anthropic.com). Gelen bağlantı yok: network.server YOK. -->
  <key>com.apple.security.network.client</key><true/>

  <!-- NSOpenPanel / NSSavePanel: kaynak ekle, SKILL.md, marka klasörü kökü, dışa aktar, PDF kaydet, yedek yükle -->
  <key>com.apple.security.files.user-selected.read-write</key><true/>

  <!-- Marka klasörü kökü için kalıcı (security-scoped) bookmark; yeniden açılışta erişim. -->
  <key>com.apple.security.files.bookmarks.app-scope</key><true/>

  <!-- Yer tutucular: provisioning profile'dan gelir; elle yazılmaz, gerçek değer depoya girmez.
  <key>com.apple.application-identifier</key><string>TAKIMKIMLIGI.com.markacalismaalani.app</string>
  <key>com.apple.developer.team-identifier</key><string>TAKIMKIMLIGI</string>
  -->
</dict>
</plist>
```

Bilerek **yok:** `…files.downloads`, `…assets.*`, `…temporary-exception.*` (örn. ev dizini göreli okuma-yazma; Apple inceleme politikası ve sandbox amacına aykırı, bu yüzden önerilmez), `…device.*`, `…personal-information.*`, `…scripting-targets`, `…automation.apple-events` (Apple Events kullanılmıyor), `…application-groups`, `keychain-access-groups` (örtük). Hardened runtime ayrı bir işarettir (`codesign --options runtime`), MAS için yeterli ek istisna gerekmediği öngörülür; doğrulanamadı. Entitlement adlarının ve geçerli değerlerin tam yazımı Apple belgesinden **doğrulanamadı**; Xcode'un "Signing & Capabilities" arayüzünün ürettiği çıktı ile karşılaştırılmalı.

## 4. Göç planı (küçük, geri alınabilir adımlar)

Genel kural: her adım ayrı, `MAS` anahtarı kapalıyken **bugünkü davranış bire bir aynı**; her adımın sonunda `scripts/test.sh` + `scripts/build-app.sh` + `python3 scripts/l10n.py check` temiz. Sandbox'lı davranış SwiftPM testlerinde ölçülemez (test koşucusu sandbox'sız); onu yalnız imzalı paket üzerinde gerçek pencere ölçümü kanıtlar.

| Adım | İçerik | Kabul ölçütü | Kanıt |
|---|---|---|---|
| S1 | `MAS` derleme anahtarı. `canonical` yardımcıya taşınır (`PathCanonical`). Hâlâ hiçbir davranış değişmez. | İki yapılandırma da derlenir; 173 test geçer. | `swift build` iki kipte; `scripts/test.sh`. |
| S2 | Codex, `BrandSandbox` profili, `ChildEnvironment`, `Joi` otomatik bulma, `MARKA_*` kancaları `#if !MAS` içine. Ayarlar/rapor/sohbet sağlayıcı listesi yalnız Anthropic. | MAS kipinde kaynakta (`#if !MAS` dışında) `Process(`, `sandbox-exec`, `/bin/zsh` yok. | Kaynak taraması betiği (`grep`) + MAS kipi derleme + test kümesinin MAS'a uygun alt kümesi. `IsolationTests` Codex profili testleri MAS dışı hedefte kalır. |
| S3 | `FolderAccess` protokolü + sahte uygulama; `BrandFolders` bu arayüzden geçer. Varsayılan uygulama bugünkü mutlak yol davranışı. | Mevcut `IsolationTests`, `TerminalOneriTests` değişmeden geçer; yeni testler: izin yok ise `izinGerekli`, kapsam eşleşmesi (başlat/bitir sayısı eşit). | Sahte `FolderAccess` ile birim test. |
| S4 | Bookmark saklama (yeni migration; geri alınabilir) + `BookmarkFolderAccess`. | Bookmark üret/çöz/bayat tespit testi geçici klasörde; migration testi bellek içi DB'de; eski `folder.*` ayarları silinmez. Bookmark'ın sandbox'sız süreçte güvenlik kapsamıyla üretilebilirliği **doğrulanamadı**; olmazsa bu test yalnız imzalı pakette elle. | `MigrationYedekTests` benzeri test + elle ölçüm. |
| S5 | Arayüz: ilk açılışta isteğe bağlı "Marka klasörü seç", Ayarlar › Konum "Değiştir", marka sekmesinde "izin gerekli" durumu. `try?` yutmaları kalkar. `defaultRoot` MAS'ta kaldırılır. | Klasör seçilmeden tüm çekirdek akışlar çalışır; seçilince BAGLAM.md yazılır. | Gerçek pencere yakalama (`scripts/pencere-goruntu.sh`), açık ve koyu tema; TR/EN `l10n.py check`. |
| S6 | Göç: eski sürüme "Yedeği dışa aktar…"; yeni sürüme "Yedekten yükle…" (dosya). | Dışa aktarılan yedek yeni sürümde geri yüklenir; marka sayısı, kaynak sayısı, görev sayısı eşleşir (manifest). Eski veri alanı dokunulmamış. | `ReportImportBackupTests` desenli test + sentetik veriyle elle uçtan uca (gerçek veri alanına dokunmadan). |
| S7 | Paketleme: entitlements dosyası + `build-app.sh --sandbox` (ayrı çıkış yolu, tek kopya kuralını bozmadan ayrı ad) + `codesign --entitlements`. Xcode gerekip gerekmediği bu adımda ölçülür. | `codesign -d --entitlements :- <app>` yalnız §3'teki anahtarları gösterir; uygulama açılır; `~/Library/Containers/<paket kimliği>` oluşur. | Komut çıktısı; container klasörünün varlığı. İmza kimliği: ad-hoc ile sandbox uygulanıp uygulanmadığı **doğrulanamadı**; geliştirme sertifikası gerekebilir. |
| S8 | Sandbox'lı gerçek pencerede akış ölçümü (aşağıdaki liste). | Listedeki her madde geçti ya da `docs/bilinen-sinirlar.md`'ye açık yazıldı. | Her madde için yakalama + `Diagnostics` içeriksiz kaydı. Çalışma zamanında sandbox içinde olunduğunu doğrulamak için `APP_SANDBOX_CONTAINER_ID` ortam değişkeninin varlığı kullanılabilir (genel bilgi; doğrulanamadı). |
| S9 | `PrivacyInfo.xcprivacy` + App Privacy beyanı. Kodda "required reason API" kullanımı: `UserDefaults` (`PreferenceStore`), dosya zaman damgaları (`contentModificationDate`, `st_mtimespec`: `ChatEngine.snapshot`, `SuggestionInbox`). Doğru neden kodları Apple belgesinden **doğrulanamadı**. | Manifest dosyası paketin içinde; kullanılan API listesi kaynak taramasıyla eşleşir. | Kaynak taraması + paket içeriği listesi. |

S8 ölçüm listesi (sandbox'lı imzalı paket, gerçek pencere): açılış ve veritabanı oluşturma; yeni marka; kaynak ekle (panel); sürükle-bırak dosya (a17); kaynağı başka uygulamada aç (a18); küçük resim (a19); PDF kaydet (a12); Mail taslağı eki (a13); marka dışa aktar; yedek al ve geri yükle; klasör kökü seç, BAGLAM.md yaz, `oneriler/*.json` oku ve `islenmis/` taşı (a6); klasörden içe al taraması (a5); Anthropic sohbeti (anahtar kaydı Keychain'de kalıcı mı: d1); menü çubuğu ve çentik zamanlayıcı (e1, e2); Finder'da göster (a9); uygulamayı kapatıp açınca bookmark erişimi sürüyor mu.

Geri alma: S1-S3 saf yeniden düzenleme (davranış aynı); S4 yeni migration yalnız ekleme yapar; S5 `MAS` kapalıyken arayüz değişikliği yok; S6 eski veri hiç silinmez; S7-S9 ayrı çıkış, mevcut paketin üretimini bozmaz.

### Durum: S1–S3 (2026-10-04, geliştirme hazırlığı; yayın değil)

| Adım | Durum | Ne yapıldı | Kanıt komutu | Çıktı |
|---|---|---|---|---|
| S1 | Yapıldı | `MAS` anahtarı yalnız komut satırından: `swift build -Xswiftc -DMAS` (`Package.swift` değişmedi). `BuildFlavor.isMAS` (`Sources/MarkaCore/BuildFlavor.swift`). `canonical` → `PathCanonical` (`Sources/MarkaCore/Workspace/PathCanonical.swift`); `FileImportGuard` ve `SuggestionInbox` onu kullanır; `SandboxProfile.canonical` MAS dışında ona yönlendiren ince sarmalayıcı olarak kaldı. | `scripts/test.sh`; `swift build --target MarkaCore -Xswiftc -DMAS --scratch-path .build/mas-kip` | Normal kip: 243 test geçti (önce 233). MarkaCore MAS kipinde derlendi. `PathCanonical` eski gövdenin kopyasıyla karşılaştırılarak sınandı (sembolik bağ, `..`, olmayan yol). |
| S2 | Yapıldı (derleme düzeyinde) | `#if !MAS` içinde: `CodexAppServer.swift`, `ChildEnvironment.swift`, `BrandSandbox.swift` (profil, `BrandIsolation`, `SandboxRunner`) bütünüyle; `ChatEngine` Codex alanları, `codexServer`/`runCodex`/`CodexTurnState`; `StructuredProvider.codex`; `AppModel` `codex`, `codexAccount`, `codexStatus`, `codexModel`, `isolation`, `refreshCodexStatus`; Ayarlar Codex bölümü ve ChatGPT giriş/çıkış; rapor özetinin Codex yolu; `JoiTodoImporter.candidateDirectories` (~ ve iCloud) ve Onboarding'deki otomatik bulma; tüm `MARKA_*` kancaları `DevHook.value` üzerinden (MAS'ta `nil`). `AIProviderKind` durumu kaldı; `AIProviderKind.selectable` MAS'ta yalnız `[.anthropic]` (izin kartı, sohbet listesi, özet seçimi); `createSession` seçilemeyen sağlayıcıyı reddeder; eski DB'den gelen Codex oturumu MAS'ta çalıştırılmaz, hata verir. | `scripts/mas-tarama.sh` | Tarama: 73 dosya, 16987 kod satırı taranıp 1183 satır `#if !MAS` içinde atlandı; `Process(`, `sandbox-exec`, `/bin/zsh`, `NSTask`, `environment["MARKA_` **bulunmadı**. Değişiklik öncesi kaynakta aynı tarama 3 `Process(`, 2 `sandbox-exec`, 1 `/bin/zsh`, 17 `environment["MARKA_` buldu (betiğin yakaladığının karşı kanıtı). `swift build --product MarkaApp -Xswiftc -DMAS`: 0 hata, `Build of product 'MarkaApp' complete!` (tek uyarı önceden var olan `BackupService.swift:28` `nonisolated(unsafe)`). |
| S3 | Yapıldı (bookmark yok) | `FolderAccess` protokolü (`root()`, `folder(savedPath:)`, `begin`, `end`) + `FolderAccessError.izinGerekli(ipucuYol:)` + varsayılan `AbsolutePathFolderAccess` (bugünkü mutlak yol, kapsam boş işlem) — `Sources/MarkaCore/Workspace/FolderAccess.swift`. `BrandFolders` kök/kayıtlı yolu bu arayüzden alır; `folder(for:)`, `existingFolder`, `writeContextFile`, `importableFiles`, `SuggestionInbox.scan` erişim kapsamı içinde çalışır (`withAccess`, `defer` ile kapanır). İzin yoksa `existingFolder` artık sessizce `nil` değil `izinGerekli` fırlatır (a3); varsayılan uygulamada izin hep var, davranış aynı. Sahte uygulama yalnız testte (`SahteKlasorErisimi`). | `scripts/test.sh` (`KlasorErisimTests`, 10 test) | İzin yoksa `izinGerekli` ve klasör/ayar oluşmaz; başlat/bitir sayısı eşit (≥7 işlemde; hata yolunda da); başlatılamayan kapsam bitirilmez; varsayılan uygulama eski yolları üretir (`… 2`, `_Tüm Markalar`, kayıtlı yol olduğu gibi); A'nın izni B'nin klasörünü (ön eki aynı kardeş ve `..` kaçışı dahil) açmaz. Mevcut `IsolationTests`, `TerminalOneriTests` değiştirilmeden geçti. |

Notlar ve sınırlar:
- **Test hedefi ve `MarkaDogrula` MAS kipinde derlenmez** (bilerek): `IsolationTests` Codex profilini, `MarkaDogrula` gerçek Codex App Server'ı sınar. Codex'e bağlı testler MAS dışı (normal) kipte kalır. MAS kipinin kanıtı yalnız `MarkaApp` + `MarkaCore` derlemesi ve kaynak taramasıdır; MAS kipinde **çalışan bir uygulama iddia edilmez**, sandbox'lı paket üretilmedi (S7).
- Tarama metin düzeyindedir (sınırları `scripts/mas-tarama.sh` başında): yalnız `#if MAS`/`#if !MAS` bilinir, satır sonu yorumları taranır, dolaylı süreç başlatma (ör. `posix_spawn`) aranmaz.
- MAS'ta marka klasörü hâlâ `BrandFolders.defaultRoot` (`.documentDirectory`) ve `AbsolutePathFolderAccess` ile çalışır; a1/a2 çakışması S4 (bookmark) + S5'e kadar açık. BAGLAM.md yazımı hâlâ markanın `.codex` iznine bağlı; MAS'ta izin verilemediği için yazılmaz (anlam değişikliği a4, S5'te karar).
- Bitti kapısındaki `scripts/build-app.sh` bu turda `~/Applications`'a kurulmadı: kullanıcının gerçek uygulaması o paketten açıktı (betik paketi `rm -rf` ile siler). Betiğin kopyası yalnız çıkış yolu geçici klasöre çevrilerek çalıştırıldı: release derleme + paketleme + `codesign --verify` geçti.

### Xcode projesi gerekir mi?

- `scripts/build-app.sh` zaten SwiftPM ürününü elle `.app` paketine koyup `codesign` ile imzalıyor (`:60-64`); `codesign --entitlements <dosya>` ile sandbox'lı imzalı paket üretmek teknik olarak aynı yolla yapılabilir görünüyor. **Doğrulanamadı** (üretilmedi).
- Apple forum ve topluluk arama sonuçları şunu söylüyor: entitlements SwiftPM tarafından yönetilmez; MAS için paketin `productbuild` ile imzalı `.pkg` yapılması, gömülü provisioning profile ve uygulama kimliği gerektiği belirtiliyor; "Xcode projesi gerek" diyenler de var. Kaynaklar: [forum 826941](https://developer.apple.com/forums/thread/826941), [forum 768361](https://developer.apple.com/forums/thread/768361), [Swift Forums 83478](https://forums.swift.org/t/is-it-possible-to-codesign-cli-applications-as-part-of-swift-run/83478). Bunlar resmî Apple belgesi değildir; hükmü kesin değildir.
- Plan `F8`, "Xcode projesi" dediği için Apple'ın MAS gönderimi (App Store Connect'e yükleme: `xcrun altool`/Transporter/Xcode) ve ikon/asset kataloğu (`Assets.xcassets`), `CFBundleIconName` gerekliliği gibi doğrulamalar için Xcode'un gerekli olabileceğini varsayıyor. Gerekli olup olmadığı **doğrulanamadı**. Önerilen karar yolu: S7'de sandbox'lı yerel imza ile geliştirmeyi SwiftPM'de sürdür; gönderim öncesi (F8) küçük bir Xcode projesi (yalnız paketleme ve arşivleme için, kaynağı SwiftPM paketine bağlı) kurulup App Store Connect doğrulaması (`Validate App`) ile karar verilsin. CLAUDE.md "Xcode yok" diyor, ama gerçek-pencere doğrulama notu Xcode'un bu makinede kurulu olabileceğini söylüyor; kurulu sürüm bu analizde ölçülmedi.

## 5. Açık sorular ve doğrulanamayanlar

1. Sandbox'lı uygulamada `FileManager.homeDirectoryForCurrentUser`, `.documentDirectory`, `NSHomeDirectory` değerleri (container mı, gerçek ev mi).
2. Bookmark davranışı: uygulama güncellemesi, imza değişimi, başka Mac'e yedek.
3. Mail'e container içi PDF eki (a13); Finder'da gösterme (a9); container içi dosyayı başka uygulamada açma (a18); sürükle-bırak erişimi (a17).
4. Keychain: sandbox'sız sürümün yazdığı kaydın okunabilirliği; `kSecAttrAccessible…ThisDeviceOnly` ve data protection keychain gerekliliği.
5. Ad-hoc imzalı, entitlements'lı yerel paketin sandbox'a girip girmediği ve container oluşturup oluşturmadığı.
6. MAS gönderimi için Xcode zorunluluğu ve gereken Info.plist anahtarları (örn. şifreleme beyanı, ikon adı).
7. Container taşıma (eski sandbox'sız veri alanı) için Apple'ın resmî mekanizmasının varlığı ve kapsamı.
8. `PrivacyInfo.xcprivacy` gerekçe kodları.
9. Aynı paket kimliği ile sandbox'lı ve sandbox'sız sürümlerin birlikte yaşaması (veri alanı, Keychain, tercihler ayrı olur; karar gerek).
10. MAS incelemesinin sonucu: bilinemez.
