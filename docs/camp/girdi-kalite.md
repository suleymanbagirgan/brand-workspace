# Dev Camp — Kalite/Altyapı görevleri (3 hafta, yalnız ürün odağı)

## Ölçülen durum (2026-10-05, yalnız okuma)
- Tests/MarkaCoreTests: 30 dosya, 255 `@Test`, 41 `@Suite`; tek test hedefi (Package.swift). docs/gelistirme.md hâlâ "133 test" yazıyor (bayat).
- Piramit: saf mantık + Store (bellek içi `makeStore()`) + AI sahte sağlayıcı (AITests, GizlilikTests, TerminalOturumTests) var. UI testi YOK; MarkaApp hedefinin testi yok.
- `.github/` YOK: CI yok. Depoda 4 commit.
- scripts: test.sh, build-app.sh, mas-tarama.sh, erisilebilirlik-tarama.sh (bilgi aracı, çıkış hep 0), l10n.py, pencere-goruntu.sh (Ekran Kaydı izni ister, CI'da çalışmaz), ui-olcum.sh, version.sh, release.sh.
- Kapsam ölçümü: yok (scripts/docs'ta `coverage` geçmiyor). Kararsız test: docs/performans-olcumu.md "bilerek gevşek süre sınırları" der; öneri geri alma `>`→`>=` geçmişini docs'ta BULAMADIM (görev girdisinde var; kaynağı doğrula).
- UI için SwiftPM yolları: `MARKA_SNAPSHOT` + SnapshotRunner (ImageRenderer, 14 ekran x açık/koyu = 28 PNG; ScrollView boş çıkar, Design.swift:142); pencere yakalama (izin gerekir); ihtiyaç: PNG karşılaştırma betiği.
- Kapı (kalite-kapisi.md) 6 adımı elle çalıştırır; tek komut yok.

## Haftalar
- H1 "Kapıyı otomatikleştir": tek komut kapı, CI, kararsızlık.
- H2 "Gözü otomatikleştir": altın ekran, kapsam, a11y.
- H3 "Sertleştir ve devret": eşikler, kancalar, belge/sürüm tutarlılığı.

## 🔴 Boss
**Q-01 GitHub Actions macOS CI** — Neden: .github yok, kapı yalnız yerelde. Kabul: `.github/workflows/ci.yml` push/PR'da test + build-app + `l10n.py check` + mas-tarama + a11y taraması koşar; kasıtlı kırık testle iş KIRMIZI, düzeltince YEŞİL (iki koşu kanıtı). Gün: 3. Bağ: Q-03. Doğrulama: Actions koşu bağlantıları; Free planda dal koruması yok, bu yüzden kırmızıda birleştirmeyi caydıran kural CLAUDE.md'ye yazılır. Not: CLT yolu runner'da Xcode ile uyuşmayabilir, test.sh dallanması denenmeli.

**Q-02 Altın ekran karşılaştırması** — Neden: UI regresyonunu yakalayan hiçbir şey yok. Kabul: `scripts/ekran-karsilastir.py` (veya Swift) 28 PNG'yi `docs/referans-ekranlar/` ile karşılaştırır; piksel farkı oranı eşiği (öneri %0,5, ayarlanır) aşılırsa çıkış 1 ve fark görüntüsü yazar; kasıtlı 1 renk değişikliği yakalanır, değişmeyen kodda 3 ardışık koşu 0 fark/kararlı. Gün: 5. Bağ: Q-05 (çizim kararlılığı). Doğrulama: yalnız geçici veri alanında MARKA_SNAPSHOT; gerçek veri yok. Risk: yazı tipi/OS farkı CI ile yerel PNG'yi ayırır; referans tek ortamda üretilir.

**Q-03 Kararsız test avcısı** — Kabul: `scripts/kararsiz-avci.sh N` testleri N (varsayılan 10) kez koşar, test başına geçme/kalma sayısını tablo yazar; N=20 koşuda 255 testin tamamı 20/20 ya da kararsızlar adıyla listelenir; bulunan her biri düzeltilir ya da gerekçeli karantinaya alınır. Gün: 2. Bağ: yok. Neden: kapı "kararsızsa 5 kez" diyor ama araç yok; süre sınırlı testler (YogunVeri ≈3,5 sn kurulum) risk.

**Q-04 Kapsam ölçümü ve eşik** — Kabul: `scripts/kapsam.sh` `swift test --enable-code-coverage` + `llvm-cov` ile MarkaCore satır kapsamını yüzde olarak yazar; ilk ölçüm `docs/gelistirme.md`'ye taban olarak işlenir; CI taban altına düşünce kırılır; kapsamı en düşük 5 dosya listelenir. Gün: 3. Bağ: Q-01. Doğrulama: CLT Testing.framework ile çalışıp çalışmadığı denenmeli; çalışmazsa Xcode runner'da. MarkaApp kapsamı dışarıda (UI testsiz) açıkça yazılır.

## 🟡
**Q-05 Çizim kararlılığı** — Kabul: aynı koddan iki ayrı SNAPSHOT koşusunda PNG'ler bayt/eşik içinde aynı (tarih/saat sabitlenir ya da maskelenir). 1 gün. Doğrulama: karşılaştırıcı 0 fark.
**Q-06 Erişilebilirlik taramasına eşik** — Neden: betik her zaman 0 döner. Kabul: `--kati` seçeneği bulgu sayısı tabanı aşınca 1 döner; mevcut bulgular taban dosyasına yazılır; yeni bulgu CI'ı kırar. 2 gün. Bağ: Q-01.
**Q-07 Bozulamaz kural-test haritası** — Kabul: CLAUDE.md'deki her kural için en az 1 test adı eşleyen `docs/kural-test-haritasi.md`; eşlenmemiş kural sayısı 0 (test-muhengisi ilkesi). 2 gün. Doğrulama: betik kural sayısı = harita satırı.
**Q-08 Yeni mantık = yeni test denetimi** — Kabul: Sources/MarkaCore'da değişen dosyanın karşılığı Tests'te değişmediyse uyarı veren betik; 3 örnek değişiklikte doğru uyarı. 2 gün. Bağ: Q-04.
**Q-09 Sürüm ve belge tutarlılığı** — Kabul: Version.swift = README "Beta X.Y.Z" = Info.plist = docs test sayısı; `gelistir-kapisi` içinde; bugünkü "133" bayatlığı yakalanır sonra düzeltilir. 1 gün.
**Q-10 UI duman testi** — Kabul: derlenmiş uygulama MARKA_SNAPSHOT ile 28 PNG üretiyor, hepsi boş değil (boyut > eşik), süre ve çıkış kodu 0; artık süreç 0. 2 gün. Bağ: Q-02.

## 🟢
- Q-11 `scripts/gelistir-kapisi.sh`: kalite-kapisi.md'deki 6 adım tek komutta, GEÇTİ/KALDI, çıkış kodu; 0,5 gün.
- Q-12 Test adı Türkçe denetimi: `@Test func` adlarının ASCII Türkçe fiil/cümle kuralı (İngilizce kalıp listesi) ihlali 0; 0,5 gün.
- Q-13 Belge bağ denetimi: docs/*.md içi göreli bağlarda kırık 0; 0,5 gün.
- Q-14 Commit öncesi sızıntı kancası: kalite-kapisi 6. adımın grep'i `pre-commit` olarak; kasıtlı e-posta ile engeller; 0,5 gün (kanca .git/hooks'ta, depoya `scripts/kancalar-kur.sh`).
- Q-15 Artık süreç denetimi `pgrep` betiği, koşu sonunda 0 yabancı süreç; 0,25 gün.
- Q-16 `docs/gelistirme.md` test sayısı otomatik: 255 gerçek sayıyla eşleşir; 0,25 gün.
- Q-17 Yasak kalıp taraması (`Process(` vb.) testlerde de: mas-tarama çıktısı CI günlüğünde özetlenir; 0,25 gün.
- Q-18 Kalite panosu: tek sayfa `docs/kalite-durumu.md` (test sayısı, kapsam, a11y bulgu, kararsız sayısı) betikle üretilir; 1 gün. Bağ: Q-03/04/06.
- Q-19 l10n kapı adımı: `l10n.py check` çıktısı eksik/fazla/biçim/çoğul = 0 olarak CI'da; 0,25 gün.

## Bitti tanımı (DoD)
Görev biter, yalnız şu hepsi doğruysa: (1) kabul ölçütü sayıyla kanıtlandı, çıktı kopyalandı; (2) `gelistir-kapisi.sh` (yoksa kalite-kapisi 6 adım) GEÇTİ; (3) yeni betik için hem geçen hem kasıtlı kırılan koşu gösterildi; (4) sınırlar belgede dürüstçe yazıldı (yapmadığını vaat etme); (5) test sayısı önce/sonra raporlandı; (6) gerçek veri alanı ve Keychain'e dokunulmadı; (7) docs/gelistirme.md güncel. Doğrulanamayan (ekran izni, runner) ayrı "doğrulanamadı" satırı.

## Öneri sırası
H1: Q-11, Q-03, Q-01, Q-19, Q-15. H2: Q-05, Q-02, Q-04, Q-10, Q-06. H3: Q-07, Q-08, Q-09, Q-12–14, Q-16–18. Toplam yaklaşık 28 gün kaba tahmin; paralel iki kişiyle 3 hafta sığar, tek kişiyle Q-08/Q-10/Q-18 kayabilir.
