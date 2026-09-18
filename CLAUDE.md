# Marka Çalışma Alanı — çalışma kuralları

Çok markalı danışman için yerel macOS uygulaması. Swift 6 + SwiftUI + GRDB 7.11.1 + SwiftTerm 1.19.0. Xcode yok; Command Line Tools ile derlenir.
Dil: arayüz, kod yorumları, test adları ve commit mesajları **Türkçe**. Commit doğrudan `main`'e (yerel depo, uzak yok).

## Komutlar
```sh
scripts/test.sh                      # Swift Testing (CLT rpath hilesi içerir) — `swift test` doğrudan çalışmaz
scripts/build-app.sh                 # dist/Marka Çalışma Alanı.app (ad-hoc imza)
python3 scripts/l10n.py check        # TR/EN çeviri kapsamı; yeni L("…") anahtarı ekleyince çalıştır
MARKA_SNAPSHOT=<klasör> "dist/Marka Çalışma Alanı.app/Contents/MacOS/MarkaCalismaAlani"   # ekranları PNG çizer
swift run MarkaDogrula codex         # gerçek Codex App Server ile uçtan uca
scripts/release.sh [--sign "Developer ID Application: …" --notarize <profil>]   # dist/MarkaCalismaAlani-<sürüm>.dmg
```
Bitti demeden önce: `scripts/test.sh` + `scripts/build-app.sh` + `python3 scripts/l10n.py check` üçü de temiz.

## Yapı
- `Sources/MarkaCore` — veri modeli (`Model/`), GRDB şeması ve tetikleyiciler (`Database/AppDatabase.swift`), `Store+*.swift` yazma/okuma, AI (`AI/`), raporlar, yedek, içe aktarım.
- `Sources/MarkaApp` — SwiftUI. Metinler `L("Türkçe metin")` ile; anahtar Türkçe metnin kendisi, İngilizcesi `Resources/en.lproj/Localizable.strings`.
- `Sources/MarkaDogrula` — canlı entegrasyon doğrulama aracı (sentetik veri).
- `Tests/MarkaCoreTests` — Swift Testing; `makeStore()` bellek içi veritabanı verir. Test adları Türkçe cümle (`@Test func hamKaynakDegistirilemezYalnizcaArsivlenir`).

## Bozulamaz kurallar (README "Güvence kuralları" ile aynı; kodda zorunlu tutulur)
1. **Marka yalıtımı.** Her okuma/yazma `brandId` ile kapsanır. AI aracı başka markanın kimliğini reddeder. Oturumun markası sonradan değişmez.
2. **Kaynak değişmez.** Ham kaynak SQL tetikleyicisiyle korunur; yalnızca arşivlenir.
3. **AI veri değiştirmez, öneri üretir.** Öneri kullanıcı onayıyla uygulanır, geri alınabilir.
4. **Rapor maddesi dayanaksız olamaz.** Yalnızca doğrulanmış çalışma kayıtlarından gelir.
5. **Her yazma denetim olayı bırakır** (`Store.audit`).
6. **İçerik Mac'ten yalnızca izin verilen sağlayıcıya gider.** Günlük, tanı raporu ve ölçümler marka adı ya da içerik taşımaz.
7. **Yapmadığımızı vaat etmeyiz.** Doğrulanmayan şey README "Bilinen sınırlar"da açıkça yazılır.

## Tuzaklar
- Sürüm tek kaynak: `Sources/MarkaCore/Version.swift`; betikler `scripts/version.sh` ile okur. README'deki sürüm satırı testle bağlı.
- Paket yalnızca arm64 (Apple Silicon).
- İç içe `sandbox-exec` çalışmaz (`sandbox_apply: Operation not permitted`, 2026-09-18'de ölçüldü). Codex'i dıştan saran bir seatbelt profili Codex'in kendi sandbox'ını bozar.
- Kullanıcının gerçek verisi `~/Library/Application Support/MarkaCalismaAlani` içinde. Deneme için `MARKA_WORKSPACE` ve `MARKA_FOLDERS` ile ayrı klasör kullan; gerçek veriye yazma.
- Deneme kopyası (`MARKA_WORKSPACE`) gerçek tercihleri ve gerçek Keychain hesabını **paylaşmaz** (D1): tercihler `com.markacalismaalani.app.deneme.<yol özeti>` takımında, anahtar `anthropic-api-key.deneme.<yol özeti>` hesabında; `MARKA_SNAPSHOT` tercih yazmaz. Kanıt: `TercihYalitimTests` (kapsam hesabı + `MarkaApp`'te `UserDefaults.standard`/sabit hesap kullanımı yok). Tercihe ya da anahtara yalnızca `app.preferences` / `app.anthropicKeyAccount` üzerinden eriş. AppKit'in pencere konumu gibi kendi tuttuğu durum hâlâ paket kimliğiyle ortaktır. Kullanıcının açık uygulamasına ve gerçek veri alanına yine dokunma.
- Anthropic API anahtarı aranmaz, Keychain taranmaz; kullanıcı verir.

## Sürüm planı
Güncel plan: `docs/surum-0.2.1.md` (yalnızca arayüz sadeleştirmesi; önceki: `docs/surum-0.2.0.md`). Arayüz ölçümü: `scripts/ui-olcum.sh`. Ajan ekibi: `.claude/agents/`.
