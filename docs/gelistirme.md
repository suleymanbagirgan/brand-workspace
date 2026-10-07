# Geliştirme

Derleme, test, ekran çizimi ve canlı doğrulama araçları. Depo kuralları: [CLAUDE.md](../CLAUDE.md).

```sh
scripts/build-app.sh                 # dist/Workspace AI.app (ad-hoc imzalı)
open "dist/Workspace AI.app"
scripts/test.sh                      # Swift Testing; test sayısı koşu çıktısından okunur
python3 scripts/l10n.py check        # TR/EN çeviri ve İngilizce çoğul kapsamı
scripts/gelistir-kapisi.sh          # tek komut kapı (aşağıda); --hizli paketi atlar
scripts/ui-olcum.sh                  # arayüz sadelik ölçümü (docs/surum-0.2.1.md §8)
scripts/release.sh                   # dist/MarkaCalismaAlani-<sürüm>.dmg (ad-hoc; katılımcı Gatekeeper uyarısı görür)
scripts/release.sh --sign "Developer ID Application: Ad Soyad (TAKIMID)" --notarize marka   # imzalı + notarize dmg
```

## Tek komut kapı ve bitti tanımı

`scripts/gelistir-kapisi.sh` yedi adımı sırayla koşar; biri KALDI olsa da kalanlar koşar, sonunda her adım tek satır
(`ADIM · GEÇTİ/KALDI · özet`) ve `KAPI: GEÇTİ` (çıkış 0) ya da `KAPI: KALDI (adımlar)` (çıkış 1) yazılır.
Adımlar: test (`scripts/test.sh`) · paket (`scripts/build-app.sh`) · çeviri (`l10n.py check`: eksik/fazla/biçim/çoğul = 0) ·
MAS taraması · erişilebilirlik taraması (bulgu toplamı 0) · sızıntı grep'i · artık süreç denetimi (yeni süreç = KALDI; öldürmez, raporlar).
`--hizli` paketi atlar ve çıktıya `HIZLI KİP (paket atlandı)` yazar; bu kip yalnız ara kontroldür, **bitti sayılmaz**.
Ayrıntı günlükleri `KAPI_GUNLUK` klasörüne (varsayılan geçici klasör) yazılır. Kapının kendisi paylaşılan ağaçta bozuk test
denemesiyle sınanmaz; kırmızı/yeşil kanıtı ayrı bir kopyada üretilir.

**Bitti kapısı** (Dev Camp planı §1.5 ile uyumlu): bir iş yalnız (1) kabul ölçütü sayıyla kanıtlandıysa, (2) `scripts/gelistir-kapisi.sh`
(bayraksız) `KAPI: GEÇTİ` verdiyse, (3) test sayısı önce/sonra raporlandıysa (sayı `scripts/test.sh` çıktısından), (4) UI değiştiyse gerçek pencere
kanıtı varsa (yoksa "gerçek pencere: doğrulanamadı"), (5) gerçek veri alanına ve Keychain'e dokunulmadıysa, açılan süreçler kapatıldıysa biter.

## Kapsam ölçümü (H3-08) ve commit öncesi kanca (H3-11)

`scripts/kapsam.sh` MarkaCore satır kapsamını `swift test --enable-code-coverage` + `llvm-cov report` ile yüzde olarak yazar. Ayrı derleme klasörü kullanır (`.build/kapsam`), ana `.build`e dokunmaz; `scripts/test.sh`'taki CLT rpath ayarını aynen taşır. `llvm-cov` yoksa ya da test koşusu kırmızıysa "doğrulanamadı: <neden>" yazar (çıkış 2). Kapsam **yalnız MarkaCore**'dur: MarkaApp (SwiftUI) testsizdir ve ölçümün DIŞINDADIR; MarkaDogrula da dışarıdadır.

**Taban (2026-10-05, bu makinede, Command Line Tools ile çalıştı):** MarkaCore satır kapsamı **%86,9** (10621 satır, 1388 kaçan; `llvm-cov` TOTAL satırıyla aynı). Kapsamı en düşük 5 dosya:

| Dosya | Satır kapsamı | Kaçan/toplam |
|---|---|---|
| `Model/SkillPacks.swift` | %0,0 | 1/1 |
| `AI/CodexProvider.swift` | %12,8 | 239/274 |
| `AI/CodexAppServer.swift` | %14,8 | 362/425 |
| `AI/AIBasics.swift` | %29,3 | 29/41 |
| `Workspace/FolderAccess.swift` | %50,0 | 5/10 |

Bu tek ölçümdür; başka makinede ya da kod değişince değişir. CI eşiği (taban altına düşünce kırma) bu işte yapılmadı.

**Sızıntı kancası.** `scripts/kancalar-kur.sh` yerel `.git/hooks/pre-commit` kancasını kurar; kanca dosyası depoya girmez (`.git/hooks` izlenmez), her klonda kurucu bir kez çalıştırır. Kanca yalnız staged EKLENEN satırlarda e-posta, kişisel yol (`/Users/<gerçek ad>`) ve `sk-ant-` + ≥ 20 karakter anahtar arar; bulursa commit'i engeller (çıkış 1, `dosya:satır`). Desen tek kaynaktan gelir: `scripts/sizinti-desenleri.sh` (`scripts/gelistir-kapisi.sh` aynı dosyayı kullanır). E-posta deseni `@gmail.com` ve `@icloud.com` ile sınırlıdır (kapıyla aynı); başka alan adlarının gerçek adresleri yakalanmaz. Uydurma `@example.test`, `@ornek` ve `/Users/ornek` benzeri yollar geçer. `scripts/kancalar-kur.sh <hedef-depo>` yalnız o depoya kurar (deneme için geçici depo).

## CI (GitHub Actions) ve "kırmızıda birleştirme yok"

`.github/workflows/ci.yml`: `pull_request` ve `push` (main) tetikler; yalnız `contents: read`; yinelenen koşular `concurrency` ile iptal edilir;
SwiftPM önbelleği (`.build`, `~/Library/Caches/org.swift.swiftpm`) kullanılır. Tek iş adımı `scripts/gelistir-kapisi.sh` (bayraksız, paket dahil).

**Kural: CI kırmızıyken (KAPI: KALDI) birleştirme/yayın yok.** Free planda dal koruması kapalıdır; kural teknik değil, sözleşme gereğidir.
Kırmızı koşu düzeltilmeden `main`'e yeni iş eklenmez.

Runner farkları (çözümleme betik okunarak yapıldı; **canlı koşuyla doğrulanamadı**, commit/push onayı yok):
- Runner etiketi: `macos-latest` (arm64 beklenir). `macos-26` etiketinin varlığı doğrulanamadı; var olduğu görülünce elle değiştirilir.
- `scripts/test.sh`: CLT rpath dalı yalnız `xcode-select -p` Xcode.app **içermiyorsa** çalışır. Runner'larda Xcode seçili olması beklenir, bu durumda düz `swift test` koşar (betik değişmedi). Runner'da CLT seçiliyse ilk dal kullanılır.
- `scripts/build-app.sh` `$HOME/Applications/Workspace AI.app` yazar; runner'da HOME geçici ve koşuya özeldir, gerçek veri alanı yoktur: zararsız.
- Paket ad-hoc imzalıdır; Developer ID/notarization CI'da yoktur ve gizli anahtar kullanılmaz.

Sürüm numarasının tek kaynağı `Sources/MarkaCore/Version.swift`; Info.plist, dmg adı ve yedek manifesti oradan türer,
build numarası git commit sayısıdır (`scripts/version.sh`). README'deki "Beta X.Y.Z" satırı bir testle aynı kaynağa bağlıdır.
Beta katılımcısı için kurulum: [`docs/beta-kurulum.md`](beta-kurulum.md). Elle deneme: [`docs/elle-test-senaryosu.md`](elle-test-senaryosu.md).

Xcode gerekmez; Command Line Tools yeterli. Paket Xcode ile de açılabilir (`Package.swift`).

Geliştirme ve denetim için ortam değişkenleri:
- `MARKA_WORKSPACE=<klasör>`: veri tabanı konumu. Varsayılan `~/Library/Application Support/MarkaCalismaAlani`.
- `MARKA_FOLDERS=<klasör>`: marka klasörleri. Varsayılan `~/Documents/Marka Çalışma Alanı`.
- `MARKA_SNAPSHOT=<klasör>`: 14 ekranı (Bugün; Akış, ayrıntı paneli ve onaylanmış öneri paneli; Yapılacaklar ve paneli; Rapor; onay sayfası; iş kaydı düzenleyicisi; Bilgiler ve AI izinleri; Ayarlar › Genel ve Veri; ilk açılış; kenar çubuğunda yeni marka alanı) açık ve koyu görünümde PNG olarak çizer (28 dosya), sonra uygulamadan çıkar. Tercih yazmaz, Keychain'e dokunmaz; `MARKA_WORKSPACE`/`MARKA_FOLDERS` ile geçici veri alanında çalıştır (`swift run MarkaDogrula demo <klasör>` bekleyen ve onaylanmış öneriler dahil örnek veri kurar; onay sayfasının "Dosyalar" grubu için marka klasörüne elle bir dosya koy).
- Çizim kararlılığı: `scripts/cizim-kararliligi.sh` kurulu uygulamayla geçici örnek veri alanında iki `MARKA_SNAPSHOT` koşusu alır, 56 PNG'yi `cmp` ile karşılaştırır, `KARARLI`/`KARARSIZ` yazar (çıkış 0/1), geçici veriyi siler; farklı çıkanları `.build/cizim-kararliligi/` altına koyar. Kapıya bağlı değildir (ağır). Kararlılık için ekran çizimi kipinde: yerel arama alanı TextField yerine metin, Ayarlar › Veri'de yedek saati yerine yalnız gün. Her iki koşuda veri alanı yolu aynı olmalı (Veri ekranı yolu yazar).
- `MARKA_TERMINAL_PROVA` kaldırıldı: terminal arayüzü 0.3.0'da bırakıldı (tarihsel not: `docs/surum-0.2.1.md`).

Doğrulama aracı:
```sh
swift run MarkaDogrula codex         # gerçek Codex App Server ile uçtan uca test (sentetik marka)
ANTHROPIC_API_KEY=sk-ant-… swift run MarkaDogrula anthropic [--model <kimlik>] [--max-tokens <n>]
                                     # gerçek Claude API ile 6 adım (sentetik iki marka), sonda token/maliyet tablosu
swift run MarkaDogrula demo <klasör> # sentetik örnek çalışma alanı
swift run MarkaDogrula joi <klasör>  # joi-todo verisiyle salt okunur kuru aktarım
```
`anthropic` komutu anahtarı yalnızca `ANTHROPIC_API_KEY` ortam değişkeninden okur (Keychain'e bakmaz); geçici klasörde
sentetik iki markalı çalışma alanı kurar ve sırayla anahtar doğrulama (ücretsiz token sayma), akışlı sohbet, araç döngüsü,
marka yalıtımı, bilgi derleme ve rapor özeti adımlarını `✓/✗`, süre, token ve tahmini maliyetle yazar (çekirdeği sınar;
bu yeteneklerin çoğunun 0.2.1'de arayüzü yok). Varsayılan model en ucuz uygun olan `claude-haiku-4-5-20251001`,
`max_tokens` üst sınırı 4096. Çıkış kodları: 0 geçti · 1 denetim düştü · 2 anahtar yok/argüman hatası · 3 anahtar
doğrulanamadı · 4 API hatası (kalan adımlar atlanır) · 5 marka yalıtımı delindi.
`ANTHROPIC_BASE_URL` verilirse istekler oraya gider (vekil ya da yerel sahte sunucu); o koşu gerçek API'yi sınamaz.
