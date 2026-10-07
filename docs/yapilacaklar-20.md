# Yapılacaklar (20) — 2026-10-04

Durum işaretleri: [x] bitti ve kanıtlı · [~] kısmen · [ ] bekliyor · [!] kullanıcı kararı/ekran/anahtar gerekir.

## Güvenlik ve doğrulama
1. [x] Gerçek veri alanının **kopyasında** migration v5–v8 denendi: bütünlük ok, yabancı anahtar ihlali 0, satır sayıları aynı (`MarkaDogrula gocu`). Not: bu alan demo veri
2. [!] Stüdyo ekranlarını gerçek pencerede doğrula (menü, bağlantı, sayfa sayfa) — ekran açık olmalı
3. [!] Canlı yapay zekâ yanıtı: rol istemi + `calisan_oner` — API anahtarı gerekir
4. [!] Elle deneme: menü çubuğu popover, çentik adası, Pano sürükle-bırak, VoiceOver
5. [ ] Kenar çubuğunda seçili satırın içerikle uyuşmama anomalisini araştır

## Ürün
6. [~] Boş sohbette "Ekibe çalışan öner" ve "Bu hafta ne yapmalıyız?" örnek istemleri (Stüdyo) — kod ve çeviri tamam, ekranda görülmedi
7. [ ] Çalışan başına aylık kullanım (`usageEntry`) ekip satırında
8. [ ] Yetenek: dosya olarak SKILL.md kaydet (panoya kopyalamaya ek)
9. [ ] Hizmet/yetenek/üye silme ve düzenlemede ⌘Z ile geri alma
10. [ ] Hindsight tarzı **gözlem** önerisi: yapay zekâ öğrendiğini kanıtla yazar, onayla "Biz kimiz"e girer
11. [ ] Bağlam bütçesi: uzun listeleri kırp, kırpılanı belirt
12. [ ] Yanıt uzunluğu ayarı (kısa/normal) Ayarlar'da
13. [ ] Uzun belge için içindekiler ağacı (PageIndex fikri)
14. [ ] Eylem kaydı (Action Registry) ilk dilim: 3 eylem

## Temizlik ve altyapı
15. [ ] Ölü terminal kodu ve SwiftTerm bağımlılığını kaldır
16. [x] Sürüm 0.4.0 (`Version.swift`) + README ve sürüm notu
17. [ ] Sandbox/entitlements taslağı (`docs/` + dosya), App Store uyum listesi
18. [x] Migration öncesi otomatik yedek (`Migration-Yedekleri/`, en yeni 5; yedek alınamazsa açılış durur) — testli
19. [x] Aynı veri alanını ikinci süreç açamaz (`flock`, anlaşılır mesaj) — testli
20. [!] Commit ve GitHub'a yükleme — kullanıcı onayı


## Otomatik geliştirme turu 1 (2026-10-04, `/gelistir`)
- [x] A. Bağlam bütçesi: tek sınır (`ContextLimits`), kırpılan listeye "… ve N öğe daha var" notu, 3 yeni test (173)
- [x] C. Bugün/Özet sadeleşme: kahraman kart kalktı (tek satır tanım), arama kutusu başlıkla hizalı, onay kutucuğu kalktı (liste üstte), kalan 3 kutucuk `TileGrid(columns: 3)`
- [x] B. Ölü terminal kodu: `TerminalPanel.swift` (332 satır), AppModel terminal alanları, `terminalProva`, SwiftTerm bağımlılığı (+ swift-argument-parser) silindi; `grep SwiftTerm` = 0
- [x] Yanıltıcı "Terminal › Marka yalıtımı" ayarı kaldırıldı (hiçbir şeyi etkilemiyordu; "yapmadığımızı vaat etmeyiz")
- [ ] Silinebilir: `MarkaCore/Terminal/TerminalSessions.swift` + `TerminalOturumTests` (5 test); yalnız testler kullanıyor, kullanıcı onayı bekleniyor

## Otomatik geliştirme turu 2 (2026-10-04): gerçek pencere doğrulaması açıldı
Ekran açıktı; `scripts/pencere-goruntu.sh` ile gerçek pencere yakalandı. Çizim aracının göstermediği üç bulgu:
- [x] Özet'te asistan paneli açıkken kutucuklar 3+1 diziliyordu → `TileGrid` dört kutuda 3 sütunu atlayıp 2+2 dizer (gerçek pencerede doğrulandı)
- [x] Kenar çubuğunda seçili markanın onay sayısı mavi üstünde indigo olduğu için görünmüyordu → pencere etkinken beyaz, etkin değilken vurgu rengi (gerçek pencerede doğrulandı)
- [x] Bugün: gerçek `TextField` arama kutusu başlıkla hizalı, onay listesi üstte (üç yakalamada doğrulandı)
- [ ] **Aralıklı:** Bugün bir kez en altta kaydırılmış açıldı (başlık araç çubuğunun altında kaldı); 5 yakalamanın 4'ünde yok. Kaynağı bulunamadı, yeniden üretilemedi. İzlenecek.
- Gerçek pencere artık mümkün: yapılacaklar #2, #4, #5 ve tasarım maddeleri (klavye gezintisi, odak halkası, kontrast, asistan paneli malzemesi) bir sonraki turda ele alınabilir.

## Örnek marka (2026-10-04): ilk 5 dakikada yapay zekâsız değer
- [x] `Store.createSampleBrand()` (`MarkaCore/Sample/SampleWorkspace.swift`): tek uydurma "Örnek Marka", tek işlem, aktör `.system`, her yazma denetimli, `setting(sampleBrandId)` ile işaretli, idempotent, AI izni yok; arşivlenmişse tekrar çağrıda arşivden çıkar. 13 test (`OrnekMarkaTests`), 218 → 231
- [x] Karşılama: ikincil "Örnek markayla gez"; Özet üstünde yalnız örnek markada bilgi şeridi (Rapora git · Arşivle…); asistan "Yapay zekâyı bağla" durumunda "Bağlamadan da kullanabilirsin…" satırı. `MarkaDogrula ornek <alan>` ve çizim ekranları 30–32
- [!] Gerçek pencerede doğrulanmadı (ekran kilitliydi; yalnız `MARKA_SNAPSHOT` çizimi). Düğmelerin tıklanması, arşiv onayı ve Özet'e geçiş elle denenmeli
- [ ] Bulgu (eski): Özet'teki "Bu hafta biten" kutucuğu iş kaydı bağlı biten görevleri saymıyor (Akış'ta yalnız iş kaydı satırı olarak görünüyorlar); örnek markada 3 biten görev varken 0 gösteriyor
- [ ] Örnek veri yalnız Türkçe (İngilizce arayüzde de Türkçe içerik)

## Uzun oturum (2026-10-04, gece): ekip otomatik çalıştı — özet
Dalga 1 (denetimler) → 2 (düzeltmeler) → 3 (Action Registry, örnek marka) → 4 (sandbox S1–S3, performans) → 5 (erişilebilirlik, Apple modeli denemesi). Testler 173 → **255**, migration v9 (yalnız indeks), çeviri 1013/1013.
Sabaha açık (ekran gerekir): gerçek pencerede doğrulanacaklar → `docs/gercek-pencere-denetimi.md` "Düzeltme durumu", `docs/erisilebilirlik.md` 12 maddelik liste; aralıklı Bugün kaydırma hatası; `OpeningFocus` (açılış odağı) etkisi.
Kullanıcı kararı: `docs/pazar/satis-plani.md` §7.
