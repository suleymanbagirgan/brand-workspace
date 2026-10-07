# Workspace AI Dev CAMP PLAN

**Kuluçka kampı · 2026-10-05 (Pzt) → 2026-10-23 (Cum) · 15 iş günü · 3 paralel hat**
Hazırlayan: ürün yöneticisi (ekibin altı girdi raporundan birleştirildi). Tarih: 2026-10-05.

> **Kuluçka: yalnız ürün.** Bu üç haftada satış, yayın, mağaza gönderimi, ödeme, imza kimliği ve pazarlama yapılmaz. App Sandbox için yalnız mimari hazırlık serbesttir; o da bu kampta havuzdadır (bkz. §5).

**Amaç.** Kullanıcının verisini kaybettiren her yolu kapatmak, uygulamanın kendini ölçebilmesini sağlamak (tek komut kapı, kararsız test avcısı, kapsam tabanı, yalıtım özellik testi) ve iki katmanı yeniden kurmak: yapay zekâ sağlayıcı katmanı ve tek tasarım dili. Her görevin sonu sayıyla kanıtlanır. Kanıtlanamayan iş "doğrulanamadı" etiketiyle kapanır, "bitti" sayılmaz.

**Bu plan neyi vaat etmez**
- Satış, beta, yayın, App Store gönderimi, fiyat, ödeme yok.
- "Uygulama hazır" ya da "güvenli" gibi genel iddia yok. Yalnız adı konmuş testlerin geçtiği iddia edilir.
- Canlı Claude yanıtı denenmedi. Anahtar gelmeden canlı kısımlar "yapılmadı" yazılır.
- **Gün tahminlerinin hiçbiri ölçülmedi.** Girdi raporlarındaki tahminler kod okumasından çıkarıldı. Kamp sırasında gerçek süreler panoya yazılır ve plan G5 ile G10 kapılarında düzeltilir.
- "Veri bu Mac'te kalır" gibi mutlak bir cümle kurulmaz. Doğrusu şu: veriler yerel saklanır. Yapay zekâ açık olan markanın içeriği yalnız o marka için izin verilmiş sağlayıcıya gider (`bilinen-sinirlar.md` §3).

---

## Kapasite özeti (önce bunu oku)

| Kalem | Hat A | Hat B | Hat C | Toplam |
|---|---:|---:|---:|---:|
| Toplam hat-günü (15 gün × 3 hat) | 15 | 15 | 15 | **45** |
| Ritüel: haftalık demo + karar kapısı (Cuma ½ gün × 3) | 1,5 | 1,5 | 1,5 | 4,5 |
| **Planlanan görev** | **13,5** | **13,5** | **13,5** | **40,5** |
| Tampon | 0 | 0 | 0 | 0 (kesme kuralı §7 tamponun yerini tutar) |

| Seviye | Görev sayısı | Puan | Hat-günü |
|---|---:|---:|---:|
| 🔴 boss (8 puan) | 6 | 48 | 18,5 |
| 🟡 orta (3 puan) | 13 | 39 | 15,75 |
| 🟢 basit (1 puan) | 13 | 13 | 6,25 |
| **Toplam** | **32** | **100** | **40,5** |

Girdilerdeki işin toplamı yaklaşık 200 kişi-gün (K≈55, T≈62, A≈31, Q≈28, G≈27; U maddeleri çoğunlukla bunlarla örtüşüyor). Kamp bunun yaklaşık beşte birini alıyor. Kalanı gerekçesiyle **Kamp sonrası havuzu**na (§5) gitti. 45 hat-günü aşılmaz: kamp ortasında eklenen her iş, plandaki bir işi çıkararak girer.

---

## 1. Kamp tüzüğü

### 1.1 Kapsam

| Kapsam içi | Kapsam dışı (kurucu: "sonra") |
|---|---|
| Veri kaybı yollarını kapatmak (U-01…U-08) | Satış, fiyat, ödeme, StoreKit |
| Kullanıcı gözüyle bulunan engelleyici ve önemli sorunlar | App Store gönderimi, ekran görüntüleri, inceleme |
| Ölçüm ve kalite altyapısı (kapı, kararsız test, kapsam, CI dosyası) | Developer ID imzası, notarization, dağıtım |
| Yapay zekâ sağlayıcı katmanı, sahte sağlayıcıyla kırmızı takım | Pazarlama, büyüme, pazar araştırması |
| Tasarım dili (token) ve onay ritüeli | Gerçek veri alanında deneme |
| Sandbox mimari hazırlığı (serbest; bu kampta havuzda) | Push, GitHub ayarları, depo görünürlüğü (kullanıcı kararı) |

### 1.2 Hatlar

| Hat | Alan | Ana dosya bölgesi (çakışmayı önlemek için) |
|---|---|---|
| **A** | çekirdek / AI / güvence kodu | `Sources/MarkaCore/**` (Store, Backup, AI), `Sources/MarkaDogrula`, **migration'lar** |
| **B** | arayüz / tasarım / kullanıcı gözü | `Sources/MarkaApp/**`, `Resources/en.lproj` |
| **C** | kalite / altyapı / belgeler | `scripts/**`, `Tests/**` (yeni test dosyaları), `.github/`, `docs/**`; küçük kullanıcı gözü düzeltmeleri |

Bir hat başka hattın bölgesine dokunacaksa bunu o günün akış tablosunda yazar (ör. H1-03, `Store+Tasks` ile `DetailPanel` dosyalarına birlikte dokunur). Aynı gün aynı dosyaya iki hat dokunmaz.

### 1.3 Ekip ve roller (13 ajan)

| Ajan | Kamptaki rolü | Hat | Ölçtüğü şey |
|---|---|---|---|
| `urun-yoneticisi` | Günlük maddeyi teyit eder, kabul ölçütünü korur, kesme kuralını uygular, karar kapısını hazırlar | tümü | planlanan ve gerçek gün, puan |
| `tasarim-lideri` | H2-04 ve H3-05 şartnameleri, token listesi | B | token sayıları, grep |
| `arayuz-gelistirici` | SwiftUI uygulaması | B (C'nin küçük UI işleri) | kabul ölçütü, l10n |
| `arayuz-denetci` | Açık ve koyu çizim ile gerçek pencere denetimi | B | kanıtlı ekran sayısı |
| `swift-gelistirici` | Çekirdek, yedek, sağlayıcı katmanı; **migration numarasının tek sahibi** | A | test, MAS derlemesi |
| `test-muhendisi` | Önce kırmızı test; yalıtım özellik testi, kapsam | C (A ve B'ye test) | test sayısı, kapsam % |
| `ai-saglayici-uzmani` | AIProvider, kırmızı takım, altın set, hata türleri | A (H3-04'te B) | senaryo geçme oranı |
| `marka-yalitim-muhafizi` | G-01 ve H3-01 denetimi; kural 1 | C/A | sızıntı sayısı = 0 |
| `veri-gizliligi-denetcisi` | H1-01, H1-10, H3-11 denetimi; kural 6 | A/C | içerik taşıyan günlük = 0 |
| `kalite-kapisi` | Her görevin mekanik kapısı (`gelistir-kapisi.sh` hazır olunca o) | tümü | GEÇTİ / KALDI |
| `surum-muhendisi` | Derleme sırası ve worktree düzeni, `Version.swift` ve belge sayı tutarlılığı; **paket yayını yok** | C | derleme çakışması = 0 |
| `pazar-arastirmacisi` | **DONDURULDU** (kamp boyunca çağrılmaz) | — | — |
| `buyume-stratejisti` | **DONDURULDU** | — | — |

### 1.4 Günlük ritim (`/gelistir` turu)

| Saat dilimi | Ne olur |
|---|---|
| Açılış | `urun-yoneticisi` günün maddesini akış tablosundan alır. Alt ajan görevine **yasakları kopyalar**: gerçek veri alanı yok, `open` yok, commit yok, geçici `MARKA_WORKSPACE`/`MARKA_FOLDERS` zorunlu, Keychain taranmaz. |
| Çalışma | Hat kendi bölgesinde çalışır. Önce test yazılır (kırmızı), sonra kod. |
| Derleme dilimi | Derleme sırası kuralına göre (§1.8). |
| Denetim | İlgili muhafız ya da denetçi. UI işinde `arayuz-denetci`. |
| Kapanış | `kalite-kapisi`, ardından kamp panosu satırı: görev, gerçek süre, test sayısı önce ve sonra. |

**Cuma (G5, G10, G15): demo ve KARAR KAPISI.** Her hat yarım gün ayırır. Demo gerçek pencereyle yapılır. Ekran kilitliyse `MARKA_SNAPSHOT` çizimi kullanılır ve "gerçek pencere doğrulanamadı" etiketi konur. Kurucuya sunulanlar: pano metrikleri, bitenler (kanıtlı), kayanlar, **kesme önerisi**, bekleyen kullanıcı kararları (§6). Commit ancak kurucu kapıda onay verirse yapılır.

### 1.5 Bitti tanımı (Q girdisinden, tüm görevler için)

Bir görev yalnız şu maddelerin **hepsi** doğruysa biter:
1. Kabul ölçütü sayıyla kanıtlandı ve komut çıktısı rapora kopyalandı.
2. `scripts/test.sh` + `scripts/build-app.sh` + `python3 scripts/l10n.py check` temiz. H1-11 bitince bunların yerine tek komut `scripts/gelistir-kapisi.sh` çalışır.
3. `scripts/mas-tarama.sh` temiz. `scripts/erisilebilirlik-tarama.sh` çıktısındaki bulgu sayısı önceki sayıdan fazla değil.
4. UI değiştiyse gerçek pencere kanıtı alındı (açık ve koyu). Alınamadıysa satırda **"gerçek pencere: doğrulanamadı"** yazar ve görev 🟡 puanının yarısını alır.
5. Test sayısı önce ve sonra raporlandı. Yeni mantık yeni test olmadan kapanmaz.
6. Gerçek veri alanına ve Keychain'e dokunulmadı. Açılan süreçler kapatıldı.
7. Sınırlar belgeye dürüstçe yazıldı (`bilinen-sinirlar.md`). Yapılmayan iş vaat edilmedi.

### 1.6 Bozulamaz 7 kural (CLAUDE.md ile aynı)

| # | Kural | Kampta en çok dokunan görevler |
|---|---|---|
| 1 | Marka yalıtımı: her okuma ve yazma `brandId` ile | H2-06, H3-01, H1-01 |
| 2 | Kaynak değişmez, yalnız arşivlenir | H1-05, H1-01 |
| 3 | AI veri değiştirmez, öneri üretir, onay ister, geri alınabilir | H3-05, H3-01, H2-01, H2-02 |
| 4 | Rapor maddesi dayanaksız olamaz | H2-03 |
| 5 | Her yazma denetim olayı bırakır | H1-03, H2-06 |
| 6 | İçerik yalnız izin verilen sağlayıcıya gider; günlükler içerik taşımaz | H3-03, H3-04, H3-11 |
| 7 | Yapmadığımızı vaat etmeyiz | H1-10, H3-09, tüm "doğrulanamadı" etiketleri |

### 1.7 Commit politikası

- Commit ve push **yalnız kurucunun açık onayıyla** yapılır. Onay için doğal an Cuma karar kapısıdır.
- Commit mesajı Türkçe olur ve yalnız `main` dalına gider. Yerel `master` ve `yerel-tam-gecmis-*` asla push edilmez.
- Depo herkese açıktır: gerçek müşteri ya da kişi adı, kişisel yol ve e-posta yazılmaz. Örneklerde Deneme Yangın, Kuzey Lojistik ve Örnek Kafe Zinciri kullanılır.
- Onay yoksa iş kaybolmasın diye her Cuma `git diff` yamaları depo dışındaki geçici klasöre alınır. Bu bir güvenlik ağıdır, commit yerine geçmez.

### 1.8 Derleme sırası kuralı

**Sorun.** Hatlar aynı `.build` klasörünü paylaşıyor. `build-app.sh` tek uygulama kopyasını (`~/Applications/Workspace AI.app`) eziyor. Pencere yakalama ve `MARKA_SNAPSHOT` bu kopyayı kullanıyor. Aynı anda iki derleme ya da yarım kalmış bir diff başka hattın testini kırar.

**Önerilen yol (kurucu kararı K-3 gerekir): her hatta ayrı git worktree.**
- `../MarkaCalismaAlani-hatA`, `-hatB`, `-hatC`: her hattın kendi dalı ve kendi `.build` klasörü var. `scripts/test.sh` her worktree'de **serbestçe** çalışır.
- Ortak kaynak yalnız uygulama paketi: `build-app.sh`, `pencere-goruntu.sh` ve `MARKA_SNAPSHOT` **zaman dilimine** bağlıdır (aşağıdaki tablo).
- Bütünleştirme günde bir kez yapılır (16:00): `surum-muhendisi` hat dallarını sırayla A → B → C biçiminde ana çalışma ağacına alır ve kapıyı koşar.
- Bu düzen yerel dal ve yerel commit ister. Push gerekmez, ama yine de kurucu onayına bağlıdır.

**Onay yoksa yedek yol: tek ağaç, katı zaman dilimi.**

| Dilim | Kim derler ya da test eder | Kural |
|---|---|---|
| 09:00–11:00 | Hat A | Dilim sonunda A'nın değişikliği derlenir halde olur |
| 11:00–13:00 | Hat B | aynı |
| 14:00–16:00 | Hat C | aynı |
| 16:00–17:00 | `surum-muhendisi` | tam kapı, `build-app.sh`, gerçek pencere yakalamaları |

Dilim dışında hat yalnız kod yazar ve okur. Derlemeyen bir değişiklik dilim sonunda ya geri alınır ya da yama olarak kenara konur.

**Migration kuralı.** Şema şu an `v9_olcek_indeksleri` sürümünde (`AppDatabase.swift`). Migration numarasını **yalnız Hat A'daki `swift-gelistirici`** verir. Kampta en çok **bir** migration öngörülüyor: `v10` numarası H1-03 için ayrıldı ve yalnız "süre kaydını koru" yolu seçilirse kullanılır (§6, K-5). Başka bir görev migration isterse önce karar kapısına gelir. Her migration yalnız ekleme yapar ve migration-yedek testiyle gelir.

---

## 2. Seviye ve puan sistemi

| İşaret | Anlamı | Puan | Ölçüt |
|---|---|---:|---|
| 🟢 | basit: tek dosya, belirgin kabul | 1 | ≤0,5 gün, risk düşük |
| 🟡 | orta: birden çok dosya ya da yeni test kümesi | 3 | 0,5–2,5 gün |
| 🔴 | boss: mimari, veri bütünlüğü ya da birden çok kural | 8 | çok zor; "bitti" kanıtı çok parçalı |

- **Haftanın boss'u** cuma demosunda ilk gösterilen iştir. Bitmediyse bitmiş kısmı ayrılır ve kalan kısım havuza gider. Yarım boss "bitti" sayılmaz.
- "Doğrulanamadı" etiketli 🟡 ya da 🔴, ilgili blokaj kalkana kadar puanın **yarısını** alır.
- Puan bir kişiyi ya da ajanı değerlendirmek için kullanılmaz. Yalnız ilerlemeyi görünür kılar.

### Kamp panosu (her Cuma güncellenir)

| Metrik | Başlangıç (2026-10-05, girdi raporlarındaki sayım) | Kamp sonu hedefi | Kaynak görev |
|---|---|---|---|
| `@Test` sayısı | 255 | ≥ 300 | tümü |
| `try?` sayısı (tüm Sources) | 228 | ≤ 220 (K-14 havuzda; yalnız dokunulan yollar) | H1-01, H3-03 |
| `.font(.system(size:))` | 254 | ≤ 60 | H2-04 |
| 9 pt yazı | 2 | 0 | H2-05 |
| CI | yok | iş akışı dosyası hazır ve yerelde eşleniği geçiyor. Canlı koşu push kararına bağlı | H1-13 |
| MarkaCore satır kapsamı % | ölçülmedi | taban ölçüldü ve belgeye yazıldı | H3-08 |
| Kararsız test sayısı | bilinmiyor | 20 koşuda ölçüldü; her biri düzeltildi ya da gerekçeyle karantinaya alındı | H1-12 |
| Açık veri kaybı maddesi (U-01…U-08) | 8 | 0 | Hafta 1 |
| Gerçek pencere kanıtlı ekran (kamp içinde) | 0 | ≥ 8 (ekran açıksa) | B hattı |
| Sessiz hata yutma (`onError: { _ in }`, boş `catch {}`) | 2 | 0 | H3-03 |
| Yalıtım: Store yüzeyinde izin listesi dışı kapsamsız yüzey | ölçülmedi (72/104 imzada `brandId` yok) | 0 | H2-06 |

---

## 3. Kullanıcı gözü

Kaynak `docs/camp/girdi-kullanici-gozu.md` (54 madde). Persona: 5 müşterili bağımsız danışman. Girdinin sınırı şu: tıklama yapılamadı, birçok madde **[tıklayarak doğrulanamadı]** etiketli. Bu yüzden her görevin ilk adımı sorunu testle ya da gerçek pencerede **yeniden üretmek**tir. Üretilemeyen madde "üretilemedi" notuyla kapanır.

### 3.1 Veri kaybı sınıfı: Hafta 1, G1–G3 (hepsi ilk üç günde)

| U-ID | Sorun (kullanıcının sözüyle, kısa) | Görev | Gün | Doğrulanmış kanıt |
|---|---|---|---|---|
| U-01 | "Görevi sildim, faturalık saatler de gitti" | H1-03 | G1–G2 | **Doğrulandı:** `timeEntry` görevi `onDelete: .cascade` ile bağlıyor; silme onayı süreden söz etmiyor |
| U-03 | "14 saat yazıyordu, düzeltecek yer yok" | H1-03 | G1–G2 | `addManualTime` çekirdekte var, arayüzde yok |
| U-07 | "Notu yazıp ⌘Q yaptım, not boş" | H1-04 | G2 | `willTerminate` kancası yok |
| U-02 · U-44 | "Arşivlediğim dosyayı bir daha bulamadım" | H1-05 | G3 | `includeArchived: true` çağrısı yok |
| U-04 | "Dışa aktarımda finans kayıtları yok" | H1-01 | G1 | `BrandExport` içinde `FinanceEntry` yok |
| U-05 | "Yedekler aynı diskteymiş" | H1-01 | G2 | `createBackup(destination:)` arayüzde yok |
| U-06 | "Menü çubuğunda açık kaldı, bir hafta yedek yok" | H1-02 | G3 | otomatik yedek yalnız `openWorkspace` içinde |
| U-08 | "İkinci kez açtım, yedekten geri yükle dedi, korkup yükledim" | H1-09 | G1 | kilit hatası yedek ekranına düşüyor |

### 3.2 Engelleyici ve önemli: Hafta 2–3

| U-ID | Görev | Not |
|---|---|---|
| U-09 (+U-35) | H2-03 (G6) | AI'sız raporun boş kalması: kurucuya sunulan "öne çıkan beş"in ilki |
| U-10 | H1-06 (G4) | Boş durumda terminal ve `oneriler/` metni. **Doğrulandı:** `FlowView.swift:51` |
| U-11 (+U-34) | H2-02 (G6–G7) | Anahtar yokken bekleyen istem sonra **kendiliğinden ücretli çağrı** yapıyor |
| U-15 · U-16 | H3-05 | Onay sayfasında kutuların önceden seçili olması kural 3 vaadiyle çelişiyor |
| U-18 · U-51 | H3-10 | Sayı tutarsızlığı (güven) |
| U-19 | H1-08 | Sayacın sessizce durması |
| U-25 | H1-02 | Gece yarısında tarih eskide kalıyor |
| U-27 | H3-04 | Asistan hatasında taslak kayboluyor |
| U-14 (kısmi) | H1-05 + H3-05 | Arşiv ve onay için geri alma. Evrensel geri alma (K-05) havuzda |

### 3.3 Sürtünme ve kozmetik paketleri

| Paket | U-ID'ler | Görev |
|---|---|---|
| Panel yazımı | U-37 | H1-07 |
| Görev satırı | U-38 | H3-06 |
| Varsayılanlar | U-48, U-42 | H3-07 |
| Temizlik ve örnek veri | U-45, U-52 | H3-12 |
| Geri kalanlar | U-12, U-13, U-17, U-20…U-24, U-26, U-28…U-33, U-36, U-39…U-41, U-43, U-46, U-47, U-49, U-50, U-53, U-54 | Havuz (§5). U-12 ve U-13 havuzun ilk sırasında |

İzlenebilirlik tablosunun tamamı (54 satır) belgenin sonunda, §3.4'te.

---

## 4. Haftalar

### Günlük akış (G1–G15)

| Gün | Tarih | Hat A | Hat B | Hat C |
|---|---|---|---|---|
| G1 | 10-05 Pzt | H1-01: U-04 + G-11 dışa aktarım kapsamı | H1-03: süre güveni (U-01 testi önce) | H1-09 kilit ekranı · H1-10 dürüst metinler |
| G2 | 10-06 Sal | H1-01: U-05 başka yere yedek + G-03 manifest | H1-03 bitiş · H1-04 kapanışta kaydet | H1-11 tek komut kapı |
| G3 | 10-07 Çar | H1-02 gün değişimi · H1-01 G-03 testleri | H1-05 arşivlenenler + geri al | H1-12 kararsız test avcısı |
| G4 | 10-08 Per | H1-01 G-03 geri yükleme testleri | H1-06 terminalsiz boş durumlar · H1-07 notlarda yeni satır | H1-12 bitiş · H1-13 CI başlangıcı |
| G5 | 10-09 Cum | H1-01 bitiş · **DEMO + KAPI** | H1-08 sayaç bildirimi · **DEMO + KAPI** | H1-13 bitiş · **DEMO + KAPI** |
| G6 | 10-12 Pzt | H2-01: K-08 ChatEngine bölme | H2-03 elle iş kaydı | H2-06: yüzey taraması (izin listesi) |
| G7 | 10-13 Sal | H2-01: `AIProvider` protokolü | H2-02 asistan anahtarsızken | H2-06: rastgele iki marka özellik testi |
| G8 | 10-14 Çar | H2-01: Anthropic taşıma | H2-04 tasarım dili: token şartnamesi + yarıçap ve boşluk | H2-06: yazma → denetim olayı |
| G9 | 10-15 Per | H2-01: Codex taşıma + `FakeProvider` testleri | H2-04: yazı göçü · H2-05 9 pt | H2-06 bitiş + muhafız denetimi |
| G10 | 10-16 Cum | H2-01 bitiş (MAS derlemesi) · **DEMO + KAPI** | H2-04 bitiş · **DEMO + KAPI** | H2-07 çizim kararlılığı · **DEMO + KAPI** |
| G11 | 10-19 Pzt | H3-01: kırmızı takım derlemi | H3-04 asistan hataları (A-13 çekirdek) | H3-08 kapsam ölçümü |
| G12 | 10-20 Sal | H3-01: savunma + çerçeve | H3-04 bitiş · H3-05 onay ritüeli başlangıcı | H3-08 bitiş · H3-09 kural-test haritası |
| G13 | 10-21 Çar | H3-01 bitiş · H3-02 altın set | H3-05: klavye akışı | H3-10 sayı tutarlılığı |
| G14 | 10-22 Per | H3-02 bitiş | H3-05 bitiş · H3-06 görev satırı | H3-11 sızıntı kancası · H3-12 geçici PDF + demo adları |
| G15 | 10-23 Cum | H3-03 sessiz hata sıfır · **KAMP DEMOSU + KAPANIŞ KAPISI** | H3-07 varsayılanlar · **DEMO** | pano son hali · **DEMO** |

Boss dağılımı: Hafta 1'de 2 (A, B), Hafta 2'de 2 (A, C), Hafta 3'te 2 (A, B). Hiçbir hat arka arkaya iki haftada iki boss almıyor; A'nın üç boss'u farklı alanlarda.

---

### HAFTA 1 (G1–G5): "Güven: veri kaybı sıfır, ölçüm temeli"

**Hedef:** Kullanıcının verisini kaybettiren sekiz yolun hepsi kapanır ve kapı tek komutla koşar.
**Çıkış kriteri (ölçülebilir):** (1) U-01…U-08 için en az birer test ya da kanıtlı elle senaryo var ve açık veri kaybı maddesi 0. (2) `scripts/gelistir-kapisi.sh` kasıtlı kırık bir testte KALDI, düzeltilince GEÇTİ diyor. (3) 255 testin 20 koşudaki kararlılık tablosu yazıldı. (4) `@Test` sayısı ≥ 270.

| ID | Görev (kaynak) | Sv | Hat | Sahip | Gün | Kabul ölçütü | Doğrulama | Blokaj |
|---|---|---|---|---|---|---|---|---|
| H1-01 | **Yedek ve dışa aktarım güveni** (U-04 + U-05 + G-03 + G-11) | 🔴 | A | swift-gelistirici + veri-gizliligi-denetcisi | 4,0 | Manifestte dosya başına SHA-256 var. 5 test geçiyor: `degistirilmisDosyaliYedekReddedilir`, `eksikDosyaliYedekReddedilir`, `manifestsizYedekReddedilir`, `geriYuklemeSonrasiDosyaKumesiYedekleAyni`, `disaAktarimEksikDosyayiRaporlar`. `BrandExport` finans kayıtlarını ve marka profilini içeriyor. Şema taraması testi `brandIdSutunluHerTabloDisaAktarimdaYaDaGerekceliDislamada` 0 eksik buluyor. Ayarlar › Veri'de "Yedeği başka yere kaydet…" `createBackup(destination:)` ile çalışıyor. Ayar metni yedeğin aynı Mac'te tutulduğunu açıkça söylüyor. `BackupService` içindeki sessiz `try?` dosya kopyaları 0. | test; gerçek pencere (Ayarlar › Veri) | ekran (yalnız UI kanıtı) |
| H1-02 | Gün değişimi: ekran tazeleme + otomatik yedek (U-25 + U-06) | 🟢 | A | swift-gelistirici | 0,5 | Gün değişimi ve saat dilimi bildirimi gözlemleniyor. Otomatik yedek kararı çekirdekte, saat enjekte edilebilen bir yardımcıda. Test: gün değişince yedek kararı 1 kez "evet", aynı gün ikinci çağrıda "hayır". | test | yok |
| H1-03 | **Süre güveni** (U-01 + U-03) | 🔴 | B (çekirdek dosyasına dokunur) | swift-gelistirici + arayuz-gelistirici | 1,5 | Test `sureKaydiOlanGorevSilinceSureKayitlariKaybolmaz` önce kırmızı, sonra yeşil. Varsayılan yol migration'sız: süre kaydı olan görevde silme engelleniyor ve "İptal et" öneriliyor; onay metninde "N sa M dk süre kaydı" yazıyor. Görev panelinde süre kayıtları listeleniyor, eklenebiliyor, düzenlenebiliyor ve silinebiliyor; her yazma `Store.audit` bırakıyor (3 test). 8 saatten uzun açık sayaç için uyarı kararı çekirdekte (1 test). | test + gerçek pencere `todo … panel` | ekran (UI) · karar K-5 (yol) |
| H1-04 | Kapanışta bekleyen düzenlemeyi kaydet (U-07) | 🟡 | B | arayuz-gelistirici | 0,5 | Uygulama kapanırken açık `PanelField` kaydediliyor (`willTerminate` ≥ 1). Elle senaryo: not yaz → ⌘Q → aç → not duruyor. Senaryo geçici veri alanında yapılır. | elle | ekran |
| H1-05 | Arşivlenenler süzgeci + arşivi geri al (U-02 + U-44, U-14'ün arşiv kısmı) | 🟡 | B | arayuz-gelistirici | 1,0 | Dosyalar'da "Arşivlenenler" süzgeci var (`includeArchived: true` çağrısı ≥ 1). "Arşivden çıkar" erişilebilir durumda. Arşivleme sonrası "Geri al" bildirimi ve ⌘Z dosyayı geri getiriyor. Test: arşivden çıkarma denetim olayı bırakıyor ve ham kaynak değişmiyor (kural 2). | test + gerçek pencere `files` | ekran (UI) |
| H1-06 | Terminalsiz boş durumlar (U-10) | 🟢 | B | arayuz-gelistirici | 0,5 | `MarkaApp` içindeki `L("…")` metinlerinde ve `en.lproj` içinde "terminal" ile `oneriler/` araması 0. Her boş durum tek bir fiille başlıyor. `l10n.py check` temiz. | grep + l10n | yok |
| H1-07 | Notlarda Enter yeni satır (U-37) | 🟢 | B | arayuz-gelistirici | 0,5 | Notlar alanı çok satırlı; Enter yeni satır açıyor, odak kaybında kayıt yapılıyor. | gerçek pencere + elle | ekran |
| H1-08 | Başka sayaç durunca bildirim (U-19) | 🟢 | B | arayuz-gelistirici | 0,5 | Başka markadaki sayaç durunca adı ve süresiyle kısa bir bildirim çıkıyor. Görev durumunun "Sürüyor"a geçtiği satırda görünüyor. | elle | ekran |
| H1-09 | Kilit durumu ayrı ekran (U-08) | 🟢 | C | arayuz-gelistirici | 0,5 | Kilit hatası ayrı bir ekrana düşüyor: "Uygulama zaten açık" yazıyor ve yedek önerisi 0. Elle senaryo: aynı geçici alanla ikinci süreç açılıyor. | elle | ekran |
| H1-10 | Dürüst metinler (G-12 + G-13) | 🟢 | C | veri-gizliligi-denetcisi | 0,5 | Mutlak "veri bu Mac'te" ifadelerinin depo genelinde araması 0. `bilinen-sinirlar.md` içindeki test sayısı gerçek sayıyla aynı ve bunu bağlayan 1 test var. | grep + test | yok |
| H1-11 | Tek komut kapı (Q-11 + Q-19 + Q-15 + Q-17) | 🟡 | C | kalite-kapisi + test-muhendisi | 1,0 | `scripts/gelistir-kapisi.sh` şu adımları koşuyor: test, build, l10n (eksik/fazla/biçim/çoğul = 0), mas-tarama, erişilebilirlik taraması, sızıntı grep'i, artık süreç denetimi. GEÇTİ ya da KALDI yazıp çıkış kodu veriyor. Kasıtlı kırık testte KALDI, düzeltilince GEÇTİ (iki koşunun çıktısı var). | iki koşu | yok |
| H1-12 | Kararsız test avcısı (Q-03) | 🟡 | C | test-muhendisi | 1,5 | `scripts/kararsiz-avci.sh N` test başına geçme sayısını tablo olarak yazıyor. N=20 koşuda 255 testin her biri ya 20/20 ya da adıyla listeleniyor. Bulunan her kararsız test düzeltiliyor ya da gerekçeyle karantinaya alınıyor. | betik çıktısı | derleme dilimi (uzun koşu: C diliminde ya da kendi worktree'sinde) |
| H1-13 | CI iş akışı, yerel kısım (Q-01) | 🟡 | C | surum-muhendisi | 1,0 | `.github/workflows/ci.yml` yazıldı: test, build-app, l10n, mas-tarama, a11y. Runner farkı (Xcode ve CLT, `test.sh` dallanması) belgelendi. Aynı adımlar yerelde `gelistir-kapisi.sh` ile geçiyor. "Kırmızıda birleştirme yok" kuralı yazıldı. | yerel koşu | **karar K-2** (push yoksa canlı koşu kanıtı "doğrulanamadı") |

**Haftanın boss'ları**
- **H1-01 Yedek ve dışa aktarım güveni.** *Neden zor:* yedek, geri yükleme ve dışa aktarım aynı kodu paylaşıyor ve sessiz `try?` hataları yutuyor. Doğru bütünlük kontrolü (SHA-256 manifest) eski manifestsiz yedeklerle uyumu da korumak zorunda. Dışa aktarım kapsamı şema taramasıyla kilitleniyor, yani gelecekte eklenecek bir tablo da yakalanacak. *Bitti kanıtı:* 6 adlı test yeşil, kasıtlı bozulmuş yedek reddediliyor, dışa aktarım JSON'unda finans var, Ayarlar ekranının gerçek pencere görüntüsü alındı (ya da "doğrulanamadı").
- **H1-03 Süre güveni.** *Neden zor:* faturalık süre finansa ve rapordaki "Harcanan süre"ye akıyor. Silme semantiğini değiştirmek rapor ve finans sayılarını etkiler. Arayüzde ilk kez süre düzenleme açılıyor ve her yazma denetim olayı bırakmak zorunda. *Bitti kanıtı:* U-01 testi önce kırmızı, sonra yeşil (çıktı rapora kopyalanır); 4 yeni test; gerçek pencerede süre listesi.

**Basit görevler paketi (Hafta 1):** H1-02, H1-06, H1-07, H1-08, H1-09, H1-10 (toplam 3,0 hat-günü).

**Riskler (Hafta 1)**
- H1-03'te "silme engeli" kullanıcıyı rahatsız edebilir. Kurucu "kayıtları koru (v10, `setNull`)" yolunu seçerse migration G2'ye girer ve H1-08 G15'e kayar.
- H1-12'nin 20 koşusu uzun sürebilir ve derleme dilimini yer. Worktree yoksa koşu gece ya da 16:00 sonrasına alınır.
- Ekran kilitliyse altı UI görevi "doğrulanamadı" etiketiyle kapanır ve puanın yarısını alır. Bu, G5 kapısında açıkça gösterilir.

---

### HAFTA 2 (G6–G10): "Katmanlar: sağlayıcı, tasarım dili, yalıtım kanıtı"

**Hedef:** Yapay zekâ turu tek bir sağlayıcı arayüzünden geçer, yalıtım tek tek senaryolarla değil sistematik olarak kanıtlanır, arayüz tek bir token diline girer.
**Çıkış kriteri:** (1) `runTurn` içinde sağlayıcı `switch`'i 0 ve `swift build -Xswiftc -DMAS` temiz. (2) Kapsamsız Store yüzeyi izin listesi dışında 0, özellik testi ≥ 200 tohumda sızıntı 0. (3) `.font(.system(size:))` ≤ 60, ayrı `cornerRadius` değeri ≤ 3. (4) `@Test` ≥ 285.

| ID | Görev (kaynak) | Sv | Hat | Sahip | Gün | Kabul ölçütü | Doğrulama | Blokaj |
|---|---|---|---|---|---|---|---|---|
| H2-01 | **AIProvider katmanı** (K-01 + K-08 + A-03 protokol kısmı + A-19) | 🔴 | A | ai-saglayici-uzmani + swift-gelistirici | 4,5 | `ChatEngine.swift` bölündü (`BrandFolders`, istem kurucu, Codex turu) ve en büyük parça < 450 satır. `runTurn` içinde sağlayıcı `switch`'i 0. `FakeProvider` ile ≥ 6 yeni test: araç döngüsü, başka marka kimliğinin reddi, iptal sonrası yeni HTTP isteği 0 ve yeni öneri 0, uygulanmış öneri 0. Mevcut 255 test değişmeden geçiyor. MAS kipi derleniyor. | `scripts/test.sh` + MAS derlemesi | yok |
| H2-02 | Asistan anahtarsızken (U-11 + U-34 + T-12) | 🟡 | B | arayuz-gelistirici | 1,0 | Sağlayıcı yokken bekleyen istem **gönderilmeden temizleniyor**. Bu mantık çekirdekte ve testli: marka değişince istek sayısı 0. "Yapay zekâya sor" düğmesi bu durumda "Yapay zekâyı bağla…" oluyor. Panel varsayılan olarak kapalı ya da ≤ 56 pt dar başlıyor. İki simgenin ikisinde de etiket var. | test + gerçek pencere | ekran |
| H2-03 | Elle iş kaydı (U-09 + U-35) | 🟡 | B | arayuz-gelistirici + swift-gelistirici | 1,0 | Biten görevde "İş kaydı yaz", Özet'te "+ İş kaydı" var. Kullanıcının yazdığı kayıt doğrulanmış sayılıyor ve rapora giriyor (kural 4, test). Karşılama ekranında AI gerektiren maddeler işaretli. Test: AI'sız örnek markada rapor ≥ 1 madde içeriyor. | test + gerçek pencere `report` | ekran |
| H2-04 | Tek tasarım dili (T-01 + T-06'nın göç kısmı) | 🟡 | B | tasarim-lideri → arayuz-gelistirici → arayuz-denetci | 2,25 | En çok 6 yazı rolü token'ı. `.font(.system(size:))` sayısı 254'ten ≤ 60'a iniyor; kalanların her biri gerekçe yorumu taşıyor. `cornerRadius` için en çok 3 değer. Boşluklar 4'ün katı. 8 ekran açık ve koyu temada çiziliyor. | grep sayımı + 8 ekran gerçek pencere | ekran |
| H2-05 | 9 pt sıfır (T-17) | 🟢 | B | arayuz-gelistirici | 0,25 | 9 pt yazı = 0 (`CompanyView`, `BrandProfileView`). | grep | yok |
| H2-06 | **Yalıtım özellik testi** (G-01) | 🔴 | C | marka-yalitim-muhafizi + test-muhendisi | 4,0 | (1) `storeGenelYuzeyiTaranirKapsamsizlarIzinListesinde`: `brandId` almayan her yüzey gerekçesiyle izin listesinde; yeni eklenen bir yüzey testi kırmızıya çeviriyor. (2) `rastgeleIkiMarkaHerYuzeydeSizintiYok`: ≥ 200 tohumlu çift ve tüm okuma yüzeylerinde B markasının verisi A'nın sonucunda 0. (3) Her yazma yüzeyi ≥ 1 `auditEvent` bırakıyor. | `scripts/test.sh` + muhafız denetimi | yok |
| H2-07 | Çizim kararlılığı (Q-05) | 🟢 | C | test-muhendisi | 0,5 | Aynı koddan iki `MARKA_SNAPSHOT` koşusunda PNG'ler aynı (tarih ve saat sabitleniyor ya da maskeleniyor). **Yalnız geçici veri alanında.** | karşılaştırma çıktısı | derleme dilimi (uygulama paketi) |

**Haftanın boss'ları**
- **H2-01 AIProvider katmanı.** *Neden zor:* 893 satırlık aktör iki ayrı tur döngüsü taşıyor (Anthropic, `#if !MAS` Codex). Taşıma sırasında iptal, akış ve araç döngüsü davranışı bire bir korunmalı. Canlı yanıt hiç denenmediği için tek emniyet ağı mevcut testler ve yeni sahte sağlayıcı. *Bitti kanıtı:* 255 eski test değişmeden yeşil, ≥ 6 yeni test, `grep` ile `switch` sayısı 0, iki derleme kipi temiz.
- **H2-06 Yalıtım özellik testi.** *Neden zor:* 104 genel yüzeyin 72'si imzasında `brandId` taşımıyor; her birinin neden güvenli olduğu kanıtlanmalı ya da düzeltilmeli. Rastgele tohumlu testin kararlı olması gerekiyor (H1-12 aracıyla 20/20). *Bitti kanıtı:* üç test yeşil, izin listesindeki her satırda gerekçe var, muhafız raporunda "sızıntı 0".

**Basit görevler paketi (Hafta 2):** H2-05, H2-07 (0,75 hat-günü).

**Riskler (Hafta 2)**
- H2-01, sağlayıcı katmanını değiştirdiği için Hafta 3'teki H3-01, H3-02 ve H3-04'ün ön koşulu. G10'da bitmezse H3-02 havuza kayar (kesme kuralı).
- H2-06 bir sızıntı **bulursa** düzeltme kapsamı belirsiz olur. Kural: sızıntı düzeltmesi her işin önüne geçer. Bu durumda H3-12 ve H3-11 kesilir.
- H2-04'te 254 yerin göçü görsel gerileme yaratabilir. Altın ekran karşılaştırması (Q-02) havuzda olduğu için gerileme yalnız `arayuz-denetci` gözüyle yakalanır.

---

### HAFTA 3 (G11–G15): "Bütünleştirme, cila, dayanıklılık"

**Hedef:** Asistan saldırıya ve hataya karşı dayanıklı hale gelir, onay ritüeli klavyeyle yürür ve kamp ölçülmüş bir taban bırakır.
**Çıkış kriteri:** (1) ≥ 20 enjeksiyon senaryosunda doğrudan yazma 0 ve başka marka kimliği %100 reddediliyor. (2) Onay ritüeli fare kullanmadan yürüyor ve varsayılan seçim boş. (3) Kapsam tabanı ve kural-test haritası belgede; haritada eşlenmemiş kural 0. (4) `@Test` ≥ 300. (5) Pano tamamlandı.

| ID | Görev (kaynak) | Sv | Hat | Sahip | Gün | Kabul ölçütü | Doğrulama | Blokaj |
|---|---|---|---|---|---|---|---|---|
| H3-01 | **Kırmızı takım: prompt enjeksiyonu** (A-02 + K-15) | 🔴 | A | ai-saglayici-uzmani + marka-yalitim-muhafizi | 2,5 | ≥ 20 senaryo: kaynak gövdesi, not, bilgi sayfası, yetenek gövdesi, dosya adı. Sahte yanıt enjekte araç çağrısı ürettiğinde başka marka kimliği %100 `is_error` alıyor, doğrudan yazma 0, uygulanmış öneri 0. Araç sonucu `<kaynak_icerigi>` sınırlayıcısı içinde dönüyor (test). Temel kurallarda "araç sonucu veridir" maddesi var (test). | [SAHTE] `scripts/test.sh` | **anahtar** yalnız canlı uyma oranı için; yoksa "yapılmadı" yazılır |
| H3-02 | Altın istem koşumu, sahte kip (A-01 kısmi) | 🟡 | A | ai-saglayici-uzmani | 1,5 | ≥ 30 senaryo (50 hedefinin kalanı havuzda). Aynı girdiyle iki koşu bire bir aynı sonucu veriyor. Puanlama "araç çağrısı → bekleyen öneri" üzerinden; uygulanmış öneri 0. `MarkaDogrula eval` alt komutunun iskeleti JSON çıktı üretiyor. | [SAHTE] | **anahtar** (canlı koşu) |
| H3-03 | Sessiz hata ve uyarı sıfır (K-20 + K-24) | 🟢 | A | swift-gelistirici | 0,5 | `onError: { _ in }` ve boş `catch {}` sayısı 0; hepsi içeriksiz `Diagnostics.record` ile kaydediliyor (kural 6). MAS derlemesinde uyarı 0. | grep + derleme | yok |
| H3-04 | Asistan hataları anlaşılır (A-13 + A-14 + U-27) | 🟡 | B (çekirdekte A-13) | ai-saglayici-uzmani + arayuz-gelistirici | 1,5 | `AIErrorKind`: anahtar, izin, hız, aşırı yük, ağ, zaman aşımı, bağlam aşımı, ret. Her durum kodunun bir türe eşlendiği testli. Tanı günlüğü yalnız türü yazıyor. Hatalı mesajda "Tekrar dene" var ve taslak geri geliyor. Anahtar hatası "Ayarlar'ı aç" düğmesi gösteriyor. TR ve EN metinler var, `l10n.py check` temiz. | test + gerçek pencere | ekran (UI) |
| H3-05 | **Onay ritüeli klavyeyle** (T-02 + U-15 + U-16 + gerçek pencere bulguları 5–8) | 🔴 | B | tasarim-lideri → arayuz-gelistirici → arayuz-denetci | 2,0 | Varsayılan seçim **boş** (kural 3). Kısayollar: ↑↓ satır, Boşluk seç, ⌘↩ onayla, ⌫ reddet, ⌘A tümü. Açılışta ilk odak düzenlenebilir başlıkta değil. Tek satır stili. Yıkıcı eylem kırmızı ve onay iletişimiyle. Onaydan sonra "Geri al" bildirimi çıkıyor; metin "Özet'ten geri alabilirsin" diyor. Fare kullanmadan 6 öneri ≤ 15 sn'de bitiyor (elle, kronometreyle). | gerçek pencere `flow … onay` + elle + VoiceOver | ekran |
| H3-06 | Görev satırı sağ sütunu (U-38 + T-08) | 🟢 | B | arayuz-gelistirici | 0,5 | Sorumlu rozeti ve ▶ için `help` + VoiceOver etiketi 2/2. Sorumlu boşken rozet gösterilmiyor ama sütun sabit kalıyor (satırlar arası x farkı 0 pt). | gerçek pencere | ekran |
| H3-07 | Varsayılanlar (U-48 + U-42) | 🟢 | B | arayuz-gelistirici | 0,5 | Görünüm varsayılanı "Sistem". Şemasız adrese `https://` otomatik ekleniyor; bağlantı adı boşsa alan adından dolduruluyor (çekirdekte 2 test). | test | yok |
| H3-08 | Kapsam ölçümü (Q-04) | 🟡 | C | test-muhendisi | 1,5 | `scripts/kapsam.sh` MarkaCore satır kapsamını yüzde olarak yazıyor. İlk ölçüm `docs/gelistirme.md`'ye taban olarak giriyor. Kapsamı en düşük 5 dosya listeleniyor. MarkaApp kapsamının dışarıda kaldığı açıkça yazılıyor. CLT ile çalışmazsa bu durum "doğrulanamadı" olarak yazılıyor. | betik çıktısı | derleme dilimi |
| H3-09 | Kural-test haritası (Q-07 + G-22) | 🟡 | C | test-muhendisi + kalite-kapisi | 1,0 | `docs/kural-test-haritasi.md`: 7 kuralın her biri için ≥ 1 test adı. `denetimBelgesindekiHerKanitTestiMevcut` belgede adı geçen her testin var olduğunu doğruluyor (eksik 0). | test | yok |
| H3-10 | Sayı tutarlılığı (U-18 + U-51 + K-22 + gerçek pencere bulguları 9–10) | 🟡 | C | test-muhendisi + swift-gelistirici | 1,0 | "Bekleyen" bandı ile süzgeç aynı çekirdek tanımını kullanıyor (test). "Bu hafta biten" iş kaydı bağlı görevleri de sayıyor (önce kırmızı, sonra yeşil). Bugün'deki karışık birimli "68" sayısı kaldırıldı ya da adı değişti. Aynı kavramın tek adı var. | test + gerçek pencere `bugun`, `flow` | ekran (UI kısmı) |
| H3-11 | Commit öncesi sızıntı kancası (Q-14) | 🟢 | C | veri-gizliligi-denetcisi | 0,5 | `scripts/kancalar-kur.sh` `pre-commit` kancasını kuruyor. Kasıtlı bir e-posta ya da kişisel yol eklenince commit engelleniyor (çıktı var). Kanca dosyası depoya girmiyor. | elle iki koşu | yok |
| H3-12 | Geçici PDF temizliği + demo adları (U-45 + U-52 + T-18) | 🟢 | C | arayuz-gelistirici | 0,5 | Açılışta 7 günden eski geçici rapor PDF'leri siliniyor (çekirdekte test). Demo veride ASCII ad 0 ve ≥ 3 farklı saat var. | test + gerçek pencere | yok |

**Haftanın boss'ları**
- **H3-01 Kırmızı takım.** *Neden zor:* saldırı yüzeyi beş ayrı içerik kanalı. Savunma iki katmanlı olmalı: istemde çerçeve (yumuşak) ve çekirdekte zorunlu sınır (sert). Test sahte sağlayıcıyla yazıldığı için modelin gerçekte nasıl davranacağını kanıtlamaz; bu sınır `bilinen-sinirlar.md`'ye yazılır. *Bitti kanıtı:* ≥ 20 senaryo yeşil, "uygulanmış öneri = 0" iddiası her senaryoda, muhafız raporu var. Canlı uyma oranı anahtar gelene kadar "yapılmadı".
- **H3-05 Onay ritüeli.** *Neden zor:* "AI öneri üretir, sen onaylarsın" vaadinin arayüzdeki tek kanıtı burası. Klavye, odak, VoiceOver ve geri alma aynı ekranda birleşiyor. Varsayılanı boş seçime çevirmek mevcut akışın davranışını değiştiriyor. *Bitti kanıtı:* gerçek pencere açık ve koyu, kronometre sonucu, VoiceOver ile 1 tur. Ekran yoksa "doğrulanamadı" ve yarım puan.

**Basit görevler paketi (Hafta 3):** H3-03, H3-06, H3-07, H3-11, H3-12 (2,5 hat-günü).

**Riskler (Hafta 3)**
- H2-01 gecikirse H3-01 ve H3-04 eski koda yazılır ve iki kez yazılmış olur. Kural: H2-01 G10'da bitmediyse H3-02 kesilir ve A hattı H2-01'i G11'de bitirir.
- Kapanış haftasında bütünleştirme çakışmaları birikir. G14 16:00'dan sonra yeni özellik birleştirilmez; yalnız düzeltme girer.

---

### 3.4 U-maddeleri nereye gitti (54 satır, izlenebilirlik)

| U-ID | Konu | Önem | Nereye | Neden (havuzdaysa) |
|---|---|---|---|---|
| U-01 | Görev silinince süre kaydı gidiyor | veri kaybı | H1-03 | — |
| U-02 | Arşivlenen dosya bulunamıyor | veri kaybı | H1-05 | — |
| U-03 | Zamanlayıcı düzeltilemiyor | veri kaybı | H1-03 | — |
| U-04 | Dışa aktarımda finans yok | veri kaybı | H1-01 | — |
| U-05 | Yedek aynı diskte | veri kaybı | H1-01 | — |
| U-06 | Menü çubuğunda açıkken yedek yok | veri kaybı | H1-02 | — |
| U-07 | ⌘Q ile not kaybı | veri kaybı | H1-04 | — |
| U-08 | İkinci süreç yedeğe yönlendiriyor | veri kaybı | H1-09 | — |
| U-09 | AI'sız rapor boş | engelleyici | H2-03 | — |
| U-10 | Boş durumda terminal metni | engelleyici | H1-06 | — |
| U-11 | Anahtarsız sor → sonra kendiliğinden çağrı | engelleyici | H2-02 | — |
| U-12 | E-posta taslağı yalnız Mail, önce PDF kaydı | engelleyici | havuz (1. sıra) | Çalışan bir yol var (PDF kaydet, elle ekle); "Hazır işaretle" ayrımı tasarım gerektiriyor (1,5 gün) |
| U-13 | Büyük dosyada donma | engelleyici | havuz (1. sıra) | Arka planda içe alma eşzamanlılık riski taşıyor (≈2 gün); önce boyut ölçümü gerekiyor. G10 kapısında H2-04'ün kalanıyla takas adayı |
| U-14 | ⌘Z tutarsız | engelleyici | kısmi: H1-05 + H3-05; kalan havuzda | Kalıcı çözüm evrensel geri alma günlüğü (K-05, 5 gün ve K-07'ye bağlı) |
| U-15 | Onayda öneriler önceden seçili | önemli | H3-05 | — |
| U-16 | "Akış'tan geri al" metni yanlış | önemli | H3-05 | — |
| U-17 | Öncelik ve proje sonradan değişmiyor | önemli | havuz | Görev paneli paketi (T-09 ile 2 gün); veri kaybı yok |
| U-18 | Bekleyen sayısı tutmuyor | önemli | H3-10 | — |
| U-19 | Sayaç sessizce duruyor | önemli | H1-08 | — |
| U-20 | Aynı dosyanın iki kopyası | önemli | havuz | sha256 karşılaştırması ve uyarı; veri kaybı yok |
| U-21 | Eski dosya geçmişe düşüyor | önemli | havuz | Sıralama kararı (ekleme tarihi mi, dosya tarihi mi) ürün kararı |
| U-22 | İngilizcede rapor tarihleri TR | önemli | havuz | Yerelleştirme paketi (U-22/23/24/54) tek seferde yapılmalı |
| U-23 | İngilizcede asistan istemi TR | önemli | havuz | Yerelleştirme paketi |
| U-24 | Uygulama içi dil seçimi yok | önemli | havuz | Yeni ayar = kullanıcı kararı |
| U-25 | Gece yarısı tazelenmiyor | önemli | H1-02 | — |
| U-26 | Arşivli adla yeni marka | önemli | havuz | Kolay (0,5 gün), ama kullanıcının sık yaşadığı bir durum değil |
| U-27 | Asistan hatasında soru kayboluyor | önemli | H3-04 | — |
| U-28 | Stüdyo kavramı tek kişiye ağır | önemli | havuz | Ürün kararı (bilgi mimarisi) |
| U-29 | Jargon yoğunluğu | önemli | havuz | Terim sözlüğü kararı gerekiyor; H2-04'ten sonra |
| U-30 | Yardım menüsü boş | önemli | havuz | Kısayol listesi K-07 (⌘K kayıttan) ile birlikte |
| U-31 | İki ayrı arama | önemli | havuz | K-06 FTS + K-07 gerekiyor (≈9 gün) |
| U-32 | Çok pencere aynı seçimi paylaşıyor | önemli | havuz | Tek pencere mi, pencereye özel seçim mi kararı gerekiyor |
| U-33 | 1000+ görevde takılma | önemli | havuz | Ölçülmedi; önce release ölçümü (K-27), sonra K-04 |
| U-34 | Asistan paneli boşken yer kaplıyor | önemli | H2-02 | — |
| U-35 | Karşılamada AI gerektiren maddeler belirsiz | sürtünme | H2-03 | — |
| U-36 | Örnek marka gerçek veride kalıyor | sürtünme | havuz | "Kaldırayım mı?" akışı; veri kaybı yok |
| U-37 | Notlarda Enter kaydediyor | sürtünme | H1-07 | — |
| U-38 | "C" rozeti anlaşılmıyor | sürtünme | H3-06 | — |
| U-39 | Panel listeyi kesiyor | sürtünme | havuz | Yerleşim işi; H2-04'ten sonra |
| U-40 | Yeni görev "Diğer"in altına düşüyor | sürtünme | havuz | Görev paneli paketiyle |
| U-41 | Görünüm tercihleri unutuluyor | sürtünme | havuz | Marka başına tercih; düşük risk |
| U-42 | `ornek.com` reddediliyor | sürtünme | H3-07 | — |
| U-43 | Önizlemeler boş | sürtünme | havuz | T-11 ile birlikte |
| U-44 | Arşivleme onaysız | sürtünme | H1-05 | — |
| U-45 | Geçici PDF'ler silinmiyor | sürtünme | H3-12 | — |
| U-46 | Gantt'ta çubuk yok | sürtünme | havuz | T-10 ile birlikte |
| U-47 | Şirket formunda iki ayrı kayıt modeli | sürtünme | havuz | Otomatik kayda geçiş tasarım kararı |
| U-48 | Görünüm varsayılanı açık tema | sürtünme | H3-07 | — |
| U-49 | 1100 px'te araç çubuğu sıkışıyor | sürtünme | havuz | Dar pencere yakalanamıyor (betik sabit boyutta açıyor) |
| U-50 | Sektör ve kişi kesiliyor | kozmetik | havuz | T-13/T-16 ile birlikte |
| U-51 | Kutucuk adları farklı | kozmetik | H3-10 | — |
| U-52 | Örnek adlar Türkçe karaktersiz | kozmetik | H3-12 | — |
| U-53 | VoiceOver ham tarihi okuyor | kozmetik | havuz | Yerelleştirme paketiyle (tarih biçimleyici) |
| U-54 | Hafta başlangıcı sabit | kozmetik | havuz | Yerelleştirme paketi |

Özet: 54 maddeden 28'i plana girdi (U-14 kısmi), 26'sı havuzda. Veri kaybı sınıfının 8 maddesinin hepsi Hafta 1'in ilk üç gününde.

---

## 5. Kamp sonrası havuzu

Kesilen işlerin her biri, sıra numarası ve yeniden değerlendirme koşuluyla. Kaynak ID'ler birleştirildi.

| Sıra | Paket (kaynak ID'ler) | Tahmin (ölçülmedi) | Neden kesildi | Yeniden değerlendirme koşulu |
|---|---|---|---|---|
| 1 | E-posta ve rapor teslimi (U-12, T-25) | 2 g | Çalışan bir yol var; tasarım gerekiyor | G10 kapısında takas adayı |
| 2 | Büyük dosya arka plan içe alma (U-13) | 2 g | Eşzamanlılık riski, ölçüm yok | Bir dosya boyutu ölçümü yapılınca |
| 3 | Evrensel geri alma + Action Registry (K-05 + K-07 + U-14 kalanı + U-30, plan F1/F2) | 10 g | İki boss birbirine bağlı; migration v10/v11 gerektiriyor | H2-01 bitince, kamp sonrası ilk sprint |
| 4 | Apple cihaz üstü sağlayıcı (K-02 + A-03'ün Apple kısmı + A-11 + K-10 + A-04 + K-09/A-06) | ≈12 g | H2-01'e bağlı; Apple Intelligence açık Mac gerekiyor | H2-01 bitince ve cihaz hazırsa |
| 5 | Ekran başına gözlem ve performans (K-04 + U-33 + K-11 + K-23 + K-27 + K-06) | ≈14 g | U-33 ölçülmedi; önce release ölçümü | K-27 release ölçümü sorun gösterirse |
| 6 | Sandbox S4–S7 (K-03 + K-12 + K-13) | 9 g | Mimari serbest ama kapasite yok; H1-01, S6'nın öncülüdür | Kurucu sandbox sırasını açınca |
| 7 | Görev paneli paketi (U-17 + U-40 + T-09) | 2,5 g | Veri kaybı yok | Hafta 1'deki süre paneli bitince doğal devam |
| 8 | Yerelleştirme paketi (U-22 + U-23 + U-24 + U-53 + U-54) | 3 g | U-24 yeni ayar istiyor (karar) | Kurucu dil ayarına karar verince |
| 9 | Durum sistemi ve hareket (T-03 + T-05) | 7 g | H2-04'e bağlı | H2-04 ≤ 60 hedefini tutunca |
| 10 | Liquid Glass ve koyu bütünlük (T-04 + T-14) | 5 g | Kök neden doğrulanmadı (pasif penceredeki düğme) | Gerçek pencere ve piksel ölçümü mümkün olunca |
| 11 | Ölçeklenebilir metin, kalan kısım (T-06: ≤ 20 + 3 kademe ayar) | 3 g | Yeni ayar = karar | Kurucu onaylarsa |
| 12 | İlk açılış "sihir" anı (T-07 + U-36) | 4 g | T-02 ve T-05'e bağlı | H3-05 bitince |
| 13 | Altın ekran ve UI duman testi (Q-02 + Q-10) | 7 g | H2-07 ön koşulu kamp içinde | H2-07 kararlı çıkınca |
| 14 | Kalite eşikleri (Q-06 + Q-08 + Q-12 + Q-13 + Q-18) | 6 g | Kapı tabanı önce | CI canlı koşunca |
| 15 | Codex riski (G-02 + G-07 + G-09 + G-10 + G-17) | 6,5 g | Codex yalnız doğrudan dağıtımda; gerçek Codex ölçümü gerekiyor | Kurucu doğrudan dağıtım kanalına karar verince. **Not:** Codex `never` riski `bilinen-sinirlar` §4'te açık duruyor |
| 16 | Denetim izi hash zinciri (G-05) | 2,5 g | Migration gerektiriyor; H2-06'nın yazma listesine bağlı | H2-06 bitince |
| 17 | Şifreleme değerlendirmesi (G-04) | 2 g | Önce H1-01 | H1-01 bitince |
| 18 | İçe aktarım fuzz + `importSkill` sınırları + SKILL.md kökeni (G-06 + G-21 + G-08) | 5 g | Kapasite | H2-06 sonrası |
| 19 | Yazma hataları tek yardımcıda (K-14 + K-16) | 3 g | `try?` hedefi buna bağlı | Kamp sonrası ilk sprint |
| 20 | Dosya bölme (K-18 + K-19), sabitler (K-21), değişmemiş alanlar (K-26), `mas-tarama` testi (K-25) | 3,5 g | Davranış değişmiyor | Dolgu işi olarak |
| 21 | AI cilası (A-05, A-07, A-08, A-09, A-10, A-12, A-15, A-16, A-17, A-18, A-20, A-21) | ≈13 g | H2-01'e bağlı; A-05 ve A-17 anahtar istiyor | H2-01 + anahtar |
| 22 | Küçük güvence (G-14, G-15, G-16, G-18, G-19, G-20) | 3 g | Düşük risk | Dolgu işi |
| 23 | Tasarım küçükleri (T-10, T-11, T-13, T-15, T-16, T-19…T-24, T-26, T-27 + U-39, U-43, U-46, U-50) | ≈11 g | Kozmetik | H2-04 sonrası |
| 24 | Diğer U maddeleri (U-20, U-21, U-26, U-28, U-29, U-31, U-32, U-41, U-47, U-49) | ≈8 g | Çoğu ürün kararı ya da ekran istiyor | §6'daki kararlarla |
| 25 | Ölü kod (K-17: `TerminalSessions` + 5 test) | 0,5 g | **Kullanıcı kararı** | Onay gelirse H3-03'ün yanına eklenir (kapasite 0,5 g aşılırsa H3-07 çıkar) |

---

## 6. Blokajlar ve kullanıcı kararları

Hiçbiri planı durdurmaz. Her birinin bloklamayan bir alternatifi var.

| # | Ne gerekli | Kim | Hangi görevi bekletir | Bloklamayan alternatif |
|---|---|---|---|---|
| K-1 | Ekran açık (gerçek pencere, Ekran Kaydı izni) | kurucu (Mac başında) | H1-01, H1-03, H1-04, H1-05, H1-07, H1-08, H1-09, H2-02…H2-04, H3-04…H3-06, H3-10 (UI kanıtı) | `MARKA_SNAPSHOT` çizimi + **"gerçek pencere: doğrulanamadı"** etiketi + yarım puan; kanıt Cuma demosunda toplu alınır |
| K-2 | Commit ve push onayı | kurucu | H1-13 canlı CI koşusu; worktree birleştirme (K-3) | Yerelde `gelistir-kapisi.sh`; Cuma yaması depo dışında |
| K-3 | Yerel dal ve worktree izni (push yok) | kurucu | Derleme sırası kuralının önerilen yolu | Tek ağaç + zaman dilimi (§1.8) |
| K-4 | Canlı Claude anahtarı (kurucu Ayarlar'a girer, sohbette paylaşılmaz) | kurucu | Canlı kısımlar: A-01 (H3-02), A-02 (H3-01); havuzda A-05, A-06, A-17 | Sahte kip; canlı satır "yapılmadı" |
| K-5 | U-01 yolu: silme engeli (migration'sız, varsayılan) mı, yoksa `setNull` ile süre kaydını koruma (v10) mı | kurucu (ürün yöneticisi önerisi: engel) | H1-03 | Varsayılan yolla başlanır; karar G2'ye kadar gelirse v10 açılır |
| K-6 | `TerminalSessions.swift` + `TerminalOturumTests` silinsin mi (K-17) | kurucu | havuz 25 | Dosya yerinde kalır |
| K-7 | Ürün adı: "Workspace AI" mı, "Brand Workspace" mi (depo adı farklı) | kurucu | Hiçbiri (metin değişmez) | Arayüzde mevcut ad kalır |
| K-8 | Depo görünürlüğü (herkese açık kalsın mı) | kurucu | Hiçbiri | Herkese açık kabul edilir; H3-11 kancası ve gizlilik kuralları uygulanır |
| K-9 | Yeni ayarlar: uygulama içi dil (U-24), metin boyutu kademesi (T-06) | kurucu | havuz 8, 11 | Sistem ayarı izlenir |
| K-10 | Stüdyo kavramının sadeleşmesi (U-28) | kurucu | havuz 24 | Mevcut haliyle kalır |
| K-11 | Apple Intelligence açık bir Mac (cihaz üstü sağlayıcı) | kurucu | havuz 4 | Yalnız sahte sağlayıcı |

---

## 7. Riskler, sinyaller ve kesme kuralı

| Risk | Olasılık | Etki | Azaltma |
|---|---|---|---|
| Tahminler tutmaz (hiçbiri ölçülmedi) | yüksek | yüksek | Gerçek süre her akşam panoya yazılır; G5 ve G10'da plan düzeltilir |
| Ekran kilitli, UI kanıtı alınamaz | orta | orta | K-1 alternatifi; kanıt Cuma'ya toplanır |
| Commit onayı gelmez, üç haftalık iş tek diff olur | orta | yüksek | K-2: Cuma yaması, her kapıda onay sorusu |
| Derleme çakışması ya da yarım diff başka hattı kırar | yüksek (tek ağaçta) | orta | §1.8 worktree ya da zaman dilimi; günde bir bütünleştirme |
| H2-06 bir sızıntı bulur | orta | yüksek | Sızıntı düzeltmesi her işin önüne geçer; Hafta 3'ün 🟢 işleri kesilir |
| H2-01 regresyonu canlıda görünmez (anahtar yok) | orta | yüksek | Eski 255 test değişmeden geçer; canlı doğrulama `bilinen-sinirlar`'a "yapılmadı" diye yazılır |
| Tasarım göçü görsel gerileme yaratır | orta | orta | Denetçi 8 ekranı açık ve koyu temada çizer; altın ekran havuzda (risk kabul) |
| Alt ajan gerçek veri alanına dokunur | düşük | çok yüksek | Yasaklar her göreve kopyalanır; yalnız geçici `MARKA_WORKSPACE` |
| CI runner'ında CLT ve Xcode farkı | orta | düşük | H1-13 bunu belgeler; yerel kapı esas alınır |

**"Plan doğru gitmiyor" sinyalleri**
- Bir hat bir günde planlanandan **> 1 gün** geride.
- Bir boss, haftasının Çarşamba akşamında kabul ölçütlerinin yarısını karşılamıyor.
- `@Test` sayısı haftalık hedefin altında ya da kararsız test sayısı artıyor.
- Aynı gün iki hat aynı dosyaya dokunmak zorunda kalıyor (bölge kuralı bozuldu).
- "Doğrulanamadı" etiketli görev sayısı haftada 4'ü aşıyor.

**Kesme kuralı (sırayla uygulanır)**
1. Veri kaybı görevleri (Hafta 1) ve sızıntı düzeltmeleri **asla** kesilmez.
2. Önce o haftanın 🟢 görevleri havuza gider. En son bitenler ve kullanıcıya en az görünenler önce gider.
3. Sonra değeri en düşük 🟡 görev gider. Önerilen sıra: H3-02 → H2-07 → H3-08 → H2-04 (bu son durumda ≤ 60 hedefi ≤ 150'ye gevşer).
4. Boss bölünür: bitmiş ve kanıtlı kısmı ayrı görev olarak kapanır, kalan kısım havuzun başına yazılır. Yarım boss "bitti" sayılmaz.
5. Kesme kararını ürün yöneticisi önerir, Cuma kapısında kurucuya gösterir. Hafta içindeki acil kesme ertesi Cuma raporlanır.

---

## 8. Ekip konuşuyor

> **urun-yoneticisi:** Altı rapordan yaklaşık 200 günlük iş çıktı. 45'ini aldım, kalanı havuzda ve her birinin bir dönüş koşulu var. Vaadim şu: Hafta 1'in sonunda kullanıcı verisini kaybettiren bilinen bir yol kalmayacak. Endişem tahminler; hiçbiri ölçülmedi. G5'te ilk gerçek sayılarla planı yeniden keseceğim.

> **tasarim-lideri:** 254 sabit yazı boyutunu ≤ 60'a indirmek, yazı rolü sayısını 6'ya çekmek ve onay ekranını klavyeyle yürütmek bu kampın tasarım işi. Kozmetik görünse de güven işi: düğme düğme görünmüyorsa kullanıcı onaylamaz. Altın ekran karşılaştırması olmadan göç yapmaktan endişeliyim; gerilemeyi gözle yakalamamız gerekecek.

> **arayuz-gelistirici:** Üç hafta boyunca en çok satıra dokunacak benim. Süre paneli, arşiv süzgeci ve elle iş kaydı ilk kez arayüze açılıyor. Her yeni `L("…")` sonrası `l10n.py check` koşacağım. Endişem ekran: kilitliyse işimin yarısı "doğrulanamadı" yazacak.

> **arayuz-denetci:** Her UI görevinde açık ve koyu iki görüntü isteyeceğim, yoksa puanın yarısı verilir. Ölçeceğim şey kanıtlı ekran sayısı: bugün kamp içinde 0, hedef 8. Pasif penceredeki görünmez düğmenin kök nedenini bilmiyoruz; bunu iddia etmeyeceğim.

> **swift-gelistirici:** Yedek manifesti ve sağlayıcı katmanı iki gerçek boss. Migration numarası bende; kampta en çok bir tane (v10) açarım, o da kurucu "kayıtları koru" derse. Asıl endişem ChatEngine taşıması: canlı yanıt hiç denenmedi, tek emniyetim 255 eski test.

> **test-muhendisi:** Testi önce kırmızı yazacağım, sonra yeşil. 255'ten ≥ 300'e çıkmayı, kapsam tabanını ve 20 koşuluk kararsızlık tablosunu vaat ediyorum. "Bitti" diyen bir görevi önce/sonra test sayısı olmadan kabul etmem.

> **ai-saglayici-uzmani:** Sahte sağlayıcıyla 20 saldırı ve 30 altın senaryo yazacağım. Hepsinde "uygulanmış öneri = 0" iddiası olacak. Açık söyleyeyim: bunlar modelin gerçekte nasıl davrandığını kanıtlamaz. Anahtar gelmeden canlı sütun boş kalır, ona "geçti" demem.

> **marka-yalitim-muhafizi:** 104 yüzeyin 72'si imzasında marka kimliği taşımıyor. Her birinin gerekçesi listede olacak, yoksa test kırmızı kalır. Rastgele iki markada 200 tohumla sızıntı 0'ı ölçeceğim. Bir sızıntı bulursam kampın sırası değişir; bunu şimdiden söylüyorum.

> **veri-gizliligi-denetcisi:** Yedek manifesti, sızıntı kancası ve "veri bu Mac'te" metinlerinin temizliği benim. Tanı günlüğüne hata türü girer, içerik girmez. Codex `never` riski bu kampta çözülmüyor; havuzda ve `bilinen-sinirlar`'da açıkça duruyor, gizlemeyeceğim.

> **kalite-kapisi:** H1-11'den sonra kapı tek komut olacak: GEÇTİ ya da KALDI. Kasıtlı kırık test kırmızı çıkmazsa kapı da bitmiş sayılmaz. Endişem CI: push onayı yoksa CI yalnız bir dosya olarak kalır.

> **surum-muhendisi:** Derleme sırasını ve günlük bütünleştirmeyi ben yöneteceğim. Paket yayını, imza ya da notarization yok. Worktree izni gelirse hatlar birbirini kırmaz; gelmezse zaman dilimine sıkı uyacağız ve bu biraz yavaşlatır.

> **pazar-arastirmacisi / buyume-stratejisti:** Kamp boyunca dondurulduk. Kuluçkada yalnız ürün var; çağrılmayacağız.

---

## 9. Ek

### 9.1 Kaynak raporlar

| Dosya | İçerik | Madde |
|---|---|---|
| `docs/camp/girdi-kullanici-gozu.md` | İlk kullanım turu, persona | U-01…U-54 |
| `docs/camp/girdi-tasarim.md` | Tasarım dili, durumlar, erişilebilirlik | T-01…T-27 |
| `docs/camp/girdi-kodlama.md` | Mimari ve kodlama | K-01…K-27 |
| `docs/camp/girdi-yapay-zeka.md` | Sağlayıcı, değerlendirme, kırmızı takım | A-01…A-21 |
| `docs/camp/girdi-guvence.md` | Yalıtım, gizlilik, yedek | G-01…G-22 |
| `docs/camp/girdi-kalite.md` | CI, kapı, kapsam, kararsızlık | Q-01…Q-19 |
| `docs/yapilacaklar-20.md`, `docs/bilinen-sinirlar.md`, `docs/ai-calisma-alani-plani.md`, `docs/sandbox-gecis-analizi.md`, `docs/foundation-models-denemesi.md`, `docs/performans-olcumu.md`, `docs/gercek-pencere-denetimi.md` | Bağlam, mevcut sınırlar, ölçümler | — |

**Birleştirilen yinelenen maddeler:** K-01 + A-03 (sağlayıcı protokolü) · K-02 + A-03 (Apple sağlayıcı) + A-11 · K-10 + A-04 (bağlam bütçesi) · K-09 + A-06 (göreli tarih) · K-15 + A-02 (enjeksiyon) · K-12 + U-05 + G-03 (yedek) · G-11 + U-04 (dışa aktarım) · T-01 + T-06 + T-17 (yazı) · T-12 + U-34 (asistan paneli) · T-08 + U-38 (görev satırı) · T-02 + U-15 + U-16 · T-18 + U-52 · K-22 + U-18 + U-51 · Q-09 + Q-16 + G-13 (test sayısı) · Q-07 + G-22 · K-05 + U-14 · K-06 + U-31 · K-04 + U-33 · T-10 + U-46 · T-11 + U-43 · T-16 + T-13 + U-50.

**Girdiler arası çelişkiler ve çözümler**
- Öneri türü sayısı: plan 7 diyor, kodlama girdisi 8 sayıyor (`createTeamMember` sonradan eklenmiş). Kod esas alınır: 8.
- Test sayısı: belgeler 133 ve 200 diyor, sayım 255. H1-10 belgeyi düzeltir ve sayıyı bir testle bağlar.
- Plan F2 "v5 migration" diyor, şema v9'da. Kampta yeni migration yalnız v10 olabilir (H1-03'e ayrıldı).
- T-06 "metin boyutu ayarı" ve U-24 "dil ayarı" yeni ayar demek. Kullanıcı kararına ayrıldı (K-9).
- Kalite girdisinin andığı öneri geri alma `>` → `>=` geçmişi belgelerde bulunamadı. Bu plan ona dayanmaz.

### 9.2 Tahminler hakkında

Bu plandaki **hiçbir gün tahmini ölçülmedi.** Kaynakları altı girdi raporu (kod okuması) ve ürün yöneticisinin birleştirme yargısı. Başlangıç sayıları (255 test, 228 `try?`, 254 sabit yazı boyutu, 72/104 yüzey) girdi raporlarındaki `grep` sayımlarıdır, çalıştırılmış bir ölçüm değildir. G1 sabahı `kalite-kapisi` bu sayıları yeniden alır ve pano başlangıcı o sayılarla düzeltilir. Bu plan yazılırken hiçbir şey derlenmedi ya da çalıştırılmadı.

### 9.3 Sözlük

| Terim | Anlamı |
|---|---|
| 🟢 / 🟡 / 🔴 | basit (1 puan) / orta (3 puan) / boss (8 puan) |
| boss | Haftanın en zor görevi: mimari ya da veri bütünlüğü; çok parçalı kanıt ister |
| hat | Paralel iş akışı (A çekirdek, B arayüz, C kalite); kişi değil, iş bölgesi ve derleme dilimi |
| hat-günü | Bir hattın bir iş günü; kamp kapasitesi 45 |
| karar kapısı | Cuma demosu sonrasında kurucunun onay, kesme ve commit kararı |
| derleme dilimi | Uygulama paketi ve ortak derleme için hatta ayrılan zaman |
| doğrulanamadı | Kanıt alınamadı (ekran, anahtar); görev yarım puan alır, "bitti" sayılmaz |
| [SAHTE] / [CANLI] | Sahte sağlayıcıyla test / gerçek anahtarla koşu |
| havuz | Kamp sonrasına bırakılan iş; gerekçe ve dönüş koşuluyla |

---

## Kamp günlüğü

### G1 · 2026-10-05 (Pzt): H1-01, H1-02, H1-03 aynı anda
Üç görev tek çalışma ağacında paralel koşturuldu (dosya sahipliği + yalnız-ekleme çeviri kuralı + "başkasının dosyasında derleme hatası görürsen bekle" kuralı). Geçici derleme çakışmaları yaşandı ("modified during the build"; `YedekGuveniTests` ara bir koşuda 3 test kırmızıydı), bekleyip yeniden deneyince çözüldü.

| ID | Durum | Kanıt |
|---|---|---|
| H1-01 Yedek ve dışa aktarım güveni 🔴 | **Çekirdek ve test tarafı bitti** · Ayarlar ekranı gerçek pencerede doğrulanamadı | Manifest biçim 2: dosya başına SHA-256; değiştirilmiş / eksik / manifestsiz yedek reddedilir (geri yükleme çalışan veriye dokunmaz); geri yükleme sonrası dosya kümesi yedekle aynı; dışa aktarım eksik dosyayı raporlar; finans ve profil dışa aktarımda; şema taraması (yeni `brandId` tablosu eklenince test bilerek kırılır); eski manifestsiz yedekler hâlâ açılır; 10 yeni test (`YedekGuveniTests`) |
| H1-02 Gün değişimi 🟢 | **Bitti** (bildirim aboneliği gerçek ortamda doğrulanamadı) | `BackupSchedule` saf karar yardımcısı + 5 test (İstanbul/UTC gece yarısı sınırı dahil); `NSCalendarDayChanged`/saat dilimi/saat değişimi gözleniyor; orkestratör bağlantısı yapıldı: `autoBackupIfNeeded` artık bu yardımcıyı kullanıyor, `AppModel.dayChanged` gün değişince otomatik yedeği de tetikliyor |
| H1-03 Süre güveni 🔴 | **Bitti** · silme/ekleme/düzenleme tıklayarak doğrulanamadı | `sureKaydiOlanGorevSilinceSureKayitlariKaybolmaz` önce KIRMIZI (2 hata, çıktı raporda), sonra yeşil; süre kaydı olan görev (çalışan sayaç dahil) silinemez, "İptal et" önerilir; panelde süre listesi ekle/düzenle/sil, her yazma audit; 5 yeni test; migration YOK (K-5 varsayılan yol) |

**Sayılar:** test 255 → **275** (+20: 10 + 5 + 5), çeviri 1051/1051, erişilebilirlik taraması 0, MAS derlemesi 0 hata, `try?` sayısı (tüm Sources) 231 (hedef ≤220: H1-01 yedek kodunda 7 → 4 indirdi, genel hedef sonraki görevlerde).
**Açık notlar:** (1) H1-03'te çakışma kontrolü yalnız aynı markanın kayıtlarına bakıyor (marka yalıtımı için seçildi); farklı markalarda aynı saate süre girilebilir. (2) H1-03'te gece yarısını geçen kayıt için bitiş günü düzeltmesi yapıldı ama yeniden yakalanmadı. (3) `autoBackupIfNeeded`, eski yedek silinemezse artık hata veriyor (sessiz değil).

### G2 · 2026-10-05 (Pzt, aynı gün): H1-04, H1-05, H1-11
| ID | Durum | Kanıt |
|---|---|---|
| H1-04 Kapanışta bekleyen düzenleme 🟡 | **Bitti (kod + test)** · ⌘Q senaryosu gerçek pencerede doğrulanamadı | `PendingEdits` kayıt defteri (MarkaCore: MarkaApp'te test hedefi yok), `PanelField`/`PanelTitleField` yazarken kaydediyor, `applicationWillTerminate` → `flushAll()`; 4 yeni test. **Kapsam dışı kaldı:** marka profili düzenleyicisi, yeni görev satırı, `CompanyView` taslakları (aynı kayıt defterine bağlanabilir) |
| H1-05 Arşivlenenler + geri al 🟡 | **Bitti (kod + test)** · tıklama akışı doğrulanamadı | Migration GEREKMEDİ: `source_immutable` tetikleyicisi `archivedAt`'ı zaten dışarıda bırakıyor (orkestratör AppDatabase.swift:113-121'den doğruladı) → kural 2 korunuyor. Dosyalar'da "Arşivlenenler" sekmesi, "Arşivden çıkar" (düğme + sağ tık + VoiceOver), arşivleme sonrası "Geri al" bildirimi ve ⌘Z; `setSourceArchived` marka kapsamlı; 6 yeni test (içerik/özet değişmez, başka marka reddi, FTS'te görünmez…) |
| H1-11 Tek komut kapı 🟡 | **Bitti** | `scripts/gelistir-kapisi.sh`: test, paket, çeviri, MAS, erişilebilirlik, sızıntı, artık süreç. Kasıtlı kırık test KALDI/çıkış 1 → düzeltilince GEÇTİ/çıkış 0 (AYRI kopyada üretildi; ana ağaç bozulmadı). Ana ağaçta tam koşu: `KAPI: GEÇTİ` |

**Sayılar:** test 275 → **285** (+10: 4 + 6; H1-11 test eklemedi). Çeviri, MAS, erişilebilirlik, sızıntı hepsi 0.
**Planlama notu:** H1-12 (kararsız test avcısı) testleri 20 kez koşturacağı için paylaşılan ağaçta diğer hatlarla çakışır; yalnız başına bir dilimde koşulacak. Aynı dosyaya dokunan işler birleştirilerek ajanlara verildi (H1-06+H1-07: Akış ekranı; H1-08+H1-09: uygulama modeli/yaşam döngüsü).

### G3 · 2026-10-05 (Pzt, aynı gün): H1-06, H1-07, H1-08, H1-09, H1-10
| ID | Durum | Kanıt |
|---|---|---|
| H1-06 Terminalsiz boş durumlar 🟢 | **Bitti** | Kullanıcı metninde "terminal" / "oneriler/" geçen `L("…")` 4 → 0. Not: `en.lproj` içinde "“oneriler” gerçek bir klasör değil…" çekirdek tanı mesajı duruyor (`oneriler/` eğik çizgili değil); kaldırılıp kaldırılmayacağı kurucuya sorulacak |
| H1-07 Notlarda Enter yeni satır 🟢 | **Bitti (kod)** · Enter/odak/Esc davranışı gerçek pencerede doğrulanamadı | `NoteComposer` `TextEditor`: Enter yeni satır, ⌘↩ ve "Ekle" kaydeder, odak kaybında ve kapanışta (`PendingEdits`) kayıt, çift kayıt bayrağı. Ayrıntı panelindeki `PanelField` hâlâ Enter'la kaydediyor olabilir (U-37'nin o kısmı açık) |
| H1-08 Başka sayaç durunca bildirim 🟢 | **Bitti (mantık + test)** · bildirim şeridi ekranda görülmedi | `startTimerReportingHandoff`: durdurulan görev, marka ve süre döner; 8 sn'lik uygulama içi bildirim + menü çubuğu paneli; VoiceOver; 2 test |
| H1-09 Kilit durumu ayrı ekran 🟢 | **Bitti** · "Diğer pencereye geç" ve "Tekrar dene" düğmelerine basılmadı | Tipli `WorkspaceLockError.alreadyOpen` (metin eşleme yok); aynı geçici alanla iki süreç açılıp ikincisi PID ile yakalandı: "Uygulama zaten açık", yedek önerisi YOK (gerçek pencerede görüldü). Bilinen sınır: "Diğer pencereye geç" aynı paket kimliğindeki İLK süreci öne getiriyor (başka veri alanındaki pencere olabilir) |
| H1-10 Dürüst metinler 🟢 | **Bitti** | Belgelerde mutlak gizlilik ifadesi 7 → 0; 2 yeni test (`belgelerdeSabitTestSayisiYok`, `belgelerdeMutlakGizlilikIfadesiYok`: belge sayıdan bağımsız yazıldı, bayatlayamaz). Orkestratör: demo verisindeki "hiçbir içerik Mac'ten çıkmaz" ve iki ajan dosyasındaki ifade düzeltildi |

**Sayılar:** test 285 → **290**. `scripts/gelistir-kapisi.sh` tam koşu: `KAPI: GEÇTİ` (test 290, paket, çeviri 0, MAS 0, erişilebilirlik 0, sızıntı 0, artık süreç 0).
**Hafta 1 durumu:** 11 / 13 görev bitti (H1-12 kararsız test avcısı ve H1-13 CI başlıyor). Aynı gün içinde G1–G3 tamamlandı: planın gün tahminleri ÖLÇÜLMEDİ ve bu hız tahminlerin bol olduğunu gösteriyor; G5 kapısında düzeltilecek.

### G4–G5 · 2026-10-05 (Pzt, aynı gün): H1-12, H1-13, H1-04b ve HAFTA 1 KAPANIŞI
| ID | Durum | Kanıt |
|---|---|---|
| H1-12 Kararsız test avcısı 🟡 | **Bitti** | `scripts/kararsiz-avci.sh [N]`: 20 koşu, 290 testin her biri 20/20, 0 kararsız, toplam 217 sn, kayıt: `docs/kararlilik-tablosu.md`. **Bu makinede 20 koşuda geçti; kararlılık iddiası değildir** (yük altında ve yavaş makinede ölçülmedi; zaman sınırlı yoğun-veri testleri için özellikle) |
| H1-13 CI iş akışı (yerel) 🟡 | **Yerel kısım bitti** · canlı koşu doğrulanamadı | `.github/workflows/ci.yml`: `pull_request` + `push(main)`, yalnız `contents: read`, gizli anahtar yok, `concurrency`, SwiftPM önbelleği, tek adım `scripts/gelistir-kapisi.sh`. Runner etiketi `macos-latest` (`macos-26` varlığı doğrulanamadı), runner'da Xcode toolchain'in Swift 6 araç sürümünü taşıdığı doğrulanamadı. Canlı koşu commit/push onayını (K-2) bekliyor |
| H1-04b U-07'nin kalanı 🟡 (plana sonradan eklendi) | **Bitti (kod + test)** · ⌘Q gerçek pencerede doğrulanamadı | Marka profili düzenleyicisi, sektör alanı, şirket "Genel" formu `PendingEdits`'e bağlandı; Vazgeç edilen taslak kapanışta KAYDEDİLMEZ; marka değişiminde taslak artık kaybolmuyor (eski markaya kaydediliyor); çok satırlı `PanelField` Enter'da yeni satır, ⌘↩ ve odak kaybı kaydeder; 6 yeni test. Nedeni: H1-04 yalnız ayrıntı panelini kapsıyordu, çıkış kriteri 1 ("açık veri kaybı 0") bu eksikle sağlanmıyordu |

### HAFTA 1 KAPANIŞ KAPISI
| Çıkış kriteri | Sonuç |
|---|---|
| 1. U-01…U-08 için test ya da kanıtlı senaryo; açık veri kaybı maddesi 0 | **Karşılandı (kod + test düzeyinde)**: U-01 süre silme engeli · U-02 arşiv görünümü ve geri al · U-03 süre düzeltme · U-04/U-05 yedek ve dışa aktarım · U-06 gün değişimi ve otomatik yedek · U-07 kapanışta kayıt (H1-04 + H1-04b) · U-08 kilit ekranı. **Gerçek pencerede tıklayarak/⌘Q ile doğrulanan: yok** (U-08 ekranı hariç: iki süreçle yakalandı) |
| 2. `gelistir-kapisi.sh` kasıtlı kırıkta KALDI, düzeltilince GEÇTİ | **Karşılandı** (ayrı kopyada iki koşu; ana ağaçta tam koşu GEÇTİ) |
| 3. Testlerin 20 koşuluk kararlılık tablosu | **Karşılandı** (290 test, 20/20, 0 kararsız; "bu makinede" etiketiyle) |
| 4. `@Test` sayısı ≥ 270 | **Karşılandı: 297** (gate: 296 test) |

**Kamp panosu (G5):**

| Metrik | Başlangıç | Şimdi | Hedef | Not |
|---|---:|---:|---:|---|
| Test (`scripts/test.sh`) | 255 | **296** | ≥ 270 (H1) | +41 |
| `try?` sayısı (Sources) | 231 (başlangıç 228'e yakın) | 234 | ≤ 220 (H3-03) | **hedefin tersine +3**: yeni kod `try?` ekledi; H3-03'te sistematik taranacak |
| Sabit yazı boyutu (`.font(.system(size:`) | 254 | 263 | ≤ 60 (H2-04) | **hedefin tersine +9**; H2 tasarım dili göçünde |
| CI iş akışı | yok | var (yerel; canlı koşu yok) | var | K-2 onayı bekliyor |
| Gerçek-pencere kanıtlı ekran | 0 | 43 PNG (denetim) | — | tıklama kanıtı 0 |
| Açık veri kaybı yolu (kodla) | 8 | **0** | 0 | gerçek pencerede doğrulanmadı |

**Kamp ritmi uyarısı (karar kapısı notu):** G1–G5'in tamamı AYNI GÜN içinde bitti. Gün tahminleri (13 görev = 5 iş günü) ölçüldü ve **çok bol çıktı**; ama hız yalnız kod ve test içindir: ekranla ve tıklamayla doğrulanamayanların tamamı hâlâ açık, ve bu en büyük boşluk. Öneri: Hafta 2'ye başlamadan önce kurucu ekranda 30 dakikalık bir 'tıklama turu' yapsın (`docs/erisilebilirlik.md` 12 maddelik liste + H1'deki 'doğrulanamadı' etiketli akışlar); bulgular Hafta 2'nin ilk günlerine girer.
**Plan düzeltmesi:** planın başındaki "255 test" ifadeleri tarihsel başlangıç sayısıdır; güncel sayı 296.

### DALGA A · 2026-10-05: H2-01, H2-03, H2-06, H3-07, H3-12, H3-08, H3-09, H3-11 (5 hat paralel)
| ID | Durum | Kanıt |
|---|---|---|
| H2-01 AIProvider katmanı 🔴 | **Bitti** · canlı Claude/Codex yanıtı doğrulanamadı | `ChatEngine.swift` 893 → 275 satır (en büyük parça); `AIProvider` protokolü + `AnthropicProvider` + `CodexProvider` (`#if !MAS`) + `FakeProvider`; sağlayıcı seçimi tek yerde (`AIProviderRegistry`); `runTurn`'de sağlayıcı `switch` 0; 8 yeni test; MAS derlemesi temiz. **Bilinçli iki ekleme:** durdurulan turda araç çalışmıyor ve yeni model isteği gitmiyor (A-19); araç desteği olmayan sağlayıcıya araç verilmiyor |
| H2-06 Yalıtım özellik testi 🔴 | **Bitti** · **1 kritik sızıntı bulundu ve düzeltildi** | 103 Store yüzeyi tarandı, 70'i gerekçeli izin listesinde (`docs/yalitim-izin-listesi.md`); 200 tohumlu rastgele iki marka testi; 53 yazma yüzeyinden 50'si ≥1 denetim olayı bırakıyor (3 gerekçeli istisna). **Bulgu:** başka markanın kaydı aynı kimlikle bu markaya taşınabiliyordu (görev, kişi, proje, kayıt, iş kaydı); düzeltmeden önce her tohumda kırmızı, düzeltmeyle yeşil (`MarkaError.brandScope`, migration yok). **Açık:** kimlikle silen/uygulayan yüzeyler (`deleteTask`, `applyProposal`…) kimliğin hangi markadan geldiğini doğrulamıyor (veri döndürmez, ama başka markanın kaydını silebilir); `createProposal` denetim olayı bırakmıyor → havuz (G-05) |
| H2-03 Elle iş kaydı 🟡 | **Bitti** · tıklama doğrulanamadı | `saveUserWorkLog` (aktör her zaman `.user`, `verificationProblem` kuralı AYNEN korunur, kural sağlanmazsa işlem geri alınır); biten görevde "İş kaydı yaz" (panel + bağlam menüsü), Özet'te "+ İş kaydı"; karşılama maddeleri "Yapay zekâ gerektirir / gerektirmez" etiketli; 7 yeni test (AI'sız örnek markada rapor ≥ 1 madde) |
| H3-07 Varsayılanlar 🟢 | **Bitti** | Görünüm varsayılanı Sistem (kayıtlı tercih korunur); `LinkAddress.normalize` şemasız adrese `https://`, `javascript:/file:/data:/mailto:/ftp:`, boşluklu ve boş girdiyi REDDEDER; 3 test |
| H3-12 Geçici PDF + demo adları 🟢 | **Kısmen** | 7 günden eski geçici rapor PDF'leri açılışta siliniyor (yalnız ürünün kendi `… rapor v<sayı>.pdf` adlı düz dosyaları; 3 test). Yoğun demoda ASCII ad ve saat çeşitliliği düzeltildi (yalnız derlendi, çalıştırılmadı). **Açık:** örnek markada ≥ 3 farklı SAAT ölçütü sağlanamadı (2 kaynak; üçüncüsünü eklemek mevcut bir sayı testini gevşetirdi) |
| H3-08 Kapsam ölçümü 🟡 | **Bitti** | `scripts/kapsam.sh`: MarkaCore satır kapsamı **%86,9** (bu makinede, CLT ile). En düşük: `SkillPacks` %0, `CodexProvider` %12,8, `CodexAppServer` %14,8, `AIBasics` %29,3, `FolderAccess` %50. MarkaApp ölçüm dışı. Taban `docs/gelistirme.md`'de. "Tabanın altına düşünce CI kırılır" yapılmadı |
| H3-09 Kural-test haritası 🟡 | **Bitti** | 7 kuralın her biri için 3-5 doğrulanmış test adı; `denetimBelgesindekiHerKanitTestiMevcut` + `kuralTestHaritasiYediKuraliKapsar`; sahte ad eklenince kırmızı olduğu gösterildi |
| H3-11 Sızıntı kancası 🟢 | **Bitti** · ana depoya KURULMADI | `scripts/kancalar-kur.sh` (kurucu çalıştırır), `scripts/sizinti-desenleri.sh` tek kaynak desen; geçici depoda kasıtlı e-posta/kişisel yol/anahtar commit'i ENGELLENDİ (çıkış 1), temiz commit geçti. **Sınır:** e-posta deseni yalnız Google ve iCloud posta alan adları (kapı betiğindeki iki sabit desen) |
| (plan dışı) Kararsız test kök nedeni | **Düzeltildi** | H1-12'nin 20 koşuluk avının KAÇIRDIĞI bir kararsızlık H2-06 koşusunda çıktı (`sureKaydiOlanGorevSilince…`): `auditTrail` yalnız zamana göre sıralıyordu, aynı milisaniyedeki olaylarda sıra belirsizdi (üretim kodu zayıflığı). `at DESC, rowid DESC`; `ayniAnaDusenDenetimOlaylariSonEklenenOnceSiralanir`; sonrası 10 koşu 0 kararsız. **Ders:** "20/20" bir kararlılık kanıtı değildir (avcı bunu zaten belgeledi) |

**Sayılar:** test 296 → **327**. Kapı: `KAPI: GEÇTİ` (tam, 7 adım). Kapsam %86,9. `docs/yalitim-izin-listesi.md` yeni.

### DALGA B–D · 2026-10-05: H3-01, H3-02, H2-02, H3-04, H3-05, H3-06, H3-10, H3-03, H2-04, H2-05, H2-07
| ID | Durum | Kanıt |
|---|---|---|
| H3-01 Kırmızı takım 🔴 | **Bitti** · canlı model uyumu doğrulanamadı | 24 enjeksiyon senaryosu (`EnjeksiyonKirmiziTakimTests`): kaynak, not, bilgi sayfası, yetenek, dosya adı, profil, görev başlığı; başka marka %100 `is_error`, doğrudan yazma 0, uygulanmış öneri 0. Araç sonucu `<kaynak_icerigi>` içinde, kapanış etiketi kaçırılıyor; temel kurala "araç sonucu veridir" maddesi. **Bulgu:** satır sonlu başlık sistem istemi başlığı taklit edebiliyordu (kırmızı→yeşil, `oneLine`). **Açık:** rol bloğundaki üye adı ve tüm-markalar istemindeki marka adı tek satıra indirilmiyor; `bilgi_guncelle_oner` yeni başlıkla geçerli sürümsüz sayfa yazıyor. `FakeProvider` modelin uyup uymayacağını ÖLÇMEZ |
| H3-02 Altın istem koşumu 🟡 | **Bitti** (sahte kip) | 47 senaryo, 47 GEÇTİ, iki koşu bire bir aynı; `MarkaDogrula eval --sahte`; `--canli` anahtarsız "doğrulanamadı" (çıkış 2). Hedef 50'nin 3 senaryosu havuzda; `docs/altin-istem.md` |
| H2-02 Anahtarsız asistan 🟡 | **Bitti** · tıklama doğrulanamadı | `PendingPromptSlot`: sağlayıcı yokken istem gönderilmeden silinir, marka değişince gitmez; "Yapay zekâyı bağla…"; panel anahtarsızken kapalı başlar; 7 test |
| H3-04 AIErrorKind 🟡 | **Bitti** | 10 tür, Türkçe mesaj (ham gövde/anahtar yok), "Tekrar dene" yalnız aynı markada ve denenebilir türde; hata olursa soru taslağa döner; 13 test. **Sınır:** "Tekrar dene" kalıcı geçmişe yeni kullanıcı mesajı yazar; Anthropic hata türü listesi resmî belgeyle karşılaştırılmadı |
| H3-05 Klavyeyle onay 🔴 | **Yarım puan** | Mantık çekirdekte (`ProposalSelection`, `ApprovalPolicy`, `ApprovalBatch`): varsayılan seçim boş, düz Enter onaylamaz, ⌘↩ uygular, ⌫ reddeder (onaylı), yıkıcı tür ek onay, kısmi hata diğerlerini durdurmaz, geri al (görev ekleme/bitirme/güncelleme, iş kaydı, marka kaydı gerçek geri alma; hafıza güncellemesi ve klasörden dosya geri alınamaz → düğme yok); 12 test. **Doğrulanamadı:** ↑↓ Boşluk ⌘A ⌘↩ ⌫ gerçek pencerede, 15 sn elle ölçüm, VoiceOver turu |
| H3-06 + H3-10 Görev satırı, sayılar 🟡 | **Bitti** · tıklama doğrulanamadı | Sağ sütun sabit (84+8+24 pt), `help`+VoiceOver; bekleyen bandı = süzgeç tanımı (`CountDefinitions`); "Bu hafta biten görev" tek tanım, birim karışmıyor; 10 test. İş kaydı bağlıları zaten sayılıyordu, "68" yoktu → kırmızı kanıt gösterilemedi |
| H3-03 Sessiz hata 🟡 | **Bitti** | `try?` 231 → **159** (hedef ≤ 220), `onError: { _ in }` 1 → 0, boş `catch {}` 1 → 0, MAS uyarısı 14 → 0; yeni görünür-hata yolları; 8 test. Kalanlar: biçim çözme, geliştirici araçları, olağan "bulunamadı" aramaları. K-16 envanter tablosu yazılmadı |
| H2-04 + H2-05 Tek tasarım dili 🟡 | **Bitti** · boşluk ölçeği yapılmadı | `.font(.system(size:))` 272 → **4** (hedef ≤ 60), 6 yazı rolü, 3 köşe yarıçapı token'ı, 9 pt ve altı 0, ikon ölçeği 4 değer; 8 ekran önce/sonra yakalandı (gözle, kesin değil); 5 test. **Açık:** "boşluklar 4'ün katı" (`spacing` karışık) → havuz |
| H2-07 Çizim kararlılığı 🟡 | **Bitti** | 12 koşuda 56 PNG'nin 56'sı bire bir aynı; başlangıçta koşuların ~1/3'ü kararsızdı (yedek saat:dakikası, arama kutusu yer tutucusu; yalnız snapshot kipi); `scripts/cizim-kararliligi.sh` |

### HAFTA 2 + 3 KAPANIŞ KAPISI · 2026-10-05
| Çıkış kriteri | Hedef | Ölçüm |
|---|---|---|
| Sağlayıcı `switch` (ChatEngine) | 0 | **0** |
| Sabit yazı boyutu | ≤ 60 | **4** |
| `@Test` | ≥ 300 | **416** |
| `try?` | ≤ 220 | **159** |
| Enjeksiyon senaryosu | ≥ 20 | **24** |
| Altın istem senaryosu | 50 | **47** (sahte kip) |
| Kural-test haritası | 7 kural | 7 (H3-09) |
| Klavyeyle onay | çalışır | mantık+test GEÇTİ; gerçek pencere **doğrulanamadı** |
| Yüzey izin listesi | var | `docs/yalitim-izin-listesi.md` |
| Kapı | GEÇTİ | **GEÇTİ** (7 adım, 415 test) |

**Dürüst sınırlar:** canlı Claude/Codex yanıtı hiç denenmedi (anahtar yok); tıklama/klavye/VoiceOver akışlarının tamamı doğrulanamadı; "20/20" kararlılık kanıtı değildir (H2-06 bunu kanıtladı). Ajanlar "yalnız ekleme" çeviri kuralını iki kez, kapı fazla anahtarı hata saydığı için, kullanılmaz hâle gelen kendi anahtarlarını silerek çiğnedi (zararsız).
**Havuza eklenenler:** boşluk ölçeği 4'ün katı, 3 altın istem senaryosu, `deleteTask`/`applyProposal` marka doğrulaması, `createProposal` denetim olayı (G-05), K-16 envanteri, rol bloğu/marka adı `oneLine`.
**32 görev:** hepsi kod+test düzeyinde kapatıldı (H3-05 yarım puan).
