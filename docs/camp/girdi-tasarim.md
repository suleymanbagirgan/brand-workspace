# Tasarım Dev Camp: 3 hafta (2026-10-05)

Kaynak: belgeler (`tasarim-denetimi`, `tasarim-gelistirme-20*`, `gercek-pencere-denetimi`, `erisilebilirlik`), `Design.swift`, `grep` ölçümleri ve bugün alınan gerçek pencereler (`png2/`: flow-light, todo-light, files-dark, onay-dark; demo veri, geçici alan). PNG'ler depoya girmez.

**Bugün görülen (kanıt):** Görevler'de "C" rozeti ve ▶ etiketsiz, son satırda C yok, sütun kayıyor (todo-light) · Dosyalar küçük resimleri koyuda parlak ve aynı, adlar ASCII ("Musteri Referanslari") (files-dark) · onay satırları iki ayrı stilde, "Tümünü reddet…" düz metin (onay-dark) · sayfa sheet arkasında/pasifken "Ayarlar'ı aç" birincil düğmesi zeminde kayboluyor (onay-dark arka plan) · Asistan paneli bağlı değilken genişliğin ~%30'u boş · koyu modda kart nötr gri, sayfa lacivert · onay açılış odağı temiz (gp-5 doğrulandı).

## Haftalık temalar
- **1. hafta: "Tek dil"**: token sadeleştirme, kontrast, bekleyen kozmetik borç.
- **2. hafta: "Klavye ve durumlar"**: onay ritüeli, boş/yükleniyor/hata, odak.
- **3. hafta: "His"**: Liquid Glass/koyu bütünlüğü, hareket, ölçeklenebilir metin, ilk açılış.

## 🔴 Boss görevleri (6)

**T-01 Tasarım dili denetimi + token sadeleştirme.** Neden: `.font(.system(size:))` 254 kez (12:63, 11:61, 13:44, 10:23; 9 pt 2 kez: `CompanyView.swift:792`, `BrandProfileView.swift:216`; HIG asgarisi 10). `cornerRadius` 10 farklı değer (14×13, 7×10, 10×8, 6, 12, 8, 16, 3, 18); `spacing` 0/3/4/6/8/10/12/14 karışık; `Design.Space` 4 adım (`Design.swift:52-56`). Kabul: yazı ≤6 rol token'ı, yarıçap ≤3, boşluk 4'ün katı; 9 pt = 0; uygulanan ekran sayısı 8/8. 4 gün. Bağımlılık: yok (T-05'in önkoşulu). Doğrulama: `grep` sayımı + 8 ekran gerçek pencere açık+koyu.

**T-02 Onay ritüelini klavye-öncelikli akışa çevir.** Neden: `ProposalInbox.swift` yalnız ↩/Esc taşır (140, 143); satır gezintisi yok. Satırlar tutarsız (gp-7), "Tümünü reddet…" vurgusuz (gp-8, satır 133). Kabul: ↑↓ satır, Boşluk seç, ⌘↩ onayla, ⌫ reddet, ⌘A tümü; 6 öneri fareye dokunmadan ≤15 sn; tek satır stili; yıkıcı eylem kırmızı + onay iletişimi. 4 gün. Bağımlılık: T-01. Doğrulama: gerçek pencere (`flow … onay`) + elle kronometre + VoiceOver.

**T-03 Boş / yükleniyor / hata durum sistemi.** Neden: `EmptyStateView` 21 çağrı, `ReadErrorView` 2 ekranda; uygulamada tek `ProgressView` (`AIChatPanel.swift:246`). Rapor üretimi/uzun iş ilerleme-iptal yok (denetim HIG #4). Kabul: her bölüm (6 + Bugün + Stüdyo) için 4 durum = 32 hücrelik matris belgeli ve çizili; yükleniyor ≥300 ms ise iskelet, iptal düğmesi. 4 gün. Bağımlılık: T-01. Doğrulama: çizim (MARKA_SNAPSHOT) + gerçek pencerede hata (boş geçici alan).

**T-04 Liquid Glass ve koyu mod bütünlüğü.** Neden: koyuda kart/sayfa iki gri aile (gp-27, bugün flow-dark/onay-dark'ta da var); pasif pencerede `glassProminent` düğme kayboluyor (onay-dark arka planı, `Design.swift:561`); kâğıt koyuda parlak (gp-26). Kabul: yüzey tonları tek aileden (`Palette.darkSurfaces`); pasif pencerede birincil düğme metin kontrastı ≥4.5:1; Artırılmış Kontrast açıkken 8 ekran çizili. 3 gün. Bağımlılık: T-01. Doğrulama: gerçek pencere açık+koyu+pasif, piksel ölçümüyle kontrast.

**T-05 Hareket dili + Hareketi Azalt.** Neden: `accessibilityReduceMotion` 7 dosyada; `NotchTimer.swift:81` `repeatForever` nabız ve `AIChatPanel.swift:144` kaydırma animasyonu bu denetim olmadan. Kabul: 3 süre token'ı (ör. 0.12/0.2/0.35) ve 2 eğri; tüm `withAnimation`/`.animation`/`.transition` (11 yer) Hareketi Azalt'ta anında; sürekli animasyon 0. 3 gün. Bağımlılık: T-01. Doğrulama: `grep` + Ayarlar › Erişilebilirlik açık/kapalı gerçek pencere elle.

**T-06 Ölçeklenebilir metin: 254 sabit boyut göçü.** Neden: `erisilebilirlik.md` "Dynamic Type… 254 sabit boyut". macOS'ta Dynamic Type yok (HIG notu, `tasarim-denetimi.md`), ama anlamsal yazı stilleri + uygulama içi metin boyutu ayarı yapılabilir. Kabul: `.font(.system(size:))` 254 → ≤20 (gerekçeli istisna yorumuyla); Ayarlar'da 3 kademe metin boyutu; en büyük kademede 8 ekranda kesilme 0. 5 gün. Bağımlılık: T-01. Doğrulama: `grep` + gerçek pencere 3 kademe.

**T-07 İlk açılış "sihir" anı.** Neden: `OnboardingView.swift:13-60` statik metin listesi (4 madde, 440 pt); örnek markayla açılınca karşılama yok. Kabul: ilk açılıştan ilk onaya ≤3 adım ve ≤60 sn; örnek veride önceden hazır 1 öneri onay sayfasında "ilk onayını ver" olarak açılır; Hareketi Azalt'ta animasyonsuz. 4 gün. Bağımlılık: T-02, T-05. Doğrulama: gerçek pencere (boş geçici alan) + elle akış.

## 🟡 Orta (9)

**T-08 Görev satırı sağ sütunu.** gp-11, todo-light: "C" ve ▶ etiketsiz, C yoksa hiza kayıyor. Kabul: sabit sütun, `help` + VoiceOver etiketi 2/2, satırlar arası x farkı 0 pt. 1 gün. Bağ: yok. Gerçek pencere.

**T-09 Görev ayrıntı paneli.** gp-16/17: yinelenen yer tutucu, `Durum` menü gibi görünmüyor, tarih biçimi "3.10.2026" vs "3 Eki", sınır/gölge yok. Kabul: tek tarih biçimi, Picker oku, panel sol ayırıcı. 2 gün. Bağ: T-01. Gerçek pencere `todo … panel`.

**T-10 Gantt/takvim düzeni.** gp-12/13/14: filtre çubuğu kayboluyor, "Bugün" çizgisi yok, ay dışı gün tutarsız, geçmiş tarih kırmızı değil. Kabul: 4 bulgu kapalı. 2 gün. Gerçek pencere `todo … gantt|calendar`.

**T-11 Dosya türü ayrımı.** gp-2, ikinci tur #15, files-dark: tüm küçük resimler aynı açık gri. Kabul: ≥5 tür simgesi/rengi, koyuda küçük resim parlaklığı kısık; kart başlığı 2 temada görünür. 2 gün. Gerçek pencere açık+koyu.

**T-12 Asistan paneli bağlı değilken.** gp-28, flow-light: ~%30 genişlik boş durum; iki simge adsız. Kabul: bağlı değilken daralmış (≤56 pt) ya da kapalı başlar; simge etiketi 2/2. 2 gün. Gerçek pencere.

**T-13 Kompakt sayfa başlığı.** İkinci tur #16: 34 pt başlık ~120 pt dikey yer; files-dark'ta alt başlık "bağlant…" kesik. Kabul: kaydırınca başlık araç çubuğuna küçülür; kesik alt başlık 0. 2 gün. Bağ: T-01. Gerçek pencere.

**T-14 11 pt yardımcı metin kontrastı.** Bekleyen (#19/#13), `erisilebilirlik.md` "Kontrast ölçümü yok"; gp-4/17. Kabul: tüm `.secondary/.tertiary` metin ≥4.5:1 iki temada, ölçüm tablosu. 2 gün. Gerçek pencere + piksel ölçümü.

**T-15 Odak ve klavye gezintisi (Stüdyo, sheet'ler).** Bekleyen #16/#12; `erisilebilirlik.md`: Üye/Hizmet/Yetenek sayfalarında ilk alan odağı yok. Kabul: Tam Klavye Erişimi ile 8 ekranda her eylem Tab'la ulaşılır, odak halkası görünür. 2 gün. Elle.

**T-16 Marka Bilgileri tutarlılığı.** gp-18 (tekrar eden alanlar kaldı), gp-20 ("token" jargonu, kesik metin), gp-21 (ISO tarih karışık, metin düğmeler). Kabul: tek tarih biçimleyici, kesilme 0, jargon 0. 2 gün. Gerçek pencere `info`.

## 🟢 Basit (11)

| ID | Başlık | Kanıt | Kabul | Gün | Doğrulama |
|---|---|---|---|---|---|
| T-17 | 9 pt simgeleri 10+ yap | `CompanyView.swift:792`, `BrandProfileView.swift:216` | 9 pt = 0 | 0.5 | grep |
| T-18 | Demo veri Türkçe karakter + farklı saat | gp-30, #19; flow-light "Musteri Referanslari", hepsi 14:35 | ASCII ad 0, ≥3 farklı saat | 0.5 | gerçek pencere |
| T-19 | Bugün arama alanı hizası | #10/#15; onay-dark (Bugün) sağ üstte kopuk | başlık taban çizgisiyle hizalı | 0.5 | gerçek pencere |
| T-20 | Bugün/Özet satırlarına hover zemin | #14/#20 | 3 ekranda aynı `rowBackground` | 0.5 | elle hover |
| T-21 | Finans tahsil edilen satır | ikinci tur #17 | yalnız durum soluk, başlık ≥4.5:1 | 0.5 | gerçek pencere |
| T-22 | Pano başlık satırı ve sütun zemini | gp-15 | `lineLimit(2)` tutarlı, iki temada aynı zemin | 0.5 | `todo … board` |
| T-23 | Yetenek araç satırı | gp-23 ("SKILL.md içe aktar…" 2 satır) | tek satır, 3 düğme tek stil | 0.5 | gerçek pencere |
| T-24 | Ekip rozetleri ve şema genişliği | gp-24 ("Junior") | İngilizce rozet 0, kart eş genişlik | 0.5 | gerçek pencere |
| T-25 | Rapor düğme ve dönem seçici | gp-26 ("Taslak" vs "Hazır, PDF al") | "PDF al"; dönem `Menu` değer gösterir | 0.5 | gerçek pencere |
| T-26 | Araç çubuğu kilit ve "…" menü adı | gp-29 | 2/2 ipucu + VoiceOver etiketi | 0.5 | elle |
| T-27 | Sıralama/filtre tek vurgu | todo-light: "Sırala" vurgu renginde, "Tüm durumlar" siyah | iki denetim aynı renk (tek vurgu ilkesi) | 0.5 | gerçek pencere |

## Plan
- **H1:** T-01 (4g), T-04 (3g) + T-17, T-18, T-19, T-21, T-27, T-14.
- **H2:** T-02 (4g), T-03 (4g) + T-08, T-09, T-15, T-20, T-22, T-26.
- **H3:** T-05, T-06, T-07 + T-10…T-13, T-16, T-23…T-25.
Not: üç haftalık toplam (~62 gün iş) tek kişiye fazla; boss'lar paralel ajanla yürür ya da 🟢'ler kesilir.

## Doğrulanamayan / sınırlar
- Bu turda VoiceOver, hover, klavye ve dar pencere denenmedi; Gantt/Takvim/Pano/Finans/Rapor bugün yakalanmadı (gp-12…26 kanıtı 2026-10-04 tarihli).
- gp-3/4 (açılış odağı, rozet) bu yakalamalarda sorun görünmedi; pencere yakalanırken anahtar pencere değildi, rozet pasif durumu kesin ölçülmedi.
- Pasif penceredeki görünmez düğme (T-04) sistem `glassProminent` davranışı olabilir; kök neden doğrulanmadı.
- T-06'nın "metin boyutu ayarı" yeni ayar demektir; ürün yöneticisi onayı gerekir.
