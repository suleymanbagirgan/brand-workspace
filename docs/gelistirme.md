# Geliştirme

Derleme, test, ekran çizimi ve canlı doğrulama araçları. Depo kuralları: [CLAUDE.md](../CLAUDE.md).

```sh
scripts/build-app.sh                 # dist/Marka Çalışma Alanı.app (ad-hoc imzalı)
open "dist/Marka Çalışma Alanı.app"
scripts/test.sh                      # 133 test (Swift Testing)
python3 scripts/l10n.py check        # TR/EN çeviri ve İngilizce çoğul kapsamı
scripts/ui-olcum.sh                  # arayüz sadelik ölçümü (docs/surum-0.2.1.md §8)
scripts/release.sh                   # dist/MarkaCalismaAlani-<sürüm>.dmg (ad-hoc; katılımcı Gatekeeper uyarısı görür)
scripts/release.sh --sign "Developer ID Application: Ad Soyad (TAKIMID)" --notarize marka   # imzalı + notarize dmg
```

Sürüm numarasının tek kaynağı `Sources/MarkaCore/Version.swift`; Info.plist, dmg adı ve yedek manifesti oradan türer,
build numarası git commit sayısıdır (`scripts/version.sh`). README'deki "Beta X.Y.Z" satırı bir testle aynı kaynağa bağlıdır.
Beta katılımcısı için kurulum: [`docs/beta-kurulum.md`](beta-kurulum.md). Elle deneme: [`docs/elle-test-senaryosu.md`](elle-test-senaryosu.md).

Xcode gerekmez; Command Line Tools yeterli. Paket Xcode ile de açılabilir (`Package.swift`).

Geliştirme ve denetim için ortam değişkenleri:
- `MARKA_WORKSPACE=<klasör>`: veri tabanı konumu. Varsayılan `~/Library/Application Support/MarkaCalismaAlani`.
- `MARKA_FOLDERS=<klasör>`: marka klasörleri. Varsayılan `~/Documents/Marka Çalışma Alanı`.
- `MARKA_SNAPSHOT=<klasör>`: 14 ekranı (Bugün; Akış, ayrıntı paneli ve onaylanmış öneri paneli; Yapılacaklar ve paneli; Rapor; onay sayfası; iş kaydı düzenleyicisi; Bilgiler ve AI izinleri; Ayarlar › Genel ve Veri; ilk açılış; kenar çubuğunda yeni marka alanı) açık ve koyu görünümde PNG olarak çizer (28 dosya), sonra uygulamadan çıkar. Tercih yazmaz, Keychain'e dokunmaz; `MARKA_WORKSPACE`/`MARKA_FOLDERS` ile geçici veri alanında çalıştır (`swift run MarkaDogrula demo <klasör>` bekleyen ve onaylanmış öneriler dahil örnek veri kurar; onay sayfasının "Dosyalar" grubu için marka klasörüne elle bir dosya koy).
- `MARKA_TERMINAL_PROVA=1` (`MARKA_SNAPSHOT` ile birlikte): çizimden sonra gerçek `DetailView` ekran dışı bir pencerede sürülür ve terminal oturumunun yaşam döngüsü gerçek kabukla ölçülür (12 denetim, `TERMINAL PROVA: ✓/✗` satırları): gizleme, yana alma, başka markaya ve Bugün'e geçişte aynı süreç ve aynı görünüm; kabuk değişkeninin korunması (kabuk marka klasörüne yazar); yalıtım değişince oturumun sürmesi; arşivlemede yalnız o markanın, kapanışta tüm kabukların bitmesi. Kullanıcının zsh başlangıç dosyaları çalışmasın diye `SHELL=/bin/sh` ile çalıştır. Tıklama değil model durumu değiştirilir.

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
