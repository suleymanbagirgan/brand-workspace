# Beta 0.2.1 — Sadelik (yalnızca arayüz)

Tarih: 2026-09-18. Önceki: 0.2.0 (`3d4de86`). İlke: Dieter Rams / Braun — **"Weniger, aber besser" (daha az, ama daha iyi).**

## 1. Neden
Kurucu: *"Çok karışık geliyor, UI açısından elverişli değil. Çok basit bir kullanım hedefle, gereksiz her şeyi kaldır."*
Kurucunun gerçek çalışma biçimi: **AI terminalde çalışır; uygulama yapılanı gösterir, onayını alır, müşteriye rapor verir.** Elle görev/kayıt yazmak değil.

Kanıt (18 Eylül, gerçek veri + kod envanteri):
- Kurucunun kendi eliyle kullandığı: marka (7), kişi (3), kaynak (1). **Hiç kullanılmayan:** uygulama içi AI sohbeti (0 oturum), sayaç (0 süre), bilgi hafızası (0 sayfa), rapor (0), öneri (0).
- Arayüz: 172 düğme, 14 sheet türü, ~37 kavram (durum adlarıyla 60+), 26 yazı stili, 70 SF Symbol, 13 farklı boşluk değeri, 11 kutu stili.
- Tekrar: çalışma kaydı oluşturmanın 7, kaynak eklemenin 8, AI çağırmanın 6, öneri onaylamanın 3 yolu (3 farklı fiil).
- Ad karmaşası: "Kayıt" 5 anlamda; "Karar" 5 söyleyiş/2 anlam; "Hedef" 3 anlam; çalışma kaydının 4 adı; öneri kavramının 4 adı; sağlayıcıların 3-4 adı.

## 2. Tek cümlelik ürün
> **Bir markaya bakınca: ne yapıldı, ne bekliyor, müşteriye ne gidecek.**

Her ekran bu üç sorudan birine cevap veriyorsa kalır; vermiyorsa kalkar.

## 3. Rams ilkelerinin bu ürüne çevirisi
| İlke | Bu üründe |
|---|---|
| Kullanışlı | Yalnız "gör · onayla · raporla". Elle veri girişi ikincil. |
| Anlaşılır | Bir kavram = bir ad = bir yer. Kılavuzsuz anlaşılır. |
| Göze batmayan | Arayüz geri çekilir, içerik öndedir. Kart, rozet, renk süsü yok. |
| Dürüst | "Planlı gönderim" gibi yapmadığını ima eden ad yok. |
| Olabildiğince az tasarım | 4 yazı stili, 1 vurgu rengi, 4 boşluk değeri, tek köşe yarıçapı. |
| Titiz | Boş, yükleniyor, hata durumu her listede aynı biçimde. |

## 4. Yeni bilgi mimarisi
```
Kenar çubuğu                 Marka ekranı
─────────────                ────────────────────────────────────────────────
 Bugün                        Kuzey Lojistik                       [Terminal]  [···]
                              ┌──────────────────────────────────────────────┐
 Markalar                     │ 3 öneri onay bekliyor              İncele →  │  ← yalnız varsa
  Deneme Yangın           2    └──────────────────────────────────────────────┘
  Kuzey Lojistik                     Akış   Yapılacaklar   Rapor
  Örnek Kafe Zinciri
  …                            (seçili bölüm)
 + Marka
```
- **Kenar çubuğu:** "Bugün" + marka listesi (+ onay bekleyen sayısı). Başka hiçbir şey (sayaç şeridi ve öneri şeridi kalkar).
- **Marka ekranı: 3 bölüm** (bugün 5 sekme + İşler'in 3 alt sekmesi + Bilgi'nin 5 görünümü = 13 görünüm → 3).
  - **Onay bandı (üstte, yalnız varsa):** terminal + uygulama içi tüm öneriler **tek yerde**. Fiiller her yerde aynı: *Onayla · Reddet · Geri al*.
  - **Akış** — *ne yapıldı.* Günlere göre, en yeni üstte, tek satırlık öğeler: iş kaydı, biten görev, not, dosya, onaylanan öneri. Tıklayınca sağda ayrıntı. Doğrulanmamış iş kaydında satır içi tek tık *Doğrula*.
  - **Yapılacaklar** — *ne bekliyor.* Tek liste: açık görev + verilen söz + müşteriden beklenen karar + açık talep; son tarihe göre. Satır başında tamamla kutusu. Üstte tek satır "Ekle…".
  - **Rapor** — *müşteriye ne gidecek.* Bu haftanın raporu kayıtlardan canlı önizleme; *PDF* ve *E-posta*. Geçmiş raporlar tek açılır liste.
- **Marka ··· menüsü:** Bilgiler (profil, kişiler, projeler), AI izinleri, klasörü Finder'da göster, dışa aktar, arşivle.
- **Terminal paneli:** başlıkta yalnız ad + yer değiştir + kapat. BAGLAM.md kendiliğinden yenilenir; "Klasörden içe al" yerine klasör kendiliğinden taranır (öneri bandı + Akış'ta "yeni dosya" satırı).
- **Bugün:** tüm markalarda onay bekleyen, geciken, bu hafta yapılan. Tek arama (⌘F) burada.
- **Ayarlar: 4 sekme → 2:** *Genel* (Claude anahtarı, Codex girişi, terminal yalıtımı) · *Veri* (konum, yedek, arşiv, içe aktarım, "Tanı bilgisini kopyala").
- **İlk açılış: 3 adım → 1:** marka adı → bitti. Eski görev listesi içe aktarımı yalnız Ayarlar › Veri'de.
- **Menü:** ⌘0 Bugün · ⌘1 Akış · ⌘2 Yapılacaklar · ⌘3 Rapor · ⌘J Terminal · ⌘F Ara · ⇧⌘N Marka.

## 5. Kalkan / gizlenen (veri ve çekirdek korunur, geri getirilebilir)
| Kalkan | Neden | Verisi |
|---|---|---|
| Masa + uygulama içi AI sohbeti, "Tüm markalarla AI" | 0 kullanım; AI terminalde çalışıyor | Oturumlar DB'de kalır |
| Bilgi sekmesi (sayfa, iddia, katman, sağlık, kurallar, derleme) | 0 kullanım; en çok kavram yükü | Kalır; kurallar BAGLAM.md'ye girmeye devam eder |
| Sayaç, elle süre, sayaç şeridi, çalışma kaydı öneri şeridi | 0 kullanım; terminal işi bu olayları üretmiyor | Kalır; rapordaki "Harcanan süre" 0 ise görünmez |
| İşler › AI değişiklikleri, Bilgi › Onay bekleyen | Onay bandında birleşir | — |
| Planlı gönderim | Göndermiyor; adı yanıltıcı | Planlar kalır, çalışmaz |
| Kayıt türü seçimi (7 tür) elle girişte | Elle girişte yalnız Görev · Söz · Not | Hedef/teklif/sözleşme/tarih terminal önerisiyle gelir, Akış ve Bilgiler'de görünür |
| Rapor sürüm/paylaşım ayrıntısı, cümle cümle özet düzenleme | Tek açılır "Geçmiş" | Kalır |
| 4 ayrı arama alanı | Tek ⌘F | — |
| 7 "Finder'da göster" | Tek yer (··· menüsü) | — |
| Model ve düşünme derinliği seçimi | Uygulama içi AI yalnız rapor özetinde; sabit varsayılan | — |
| Ayarlar › Kullanım (maliyet) | Uygulama içi AI kalkınca anlamsız; beta ölçümleri "Tanı bilgisi"ne katılır | — |

## 6. Adlandırma sözlüğü (bir kavram = bir ad)
| Kavram | Tek ad | Bırakılan adlar |
|---|---|---|
| Ana ekran | **Bugün** | Genel Bakış |
| Yapılan iş kaydı | **İş kaydı** · durum: *Doğrulanmadı / Doğrulandı* | Çalışma kaydı, Kayıt, İş kaydı doğrulanır, Taslak |
| AI'ın önerdiği değişiklik | **Öneri** · *Onayla / Reddet / Geri al* | AI değişikliği, Onay bekleyen, Öneri oluştur, Uygula |
| Müşteriden beklenen | **Karar bekleniyor** | Beklenen müşteri kararı, Bekleyen kararlar, Müşteri kararı bekleyen… |
| Verilen söz | **Söz** | Verilen söz, Sözler |
| Dosya/not | **Dosya**, **Not** | Kaynak, Ham kaynak, İş çıktısı, Dayanak kaynağı |
| Sağlayıcılar | **Claude**, **Codex** | Anthropic (Claude API), OpenAI Codex — App Server (deneysel)… |
| Görev durumu | *Yapılacak · Sürüyor · Bekliyor · Bitti* | İptal elle seçilmez (menüde) |
Kavram sayısı hedefi: **≤ 12** (Bugün, Marka, Akış, Yapılacaklar, Rapor, Öneri, İş kaydı, Görev, Söz, Karar bekleniyor, Not/Dosya, Terminal).

## 7. Görsel dil (DESIGN belirteçleri)
- **Renk:** nötr gri tonlar (sistem) + **tek vurgu** (Braun turuncusu, mevcut AA uyumlu değerler). Vurgu yalnız: birincil düğme, onay bekleyen sayısı, seçim. Kırmızı yalnız *gecikmiş*. Yeşil/turuncu durum renkleri kalkar; durum metinle söylenir.
- **Yazı: 4 stil.** Başlık `title2.semibold` · Bölüm `headline` · Gövde `body` · Ek `caption` + `.secondary`. Eş aralıklı yalnız terminalde.
- **Boşluk: 4 değer** — 4 · 8 · 16 · 24. **Köşe:** tek değer 6 (yalnız giriş alanları ve bant).
- **Kutu yok:** kart, gölge, rozet kapsülü yok. Ayrım boşluk ve ince çizgiyle. Tek istisna onay bandı.
- **Simge ≤ 16.** Metin tek başına anlatıyorsa simge yok.
- **Düğme:** ekran başına en fazla bir birincil (`borderedProminent`); gerisi metin düğmesi. Satır eylemleri yalnız üzerine gelince.
- **Liste satırı:** tek satır · solda başlık · sağda tarih (ek stil) · gerekirse tek satır ikincil metin.

## 8. Kabul ölçütleri (ölçülür)
| Ölçü | Bugün | Hedef |
|---|---|---|
| Marka ekranındaki görünüm sayısı | 13 | 3 |
| `Button` (koddaki geçiş) | 172 | ≤ 70 |
| Sheet türü | 14 | ≤ 6 |
| Kavram | ~37 | ≤ 12 |
| Yazı stili | 26 | 4 |
| SF Symbol | 70 | ≤ 16 |
| Boşluk değeri (`spacing`/`padding`) | 13 / 14 | 4 |
| Öneri onaylama yeri | 3 | 1 |
| "Bugün ne yapıldı?" | 3+ tık, 2 ekran | markayı aç → Akış (1 tık) |
| Önerileri onayla | 2-4 tık, 3 yer | bant → Onayla (2 tık) |
| Haftalık rapor PDF | 4+ tık | Rapor → PDF (2 tık) |
- Sayımlar betikle yapılır (`scripts/ui-olcum.sh`: `grep` tabanlı; envanterdeki yöntem) ve plan kapanışında raporlanır.
- Mevcut 107 test geçer; `l10n.py check` temiz; kaldırılan metinler çeviri dosyasından da temizlenir.
- **Görsel kanıt:** her ekran açık/koyu çizilir. Önkoşul: snapshot aracının liste ve koyu bölmeleri boş çizme hatası (İ3 bulgu 2) düzeltilir.
- **Veri güvenliği:** migration yok, veri silinmez; kaldırılan her özelliğin verisi yerinde kalır (test: 0.2.0 verisiyle açılış, sayımlar aynı).

## 9. İş sırası
| # | İş | Ajan |
|---|---|---|
| U0 | Tasarım belirteçleri (`Design.swift` yeniden: 4 yazı, 4 boşluk, 1 vurgu) + snapshot aracının düzeltilmesi + `scripts/ui-olcum.sh` | swift-gelistirici |
| U1 | Kabuk: kenar çubuğu, marka başlığı ve ··· menüsü, 3 bölüm, menü/kısayollar; Masa/Bilgi/İşler ve şeritlerin kaldırılması | swift-gelistirici |
| U2 | Tek onay bandı (terminal + uygulama içi öneriler; `ProposalInbox` üzerine) | swift-gelistirici |
| U3 | Akış | swift-gelistirici |
| U4 | Yapılacaklar | swift-gelistirici |
| U5 | Rapor sadeleştirme | swift-gelistirici |
| U6 | Bugün + tek arama | swift-gelistirici |
| U7 | Ayarlar 2 sekme + 1 adımlı ilk açılış + terminal başlığı | swift-gelistirici |
| U8 | Metin sözlüğünün uygulanması, çeviri temizliği | swift-gelistirici |
| U9 | Bağımsız arayüz denetiminin düzeltmeleri (terminal oturumu, onay tek yerde, rapor, görsel dil, sözlük, ölçüm) — §12 | swift-gelistirici |
| D | Denetim: arayüz (çizimlerle), ölçüm betiği, demo akışı | arayuz-denetci |
U0 önce; U1 kabuğu kurar; U2–U7 kabuk üzerine; U8 ve D en son.

## 10. Kapsam dışı
Çekirdek/veri modeli değişikliği, yeni özellik, yeni AI yeteneği. (Akış ve Yapılacaklar için gereken salt okunur sorgular çekirdeğe eklenebilir; yazma yolu değişmez.)

## 11. Durum (U8 kapanışı, 2026-09-18)
Ölçüm: `scripts/ui-olcum.sh` (U8'de dürüstleşti: `.sheet(item:)` içindeki `switch` ile açılan sayfalar da sayılır; düğme toplamı menü öğelerini **içerir** ve ayrıca kırılır; `Design.Font` dışı yazı ve `.fontWeight` çeşitlemeleri listelenir). "Önce" 0.2.0 envanteridir; "U8 başı" U7 sonundaki koddur (`d24a040`), betiğin düzeltilmiş hâliyle.

| Ölçü | Önce (0.2.0) | U8 başı | Hedef | Sonra | Tuttu mu |
|---|---|---|---|---|---|
| Marka ekranındaki görünüm | 13 | 3 | 3 | 3 (Akış · Yapılacaklar · Rapor) | ✓ |
| `Button` (koddaki geçiş, toplam) | 172 | 107 | ≤ 70 | **69** = ekranda 47 + menü öğesi 12 + menü çubuğu 5 + diyalog 5 | ✓ (payı 1) |
| Sayfa türü (`.sheet`) | 14 | 7 (eski betik 4 diyordu) | ≤ 6 | **3** (onay sayfası, Bilgiler ve AI izinleri, iş kaydı düzenleyicisi); ayrıca 5 onay diyaloğu, 1 uyarı, 3 sistem paneli | ✓ |
| Kavram | ~37 | — | ≤ 12 | ana akışta 12; tüm ekranlarda 29 ad (aşağıda) | ana akış ✓, toplam ✗ |
| Yazı stili | 26 | 7 | 4 | 3 `.font` ifadesi (başlık, bölüm, ek) + varsayılan gövde = 4; seçim için 2 `.fontWeight` çeşitlemesi (sekme, kenar çubuğu) | ✓ (çeşitleme açıkça sayıldı) |
| SF Symbol | 70 | 4 | ≤ 16 | 4 (kutu: `square`, `checkmark.square.fill`; Ayarlar sekmeleri: `gearshape`, `externaldrive`) | ✓ |
| Boşluk değeri (`spacing`/`padding` sayısal) | 13 / 14 | 4 / 0 | 4 | yalnız `0` / 0 — hepsi `Design.Space` (4 · 8 · 16 · 24) | ✓ |
| Öneri onaylama yeri | 3 | 1 | 1 | 1 (onay sayfası; Bugün'deki "İncele" aynı sayfayı açar) | ✓ |
| "Bugün ne yapıldı?" | 3+ tık, 2 ekran | — | 1 tık | markayı aç → Akış: 1 tık (Akış açık bölümse; son seçilen bölüm korunur, değilse ⌘1 ile 2) | ✓ koşullu |
| Önerileri onayla | 2-4 tık, 3 yer | — | 2 tık | bant "İncele" → "Seçilenleri onayla": 2 tık | ✓ |
| Haftalık rapor PDF | 4+ tık | — | 2 tık | Rapor → PDF: 2 tık + sistem kaydetme panelinde "Kaydet" | ✓ (panel hariç) |
| Metin (`L(…)`) | — | 434 | — | 374 | — |
| Test | 107 | 124 | geçer | 125 geçti | ✓ |
| `l10n.py check` | — | temiz | temiz | eksik 0, fazla 0 (92 artık anahtar silindi), çoğul kuralı 19 | ✓ |
| Görsel kanıt | — | — | her ekran açık/koyu | 13 ekran × 2 = 26 PNG (`MARKA_SNAPSHOT`, geçici veri alanı) | ✓ (iş kaydı düzenleyicisi ve arama sonuçları çizilmiyor) |
| Veri güvenliği | — | — | migration yok | `Database/` ve `Model/` 0.2.0'dan (`3d4de86`) beri değişmedi; kaldırılan özelliklerin verisi yerinde. Ayrı "0.2.0 verisiyle açılış" testi **yazılmadı** | kısmen |

**Düğme kırılımı nasıl sayılır:** betik her `Button(`/`Button {` geçişini sayar (§8 toplamı). Geçiş `TextMenu`/`Menu`/`.contextMenu` bloğunun (ya da blokta adıyla anılan `var x: some View` gövdesinin) içindeyse "menü öğesi", `CommandMenu`/`CommandGroup` içindeyse "menü çubuğu", `.confirmationDialog`/`.alert` içindeyse "diyalog", değilse "ekranda" sayılır. Menüye taşımak toplamı düşürmez; toplam, ikinci yolları kaldırarak ve aynı kalıbı tek bileşende birleştirerek (ör. `StatusMenu`, `EditableRow`) düştü. Tek geçiş birden çok ekran düğmesi üretebildiği için betik düğmeli bileşenlerin çağrı sayısını da yazar (ör. `SettingsSection ×8`, `CheckBox ×6`, `TodayRow ×5`).

**Kavramlar (ekranda adı geçen, 29):**
- Ana akış (12, hedef): Bugün (kenar çubuğu, ⌘0) · Marka (kenar çubuğu, başlık) · Akış · Yapılacaklar · Rapor (sekmeler) · Öneri (onay bandı, onay sayfası, Akış "Öneri onaylandı") · İş kaydı (Akış, panel, Rapor) · Görev (Yapılacaklar, Akış) · Söz (Yapılacaklar, Akış) · Karar bekleniyor (Yapılacaklar, Akış, Bugün) · Not/Dosya (Akış) · Terminal (başlık, ⌘J).
- İkincil (17): Talep; Hedef · Teklif · Sözleşme · Önemli tarih (terminal önerisiyle gelen kayıt türleri, Yapılacaklar'ın altında); Bilgiler · Kişi · Proje (··· › Bilgiler); AI izinleri (Bilgiler); Bilgi güncellemesi / bilgi sayfası (onay sayfası ve Akış; yalnız eski veri ya da eski AI önerileri üretir); Sürüm · Paylaşım (Rapor › Geçmiş); Yedek · Arşiv (Ayarlar › Veri; dosya ve marka arşivi); Geri çekme (iş kaydı düzenleyicisi); Tanı bilgisi (Ayarlar › Veri).
- Sözlük (§6) uygulandı: "Kaynak" → Dosya/Not, "Çalışma kaydı" → İş kaydı, "Uygula/uygulanmış" → Onayla/onaylanmış, "Müşteri talebi" → Talep (tek ad; `todoTitle` birleşti), "Müşteriden beklenen" → Karar bekleniyor, "Anthropic" → Claude, "Genel bakış" kalktı. Çekirdekteki PDF başlıkları (ör. "Müşteri kararı bekleyenler") müşteriye giden belge olduğu için değişmedi.

**U8'de kalkan ikinci yollar:** kayıt sayfası (Bugün/arama/rapor dayanağı kaydı yerinde açar), "Klasördeki yeni dosyalar" sayfası (Akış'ta "Yeni dosya" satırları), ··· › Öneriler ve Klasördeki yeni dosyalar, ayrı AI izinleri sayfası (Bilgiler'e katıldı), yeni marka sayfası (kenar çubuğunda alan), onay sonrası "Geri al" adımı (Akış'tan), panel/terminal Kapat düğmeleri (Esc, boş yere tıklama, başlıktaki Terminal), not alanı Vazgeç'i, Rapor'daki üç metin düğmesi (··· menüsü), paylaşımdaki Finder düğmesi, kenar çubuğu sağ tık Arşivle, Yardım › Veri klasörü, Claude "Doğrula", düzenleyicideki "Kaydet ve doğrula", marka logosu (hiçbir yerde gösterilmiyordu).

**Açık kalanlar:** arayüz hiç tıklanarak/klavyeyle/VoiceOver ile denenmedi (Esc ile panel kapatma, odak, adlı erişilebilirlik eylemleri dahil) — `docs/elle-test-senaryosu.md` bunun için; toplam kavram sayısı 29; sürüm numarası 0.2.0'da.

## 12. U9 — bağımsız arayüz denetiminin düzeltmeleri (Durum, 2026-09-18)

Başlangıç: U8 sonu (`ce23ff5`). Yalnız arayüz: migration yok, çekirdek yazma yolları değişmedi. Çekirdeğe eklenenler salt okunurdur ya da saf mantıktır: `Store.flow` (açık söz/talep/karar satırı kalktı, kapanış satırı durumu taşır, iş kaydı bağlı biten görev gizlenir), `Store.todo` (yalnız görev + söz/karar/talep), yeni `Store.referenceRecords`, yeni `TerminalSessionCache` (görünümden bağımsız oturum yaşam döngüsü). Sürüm `0.2.1` (README satırı testle bağlı).

### Bulgular
| # | Bulgu | Durum |
|---|---|---|
| 1 (engelleyici) | Terminal oturumu marka/Bugün geçişi, ⌘J, "Terminal", "Yana al"da ölüyordu | **Düzeltildi.** Oturum (SwiftTerm görünümü + süreç) marka başına `AppModel.terminals`'da; `TerminalHost` önbellekteki görünümü kap içinde yeniden ebeveynler, sökülünce süreç öldürülmez. Süreç yalnız kabuktan çıkınca, arşivlemede ve kapanışta (tek soru) biter; sonlandırma SIGHUP → 2 sn → SIGKILL (etkileşimli kabuk SIGTERM'i yok saydığı ölçüldü). Yalıtım değişince açık oturum eski profilde, başlıkta tek satır. Saf mantık 5 testle (`TerminalOturumTests`); gerçek kabukla ekran dışı prova 12/12 (`MARKA_TERMINAL_PROVA`). Tıklanarak ve gerçek Claude oturumuyla denenmedi. |
| 2 | Onay sayfasında işareti kaldırılan öneri reddediliyordu | **Düzeltildi.** *Seçilenleri onayla* yalnız seçilenleri karara sokar, seçilmeyenler bekler; *Tümünü reddet…* ayrı ve onaylı. Kısmen onaylanan dosya: öğeler ilk taramada DB'ye yazılır, dosya `islenmis/`'e taşınır ve sha kaydedilir — bekleyenler kaybolmaz, dosya yeniden önerilmez (test `kismenOnaylananDosyaninBekleyenleriKalirDosyaYenidenOnerilmez`). Açıklama paragrafı ve dosya yolu kalktı; tek cümle; "Öncelik" yok. |
| 3, 13 | Rapor: müşteriye temiz PDF yolu, "Onayla" fiili, başlık, Geçmiş, uyarılar | **Düzeltildi.** Birincil düğme taslakta "Hazır, PDF al" (hazır işaretler + filigransız PDF), hazırken "PDF"; durum *Taslak / Hazır*; ··· yalnız Düzenle ve E-posta taslağı; başlık satırı tam genişlik, düğme sağ kenarda; kaydedilmiş raporlar dönem menüsünden Geçmiş'e taşındı (tek yer); uyarılar tek satır. |
| 4, 5, 6 | Onay tek yerde; Akış yalnız "ne yapıldı" | **Düzeltildi.** Klasördeki yeni dosyalar onay sayfasında "Dosyalar" grubu (bant ve kenar çubuğu sayısına dahil); Akış'taki "Yeni dosya · Ekle / Tümünü ekle" ve açılan söz/talep/karar satırları kalktı; kapanan kayıt "Söz · Bitti"; iş kaydı bağlı biten görev tek satır; satır içi *Doğrula* kalktı (yalnız panelde). |
| 7, 8 | Tek vurgu, tek ikincil düğme stili | **Düzeltildi.** `TextButtonStyle` (`.buttonStyle(.text)`: gövde rengi, üzerine gelince hafif zemin) tüm metin düğmelerinde; gri ve turuncu bağlantı biçimleri kalktı (panel bağlantıları altı çizili metin düğmesi). Vurgu: birincil düğme, onay sayısı, seçili sekme alt çizgisi, onay kutusu (seçim). "Terminal" açıkken seçili zemin alır. **Kalan istisna:** sürükle-bırak hedef çerçevesi vurgu renginde. |
| 9, 10, 25 | Görünür yollar | **Düzeltildi.** Panel başlığında "Kapat" (Esc ve boş yere tıklama da); Yapılacaklar panelinin altında "Sil…" (onaylı) ve "İptal et" (sağ tık menüsü ikinci yol olduğu için kalktı); yeni marka alanında "Marka adı — ↩" ve "Ekle". |
| 11, 12 | Dürüstlük | **Düzeltildi.** AI izinleri metni verilen cümle; Akış boş durumu `oneriler/` yolunu "isteyebilirsin" diye anlatır, vaat etmez (README'de denenmedi). |
| Sözlük | Bilgi güncellemesi, Bitti, Amaç, Ne kararlaştırıldı? | **Düzeltildi.** "Bilgi güncellemesi" → **"Hafıza güncellemesi"** (gerekçe: "Bilgiler" ile karışıyordu; önerilen "Marka notu" Akış'taki "Not" ile karışırdı; "hafıza" arayüzde başka hiçbir kavramda geçmez ve özelliğin ilk adıdır — "bilgi hafızası"). Kayıt durumu "Tamamlandı" → "Bitti"; proje "Hedef" → "Amaç"; "Hangi karar alındı?" → "Ne kararlaştırıldı?". |
| Sadelik | Panel satırları, ipuçları, "—", Hedef/Teklif, tür seçimi, boş durumlar, panel düğmeleri, hover, Ayarlar, düzenleyici | **Düzeltildi.** "Nereden geldi?/Ne önerildi?" kalktı; sürükle ipucu ve "Bitenler Akış'ta görünür." yalnız boş durumda; boş sütun boş; hedef/teklif/sözleşme/önemli tarih Bilgiler'de salt okunur liste; "Görev \| Söz" görünür seçim; tek `EmptyStateView` (sola hizalı) tüm listelerde; panel eylemleri içeriğin hemen altında; düzenlenebilir satır/alan üzerine gelince hafif zemin; Ayarlar › Veri'de "Geri yükle…"/"Arşivden çıkar" hep görünür, "cli-todo-for-agentic" → "eski görev listesi", "belirteç" → "giriş bilgi"; iş kaydı düzenleyicisi düz satır (artık ekran çizimine de giriyor). |
| Ölçüm | `onTapGesture` ve `TextMenu` ayrı kalem | **Düzeltildi** (aşağıda). |
| Sürüm | 0.2.1 | **Düzeltildi.** |

### Ölçüm (`scripts/ui-olcum.sh`; "U9 başı" `ce23ff5`'in kaynağı aynı betikle)
| Ölçü | U9 başı | Hedef | Sonra | Tuttu mu |
|---|---|---|---|---|
| `Button` geçişi (toplam) | 69 = ekran 47 + menü 12 + menü çubuğu 5 + diyalog 5 | ≤ 70 | **73** = ekran 52 + menü 10 + menü çubuğu 5 + diyalog 6 | **✗ (3 fazla)** |
| `onTapGesture` eylemi (düğme değil) | 8 | — | 8 (satır seçimi ×2, boş yere tıklayınca kapatma ×2, kutu etiketine tıklama ×4) | ayrı kalem |
| `TextMenu` tetikleyicisi | 5 | — | 5 (··· marka, durum, dönem, ··· rapor, düzenleyicide görev) | ayrı kalem |
| Eylem toplamı (Button + tap + TextMenu) | 82 | — | 86 | — |
| Sayfa türü | 3 | ≤ 6 | 3 (onay, Bilgiler, iş kaydı düzenleyicisi) | ✓ |
| Onay diyaloğu | 5 | — | 6 (+ Tümünü reddet) | — |
| Yazı stili / SF Symbol / boşluk | 3 `.font` + gövde / 4 / yalnız 0 | 4 / ≤ 16 / 4 | aynı | ✓ |
| Metin (`L(…)`) | 374 | — | 371 | — |
| Test | 125 | geçer | **133 geçti** (+5 terminal oturumu, +2 Akış/Bilgiler sorgusu, +1 kısmi onay) | ✓ |
| `l10n.py check` | temiz | temiz | eksik 0, fazla 0, çoğul kuralı 20 | ✓ |
| Görsel kanıt | 26 PNG | her ekran açık/koyu | 14 ekran × 2 = 28 PNG (iş kaydı düzenleyicisi eklendi) | ✓ |

**Düğme hedefi neden aşıldı:** denetim görünür yollar istedi ve bunlar eylem ekledi: panel "Kapat" (+1), panel "Sil…"/"İptal et" ve silme onayı (+3), yeni marka "Ekle" (+1), onay sayfası "Tümünü reddet" onayı (+1), "Görev \| Söz" seçimi (+1), Geçmiş'te diğer raporu açma (+1), terminal "Yeni oturum" (+1), düzenleyicide görev menüsü öğeleri (+2). Düşen: Akış'taki yeni dosya "Ekle"/"Tümünü ekle" ve satır içi "Doğrula" (−3), rapor ··· "Onayla" (−1), Yapılacaklar sağ tık menüsü ve onayı (−3, panelle aynı ikinci yol). Hedefi tutturmak için görünür eylem gizlenmedi; sadelik ölçütü sayı değil, her eylemin tek yeri olması.

**Açık kalanlar:** arayüz hâlâ tıklanarak/klavyeyle/VoiceOver ile denenmedi (senaryo `docs/elle-test-senaryosu.md`, §2 terminal oturumu); kapanış sorusu penceresi ve gerçek Claude Code oturumunun geçişte yaşaması denenmedi; terminal oturumu uygulama yeniden açılınca kurtarılmaz; aynı marka iki pencerede terminali açık gösterirse görünüm tek pencerede kalır; bant/kenar çubuğu sayısındaki dosyalar yalnız bu oturumda açılmış markalar için bilinir; `Button` toplamı 73 (> 70); toplam kavram sayısı 29 (+"Hafıza", −"Bilgi güncellemesi").

## 13. Kurucu kararı → 0.2.2 (2026-09-18)
- **Onay = doğrulama:** terminalden gelen iş kaydı onay sayfasında onaylanınca doğrudan "Doğrulandı" sayılır (kurucu: "Evet, onay = doğrulama"). Gerekçe: içerik onay sayfasında görülerek onaylanıyor; ikinci kapı aynı işi iki kez onaylatıyor. Çekirdek kuralına (doğrulama = en az bir bağlantı + "ne yapıldı") dokunduğu için 0.2.2'de; onayda bu koşul sağlanmıyorsa kayıt "Doğrulanmadı" düşer ve onay sayfası bunu satırda söyler.
- 0.2.1 kalanları: Akış'ta "Bilgi sayfası: …" başlığı hâlâ eski adla ("Hafıza"ya), kurucunun elle turu (`docs/elle-test-senaryosu.md`), gerçek Claude Code oturumunun `oneriler/` akışı.
