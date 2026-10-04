# Tasarım denetimi — Apple HIG'e karşı (1 Eki 2026)

Kaynak: Apple'ın Human Interface Guidelines sayfalarının JSON verisi (`developer.apple.com/tutorials/data/design/human-interface-guidelines/<sayfa>.json`),
bir alt ajanla okundu. Okunamayanlar: `tables` ve `inspectors` (404). HIG'in kendi notu: macOS'ta Dynamic Type yoktur; sabit punto başlı
başına ihlal değildir, kural varsayılan 13 pt ve en az 10 pt'dir.

## Ölçülen durum (denetimin başı → şimdi)
| Ölçü | Önce | Şimdi |
|---|---|---|
| Araç çubuğu öğesi | 0 | Terminal anahtarı, Yerel etiketi, ··· menüsü |
| Bağlam menüsü | 0 | marka, görev, dosya satırları |
| Geri alma (⌘Z) | 0 | görev tamamlama (Düzen › Geri Al) |
| Klavyeyle liste gezinmesi | yok | görevlerde ↑↓, Boşluk |
| Animasyon (Hareketi Azalt'a saygılı) | 0 | panel, grup kapanışı, bölüm geçişi |
| Sekme sayısı (HIG: en çok 6) | 8 | 6 |
| Kenar çubuğu | özel satırlar | gerçek pencerede sistem listesi (`List(.sidebar)`) |
| 10 pt altı yazı | 2 | 0 |

## Yapılanlar
1. **Gerçek araç çubuğu.** Pencere düzeyi eylemler (Terminal, ···) araç çubuğunda; marka adı pencere başlığı, sektör alt başlık.
2. **Sistem kenar çubuğu.** Okla gezinme, yazarak seçme, odak halkası, VoiceOver, vurgu rengi sistemden. Üstte arama (⌘K), altta "+ Marka".
3. **Altı sekme.** Planlama, Görevler'in Gantt ve Takvim görünümü oldu (Liste · Pano · Gantt · Takvim). Hedefler, Marka Bilgileri'nin bölümü oldu.
4. **Menü çubuğu.** Görünüm › Kenar Çubuğunu Gizle/Göster (`SidebarCommands`) ve Terminali Gizle/Göster (⌘J, değişen etiket); Dosya › Yeni Görev (⌘N);
   Düzen › Komut paleti (⌘K); Git menüsü ⌘0–⌘6.
5. **Bağlam menüleri, klavye, geri alma, hareket** (yukarıdaki tabloya bakın).
6. **Komut paleti (⌘K).** Marka, bölüm ve eylem arama; yalnız gezinme ve arayüz eylemleri.

## İkinci tur: Apple uygulamaları ve macOS 26 (aynı gün)
Kaynak: Apple dokümantasyon JSON'u (`metadata.platforms[macOS].introducedAt` alanı) ve WWDC25 323/356/310/256 metinleri. Doğrulanan sürümler:
- **macOS 26.0:** `glassEffect`, `GlassEffectContainer`, `backgroundExtensionEffect`, `scrollEdgeEffectStyle`, `ToolbarSpacer`, `sharedBackgroundVisibility`,
  `buttonStyle(.glass/.glassProminent)`, `searchToolbarBehavior`, `safeAreaBar`, `ConcentricRectangle`, `controlSize(.extraLarge)`.
- **macOS 15.0:** `sidebarAdaptable`, `defaultWindowPlacement`, `restorationBehavior`, `searchFocused`.
- **macOS 14.0 ve öncesi (sorunsuz):** `inspector`, `ContentUnavailableView`, `symbolEffect`, `onKeyPress`, `TableColumnCustomization`, `sensoryFeedback`.
- Doğrulanamayan: `tabViewBottomAccessory`, `SearchToolbarBehavior.minimize` (macOS alanı boş). `dropDestination` sayfasında "27.2'de kullanımdan kalkma"
  görünüyor; mantık dışı, doğrulanmadı. Apple Destek sayfalarının çoğu JS ile çizildiği için Hatırlatıcılar dışındaki uygulamalardan somut metin alınamadı.

Uygulananlar (macOS 26'ya özgü olanlar `#available(macOS 26, *)` ve ekran çizimi dışı koşullarla sarılı):
- Tamamlananları gizle/göster (⇧⌘H, Hatırlatıcılar kalıbı) ve tamamlananı yeniden aç (⌘Z ile geri alınır).
- Görev sıralama menüsü (önerilen, teslim tarihi, öncelik, başlık, oluşturulma).
- Onay halkası yay animasyonu ve dokunsal onay (Hareketi Azalt'a saygılı).
- Birincil/ikincil düğmelerde macOS 26'da sistemin `glassProminent`/`glass` stili; eski sürümde kendi stilimiz.
- Yoğun listelerde `scrollEdgeEffectStyle(.hard)`.
- Boş durumlar için `ContentUnavailableView` (simge, başlık, açıklama).
- Akış ekranı diğer bölümlerle aynı başlık düzenine alındı.
- Yerel arama alanları (Görevler, Dosyalar), durum geri yükleme (açık bölüm, terminal), geri alma kapsamı (finans, profil metni).

Bilerek alınmayanlar: `.inspector` (dağıtık yerleşimimizde davranışı gerçek pencerede doğrulanamadı), yerel `.searchable` (⌘F ile çakışma riski),
alt görevler ve akıllı listeler (ayrı büyük işler).

## Üçüncü tur: son kullanıcı bakışı (2 Eki)
Hedef: ürün son tüketiciye gidecek; ilk izlenim ve ana ekran Apple kalitesinde olmalı.
- **Bölüm seçici araç çubuğuna taşındı** (`Picker(.segmented)`, `ToolbarItem(.principal)`): yalnız metin, altı segment; marka adı ve sektör pencere
  başlığı/alt başlığı (`windowToolbarStyle(.unified(showsTitle: true))`). Gerçek pencerede elle çizilmiş başlık ve sekmeler yok; ekran çizimi araç çubuğunu
  çizemediği için yalnız orada eski başlık/sekmeler gösterilir. **Gerçek pencerede doğrulanmadı.**
- **Bugün ana ekranı:** saate göre selamlama, tarih, dört özet kutucuğu (onay bekleyen, geciken, bu hafta yapılan, karar bekleyen; sayı + simge + dokununca
  ilgili yere gider), altında ayrıntı listeleri.
- **İlk açılış:** karşılayıcı tek ekran: simge, başlık, dört değer cümlesi (terminalde çalış, burada onayla, müşteriye raporla, verin sende kalır), marka adı,
  tam genişlik birincil düğme.

## Dördüncü tur: ortak geliştirici ve tasarımcı brief'i
Kurucunun getirdiği brief (native his, etkileşim ve performans, ekosistem, kapsayıcılık). Brief'in "2026 Apple Design Awards kazananları şunu gösteriyor"
iddiaları doğrulanmadı; yön olarak alındı. "Sistem yazı boyutu büyüyünce arayüz esnesin" maddesi macOS'ta uygulanamaz (HIG: macOS'ta Dynamic Type yok).
Ortamda doğrulananlar:
- `appintentsmetadataprocessor` yalnız Xcode'da var, bu makinede (yalnız Command Line Tools) yok → **App Intents/Kısayollar/Spotlight eylemleri burada
  düzgün üretilemez**. Widget'lar ayrı uzantı hedefi ister → Xcode gerekir. Bunlar Xcode kurulu bir makinede yapılmalı.
- `MenuBarExtra` macOS 13.0, `FoundationModels` (`SystemLanguageModel`, `LanguageModelSession`) macOS 26.0 (Apple belgelerinden).
Yapılanlar: satırlarda fare üstü vurgusu (Hareketi Azalt'a saygılı), Akış satırı bağlam menüsü (toplam 4 bağlam menüsü), Artırılmış Kontrast ayarında ayraç
renkleri koyulaşır (`colorSchemeContrast`), ikon-yalnız düğmelere erişilebilirlik etiketi (15 → 25 etiket), isteğe bağlı **menü çubuğu simgesi** (bekleyen onay
sayısı, markaya göre onay listesi; Ayarlar › Genel'den açılır, varsayılan kapalı; açıkken pencere kapansa da uygulama yaşar).
Sıradaki aday: **cihaz üstü özet** (`FoundationModels`, macOS 26, `#available` ve model durumu denetimiyle): rapor özetini üçüncü taraf sağlayıcıya göndermeden
yazmak "verin sende kalır" sözüyle örtüşür. Gerçek cihazda model kullanılabilirliği doğrulanmadı.

## Beşinci tur: gerçek pencere doğrulaması (2 Eki)
Ekran Kaydı izni verildi; `scripts/pencere-goruntu.sh` (geçici veri alanı + örnek veri, yalnız kendi PID'sinin penceresini yakalar) ile uygulamanın GERÇEK penceresi
ilk kez görüldü. ImageRenderer ekran görüntüleri araç çubuğunu, sistem malzemesini, terminali, menüleri ve macOS 26'nın yüzen kenar çubuğunu çizmediği için
şu hatalar o güne kadar görünmemişti:
- **Liste/Pano/Gantt/Takvim seçicisi ezilmişti** (harfler alt alta): metin sığmayınca satır kırıyordu → `lineLimit(1)` + `fixedSize`.
- **Araç satırı ve Finans sayfası sağa taşıyordu**, terminal sütunu içeriği örtüyordu (düğme "+ K" diye kesik): sabit genişlikli arama alanı, sayaç ve dört
  özet kartının asgari genişliği sayfa genişliğini aşıyordu → esnek arama alanı, sayaç kaldırıldı, kartlar uyarlanabilir ızgaraya çevrildi, tablo sütunları daraltıldı.
- **macOS 26'da kenar çubuğu içeriğin üstünde yüzen cam panel**; sütun kenarından ~24 pt taşıyor, içerik cama yapışık görünüyordu → `Design.pageLeading`
  (macOS 26'da 54, önceki sürümlerde 34) ve `pagePadding()`.
- Bugün'de arama alanı açılışta kalın odak halkasıyla seçili geliyordu → ilk yanıtlayıcı bırakılır. Boş durum başlığı fazla iriydi → küçültüldü.
  Terminale yazılan Codex ipucu kelime ortasından bölünüyordu → kaldırıldı (düğme zaten doğru komutu çalıştırıyor).
- Doğrulananlar: araç çubuğundaki yerel segment kontrolü, başlık/alt başlık, terminal paneli, açık ve koyu görünüm iyi çalışıyor.
- Tekrarlanamayan: ilk yakalamada kenar çubuğunda seçili satır içerikle uyuşmuyordu (mavi vurgu başka markada); sonraki yakalamalarda görülmedi.

## Altıncı tur: iç sayfaların yeniden tasarımı (gerçek pencerede doğrulandı, 2 Eki)
- **Tasarım dili:** her markaya kimlik rengi (`BrandTint`, sekiz uyumlu renk; avatar, bölüm simgesi rozeti, özet çubukları), gruplanmış kart yüzeyleri (`card()`),
  durum hapları (`Pill`), bölüm başlığında simge rozeti (`SectionHeading(symbol:tintKey:)`). Eylemler indigo vurguda kalır.
- **Görevler:** gruplar kart içinde; **Akış:** gün başına kart, türe göre simge rozetli satırlar ve "Doğrulanmadı" hapı; **Dosyalar:** galeri (gerçek Quick Look
  küçük resimleri, yoksa tür simgesi) ve liste, kart içinde; **Finans:** simgeli özet kartları (dar pencerede sarılır), tablolar kart içinde; **Marka Bilgileri:**
  künye ve doluluk kartları, bölüm kartları (eşit yükseklikli iki sütun), hedefler ve kararlar kartları; **Rapor:** gölgeli kâğıt tuvali (kâğıt her iki görünümde
  açık ve koyu yazılı, çünkü müşteriye giden belge); **Bugün:** özet kutucukları ve kartlı listeler; **ayrı Planlama kartı:** Gantt ve takvim kart içinde.
- **Ayrıntı paneli:** yan yana yerleşim orta sütunu ezip paneli terminalin altına taşırıyordu (gerçek pencerede görüldü) → panel listenin üstüne kayan katman
  oldu (gölgeli, sütun genişliğiyle sınırlı); içi: büyük çerçevesiz başlık, bilgiler tek kartta, tam genişlik birincil düğme.
- **İkincil düğme:** macOS 26 cam stili kök vurgu rengini devralıp birincil gibi görünüyordu → ikincil eylemler kendi çerçeveli stilimizi kullanır.
- Geliştirme kancaları: `MARKA_SEKME`, `MARKA_GORUNUM`, `MARKA_PANEL=1`; betik: `scripts/pencere-goruntu.sh <bölüm> <png> [light|dark] [panel]`.
- Doğrulanmayan: Gantt/Takvim/Pano görünümleri ve Hedefler kartı gerçek pencerede yakalanmadı (açılış kancası yok); galeride gerçek dosya küçük resmi
  örnek veride görülmedi (örnek dosyalar diskte yok); VoiceOver ve klavye elle denenmedi.

## v2.2 (başladı, 2 Eki): v2.1.1 üzerine
Kurucu mevcut hâli "v2.1.1" saydı; yerel etiket `tasarim-v2.1.1` (commit'e girmeyen, çalışma ağacının anlık görüntüsü; `git checkout tasarim-v2.1.1 -- .` ile
dönülür) ve çalışan kopya `dist/v2.1.1/` (git dışı). v2.2 değişiklikleri:
- **Özet ekranı (eski Akış sekmesi):** marka renginde geniş künye kartı (büyük avatar, ad, sektör hapı, tanım), dört özet kutucuğu (açık görev, bu hafta biten,
  karar bekleniyor, doğrulanmadı), altında Akış; marka rengi sayfanın üstüne yumuşak ton geçişi olarak yayılır.
- **Sıradaki teslimler** kartı (Özet): tarihli ilk üç açık iş, gecikenler önce; tıklayınca Görevler'de ayrıntısı açılır.
- **Onay sayfası yeniden tasarlandı:** marka renginde simge rozetli başlık ve büyük bekleyen sayısı, grup başlığı + kart içinde satırlar (tür simgeli), "Tümünü seç /
  Seçimi kaldır", birincil/ikincil düğmeler. Mantık değişmedi (seçilmeyenler beklemeye devam eder). ImageRenderer ile doğrulandı; sayfa gerçek pencerede
  (sheet) yakalanamadı.
- **Pano** gerçek kanban: renkli sütun yüzeyleri (durum halkalı başlık, sayaç), gölgeli kartlar (tür, "Yüksek" hapı, tarih), boş sütunda kesikli "Boş" alanı,
  sağ tık menüsü. Gantt, Takvim ve Pano gerçek pencerede yakalandı (`MARKA_MOD`); Gantt'ta sağ kenarda kesilen teslim etiketi düzeltildi (düzeltme yakalanmadı).
- **Pano'da sürükle-bırak:** görev kartı başka sütuna bırakılınca durum değişir (yalnız görevler; söz/karar/talep sürüklenmez), hedef sütun vurgulanır, ⌘Z geri alır.
  **Elle denenmedi** (fare otomasyonu yok; yalnız derleme ve mevcut durum testleri). Markalar arası geçişe kısa çapraz solma eklendi (Hareketi Azalt'a saygılı).
- Geliştirme düzeltmesi: pencere kimliği `optionAll` ile aranır (ekran dışı pencereler `optionOnScreenOnly`'de görünmüyordu); betik her çalıştırmada deneme
  tercih plist'ini siler (biri 29 plist bırakmıştı, temizlendi).

## v3 yönü (3 Eki): "Sakin Atölye" (Things 3 / Hatırlatıcılar sakinliği)
Kurucu referansı bana bıraktı ve "hepsi" bozuk dedi. Karar: sakinlik. Kurallar: (1) listeler düz, çerçevesiz (`flatList()`: yalnız üst/alt ince çizgi; kart yalnız künye
ve özet kutucuklarında); (2) büyük, cesur başlık (34 pt), simge rozeti yok; (3) terminal yüzen yuvarlak panel (boşluklu, gölgeli); (4) onay bandı kutu değil,
tek satırlık yumuşak hap; müşteri bekleyen uyarısı kutusuz tek satır; (5) marka rengi tek vurgu, sayfa zemini düz.
Gerçek pencerede Özet ve Görevler (açık) yakalandı. Diğer sayfalar aynı kurala geçti ama yakalanıp görülmedi.

## Araştırma sonuçları: kütüphane ve araçlar (2 Eki, `gh api` ile)
- Eklenmeyecek: Pow, Vortex, Lottie, Wave, Shimmer, Glur, Confetti, swift-markdown-ui (bakım modunda), Splash, Defaults, LaunchAtLogin-Modern, SwiftUIX, Inject,
  periphery (arşivlendi). Animasyon dilimizi kendimiz yazarız; bağımlılık sayısı düşük kalır (GRDB, SwiftTerm).
- Eklenebilecek: KeyboardShortcuts (sindresorhus, MIT, aktif) ayarlar yapılınca; Sparkle (otomatik güncelleme) imzalama/noter onayı kurulduktan sonra. Her biri
  sürüm etiketine sabitlenir, `Package.resolved` depoya girer.
- Kurulan araçlar: SF Symbols 27, SF Pro ve SF Mono (kullanıcı klasörüne), SwiftFormat 0.63, create-dmg 1.3. Xcode 26.6 (kullanıcı kurdu): Icon Composer,
  Accessibility Inspector, Instruments, `appintentsmetadataprocessor` (App Intents artık üretilebilir). Sistem genelini değiştirmeden kullanmak için
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- ADA resmî kategorileri (doğrulandı): Delight and Fun, Inclusivity, Innovation, Interaction, Social Impact, Visuals and Graphics. Ayrıntılı puanlama ölçütü ve
  Mac'e özgü kazananların ortak özellikleri doğrulanamadı; genelleme yapılmadı.

## Son kullanıcıya çıkmadan önce kalanlar (tasarım dışı, ürün hazırlığı)
Bunlar tasarım turlarında çözülmedi ve doğrulanmadı: imzalı ve notarize paket (Apple Developer ID kurucudan bekleniyor), otomatik güncelleme,
uygulama ikonunun son hâli, Claude Code/Codex kurulu değilse ilk açılışta yönlendirme, büyük veride performans ölçümü, erişilebilirlik testi (VoiceOver ve
Tam Klavye Erişimi gerçek pencerede), gizlilik metni ve lisans/ödeme akışı.

## HIG'in söylediği, henüz yapılmayanlar (öncelik sırasıyla)
1. Tablolarda sütun sıralama ve yeniden boyutlandırma yok (Dosyalar, Finans).
2. Rapor içinde yerel arama yok (görev ve dosyalarda var).
3. Gantt ve takvimde sürükleyerek süre/tarih değiştirme yok.
4. Uzun işlerde (rapor üretimi, terminal) ilerleme ve iptal geri bildirimi denetlenmedi.
5. Önceki durumu geri yükleme: açık marka, bölüm, terminal durumu ve genişliği kaydediliyor; grup açık/kapalı ve görünüm modu (Liste/Pano…) kaydedilmiyor.
6. Artırılmış Kontrast ayarı için ayrı değerler yok; durum renkleri yanında şekil/etiket taşıyor (görev halkaları, tarih etiketleri).
7. Sürükle-bırak: dosya bırakma var; görev sürükleme ve Gantt'ta sürükleme yok.
8. Özel düğmelerde (`.plain`) basılı durum tutarlı değil; 44 pt hedef kuralı çoğu küçük simge düğmesinde karşılanmıyor (macOS'ta fare hedefi için gevşek).

## Doğrulanmayanlar
- Hiçbir değişiklik gerçek pencerede elle denenmedi (ekran kilitli ya da izin yok). Araç çubuğu, sistem kenar çubuğu listesi, menüler, bağlam menüleri,
  ⌘Z ve klavye gezinmesi yalnızca derleme ve testlerle (142) doğrulandı; ekran görüntüleri ImageRenderer ile alındı ve bunları çizmez.
