# Gerçek pencere denetimi (2026-10-04)

Kapsam: `scripts/pencere-goruntu.sh` ile alınan gerçek pencere görüntüleri (geçici veri alanı, demo veri: Deneme Yangın, Kuzey Lojistik, Örnek Kafe Zinciri, Nova Stüdyo). 40 görüntü: açık + koyu × bugün, flow (Özet), todo (liste, pano, gantt, takvim, panel), files, info (profil, hedefler, kişiler, izinler), finance, report, şirket (5 sekme), onay sayfası.

Kanıt PNG'leri depoda tutulmaz; adlar `denetim/<ekran>-<light|dark>.png` biçimindedir (denetçinin geçici klasörü).

## Sınırlar (dürüstçe)
- **Tıklama, kaydırma, üzerine gelme (hover), sürükleme, klavye yapmadım.** Yalnız her ekranın ilk görünür kısmını (açılış durumu) gördüm. Menüler/açılır listeler/DatePicker açık hâli, araç ipucu (tooltip), odak sırası, VoiceOver doğrulanmadı.
- Yalnız Türkçe ve yalnız Deneme Yangın (+ Nova Stüdyo) markası; İngilizce taşma, boş durum, hata durumu görülmedi.
- Demo veri her çalıştırmada rastgele marka rengi/proje adı üretiyor (aynı ekran açık/koyu karşılaştırmasında vurgu rengi ve grup adları farklı çıktı); renk farkları hata sayılmadı.
- Pencere boyutu tek (yaklaşık 1291×860 pt); dar pencerede taşma ölçülmedi.

## Bulgular

| # | Ekran | Sorun | Kanıt | Önem | Önerilen düzeltme |
|---|---|---|---|---|---|
| 1 | Dosyalar · galeri · KOYU | Kart başlıkları görünmüyor: beyaz küçük resim alanı kartın alt şeridini örtüyor, yalnız "Çıktı · 4 Eki" kalıyor. Açıkta başlıklar var. | `denetim/files-dark.png` (açıkta karşılaştırma: `files-light.png`) | engelleyici | Galeri kartında küçük resim yüksekliğini sabitle, başlığı küçük resmin altına koy ya da koyu temada kart yüksekliğini küçük resimden bağımsız tut (`FilesView.swift` / galeri kartı). |
| 2 | Dosyalar · galeri | Küçük resimler neredeyse boş beyaz sayfa (3 satırlık minik metin); koyu temada parlak beyaz kareler gözü alıyor. | files-light.png, files-dark.png | kozmetik | Küçük resme koyu temada hafif kısma/kenarlık ver; metin türü için simge+uzantı göster. |
| 3 | Görevler, Dosyalar (açılış) | Açılışta arama alanı otomatik odaklı (imleç "Görevlerde ara" içinde). Odak kenar çubuğundan çıkınca seçili marka satırı gri "pasif" renge dönüyor. | todo-liste-light.png, files-light.png | önemli | `@FocusState` ile açılışta odak verme; arama yalnız ⌘F ile odaklansın. |
| 4 | Kenar çubuğu · AÇIK | Pasif (gri) seçili satırda rozet sayısı ("5", "8") beyaza yakın, gri zeminde okunmuyor. Koyuda okunuyor. | todo-liste-light.png, bugun-light.png, sirket-about-light.png | önemli | Seçili satır rozet rengini `.secondary`/vurgu kontrastına bağla; pasif seçimde de en az 4.5:1 (`Sidebar*.swift`). |
| 5 | Onay sayfası (sheet) | Açılışta ilk başlık alanı odaklı ve metni seçili: yanlışlıkla yazınca başlığın üstüne yazılır. | onay-light.png, onay-dark.png | önemli | İlk odağı "Seçilenleri onayla"/boş alana ver; `onay` sayfasında `defaultFocus` kaldır (`ApprovalSheet.swift`). |
| 6 | Onay sayfası | Üst sayı "5" ama görünür kayıt 4 (3 yapılacak + 1 iş kaydı); listenin kalanı alt şeridin altında kalıyor, kaydırma ipucu yok. | onay-light.png | önemli | Altına gölge/kesik ipucu ekle ya da gruplara daralt/aç; sayıyı grup toplamıyla eşle. |
| 7 | Onay sayfası | Satırlar tutarsız: ilk ikisi kenarlıklı düzenlenebilir alan + "Son tarih" onay kutusu, 3. ("Cuma teklif gönderimi", Söz) kalın düz metin, düzenlenemez görünüyor. | onay-light.png | kozmetik | Tüm satırlarda aynı alan stilini kullan; düzenlenemezse nedenini yaz. |
| 8 | Onay sayfası | "Tümünü reddet…" ve "Seçimi kaldır" düz metin; düğme olduğu anlaşılmıyor, birincil/ikincil sıralama zayıf. | onay-light.png, onay-dark.png | kozmetik | `.bordered`/`.link` stilini tutarlı ver; yıkıcı eylemi kırmızı yap. |
| 9 | Bugün | "Bu hafta yapılan: 68" kartı farklı birimleri (görev+iş kaydı+dosya+not) topluyor (2+8+15+3, 1+6+11+2, 1, 1+6+11+1 = 68). Altındaki satırlarla birlikte yanıltıcı büyük sayı. | bugun-light.png, bugun-dark.png | önemli | Sayıyı yalnız biten görev sayısı yap ya da kartı "68 kayıt" diye adlandır (`BugunView.swift`). |
| 10 | Özet / Görevler | Sayı uyumsuzluğu: Özet "Açık görev 9", Görevler başlığı "15 açık", pano 10+1+4=15. Hedefler "Görev 13/15 tamamlandı". Tanımlar farklı olabilir ama ekranda açıklanmıyor. | flow-light.png, todo-liste-light.png, info-goals-light.png | önemli | Ortak tanım: etiketlerde "görev/söz/karar" ayrımını yaz, aynı kaynaktan say. |
| 11 | Görevler · liste | Satır sonundaki gri yuvarlak "C" ve ▶ düğmelerinin ne yaptığı anlaşılmıyor (yalnız harf/simge, etiket yok); gecikmiş satırda "C" hiç yok, sağ sütun hizası değişiyor. | todo-liste-light.png | önemli | `help`/`accessibilityLabel` ekle; "C" için tam ad ya da ikon; sütun genişliğini sabitle. |
| 12 | Görevler · gantt/takvim | Üstteki durum/sıralama/arama çubuğu ve "Müşteri yanıtı bekleyen iş" şeridi bu iki görünümde kayboluyor; kullanıcı filtre yapamıyor, düzen zıplıyor. | todo-gantt-light.png, todo-calendar-light.png | kozmetik | Filtre çubuğunu görünüm değiştiriciyle birlikte sabit tut ya da devre dışı göster. |
| 13 | Görevler · gantt | Yalnız elmas (tek tarih) var, çubuk yok; "Bugün" çizgisi yok; ilk hafta sütununun solunda ayırıcı çizgi olmadığından 6/8 Eki elmasları başlık sütununa taşmış görünüyor. | todo-gantt-light.png, todo-gantt-dark.png | kozmetik | Bugün dikey çizgisi, ilk sütuna sol ayırıcı, başlangıç-bitiş varsa çubuk (`GanttView.swift`). |
| 14 | Görevler · takvim | Sonraki ayın günü "1" (sağ alt) soluk değil, önceki ay günleri soluk; gecikmiş "3 Eki" kutusu kırmızı değil; kısaltılmış kutucuklar ("Teknik föy…" ×2) birbirinden ayırt edilmiyor. | todo-calendar-light.png | kozmetik | Ay dışı günleri iki yönde de soluklaştır; gecikmişe kırmızı; ipucu/uzun metin için 2 satır. |
| 15 | Görevler · pano | Etiketli kartta başlık tek satıra kesiliyor ("Teklifi kontrol et ve g…") diğerleri 2 satıra sarıyor; sütun arka planı açıkta yok, koyuda var. | todo-board-light.png, todo-board-dark.png | kozmetik | `lineLimit(2)` tutarlı; sütun zeminini iki temada da aynı yap. |
| 16 | Görev paneli | "Notlar" ve "Sorumlu" için üstte etiket + içinde aynı yer tutucu (yineleme). "Durum: Yapılacak" düz metin görünüyor, menü olduğu anlaşılmıyor. Tarih "3.10.2026", listede "3 Eki". "Sil…" ve "İptal et" düz metin; "İptal et" neyi iptal ediyor belirsiz (zaten X var). Alt yarı boş. | todo-panel-light.png, todo-panel-dark.png | önemli | Yer tutucuları kaldır/farklılaştır; `Picker` oku göster; tarih biçimini ortakla; "İptal et"i "Kapat" yap (`TaskDetailPanel.swift`). |
| 17 | Görev paneli | Panel liste üzerine kenarsız biniyor: listedeki başlıklar yarıdan kesiliyor ("Sertifika görsellerini ç"), açık temada panelle liste arasında belirgin sınır/gölge yok. | todo-panel-light.png | kozmetik | Panel sol kenarına ayırıcı + gölge; liste sağ iç boşluğunu panel açıkken daralt. |
| 18 | Marka Bilgileri · Ayrıntılar ve izinler | "Terminal bu izne bağlı değildir." ölü/yanıltıcı: uygulamada terminal kalktı (asistan paneli var). Aynı sekme Profil'deki Ad/Sektör/Tanım'ı tekrar ediyor. Çerçevesiz düz yerleşim diğer sekmelerin kart yapısından farklı, alt yarı boş. | info-access-light.png, info-access-dark.png | önemli | Metni güncelle ("Asistan bu izne bağlıdır"); tekrar eden alanları kaldır; kartlarla tutarlı hale getir (`BrandInfoView.swift`, `en/tr .strings`). |
| 19 | Marka Bilgileri · Kişiler ve projeler | "Kampanya başlangıcı" "Bitti" iken tarihi (26 Tem) kırmızı; bitmiş iş gecikmiş gibi görünüyor. | info-people-dark.png | önemli | Kırmızıyı yalnız açık+geçmiş kayıtta uygula. |
| 20 | Marka Bilgileri · Profil | "Yangın güvenl…" ve "Ayşe Demir · Satın alma müd…" kesiliyor; "Bağlam boyutu (token): ~298", "Sözcük/Token" jargonu; düzenleme kalemi çok soluk. | info-light.png, info-dark.png | kozmetik | Çok satır/uzun metinde tam göster; "token"i "yaklaşık uzunluk" yap; kalem kontrastını artır. |
| 21 | Marka Bilgileri · Hedefler | Tarihler biçimce karışık: "2026-10-18" (ISO) ve "2 Eki", "Kasım 2026". "Hedef ekle" ve "Ekle" düz metin, düğme gibi görünmüyor. İkinci hedefin ilerleme çubuğu/yan sayı yok (neden boş belli değil). | info-goals-light.png, info-people-dark.png | kozmetik | Tek tarih biçimleyici; düğmeleri `.bordered`; boş ilerleme için "Bağlı görev yok" yaz. |
| 22 | Şirket · üst özet | "Yetenek 13" kartında sayı 2 satıra bölünüyor ("1"/"3") ve kart diğerlerinden uzun; "Yapay zek…" ve "Bekleyen…" etiketleri kesiliyor. | sirket-about-light.png, sirket-services-dark.png (tümü) | önemli | Sayıya `lineLimit(1)`+`minimumScaleFactor`, kart genişliğini eşitle, etiket kısalt ("YZ", "Bekleyen") (`CompanyHeader.swift`). |
| 23 | Şirket · Yetenekler | "SKILL.md içe aktar…" düğmesi 2 satıra sarıyor, araç çubuğu hizası bozuluyor; "SKILL.md" kullanıcıya jargon; "Hazır paket yükle" menüsü diğer düğmelerden farklı çerçeveli. | sirket-skills-light.png | kozmetik | Tek satır + kısa metin ("Dosyadan içe aktar"); üç düğmeyi aynı stile getir. |
| 24 | Şirket · Ekip/Şema | Unvan rozetleri iki dilli ("Junior", "Kıdemli", "Takım lideri"); şemada kartlar içeriğe göre farklı genişlikte, sağ kenar pürüzlü. | sirket-team-light.png, sirket-chart-dark.png | kozmetik | Rozet adlarını Türkçeleştir ("Yeni başlayan"); şema kartlarına sabit genişlik. |
| 25 | Finans | "Ödeme planı" başlığı yanında "Kasım – Aralık 2026" yazıyor ama ilk satırlar Kas 2025'ten başlıyor. "Açıklama" iki satıra sarıyor, Durum sütununda boşluk var; satır menüsü "…" çok küçük; kartlarda büyük boş alan. | finance-light.png, finance-dark.png | önemli | Aralık etiketini tablo verisinden hesapla; sütun genişliklerini oransal yap. |
| 26 | Rapor | Önizleme "Taslak" yazarken ana eylem "Hazır, PDF al" (çelişki; uyarılar da doğrulanmamış kayıt diyor). "Dönemi değiştir · Bu hafta" eylem ve değeri tek bağlantıda karıştırıyor. Alt başlık "Müşteri özeti" belirsiz. Koyu temada beyaz sayfa parlak (kağıt benzetmesi olarak bilinçli olabilir). | report-light.png, report-dark.png | kozmetik | Düğmeyi "PDF al"; dönem seçiciyi `Menu` olarak değer göster; koyuda kağıt parlaklığını kıs. |
| 27 | Koyu görünüm (genel) | Kartlar/tablolar nötr siyah (#1e1e1e civarı), sayfa zemini mavimsi lacivert; iki ayrı gri aile yan yana (Özet, Finans, Gantt, Takvim). | flow-dark.png, finance-dark.png, todo-calendar-dark.png | kozmetik | Kart yüzeyini zeminin tonundan türet (`Theme.surface` koyu). |
| 28 | Asistan paneli (tüm marka ekranları) | Panel sağ ~%30 genişliği boş durumla kalıcı kaplıyor; yazma alanı yok, tek eylem "Ayarlar'ı aç". Üst sağdaki iki küçük simgenin adı yok. Düğme açık temada gölgeli, diğer düğmelerden farklı. | flow-light.png | kozmetik | Bağlı değilken paneli daralt/kapalı başlat; simgelere `help`/`accessibilityLabel`. |
| 29 | Araç çubuğu | "Demo veri" hapı yanındaki kilit simgesinin anlamı yazısız; sağdaki "…" + ok menüsü ne olduğunu söylemiyor. Sekme ayırıcı çizgileri seçili sekmenin yanında kayboluyor. | todo-liste-light.png | kozmetik | Kilit için etiket/ipucu; menüye ad/simge anlamlı (ör. "Marka"). |
| 30 | Demo verisi / Akış | Dosya adları ASCII ("Musteri Referanslari", "Egitim Senaryosu"); tüm Akış satırları aynı saat (18:37). Gerçek görünümü yansıtmıyor ve Türkçe karakter sorununu gizleyebilir. | flow-light.png, files-light.png | kozmetik | `MarkaDogrula demo` verisini Türkçe karakterli ve farklı saatli yap. |

## İyi çalışanlar (görülen)
- Gerçek `TextField`, `Toggle`, `DatePicker` (Şirket · Genel, görev paneli), onay kutusu, yığın düğmeler açık ve koyuda doğru çiziliyor.
- Koyu temada genel metin kontrastı iyi; kesin kırmızı/turuncu uyarılar okunuyor.
- Liquid Glass araç çubuğu kapsülü ve sekme seçimi iki temada tutarlı.

## Önerilen sıra
1 → 3/4 (odak + rozet kontrastı) → 5/6 (onay sayfası) → 9/10/19/25 (yanıltıcı sayılar) → 18/22 → kalan kozmetik.

## Düzeltme durumu (2026-10-04, `arayuz-gelistirici`)

Kapı: `scripts/test.sh` (200 test geçti) · `scripts/build-app.sh` · `python3 scripts/l10n.py check` (987/987, eksik 0) temiz.
**Gerçek pencerede doğrulanamadı:** düzeltmeden sonra ekran kilitliydi (`CGSSessionScreenIsLocked = Yes`); `scripts/pencere-goruntu.sh`
"could not create image from window" verdi. Kanıt, geçici alanla `MARKA_SNAPSHOT` çizimidir (ImageRenderer; odak, kenar çubuğu
seçim rengi ve sayfa odağı bu çizimde görünmez). Odak düzeltmeleri (3, 4, 5) gerçek pencerede yeniden yakalanmalı.

| # | Durum | Kanıt |
|---|---|---|
| 1 | düzeltildi: küçük resim kabı taşırmıyor (zemin + üstüne bindirilmiş, kırpılmış resim; kart başlığı her temada görünür) | `16-dosyalar-koyu.png` (çizim) |
| 2 | kısmen: koyu temada küçük resim %82 opaklıkla kısıldı; simge+uzantı yapılmadı | kod (`FileThumbnail`); QuickLook çizimde yok |
| 3 | düzeltildi (kod): Görevler, Dosyalar, Bugün, Stüdyo açılışında odak kenar çubuğu listesine verilir (`OpeningFocus.settle`), metin alanı odaklanmaz | gerçek pencerede doğrulanamadı |
| 4 | düzeltildi (kod): rozet beyazı yalnız vurgulu seçimde (`backgroundProminence == .increased`), pasif gri seçimde vurgu rengi | gerçek pencerede doğrulanamadı |
| 5 | düzeltildi (kod): onay sayfası açılışında metin alanı odağı bırakılır (`OpeningFocus.clearTextFocus`) | gerçek pencerede doğrulanamadı |
| 6 | düzeltildi: sayı doğruydu (5 = 3 yapılacak + 1 iş kaydı + 1 hafıza güncellemesi; 5. satır kaydırma altındaydı, klasör dosyası değil). Başlığa grup dökümü eklendi, sayı ve döküm aynı satırları sayar | `07-onay-acik.png` |
| 7, 8 | yapılmadı (kozmetik) | — |
| 9 | düzeltildi: kutucuk "Bu hafta biten görev", yalnız biten görevler (demo: 4); satır içi döküm aynı | `01-bugun-koyu.png` |
| 10 | düzeltildi: Özet kutucuğu "Açık iş" = `store.todo` öğelerinin tümü; Görevler "15 açık" ile aynı (15) | `02-akis-acik.png` |
| 11–17 | yapılmadı (zaman; 16'daki "İptal et" kaydı iptal eder, "Kapat" olamaz) | — |
| 18 | düzeltildi: "Terminal bu izne bağlı değildir" kaldırıldı → "Asistan sohbeti ve rapor özeti yalnız izin verdiğin sağlayıcıyı kullanır. İzin varsayılan olarak kapalıdır."; Codex açıklaması "yalıtılmış çalışır" yerine gerçek yetki. Tekrar eden alanlar kaldırılmadı | kod (`BrandInfoView.swift`) |
| 19 | düzeltildi: `DueLabel(isOpen:)`; bitmiş/iptal proje, kayıt, görev ve plan öğesinin geçmiş tarihi kırmızı değil | kod; çizimde geçmiş tarihli bitmiş kayıt görünmedi |
| 20, 21 | yapılmadı (kozmetik) | — |
| 22 | düzeltildi: sayı tek satır (`lineLimit(1)` + `minimumScaleFactor`), Şirket kutucuk etiketleri iki satıra sarar ve iki satır yer ayırır (kesilmez, eş boy) | `20-studyo-genel-acik.png` (geniş çizim; dar pencere ölçülmedi) |
| 23, 24 | yapılmadı | — |
| 25 | düzeltildi: aralık yıllar farklıysa iki yıllı ("Kasım 2025 – Aralık 2026"), aynı aydaysa tek ay | `18-finans-koyu.png` |
| 26–30 | yapılmadı (kozmetik) | — |
| Gizlilik O2 | düzeltildi: Onboarding "Verin Mac'inde saklanır / Veriler bu Mac'te yerel saklanır; yapay zekâyı açtığın markanın içeriği yalnız o marka için izin verdiğin sağlayıcıya gönderilir."; kilit ipucu markanın iznine göre (kapalı / izinli sağlayıcı adı) | `11-ilk-acilis-koyu.png`; ipucu gerçek pencerede doğrulanamadı |
| Gizlilik Y2 | düzeltildi (metin): Codex izin onayında onaysız komut, açık ağ ve Mac dosyalarını okuma riski yazılı (TR/EN) | kod (`AIChatPanel.swift`); iletişim kutusu çizilmedi |
| Gizlilik D6 | düzeltildi (18 ile aynı) | — |
