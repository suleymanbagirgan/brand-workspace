# Beta 0.2.0 — çalışma planı

Tarih: 2026-09-18. Önceki sürüm: 0.1.0 (2026-09-17, `8559a95`).

## Hedef
0.1.0 bu Mac'te çalışıyor ama **başka bir danışmanın Mac'ine verilecek durumda değil.** Engeller:
Codex'in marka yalıtımı okumada delik, Claude API hiç canlı denenmedi, arayüz elle tıklanmadı, paket kurulum talimatsız,
beta katılımcısından hata bilgisi toplamanın yolu yok.

**0.2.0'ın tek sorusu:** 5 danışmanlı betaya (`docs/degerlendirme-plani.md`) bu paket verilebilir mi?

## İşler

| # | İş | Kabul ölçütü (ölçülebilir) | Sahip ajan |
|---|---|---|---|
| İ1 | **Marka okuma yalıtımı** (Codex + terminal) | Codex oturumu ve marka terminali, başka markanın klasörünü **okuyamaz**; `MarkaDogrula codex` bunu gerçek Codex ile kanıtlar. Yazma yalnızca marka klasörü + gerekli sistem yolları. Mevcut Codex akışı (akış, araç, devam ettirme) bozulmaz | swift-gelistirici → marka-yalitim-muhafizi |
| İ2 | **Claude API canlı doğrulama aracı** | `MarkaDogrula anthropic` anahtarı yalnızca `ANTHROPIC_API_KEY` ortam değişkeninden alır; sohbet akışı, araç döngüsü, bilgi derleme (B5) ve rapor özeti (D4) sentetik markayla gerçek API'ye karşı adım adım geçer/düşer. Anahtar yoksa net mesajla çıkar | ai-saglayici-uzmani |
| İ3 | **Elle kullanım turu ve düzeltmeler** | `docs/elle-test-senaryosu.md` yazılı; kurucunun gerçek kullanımından ve turdan çıkan her kusur düzeltilir ya da "Bilinen sınırlar"a yazılır | arayuz-denetci + swift-gelistirici |
| İ4 | **Beta paketi** | Sürüm 0.2.0 (tek kaynak); `scripts/release.sh` → `.dmg`; Developer ID verilirse imza + notarization, verilmezse ad-hoc ve katılımcı için Gatekeeper talimatı (`docs/beta-kurulum.md`) | surum-muhendisi |
| İ5 | **İçeriksiz tanı raporu** | Ayarlar'da "Tanı bilgisini kopyala": sürüm, macOS, son hatalar (tür + yer), beta ölçümleri. Marka adı, kaynak metni, dosya yolu içermez — testle kanıtlanır | swift-gelistirici → veri-gizliligi-denetcisi |
| İ6 | **İngilizce çoğullar** | Arayüzdeki tüm sayaçlar `stringsdict` ile; "1 … s" kalmaz; `l10n.py check` çoğul kapsamını da denetler | swift-gelistirici |

Kurucunun hesabına bağlı olanlar (kod hazırlanır, kurucu verince çalışır):
- Anthropic API anahtarı → İ2'nin canlı koşusu.
- Apple Developer ID → İ4'ün imzalı/notarize dalı.

## İ3 denetim bulguları (2026-09-18) ve karar
Kaynak: arayüz denetimi (commit `f689db7`), senaryo `docs/elle-test-senaryosu.md`.

**0.2.0'da düzeltilir (İ3-D):**
- D1 Deneme kipi (`MARKA_WORKSPACE`) gerçek tercihleri ve Keychain kaydını paylaşıyor — deneme kopyası gerçek anahtarı silebilir. Ayrı `UserDefaults` suite + ayrı Keychain hesabı.
- D2 Masa'da ilk gün çıkmazı: yalnızca kaynak varken "sıradaki adım"da eylem yok; "Müşteri talebi" kaynağı açık talep kaydı oluşturmuyor (beta Gün 1 koşulu).
- D3 Görev → çalışma kaydı yolu yalnızca sağ tıkta; sayaç durunca/görev bitince kayıt önerilmiyor. Rapordaki "girmeyen işler" satırından doğrudan kayıt oluşturulamıyor.
- D4 Yıkıcı eylemler onaysız (görev/kişi/kayıt silme, geri çekme, plan silme, marka arşivleme); arşivden çıkarma arayüzü yok.
- D5 Rapor "AI ile özet öner" hatası yanlış sebebi söylüyor (anahtar eksikken "izin yok").
- D6 Codex açıklamaları Marka ekranı ile Ayarlar arasında çelişkili (İ1 ile birlikte).
- D7 İlk açılışta içe aktarımdan "Vazgeç" ilk açılışı bitmiş sayıyor.
- D8 Kontrast: açık görünüm vurgusu ~4.0:1, koyu görünüm dolgulu düğmede beyaz yazı ~2.5:1 (AA altı).
- D9 Veri okuma hatasında ekranlar boş kalıyor (hata durumu yok).

**Durum (2026-09-18):** D1–D5 ve D7–D9 düzeltildi; mantık kanıtları `TercihYalitimTests` (D1), `IlkGunTests` (D2, D3), `arsivdenCikarilanMarkaListeyeDonerVeDenetimBirakir` (D4), `OzetSaglayiciTests` (D5), `KontrastTests` (D8); D7 ve D9 yalnızca arayüz akışı (testsiz, derlendi). Arayüz değişiklikleri tıklanarak denenmedi (elle test senaryosu güncellendi). D6 İ1'de düzeltildi: Marka ekranı ve Ayarlar'daki Codex metinleri yalıtımın gerçeğine göre, README "Bilinen sınırlar" ile tutarlı.

**Bilinen sınıra yazılır / 0.3.0 adayı:** snapshot aracının pencere çizimlerinde liste ve koyu bölmeleri boş çizmesi (araç sorunu), terminal "Klasörden içe al" ve kabuk kapanma mesajı, "Bölümde aç"ın kaydı seçmemesi, küçük metin/adlandırma düzeltmeleri (bunlar D-işleriyle aynı dosyaya dokunuluyorsa birlikte yapılır).

## Kapsam dışı (0.2.0)
PRD 6.2 ve 5 geçerli: Sparkle otomatik güncelleme, Paddle ödeme, App Store, otomatik e-posta, bulut eşitleme, ekip yetkisi.
Tekrar tartışılmaz; 0.3.0 ancak beta sonucu (karar ölçütü) ile açılır.

## Tasarım kararı — İ1
Ölçüm (2026-09-18): macOS'ta iç içe `sandbox-exec` çalışmıyor. Codex'in kendi seatbelt'i dıştan sarılmış süreçte uygulanamaz.
Yol: Codex App Server'ı **bizim** seatbelt profilimizle başlat, Codex'in iç sandbox'ını kapat (`danger-full-access`); okuma
yasağı (diğer marka klasörleri + uygulama veri alanı) ve yazma sınırı (marka klasörü, Codex ev dizini, geçici klasör) tek
profilde. Bedeli: marka klasörü dışına yazma artık onayla değil **kesin redle** kapanır; komutların ağ erişimi app-server'ınkinden
ayrılamaz. Bu bedeller README "Bilinen sınırlar"a yazılır. Profil ölçümle doğrulanamazsa Codex varsayılan kapalı kalır (bugünkü durum).

**Durum (2026-09-18):** uygulandı. Kapsam başına ayrı yalıtımlı Codex süreci (ayrı `CODEX_HOME`: oturum kayıtları markalar
arasında paylaşılmaz), terminal de aynı profil üreticisiyle yalıtıldı (varsayılan açık). Kanıt: `IsolationTests` (gerçek
`sandbox-exec` dahil) ve `swift run MarkaDogrula codex` (gerçek Codex; `command/exec` ve model turu). "Tüm markalar" Codex
oturumunda hiçbir marka klasörü açılmaz; veri yalnızca izinli markalarla sınırlı araçlardan gelir. Codex izni varsayılanı kapalı kalır.

**Bağımsız denetim düzeltmeleri (2026-09-18, `5c4fea2` sonrası):** ölçümlü kaçışlar kapatıldı — LaunchServices/`open`+AppleEvents+Kısayollar ile
profil dışı süreç başlatma, sembolik/klasör bağı izleyerek başka markayı içe aktarma (`FileImportGuard`, `O_NOFOLLOW`, kanonik
klasör hapsi), ortak kabuk başlangıç dosyalarıyla köprü (terminal profilinde yazma koruması), yalıtımsız denetim sürecinin
kurcalanmış `codex` ikilisini çalıştırması (denetim süreci de okuma yasaklı profille sarıldı), yerel Unix soketi (tmux) köprüsü,
güvenlik tercihinin `defaults` ile kapatılması (tercih DB'ye taşındı), "_Tüm Markalar" ad çakışması, Codex'in kabuk geçmişini
okuması. Kanıt: genişletilmiş `IsolationTests` + ÖNCE/SONRA `sandbox-exec` ölçümleri + `swift run MarkaDogrula codex` (canlı, geçti).
Kapatılamayanlar README "Bilinen sınırlar"da: varlık sızıntısı (`EPERM`/`ENOENT`), pano, ağ erişimi, yalıtım dışında kurulmuş sert bağ.

## Yürütme sırası
1. İ1, İ2, İ4, İ5+İ6 paralel (ayrı çalışma ağaçları), her biri kendi testleriyle.
2. Birleştirme → `scripts/test.sh` + `build-app.sh` + `l10n.py check`.
3. Denetim: marka-yalitim-muhafizi (İ1), veri-gizliligi-denetcisi (İ5, İ2).
4. İ3 elle tur → düzeltmeler → 0.2.0 etiketi.

## Durum (2026-09-18 gece)
| İş | Durum | Kanıt |
|---|---|---|
| İ1 yalıtım | Bitti + bağımsız denetim + kaçış düzeltmeleri | `5c4fea2`, `1c4e75c`…`2573e8e`; LaunchServices ve sembolik bağ kaçışı ana daldaki profille yeniden ölçüldü, kapalı |
| İ2 Claude doğrulama aracı | Kod bitti; **canlı koşu anahtar bekliyor** | `9115594`, `1ad8566` |
| İ3 elle tur | Senaryo + D1–D9 bitti; **kurucunun elle turu bekliyor** | `docs/elle-test-senaryosu.md` |
| İ4 paket | Bitti (ad-hoc); imzalı dal Developer ID bekliyor | `da4f281` |
| İ5 tanı / İ6 çoğul | Bitti + gizlilik denetimi düzeltmeleri | `c469d68`, `631cddf`, `1ad8566` |
| Ek: terminal yan panel | Bitti, ekranda görülmedi | `598cfcf` |
| İ7 terminal öneri köprüsü (`oneriler/*.json` → onaylı öneri) + İ3 bulgusu 16 ("Klasörden içe al") | Bitti (testli, gerçek `sandbox-exec` ile uçtan uca); gerçek Claude Code oturumu ve arayüz tıklanarak **denenmedi** | `TerminalOneriTests`, elle test 6.9–6.11 |

0.2.0 etiketi: kurucunun elle turundaki engelleyici bulgular kapanınca.
