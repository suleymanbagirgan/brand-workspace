# Dağıtım, güncelleme, ödeme ve AI sağlayıcıları

Kaynaklar 17 Eylül 2026'da kontrol edildi. Hukuki görüş değildir.

## 1. Mac App Store ile doğrudan dağıtımın karşılaştırması

| Konu | Mac App Store | Doğrudan dağıtım (Developer ID + notarization) |
|---|---|---|
| Sandbox | Zorunlu ("To distribute a macOS app through the Mac App Store, you must enable the App Sandbox capability") | İsteğe bağlı |
| Terminal ve kullanıcının kurulu `claude`/`codex` araçları | Sandbox'lı süreç alt süreçlerine sandbox'ı devrediyor (Apple DTS, forums/thread/706390). `~/.local/bin` altındaki araçlar çalıştırılamıyor (forums/thread/654579). Review 2.5.2 kod çalıştırmayı kısıtlıyor. Ürünün terminal ve Codex bölümü pratikte çalışmaz | Çalışır (bu yapıda doğrulandı) |
| Güncelleme | Yalnızca App Store (Review 2.4.5 vii) | Sparkle 2.x (MIT) ile |
| Ödeme | Apple IAP, %15-30 komisyon | Paddle gibi Merchant of Record. Türkiye Paddle'ın desteklenmeyen ülkeler listesinde değil. Stripe'ın desteklediği işletme ülkeleri arasında Türkiye yok |
| Hesap | Apple Developer Program (yıllık 99 USD) | Aynı program; Developer ID sertifikası için Account Holder olmak gerekir |

**Öneri:** Doğrudan dağıtım. Developer ID ile imzala, notarize et, güncellemeleri Sparkle ile yap, ödemeyi Paddle'a bırak. App Store sürümü ancak terminal ve Codex'siz, sadeleştirilmiş bir ürün olarak düşünülebilir; bu beta için önerilmez.

## 2. Senin yapman gereken hesap ve yayın adımları

Paketleme tek komuttur: `scripts/release.sh` (18 Eylül 2026, 0.2.0). Sürüm `Sources/MarkaCore/Version.swift`'ten,
build numarası git commit sayısından gelir (`scripts/version.sh`); Info.plist ve dmg adı ondan türer.

**Ad-hoc beta (bugünkü durum, hesap gerekmez):**
```
scripts/release.sh
```
`dist/MarkaCalismaAlani-<sürüm>.dmg` üretir (uygulama + `/Applications` kısayolu) ve doğrular: `codesign --verify --deep --strict`,
Info.plist sürümü, `hdiutil verify`, dmg salt okunur bağlanıp içindeki uygulamanın imzası ve sürümü, `spctl` değerlendirmesi
(ad-hoc'ta ret beklenir). Çıktı "İMZASIZ/AD-HOC — katılımcı Gatekeeper uyarısı görecek" der. Katılımcıya dmg ile birlikte
`docs/beta-kurulum.md` gönderilir (macOS 14: Sağ tık › Aç; macOS 15+: Sistem Ayarları › Gizlilik ve Güvenlik › Yine de Aç).

**İmzalı ve notarize beta (hesap açılınca):**
1. Apple Developer Program üyeliği (yıllık 99 USD, kimlik doğrulama gerekir): https://developer.apple.com/programs/enroll/
2. developer.apple.com › Certificates › **Developer ID Application** sertifikası oluştur (Account Holder olmalısın), indirip
   bu Mac'te çift tıkla. Kontrol: `security find-identity -v -p codesigning` listesinde
   `"Developer ID Application: Ad Soyad (TAKIMID)"` görünmeli.
3. Notarization kimlik bilgisini bir kez Keychain'e kaydet (uygulamaya özel parola appleid.apple.com'dan):
   ```
   xcrun notarytool store-credentials marka --apple-id <apple-id> --team-id <TAKIMID>
   ```
4. Paketi üret:
   ```
   scripts/release.sh --sign "Developer ID Application: Ad Soyad (TAKIMID)" --notarize marka
   ```
   Betik sırayla: kimliği Keychain'de ve profili notarytool'da denetler (yoksa ne yapılacağını söyleyerek durur) →
   hardened runtime + zaman damgasıyla imzalı `.app` → uygulamayı notarize eder ve bileti zımbalar (`stapler staple`) →
   dmg'yi oluşturur, imzalar, notarize eder, zımbalar → `spctl -a -t open --context context:primary-signature -vv` ile dmg'yi,
   `spctl -a -t exec -vv` ile içindeki uygulamayı doğrular; "Notarized Developer ID" görmezse hata verir.
   Kimlik, Apple ID ve parola betikte yoktur. `--sign` tek başına da çalışır ama notarize edilmemiş paket macOS 15'te yine
   engellenir; betik bunu uyarır.
5. Beta dağıtımı: dmg dosyasını 5 katılımcıya doğrudan gönder; SHA-256 değeri betik çıktısının sonundadır.
6. Sonraki adımlar (henüz yapılmadı):
   - Sparkle entegrasyonu ve EdDSA anahtarları
   - Paddle satıcı hesabı
   - Anthropic ticari kullanım koşullarının ve OpenAI'ın app-server'ın ticari kullanımına dair görüşünün teyidi

**Durum:** Bu Mac'te Developer ID sertifikası yok; imzalı/notarize dal yazıldı ama hiç çalıştırılmadı (ilk gerçek
koşuda doğrulanacak). Ad-hoc dal çalıştırıldı ve doğrulandı. Paket yalnızca Apple Silicon (arm64) içindir; Intel Mac'te
açılmaz. Evrensel (arm64 + x86_64) derleme Command Line Tools ile denenmedi.

## 3. Anthropic (Claude)

- Uygulama **Anthropic Messages API**'yi kullanıcının kendi API anahtarıyla çağırır. Anahtar Keychain'de, `WhenUnlockedThisDeviceOnly` erişim sınıfıyla saklanır.
- Claude.ai tüketici aboneliği (Pro/Max) bağlanmaz. Anthropic'in belgesi: "Anthropic does not permit third-party developers to offer Claude.ai login into their own applications, or to route requests through Free, Pro, or Max plan credentials on behalf of their users." (code.claude.com/docs/en/legal-and-compliance)
- Terminal bölmesinde kullanıcı kendi kurduğu, değiştirilmemiş `claude` CLI'ını kendi hesabıyla çalıştırır. Uygulama bu oturumun belirteçlerini okumaz ve saklamaz. Terminal bir "abonelik entegrasyonu" olarak sunulmaz.
- Varsayılan model `claude-opus-5`; Sonnet 5 ve Haiku 4.5 de seçilebilir. Opus 5 isteklerinde `fallbacks: "default"` açıktır. Maliyet, yanıttaki token sayılarından liste fiyatıyla (2026-06-24 tablosu) **tahmini** olarak gösterilir.
- **Effort:** `output_config.effort` yalnızca destekleyen modellere gönderilir (Opus 5, Sonnet 5). Haiku 4.5 effort'u desteklemez ve alan gönderilirse 400 döner; bu modelde Ayarlar'daki effort seçimi yok sayılır ([Effort](https://platform.claude.com/docs/en/build-with-claude/effort) "Supported models"). Haiku 4.5'e `thinking` de gönderilmez (adaptive yalnızca Opus/Sonnet 5; [Models overview](https://platform.claude.com/docs/en/about-claude/models/overview)).
- **Belgeyle karşılaştırma (2026-09-18):** gönderilen alanların tümü belgelenmiş: `cache_control` (üst düzey), `thinking: {type: "adaptive"}`, `output_config.effort`/`format` ([Messages API](https://platform.claude.com/docs/en/api/messages/create)); `fallbacks: "default"` + `anthropic-beta: server-side-fallback-2026-07-01` ([beta Messages API](https://platform.claude.com/docs/en/api/beta/messages/create)); araçlarda `eager_input_streaming: true` ([Fine-grained tool streaming](https://platform.claude.com/docs/en/agents-and-tools/tool-use/fine-grained-tool-streaming), tüm modeller); anahtar doğrulama `POST /v1/messages/count_tokens` ([Token counting](https://platform.claude.com/docs/en/build-with-claude/token-counting), ücretsiz). Yapılandırılmış çıktı Haiku 4.5'te de destekli ([Structured outputs](https://platform.claude.com/docs/en/build-with-claude/structured-outputs)); şemalarımız desteklenmeyen `minimum`/`maximum` kullanmıyor.
- **Canlı doğrulama aracı:** `ANTHROPIC_API_KEY=sk-ant-… swift run MarkaDogrula anthropic [--model <kimlik>] [--max-tokens <n>]`. Anahtar yalnızca ortam değişkeninden okunur; geçici klasörde sentetik iki marka kurulur; anahtar doğrulama, akışlı sohbet, araç döngüsü (`kaynak_oku` → sonuç → yanıt), marka yalıtımı (B markasının kimliğiyle araç çağrısı reddedilmeli), bilgi derleme (B5; kaynaksız ve başka marka kaynaklı iddia reddedilmeli) ve rapor özeti (D4; her cümle madde referansı taşımalı) adımları `✓/✗`, süre, token ve tahmini maliyetle yazılır. Varsayılan model `claude-haiku-4-5-20251001`, `max_tokens` ≤ 4096; beklenen toplam birkaç sent. Çıkış kodları README "Doğrulama aracı" bölümünde.
- **Canlı test durumu:** Bu Mac'te bir Anthropic API anahtarına erişim yoktu ve anahtar araması bilinçli olarak yapılmadı. Akış ayrıştırıcısı, araç döngüsü, geçmiş, maliyet ve marka yalıtımı kayıtlı SSE yanıtlarıyla birim testlerinde doğrulandı; doğrulama aracı yalnızca anahtarsız (çıkış kodu 2) ve yerel sahte sunucuyla (`ANTHROPIC_BASE_URL`) kuru çalıştırıldı. Gerçek API çağrısı yapılmadı.

## 4. OpenAI Codex App Server

- Kullanıcının kurulu `codex` aracı `codex app-server` olarak başlatılır (satır sonlu JSON-RPC). Giriş Codex'in kendi ChatGPT akışıyla yapılır ve belirteçler Codex'te kalır.
- **Doğrulandı (codex-cli 0.146.0, ChatGPT Plus hesabı, sentetik marka):**
  - `initialize` ve `account/read`
  - `model/list` (varsayılan model buradan seçilir; kullanıcı config'indeki model ChatGPT hesabında desteklenmeyebilir)
  - `thread/start` ile akışlı yanıt (183 delta)
  - Dinamik araçlar (`item/tool/call`): marka kapsamlı arama, okuma ve öneri
  - Öneri onaylama ve geri alma
  - Süreç yeniden başlatıldıktan sonra `thread/resume` ve geçmişin korunması (markanın kendi Codex ev dizininde)
  - Yapılandırılmış çıktı (`outputSchema`, bilgi derleme ve rapor özeti yolu) yalıtımlı süreçte
  - Marka yalıtımı (0.2.0, 2026-09-18): diğer markanın dosyası okunamadı, kendi dosyası okundu, kendi klasörüne yazıldı, diğer markaya ve ev dizinine yazılamadı, marka kökü ve uygulama verisi listelenemedi, `~/.codex/sessions` okunamadı. Hem modelden bağımsız `command/exec` ile hem modelin çalıştırdığı kabuk komutlarıyla ölçüldü; "tüm markalar" oturumunda da iki markanın klasörü `Operation not permitted` ile okunamadı.
- **Güvenlik ayarı (0.2.0):** Codex App Server `sandbox-exec -p <profil> codex app-server` olarak başlar. Profil (`Sources/MarkaCore/AI/BrandSandbox.swift`): `(allow default)` taban; yazma yalnızca marka klasörü, markanın Codex ev dizini (`CODEX_HOME=<veri alanı>/Codex/marka-<kimlik>`), `~/.codex/auth.json`, `/private/tmp`, kullanıcının geçici klasörü ve `/dev`; okuma ve yazma yasağı marka klasörleri kökü, kayıtlı tüm marka klasörleri, uygulama veri alanı, `~/.codex` (giriş dosyası ve kurulum klasörü hariç), `~/.claude`, `~/.claude.json` ve kullanıcının kabuk geçmişi (`~/.zsh_history`, `~/.zsh_sessions`, `~/.bash_history`); oturum markasının klasörü sonra yeniden açılır (seatbelt'te sonraki kural öncekini ezer; ölçüldü). Yollar `realpath` ile yazılır (`/tmp` kuralı `/private/tmp`'yi tutmaz; ölçüldü), seatbelt eşleşmesi NFC/NFD biçiminden bağımsızdır (ölçüldü). Profil ayrıca profil dışı süreç başlatma yollarını kapatır: LaunchServices/`open`, AppleEvents, Kısayollar (`mach-lookup` reddi) ve `/private/tmp` · `/private/var/folders` altındaki yerel Unix soketleri (tmux/screen köprüsü), ssh-agent'ın launchd soketi istisna. Profil uygulandı mı, her başlatmada yasaklı bir sınama dosyası okunarak ölçülür; ölçülemezse süreç başlamaz. Codex'in iç sandbox'ı yalnızca bu durumda `danger-full-access` yapılır; onay politikası `never`. Denetim süreci (hesap/giriş/model listesi) da aynı okuma yasaklı profille sarılır ama LaunchServices açık kalır (ChatGPT girişi tarayıcı açar) ve tur başlatamaz; kullanıcının `codex` ikilisi kurcalanmış olsa bile marka verisi okunamaz.
- **Neden iç sandbox kapalı:** macOS'ta iç içe `sandbox-exec` yalnızca dış profil saf `(allow default)` iken çalışıyor; herhangi bir `deny` kuralı olan dış profilin içinde `sandbox_apply: Operation not permitted` (çıkış 71) veriyor (2026-09-18 ölçümü). Codex'in kendi seatbelt'i bizim profilimizin içinde kurulamaz.
- **Sınırlar:**
  - OpenAI app-server'ı "experimental" olarak işaretliyor ve üretim için desteklemiyor.
  - Üçüncü taraf ticari bir uygulamanın kullanıcının ChatGPT planını kullanmasına dair açık bir izin bulunamadı. Ticari satıştan önce teyit alınmalı; yedek yol API anahtarı modu olabilir.
  - Yalıtımın bedelleri: marka klasörü dışına yazma onayla değil kesin redle kapanır; komutların ağ erişimi app-server'ınkinden ayrılamaz (komutlar internete çıkabilir); sistem geçici klasörleri markalar arasında ortaktır; bilgisayarın marka klasörleri dışındaki kısmı okunabilir; iç içe sandbox kullanan araçlar (Codex CLI'nın varsayılan kipi, sandbox'ı açık Claude Code) marka terminalinde komut çalıştıramaz. Ayrıntı README "Bilinen sınırlar".
  - Kullanıcının `~/.codex/config.toml` ayarları uygulamanın Codex süreçlerine uygulanmaz (dosyadaki proje yolları başka markaların adlarını taşır, bu yüzden bağlanmaz). Giriş dosyası sembolik bağla paylaşılır; belirteç yenilemesinin bağ üzerinden yazıldığı doğrulanmadı.
  - Markada Codex izni yine varsayılan olarak kapalıdır.
  - 0.1.0 test oturumları `~/.codex/sessions/2026/09/17/` altında Codex geçmişinde görünür; 0.2.0'dan itibaren uygulamanın Codex kayıtları `<veri alanı>/Codex/` altındadır.

## 5. Uygulama aboneliğine AI kredisi dahil etme (ayrı değerlendirme)

Henüz uygulanmadı. Anthropic'in Claude Code belgesi, müşterinin son kullanıcı adına Claude kullanımını ödeyip aracılık etmesini ("pay for, resell, or intermediate") Claude Code bağlamında kısıtlıyor. API tabanlı bir yeniden satış için Anthropic'in ticari koşulları ve satış ekibiyle ayrıca görüşülmeli.
