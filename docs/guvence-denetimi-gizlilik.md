# Güvence denetimi: veri gizliliği (kural 6 ve kullanıcıya verilen gizlilik iddiaları)

Denetçi: `veri-gizliligi-denetcisi` · Tarih: 2026-10-04 · Kip: **salt okuma**. Kod çalıştırılmadı, test ya da derleme yapılmadı;
bulgular kaynak okumasına dayanır. "Ölçüldü" yazmayan hiçbir şey çalıştırılarak doğrulanmadı. Kanıtlanamayan yerler **şüphe** diye işaretli.

Kapsanan dosyalar: `AI/ChatEngine.swift`, `AI/AnthropicClient.swift`, `AI/ContextAndTools.swift`, `AI/Compilers.swift`,
`AI/CodexAppServer.swift`, `AI/BrandSandbox.swift`, `AI/ChildEnvironment.swift`, `AI/AIBasics.swift` (Keychain),
`Status/Diagnostics.swift`, `Status/BetaMetrics.swift`, `Backup/BackupService.swift`, `Store/Store.swift` (denetim olayı),
`Store/Store+Organization.swift`, `Store/Store+Proposals.swift`, `Workspace/WorkspacePreferences.swift`, `MarkaApp/AppModel.swift`,
`AIChat.swift`, `AIChatPanel.swift`, `BrandView.swift`, `BrandInfoView.swift`, `OnboardingView.swift`, `SettingsView.swift`,
`ReportsView.swift`, `MarkaDogrula/main.swift`, README, `docs/kullanim-kilavuzu.md`, `docs/beta-kurulum.md`, `docs/bilinen-sinirlar.md`,
`docs/degerlendirme-plani.md`, `docs/dagitim-ve-saglayicilar.md`; depo genelinde kişisel veri taraması (`git ls-files` + izlenmeyen dosyalar).

## Özet tablo

| # | Önem | Kod | Konu |
|---|---|---|---|
| Y1 | Yüksek | G5 / iddia | Marka açılınca `BAGLAM.md` (marka bağlamı) AI izninden bağımsız olarak `~/Documents` altına yazılıyor |
| Y2 | Yüksek | G5 / iddia | Codex izni onay metni, Codex'in onaysız komut + açık ağ + ev dizini okuma yetkisini söylemiyor |
| O1 | Orta | G5 | Stüdyo'nun (şirket) profili ve ekibi, Stüdyo'nun kendi AI izni sorulmadan her müşteri markasının sağlayıcısına gidiyor |
| O2 | Orta | iddia | Mutlak "veri bu Mac'te durur" iddiaları (Onboarding, araç çubuğu, kılavuz, beta kurulum) |
| O3 | Orta | G2/G5 test | İletişim bilgisi ve izin sınırları için ayırt edici test eksik |
| D1 | Düşük | G5 | Tüm markalar oturumunda izin geri alınınca eski içerik geçmişle yeniden gönderilir (arayüz yolu yok; gizli) |
| D2 | Düşük | G5 | `ContextBuilder.allBrandsContext` izin süzgeçsiz ve `public` (çağıranı yok; tuzak) |
| D3 | Düşük | G4 | `ChatEngine.init` varsayılan anahtar kapatması gerçek Keychain hesabını okur |
| D4 | Düşük | G1 | Codex geliştirici talimatında tam klasör yolu (macOS kullanıcı adı dahil) OpenAI'a gider |
| D5 | Düşük | G6 | Herkese açık depoya girebilecek kişisel iz: test dizgisinde yerel kullanıcı adı, ajan dosyasında gerçek soyadı |
| D6 | Düşük | iddia | "AI izinleri" kartında eskimiş metin (terminal; yalnız rapor özeti) |
| D7 | Düşük | G5 | `ReportSummarizer.summarize` markayı çağırandan alır; içerik–marka eşleşmesini denetlemez |
| D8 | Düşük | iddia | README "tüm markalar sohbeti" diyor; arayüzde böyle bir yol yok |

---

## Bulgular

### Y1 · Yüksek · Marka bağlamı izin olmadan `~/Documents`'a yazılıyor

- **Kod:** `Sources/MarkaApp/BrandView.swift:74-75` (`.task(id: brand.id) { app.writeContext(brandId:) }`),
  `Sources/MarkaApp/AppModel.swift:329-333`, `Sources/MarkaCore/AI/ChatEngine.swift:62-84` (`writeContextFile`),
  kök `BrandFolders.defaultRoot` = `~/Documents/Marka Çalışma Alanı` (`ChatEngine.swift:11-13`).
- **Ne yazılıyor:** `ContextBuilder.brandContext` çıktısının tamamı: marka adı, sektör, tanım, şirket profili (ad/slogan/hakkımızda/misyon),
  ekip adları ve unvanları, marka profili bölümleri, kişi adları ve rolleri, açık kayıt/görev başlıkları, kaynak başlıkları, bilgi sayfası
  başlıkları, bilgi kuralları. Klasör adı da marka adıdır.
- **Senaryo:** Kullanıcı hiçbir markaya AI izni vermemiştir. Bir markayı açar; uygulama `~/Documents/Marka Çalışma Alanı/<Marka>/BAGLAM.md`
  dosyasını yazar. macOS'ta "Masaüstü ve Belgeler klasörleri" iCloud eşitlemesi açıksa bu dosya ve marka adlı klasör Apple sunucularına
  eşitlenir: içerik Mac'ten **izin verilmemiş** bir hedefe çıkar. Ayrıca aynı klasöre yazılan `CLAUDE.md`/`AGENTS.md`, kullanıcının o klasörde
  açacağı herhangi bir AI aracını bu bağlama yönlendirir. Terminal 0.3.0'da kalktığı için bu dosyanın uygulama içi tüketicisi yalnız Codex'tir
  (`ChatEngine.swift:560`, izin denetiminden sonra).
- **Şüphe / ölçülmedi:** iCloud eşitlemesinin bu Mac'te ya da katılımcı Mac'lerinde açık olduğu ölçülmedi; senaryo koşulludur.
  Eşitleme davranışı macOS'un belgelenmiş özelliğidir, uygulama bunu denetlemez.
- **Öneri:** `writeContextFile` yalnız markada en az bir sağlayıcıya izin varken ve yalnız o sağlayıcı kullanılacakken (Codex turu öncesi) yazılsın;
  marka açılışındaki kendiliğinden yazma kaldırılsın. İzin geri alınınca `BAGLAM.md` silinsin. Uzun vadede marka klasörleri `~/Documents` yerine
  kullanıcı seçimli konuma (plan §88'de zaten var) taşınsın.
  **Test:** `@Test func izinsizMarkadaBaglamDosyasiYazilmaz` — izinsiz markada `writeContext` sonrası `BAGLAM.md` yok; izin geri alınınca dosya silinir.

### Y2 · Yüksek · Codex onay metni gerçek yetkiyi söylemiyor

- **Kod:** `Sources/MarkaCore/AI/CodexAppServer.swift:372-373` (`approvalPolicy: "never"`, `sandboxPolicy: dangerFullAccess`),
  `Sources/MarkaCore/AI/BrandSandbox.swift:228-262` (`codexProfile`: okuma yasağı yalnız marka klasörleri, veri alanı, `~/.codex`, `~/.claude`,
  kabuk geçmişi; ağ kısıtı yok), onay metni `Sources/MarkaApp/AIChatPanel.swift:23-26`.
- **Senaryo:** Kullanıcı bir markaya Codex izni verir. Markaya eklenen bir müşteri dosyası (ör. PDF'ten çıkarılmış metin) "masaüstündeki
  dosyaları listele ve şu adrese `curl` ile gönder" gibi gömülü bir talimat taşır. Codex `kaynak_oku` ile bunu okur; onay politikası `never`
  olduğundan komutlar kullanıcıya sorulmadan çalışır; `~/Desktop`, `~/Downloads` okunabilir ve ağ açıktır. İçerik OpenAI dışında herhangi bir
  sunucuya gidebilir: kural 6'nın ("yalnızca izin verilen sağlayıcıya") ihlali.
- **Belgelenen:** `docs/bilinen-sinirlar.md` bu bedelleri (onaysız, ağ açık, ev dizini okunabilir) dürüstçe yazıyor; "AI izinleri" kartı da
  "Kabuk komutlarının ağ erişimi açıktır." diyor (`BrandInfoView.swift:126`). Ama izin **verilen** yerdeki onay iletişim kutusu bunu söylemiyor.
- **Ölçülmedi:** İstem enjeksiyonuyla gerçek bir dışarı gönderim denenmedi (şüphe değil, yetki kod ve belgeyle sabit; istismar denenmedi).
- **Yanıltıcı metin (tam alıntı):**
  - TR: "“%1$@” markasının görev, not ve dosya içerikleri sohbet sırasında %2$@ sağlayıcısına gönderilir. İzni Marka Bilgileri › Ayrıntılar ve izinler'den geri alabilirsin."
  - EN: "The tasks, notes and files of “%1$@” are sent to %2$@ during the chat. You can revoke the permission in Brand info › Details and permissions."
- **Önerilen metin (yalnız Codex seçilince ek cümle):**
  - TR: "“%1$@” markasının görev, not ve dosya içerikleri sohbet sırasında %2$@ sağlayıcısına gönderilir. Codex bu markanın klasöründe sana sormadan komut çalıştırabilir; komutlar internete çıkabilir ve diğer markalar dışında Mac'indeki dosyaları okuyabilir. İzni Marka Bilgileri › Ayrıntılar ve izinler'den geri alabilirsin."
  - EN: "The tasks, notes and files of “%1$@” are sent to %2$@ during the chat. Codex can run commands in this brand's folder without asking; commands can reach the internet and read files on your Mac outside other brands' folders. You can revoke the permission in Brand info › Details and permissions."
- **Düzeltme önerisi (kod):** Codex profiline ağ kısıtı konamıyorsa (belgede gerekçeli), en azından sohbet turlarında `approvalPolicy` `untrusted`/`on-request`
  yapılıp onay kartı kullanılsın (onay akışı `handleCodexRequest`'te zaten var). Okuma yasağına `~/Desktop`, `~/Downloads`, `~/Documents`
  (marka kökü hariç) eklenmesi değerlendirilsin.

### O1 · Orta · Stüdyo verisi Stüdyo'nun izni sorulmadan gidiyor

- **Kod:** `Sources/MarkaCore/AI/ContextAndTools.swift:61-77` (şirket profili ve ekip her `brandContext`'e eklenir),
  `Sources/MarkaCore/AI/ChatEngine.swift:671-685` (`personaPrompt`: kütüphanedeki yetenek gövdeleri, 6000 karaktere kadar),
  `Sources/MarkaCore/Store/Store+Organization.swift:173-186`. İzin denetimi yalnız oturum markası için yapılır (`ChatEngine.swift:327-336`).
- **Senaryo:** Kullanıcı Stüdyo'ya (kendi şirketi, `isOwn`) hiçbir AI izni vermez; bir müşteri markasına Anthropic izni verir. O müşterinin her
  sohbetinde şirketin adı, sloganı, "hakkımızda" ve misyon metni, markaya atanmış (insan dahil) çalışanların ad ve unvanları, yapay zekâ
  çalışanların görev tarifi ve çalışan rolüyle açılan sohbette yetenek dosyalarının gövdesi Anthropic'e gider. Stüdyo'nun izin anahtarı bu
  akışı durdurmaz. E-posta ve biyografi gitmez (doğrulandı: yalnız `name`, `title`, `kind`, `level`, `charter`).
- **Not:** `SirketVeEkipTests.yapayZekaBaglamiYalnizBuMarkanin_EkibiniVeSirketiTasir` bunun bilinçli tasarım olduğunu gösteriyor; sorun
  tasarım değil, kullanıcıya "izin vermediğin yere gitmez" denmesi (bkz. O2) ve Stüdyo izninin anlamsızlaşması.
- **Öneri:** Ya (a) şirket bloğu ve yetenek gövdeleri yalnız Stüdyo da aynı sağlayıcıya izin veriyorsa eklensin, ya da (b) izin onay metnine
  "Şirket profilin ve bu markaya atanmış ekip adları da gönderilir." cümlesi eklensin (TR) / "Your company profile and the names of team members
  assigned to this brand are also sent." (EN). **Test:** `@Test func stüdyoIzniYoksaSirketBloguMusteriBaglaminaGirmez` (a seçilirse).

### O2 · Orta · Mutlak "veri bu Mac'te" iddiaları

Kod karşılığı: AI açıkken marka bağlamı ve kaynak gövdeleri Anthropic/OpenAI'a gider (`ChatEngine.swift:473-486`, `ContextAndTools.swift:291-296`);
Codex komutları ağa çıkabilir (Y2); `BAGLAM.md` `~/Documents`'tadır (Y1); şirket bloğu izin dışıdır (O1).

1. `Sources/MarkaApp/OnboardingView.swift:26`
   - Alıntı TR: "Verin sende kalır" / "Her şey bu Mac'te durur. Yapay zekâ yalnızca senin izin verdiğin yerde çalışır."
   - Alıntı EN: "Your data stays with you" / "Everything stays on this Mac. The AI works only where you allow it."
   - Önerilen TR: "Verin Mac'inde saklanır" / "Kayıtların bu Mac'te tutulur. Yapay zekâyı bir markada açarsan o markanın içeriği yalnız seçtiğin sağlayıcıya gider."
   - Önerilen EN: "Your data is stored on your Mac" / "Your records are kept on this Mac. If you turn on AI for a brand, that brand's content goes only to the provider you choose."
2. `Sources/MarkaApp/BrandView.swift:53-54` (araç çubuğu kilit simgesi, AI izni olan markada da her zaman görünür)
   - Alıntı TR: "Veri bu Mac'te durur" · EN: "Data stays on this Mac"
   - Önerilen: izinli markada TR "Veri bu Mac'te saklanır; AI açık: içerik %@ sağlayıcısına gider" / EN "Stored on this Mac; AI on: content goes to %@";
     izinsiz markada TR "Veri bu Mac'te saklanır; bu markada AI kapalı" / EN "Stored on this Mac; AI is off for this brand".
3. `docs/kullanim-kilavuzu.md:61`
   - Alıntı: "izin verilmeden o markanın içeriği hiçbir sağlayıcıya gitmez."
   - Doğru TR: "izin verilmeden o markanın içeriği hiçbir sağlayıcıya gitmez. İstisna: şirket profilin (Stüdyo) ve markaya atanmış ekip adları, izin verdiğin her markanın sohbetine eklenir."
   - Doğru EN: "without permission, that brand's content goes to no provider. Exception: your company profile (Studio) and the names of team members assigned to a brand are included in the chat of every brand you allow."
4. `docs/beta-kurulum.md:66-67`
   - Alıntı: "Yalnızca AI ile çalıştığında, o markada izin verdiğin sağlayıcıya (Claude ya da Codex) o konuşmanın içeriği gider."
   - Doğru TR: "Yalnızca AI ile çalıştığında, o markada izin verdiğin sağlayıcıya (Claude ya da Codex) konuşmanın yanında markanın özeti (profil, görev ve kaynak başlıkları, kişi adları, şirket profilin) ve asistanın okuduğu kaynakların metni gider."
   - Doğru EN: "Only when you work with AI, the provider you allowed for that brand (Claude or Codex) receives the conversation plus the brand's summary (profile, task and source titles, contact names, your company profile) and the text of sources the assistant reads."
5. README:63 ve README:111 ("izinsiz sağlayıcıya istek gitmez") teknik olarak doğru (izinsiz **sağlayıcıya** istek gitmez) ama O1 ve Y1 istisnaları yazılmalı; "Bilinen sınırlar"a bir madde önerilir.

Doğrulanıp **doğru** bulunan iddialar: Tanı bilgisi metni (`SettingsView.swift:350`, kılavuz :92/:105, README "Tanı bilgisi içerik taşımaz") —
`DiagnosticEntry` mesaj okumaz, bağlam anahtarı `StaticString`, diskten okunan kayıt yeniden süzülür; "hiçbir yere kendiliğinden gönderilmez" doğru
(ağ çağrısı yok). Beta ölçümleri yalnız sayı taşır (`BetaMetrics.swift:63-74`). Claude ayar metni (`SettingsView.swift:153`) O1 istisnası dışında doğru.

### O3 · Orta · Ayırt edici test eksikleri

- Kişi kartının `email`, `phone`, `notes` alanlarının sistem istemine girmediğini kanıtlayan test yok (kod doğru: `ContextAndTools.swift:84-88`
  yalnız ad/rol yazar). Ekip için yalnız *atanmamış* üyenin e-postası sınanıyor; *atanmış* insan üyenin e-postası ve `bio`su sınanmıyor.
  **Test:** `@Test func baglamKisininEpostaTelefonVeNotunuTasimaz` ve `@Test func atanmisEkipUyesininEpostasiBaglamaGirmez` — ayırt edici
  dizgilerle (`gizli.kisi@ornek-sirket.com`, `+90 555 000 00 00`) `systemPrompt` ve `BAGLAM.md` çıktısında yokluk.
- Y1 ve O1 için test yok (yukarıda önerildi).

### D1 · Düşük · Tüm markalar oturumunda izin geri alındığında geçmiş yeniden gönderilir

- **Kod:** `ChatEngine.swift:446-463` (`history`) + `:474`. `allowedBrandIds` her turda yeniden hesaplanır ama geçmişteki `tool_result` metinleri
  (ör. `kaynak_ara` parçaları) süzülmez.
- **Senaryo:** Tüm markalar oturumunda A markasının kaynak parçaları okunur; kullanıcı A'nın Anthropic iznini kaldırır; aynı oturumda bir sonraki
  mesajda A'nın parçaları geçmiş olarak yine Anthropic'e gider. **Arayüzde tüm markalar oturumu açan yol yok** (`AIChat.swift:93` yalnız `.brand`),
  bu yüzden şu an yalnız çekirdek API'de gizli. **Öneri:** izin kümesi oturum açılışındakinden daralmışsa tüm markalar oturumu devam etmesin.

### D2 · Düşük · `allBrandsContext` izin süzgeçsiz

- **Kod:** `ContextAndTools.swift:39-51`, `:123-135`: `systemPrompt(scope: .allBrands)` tüm markaların adını ve son temas metnini izinden bağımsız yazar.
  `ChatEngine` süzgeçli aşırı yüklemeyi kullanıyor (`ChatEngine.swift:687-701`), başka çağıran yok. Gelecekte biri `public` yolu çağırırsa izinsiz marka
  adları ve içerik gider. **Öneri:** `allowedBrandIds` parametresini zorunlu yapın ya da bu yolu kaldırın.

### D3 · Düşük · Varsayılan anahtar kapatması gerçek hesabı okur

- **Kod:** `ChatEngine.swift:247` `anthropicKey` varsayılanı `Keychain.load(account: "anthropic-api-key")` (kapsamsız). Uygulama kapsamlı hesabı veriyor
  (`AppModel.swift:224-232`); `MarkaDogrula/main.swift:74,196` varsayılanı kullanıyor (yalnız Codex adımlarında; Anthropic turu açmadığı için
  şu an okunmuyor). `TercihYalitimTests` yalnız `MarkaApp`'i tarıyor. **Öneri:** varsayılanı `{ nil }` yapın.

### D4 · Düşük · Codex talimatında tam yol

- **Kod:** `ChatEngine.swift:564` `Çalışma klasörün: \(cwd.path)`; `CodexAppServer.swift:378,416` `cwd`. Yol `/Users/<kullanıcı adı>/Documents/...`
  biçiminde OpenAI'a gider. Marka adı zaten izinle gidiyor; yeni olan macOS kullanıcı adı. Codex'in kendisi de ortam bağlamında cwd gönderiyor
  olabilir (**şüphe**, doğrulanmadı). **Öneri:** talimatta göreli ifade ("bu klasör") kullanın.

### D5 · Düşük · Herkese açık depoda kişisel iz

- `Tests/MarkaCoreTests/DiagnosticsTests.swift:94`: yasaklı dizgi listesinde geliştiricinin **yerel macOS kullanıcı adı** düz metin olarak duruyor
  (izlenen dosya). Öneri: `NSUserName()` kullanın.
- `.claude/agents/kalite-kapisi.md:18` (henüz izlenmiyor, ama `.claude/agents/` klasörü depoda izleniyor): sızıntı tarama deseni **gerçek bir soyadı**
  ve kişisel ev dizini yolu içeriyor. Commit edilirse koruduğu bilgiyi yayımlar. Öneri: deseni depo dışı bir dosyadan (`.git/info/` ya da
  `~/.config`) okuyun.
- `docs/eski-depo-analizi.md:4`: kişisel iCloud yolu ve eski veri klasörünün adı. Düşük; kaldırılması önerilir.
- Tarama: `git ls-files` + izlenmeyen dosyalarda e-posta, telefon, `sk-ant-`, `/Users/` desenleri. Bunlar dışında gerçek e-posta/telefon/anahtar
  bulunmadı (örnekler `ornek-sirket.com`, `ornek.test`, `/Users/ornek`). `docs/images/*.png` içeriği görsel olarak denetlenmedi (**şüphe**: yalnız
  uydurma veriyle çizildiği varsayılıyor).

### D6 · Düşük · "AI izinleri" kartında eskimiş metin

- `Sources/MarkaApp/BrandInfoView.swift:114`
  - Alıntı TR: "Uygulama içindeki rapor özeti yalnız izin verdiğin sağlayıcıyı kullanır. Terminal bu izne bağlı değildir."
  - Alıntı EN: "The in-app report summary uses only the providers you allow. The terminal is not bound by this permission."
  - Terminal arayüzü 0.3.0'da kalktı; asistan sohbeti de bu izne bağlı ama metinde yok.
  - Önerilen TR: "Asistan sohbeti ve rapor özeti yalnız izin verdiğin sağlayıcıyı kullanır. İzin varsayılan olarak kapalıdır."
  - Önerilen EN: "The assistant chat and report summary use only the providers you allow. Permission is off by default."

### D7 · Düşük · Rapor özeti markayı çağırandan alır

- `Compilers.swift:184-190`: izin `brand.allows` ile denetleniyor (iyi), ama `ReportContent` marka kimliği taşımadığı için içeriğin o markaya ait olduğu
  çekirdekte denetlenmiyor. Uygulamadaki tek çağıran (`ReportsView.swift:314,339`) aynı markayı veriyor; bugün sızıntı yok. **Öneri:** `ReportContent`'e
  `brandId` ekleyip `summarize` içinde eşleşmeyi zorunlu kılın.

### D8 · Düşük · README'de olmayan özellik

- README "Asistan paneli" satırı: "Tek marka sohbeti, **tüm markalar sohbeti** ve ekip üyesi rolüyle sohbet." Arayüzde tüm markalar sohbeti açan yol yok
  (`AIChat.swift:93`). Kural 7. Önerilen TR: "Marka sohbeti ve ekip üyesi rolüyle sohbet." / EN: "Brand chat and chat in a team member's role."

---

## Temiz bulunanlar (kanıtla)

- **G1 Günlük:** `MarkaCore` ve `MarkaApp`'te `print`/`NSLog`/`os_log`/`Logger` yok; tek istisna `SnapshotRunner.swift:37-38` (geliştirici çizim kipi,
  geçici klasör yolu yazar). Codex `stderr` `/dev/null`'a gider (`CodexAppServer.swift:84,160`).
- **G2 Tanı:** `Diagnostics.swift` hata mesajını, `userInfo` metnini ve ilişkili değerleri okumaz; alan adları izin listesiyle, bağlam anahtarı
  ASCII/64 karakter kuralıyla süzülür, diskten okunan kayıt yeniden süzülür. Tüm çağıranlar sabit anahtar ya da `StaticString` kullanıyor
  (`AppModel.swift:437-456`). `DiagnosticsTests` ayırt edici içerikle sınıyor.
- **Denetim olayları:** `auditEvent.beforeJSON/afterJSON` içerik (ör. ekip üyesinin e-postası) taşır ama yalnız yerel veri tabanında ve yedekte durur;
  tanı metnine (yalnız sayı) ve marka dışa aktarımına (`BackupService.swift:150-169`, `auditEvent` ve AI mesajları yok) girmez; AI araçları okumaz.
- **G3 Hata mesajı:** `AnthropicClient.apiError` anahtarı ve her `sk-ant-…` dizisini karartır, gövdeyi 200/500 karakterde keser; 401/429/5xx'te gövde hiç
  gösterilmez. Mesaj tanıya yazılmaz.
- **G4 Anahtar:** Keychain `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`; deneme kopyası ayrı hesap ve tercih takımı (`WorkspacePreferences.swift`);
  `ChildEnvironment` `ANTHROPIC_*`/`OPENAI_API_KEY`'i Codex'ten süzer; doğrulama isteği yalnız `"test"` gönderir. Anahtar `UserDefaults`'a yazılmıyor
  (`UserDefaults` yalnız `WorkspacePreferences.swift`'te).
- **G5 İzin:** Sohbet (`createSession` ve her tur, `ChatEngine.swift:341,403`), rapor özeti (`Compilers.swift:186`), bilgi derleme (`Compilers.swift:95`)
  izni çekirdekte denetliyor; `MARKA_SOHBET_ORNEK=1` arayüz atlamasını da çekirdek reddeder. Araçlar başka markanın kaynağını/sayfasını/görevini
  reddediyor (`ownSource`, `bilgi_sayfasi_oku`, `Store+Proposals.swift:196-199`).

## Düzeltme durumu (2026-10-04, `swift-gelistirici`)

Kanıt testleri `Tests/MarkaCoreTests/GuvenceDuzeltmeTests.swift` (G) ve `AITests.swift` (A) içindedir; test sayısı 173 → 200, kapı temiz.

| Bulgu | Durum | Kanıt testi |
|---|---|---|
| Y1 BAGLAM.md izinsiz yazılıyor | düzeltildi (yalnız markanın Codex izni varsa yazılır; izin yoksa klasör de oluşmaz; var olan dosya silinmez; içerikte şirket/ekip/görev tarifi/yetenek yok). Marka açılışı ve profil kaydı aynı kurala bağlı; "Klasörü göster" klasörü oluşturur ama BAGLAM.md'yi yine yalnız Codex izniyle yazar. Öneri "izin kalkınca sil" karar gereği uygulanmadı | G `izinsizMarkadaBaglamDosyasiYazilmazKlasorOlusmaz`, `codexIzinliMarkadaBaglamDosyasiSirketEkipYetenekTasimaz`, `izinKalkincaVarOlanBaglamDosyasiSilinmezYenidenYazilmaz` |
| Y2 Codex onay metni | yapılmadı (başka ajanda ele alınacak) | — |
| O1 Stüdyo verisi Stüdyo izni sorulmadan gidiyor | düzeltildi (seçenek a) | G `studyoIzniYoksaSirketVerisiMusteriBaglaminaGirmez`, `studyoBaskaSaglayiciyaIzinliyseCodexYolunaSirketVerisiGirmez`, `calisanRoluStudyoIzniOlmadanAcilmaz`; A `anthropicIstegindeStudyoIzniYoksaSirketVerisiVeCalisanOnerYok` |
| O2 mutlak "veri bu Mac'te" iddiaları | yapılmadı (metin işi; karar kapsamında değil) | — |
| O3 ayırt edici test eksikleri | düzeltildi | G `baglamKisininEpostaTelefonVeNotunuTasimaz` (bağlam + BAGLAM.md), `atanmisEkipUyesininEpostasiVeBiyografisiBaglamaGirmez` |
| D1 tüm markalar oturumunda geçmiş | yapılmadı (arayüz yolu yok) | — |
| D2 `allBrandsContext` izin süzgeçsiz | düzeltildi (`allowedBrandIds` zorunlu; genel `systemPrompt(.allBrands)` sağlayıcıdan izinli kümeyi hesaplar, sağlayıcısız boş) | G `tumMarkalarBaglamiYalnizIzinliMarkalariTasirSirketEkipYetenekYok` |
| D3–D8 | yapılmadı (karar kapsamında değil) | — |
