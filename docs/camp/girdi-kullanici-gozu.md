# Kullanıcı gözü: ilk kullanım turu (2026-10-05)

**Persona:** 5 müşterili bağımsız danışman, Mac kullanıcısı. Bugüne kadar not defteri, e-tablo ve takvimle çalışmış. Yapay zekâyı merak ediyor ama sabırsız. Türkçe kullanıyor, İngilizce arayüzü de deniyor.

**Yöntem:** Görüntüler yalnızca `scripts/pencere-goruntu.sh` ile alındı. Bu betik geçici veri alanında örnek veri kullanıyor; gerçek veriye dokunulmadı. PNG'ler `camp-girdi/kullanici/` klasöründe (22 adet: bugun/flow/todo/files/info/finance/report/sirket açık tema; bugun/todo/report/flow/sirket/finance/files koyu tema; todo-panel, flow-panel, onay-todo, todo-board/gantt/calendar).

**Sınır:** Tıklama ya da klavye etkileşimi YAPAMADIM. Tıklanınca ne olacağı `Sources/MarkaApp/*.swift` ve `Sources/MarkaCore/*` okunarak çıkarıldı. Görsel kanıtı olmayan her maddede **[tıklayarak doğrulanamadı]** etiketi var. OnboardingView'ın görüntüsü yok: betik hep örnek veriyle açıyor, yani karşılama ekranına hiç düşmüyor.

Önem sırası: veri kaybı > engelleyici > önemli > sürtünme > kozmetik.

---

## A. Veri kaybı

**U-01 · (4) Görev silme**
- **Ben:** "Yanlış açtığım görevi sildim. Sonra ay sonunda faturalayacağım saatlerin de gittiğini fark ettim."
- **Kanıt:** `MarkaCore/Database/AppDatabase.swift:155-158` (timeEntry → workTask `onDelete: .cascade`). Silme onay metni süre kayıtlarından hiç söz etmiyor; yalnız "Bağlı iş kayıtları kalır" diyor (`DetailPanel.swift:378-380`).
- **Önem:** veri kaybı
- **Öneri:** Süre kaydı olan görevde silme yerine "İptal et" önerilsin, ya da onay metni "N saat süre kaydı da silinir" desin; tercihen süre kayıtları korunsun (`setNull`).
- [tıklayarak doğrulanamadı]

**U-02 · (5) Dosya arşivleme**
- **Ben:** "Dosyalar'da sağ tıkla 'Arşivle' dedim. Dosya kayboldu ve bir daha bulamadım."
- **Kanıt:** Arşivleme onaysız ve ⌘Z yok (`BrandSections.swift:548, 584-585`). Uygulamanın hiçbir yerinde `sources(... includeArchived: true)` çağrılmıyor; arşivlenmiş dosyayı listeleyen bir görünüm yok. Paneldeki "Arşivden çıkar" (`DetailPanel.swift:467`) bu yüzden erişilemez.
- **Önem:** veri kaybı (kullanıcı açısından)
- **Öneri:** Dosyalar'a "Arşivlenenler" süzgeci ekle ve arşivlemeye ⌘Z bağla.
- [tıklayarak doğrulanamadı]

**U-03 · (4) Zamanlayıcı**
- **Ben:** "Akşam zamanlayıcıyı kapatmayı unuttum. Sabah görevde 14 saat yazıyordu ve düzeltecek yer bulamadım."
- **Kanıt:** Çekirdekte `addManualTime` var (`Store+Tasks.swift:140`) ama arayüzde süre ekleme, düzenleme ya da silme yok (grep: MarkaApp'te çağrı yok). Görev panelinde yalnız başlık, notlar, durum, son tarih ve sorumlu var (`DetailPanel.swift:320-331`). Boşta kalma algılaması yok.
- **Önem:** veri kaybı (yanlış saat finansa ve rapordaki "Harcanan süre"ye gidiyor)
- **Öneri:** Görev panelinde süre kayıtları listelensin, düzenlenip silinebilsin; uzun açık kalan sayaçta "Hâlâ çalışıyor musun?" diye sorulsun.
- [tıklayarak doğrulanamadı]

**U-04 · (8) Dışa aktarma**
- **Ben:** "Müşteriyle işi bitirince markayı dışa aktardım. Ödeme planı ve finans kayıtları dosyada yoktu."
- **Kanıt:** `BackupService.swift:176-196` dosyasındaki `BrandExport` kişileri, projeleri, kayıtları, kaynakları, görevleri, süreleri, iş kayıtlarını, hafızayı ve raporları içeriyor; `FinanceEntry` yok. Dışa aktarılanı geri içe almanın yolu da yok.
- **Önem:** veri kaybı
- **Öneri:** Finans kayıtlarını ve marka profilini dışa aktarıma ekle; "Dışa aktarılanı içe al" yolunu ya da en azından "bu dosya geri yüklenemez" uyarısını ekle.

**U-05 · (8) Yedek**
- **Ben:** "Mac'imin diski bozuldu. 'Her gün yedek alınıyor' yazıyordu ama yedekler aynı klasördeymiş."
- **Kanıt:** `backupsRoot = workspace/Yedekler` (`BackupService.swift:24`). `createBackup(destination:)` parametresi arayüzde kullanılmıyor (`SettingsView.swift:297-300`). Dosyalar sabit bağlantıyla (hard link) aynı diske yazılıyor (`:80`).
- **Önem:** veri kaybı
- **Öneri:** Ayarlar › Veri'de "Yedeği başka yere kaydet…" (harici disk ya da iCloud klasörü) seçeneği olsun; ayarlardaki metin "aynı Mac'te tutulur" diye açıkça söylesin.

**U-06 · (8) Otomatik yedek**
- **Ben:** "Menü çubuğu simgesini açtım, uygulamayı hiç kapatmadım. Bir hafta boyunca yeni yedek alınmamış."
- **Kanıt:** Otomatik yedek yalnız `openWorkspace` içinde çalışıyor (`AppModel.swift:289-293`). Menü çubuğu simgesi açıkken pencere kapansa da süreç yaşıyor (`MarkaApp.swift:20`). Günlük bir zamanlayıcı yok.
- **Önem:** veri kaybı riski
- **Öneri:** Gün değişince ya da uygulama öne gelince `autoBackupIfNeeded` yeniden çağrılsın.
- [tıklayarak doğrulanamadı]

**U-07 · (13) Kapatıp açma**
- **Ben:** "Görevin notuna bir paragraf yazdım ve hemen ⌘Q yaptım. Açınca not boştu."
- **Kanıt:** `PanelField` yalnız Enter'da ya da odak kaybında kaydediyor (`DetailPanel.swift:205-206`). Uygulama kapanırken bekleyen düzenlemeyi kaydeden bir kanca yok (grep: `willTerminate` yok).
- **Önem:** veri kaybı
- **Öneri:** Yazarken kısa gecikmeyle otomatik kaydet ya da kapanışta açık alanı kaydet.
- [tıklayarak doğrulanamadı]

**U-08 · (13) İkinci süreç**
- **Ben:** "Uygulamayı ikinci kez açtım. 'Veri tabanı açılamadı… Yedekten geri yüklemek için Ayarlar › Veri' dedi. Korkup yedekten geri yükledim."
- **Kanıt:** Kilit hatası (`AppModel.swift:230-232`) aynı `startupError` ekranına düşüyor ve bu ekran her durumda yedeğe yönlendiriyor (`MarkaApp.swift:128-131`).
- **Önem:** veri kaybı riski (gereksiz geri yükleme)
- **Öneri:** Kilit durumu ayrı bir ekran olsun: "Uygulama zaten açık, oraya geç" düğmesi olsun, yedek önerisi olmasın.
- [tıklayarak doğrulanamadı]

## B. Engelleyici

**U-09 · (6) Rapor, yapay zekâ olmadan**
- **Ben:** "Yapay zekâ bağlamadım. Görevleri bitirdim ve 'Hazır, PDF al' dedim. Raporda tek bir yapılan iş yok."
- **Kanıt:** Rapora yalnız doğrulanmış iş kaydı giriyor (`ReportsView.swift:79`, report-light.png'de "İş kaydı olmayan biten görev: 2. Rapora girmez"). Arayüzde yeni iş kaydı oluşturma yolu yok; `WorkLogEditor` yalnız var olan kaydı düzenliyor (`DetailPanel.swift:290`, `WorkLogViews.swift`). `needsWorkLog` arayüzde kullanılmıyor. Asistan panelinde ise "rapor yapay zekâsız çalışır" yazıyor (flow-light.png).
- **Önem:** engelleyici (karşılamadaki vaadin karşılığı yok)
- **Öneri:** Biten görevde "İş kaydı yaz" düğmesi ve Özet'te "+ İş kaydı" olsun; ya da AI'sız kullanıcıya bunun neden boş olduğu açıkça söylensin.

**U-10 · (3) Boş marka, Özet**
- **Ben:** "İlk markamı ekledim. Özet'te 'Terminalde çalışırken Claude'dan yaptıklarını oneriler/ klasörüne yazmasını isteyebilirsin' yazıyor. Hangi terminal?"
- **Kanıt:** `FlowView.swift:50-51` (terminal kaldırıldı, metin kaldı). `TodoView.swift:138` ("terminaldeki araç") ve Hedefler'in boş durum metni de aynı (`en.lproj` satır 432 ve 682).
- **Önem:** engelleyici (ilk izlenim)
- **Öneri:** Boş durum tek bir fiille başlasın ("Görev ekle", "Dosya sürükle", "Asistana sor"); terminal ve klasör adları kalksın.

**U-11 · (9) Asistan, anahtar yokken**
- **Ben:** "'Yapay zekâya sor'a bastım. Hiçbir şey olmadı. Ertesi gün anahtar ekledim, başka bir markayı açınca kendi kendine soru gönderdi."
- **Kanıt:** `askAI` istemi `pendingChatPrompt`'a yazıyor (`AIChat.swift:~150`). `consumePending` sağlayıcı yokken istemi silmeden dönüyor (`AIChatPanel.swift:216-219`) ve marka açılınca yeniden tetikleniyor (`:21`). Düğme anahtar yokken de görünüyor (todo-light.png).
- **Önem:** engelleyici + beklenmedik ücretli çağrı
- **Öneri:** Anahtar yokken düğme "Yapay zekâyı bağla…" olsun ya da doğrudan Ayarlar'ı açsın; bekleyen istem gönderilmeden temizlensin.
- [tıklayarak doğrulanamadı]

**U-12 · (6) E-posta taslağı**
- **Ben:** "Raporu e-postayla göndermek istedim. Düğme gri. Önce PDF'i diske kaydetmem gerekiyormuş. Gmail kullanıyorum, Mail açıldı."
- **Kanıt:** E-posta düğmesi `disabled(!p.isApproved)` (`ReportsView.swift:114`). "Hazır" yapmanın tek yolu kaydetme paneli (`:263-267`). Gönderim `NSSharingService(.composeEmail)` ile yalnız Mail'e gidiyor. Kişinin e-postası okunuyor ama `recipients = []` (`:297-298`).
- **Önem:** engelleyici (Mail kullanmayan için)
- **Öneri:** "Hazır işaretle" adımını PDF kaydetmekten ayır, alıcıyı marka kişisinden doldur, Mail yoksa "PDF'i Finder'da göster + metni kopyala" yolu sun.

**U-13 · (5) Büyük dosya**
- **Ben:** "500 MB'lık bir video ve 300 sayfalık bir PDF sürükledim. Uygulama dondu."
- **Kanıt:** `addFiles` ana iş parçacığında döngüyle `addFileSource` çağırıyor (`FlowView.swift:129-134`). Bu çağrı dosyayı kopyalıyor ve `TextExtractor.extract` ile PDF metnini çıkarıyor (`Store+Sources.swift:97-104, 176-187`). Boyut sınırı ya da ilerleme göstergesi yok.
- **Önem:** engelleyici
- **Öneri:** İçe alma arka planda çalışsın, ilerleme göstersin, büyük dosyada metin çıkarmayı ertelesin.
- [tıklayarak doğrulanamadı]

**U-14 · (12) ⌘Z tutarsız**
- **Ben:** "Görev tamamlamayı ⌘Z ile geri aldım. Görev eklemeyi, başlık değiştirmeyi, dosya arşivlemeyi ve öneri onayını geri alamadım."
- **Kanıt:** `registerUndo` yalnız `TodoView` (tamamla, sürükle), `BrandProfileView` (2 yer) ve finans (sil, durum) içinde var. Panel düzenlemesi, ekleme, arşivleme ve onaylamada yok.
- **Önem:** engelleyici (güven)
- **Öneri:** Her yazma eylemine ⌘Z bağla ya da Düzen menüsündeki "Geri Al"ın neyi geri aldığını hep göster.
- [tıklayarak doğrulanamadı]

## C. Önemli

**U-15 · (7) Onay sayfası**
- **Ben:** "Onay sayfasını açtım. 6 öneri zaten işaretliydi; tek tıkla hepsini kabul ediyormuşum."
- **Kanıt:** onay-todo.png (bütün kutular dolu, "Seçilenleri onayla (6)").
- **Önem:** önemli ("AI veri değiştirmez, sen onaylarsın" vaadi)
- **Öneri:** Varsayılan seçim boş olsun ya da her satırda belirgin "Ekle / Atla" olsun.

**U-16 · (7) Onayı geri alma**
- **Ben:** "Onayladığım görevi geri almak istedim. Sayfa 'Akış'tan geri alabilirsin' diyor ama sekmelerde Akış yok, Özet var."
- **Kanıt:** onay-todo.png alt başlığı; sekmeler "Özet · Görevler · Dosyalar…" (flow-light.png). Geri alma, öneri kaydının panelinde (`DetailPanel.swift:~505`).
- **Önem:** önemli
- **Öneri:** Onaydan hemen sonra "Geri al" bildirimi göster; metinde sekme adını "Özet" yap.

**U-17 · (4) Öncelik sonradan değişmiyor**
- **Ben:** "Görevi 'Orta' öncelikle ekledim. Listede hiçbir iz yok ve sonradan önceliği değiştiremiyorum."
- **Kanıt:** Ekleme kartında Normal/Orta/Yüksek var (`TodoView.swift:~650`). Listede yalnız `priority >= 3` gösteriliyor (`:489`). Panelde öncelik ve proje alanı yok (todo-panel.png).
- **Önem:** önemli
- **Öneri:** Panele öncelik ve proje seçici ekle; "Orta" listede de görünsün.

**U-18 · (4) Bekleyen sayısı tutmuyor**
- **Ben:** "'Müşteri yanıtı bekleyen iş: 2' yazıyor. 'Bekleyenleri gör'e basınca 4 iş çıkıyor."
- **Kanıt:** todo-board.png (Bekliyor sütununda 4). Bant yalnız kararları sayıyor (`TodoView.swift:107`), süzgeç ise bütün bekleyenleri gösteriyor (`:192`).
- **Önem:** önemli
- **Öneri:** Bant ve süzgeç aynı tanımı kullansın.

**U-19 · (4) Zamanlayıcı durumu sessizce değiştiriyor**
- **Ben:** "'Bekliyor' görevde zamanlayıcıyı başlattım; görev 'Sürüyor' oldu. Başka markada çalışan sayaç da sessizce durdu."
- **Kanıt:** `Store+Tasks.swift:99-111`
- **Önem:** önemli
- **Öneri:** Başka sayaç dururken kısa bir bildirim göster; durum değişikliğini kullanıcıya bırak ya da göster.

**U-20 · (5) Aynı dosyayı iki kez eklemek**
- **Ben:** "Aynı sözleşmeyi iki kez ekledim. Listede iki kopya var, uyarı yok."
- **Kanıt:** `insertSource` içinde sha256 karşılaştırması yok (`Store+Sources.swift:207-213`). Depoda içerik adresli tek kopya var ama iki kayıt oluşuyor.
- **Önem:** önemli
- **Öneri:** Aynı özetli dosyada "Bu dosya zaten ekli (tarih)" desin, isterse yine eklesin.
- [tıklayarak doğrulanamadı]

**U-21 · (5) Eski dosya geçmişe düşüyor**
- **Ben:** "2023'te imzalanmış sözleşmeyi bugün ekledim. Özet'te 'Bugün'de görünmedi, listenin dibine gitti."
- **Kanıt:** `capturedAt = contentModificationDate ?? Date()` (`Store+Sources.swift:186`)
- **Önem:** önemli
- **Öneri:** Akış'ta ekleme tarihine göre sırala, dosya tarihini ikincil bilgi olarak göster.
- [tıklayarak doğrulanamadı]

**U-22 · (10) İngilizcede rapor**
- **Ben:** "Arayüzü İngilizceye aldım. Rapor başlığı İngilizce, tarihler '5 Ekim 2026', 'hedef tarih 7 Eki'."
- **Kanıt:** `Reports.swift:66` ve `:143` tarih biçimleyicisi `tr_TR` olarak sabit.
- **Önem:** önemli (müşteriye giden belge)
- **Öneri:** Rapor dili ayrı seçilebilsin, tarih biçimi o dilden gelsin.

**U-23 · (10) İngilizcede asistan**
- **Ben:** "İngilizce arayüzde 'Ask AI: What should I do?' dedim. Sohbette benim adıma upuzun Türkçe bir paragraf göründü."
- **Kanıt:** `ChatPrompts.whatToDo` ve hazır istemler Türkçe sabit (`AIChat.swift:153-172`). `send` bu metni kullanıcı balonu olarak ekliyor (`AIChat.swift:~85`).
- **Önem:** önemli
- **Öneri:** Balonda kısa etiket ("Ne yapmalıyım?") görünsün, iç talimat gizli ve dile göre olsun.
- [tıklayarak doğrulanamadı]

**U-24 · (10) Dil değiştirme**
- **Ben:** "Dili uygulamanın içinden değiştirmek istedim. Ayarlar'da dil seçeneği yok."
- **Kanıt:** SettingsView'da yalnız Genel ve Veri sekmesi var; `L()` her zaman sistem dilini izliyor (`Store.swift:5-7`).
- **Önem:** önemli
- **Öneri:** Ayarlar'a "Dil: Sistem / Türkçe / English" ekle ya da macOS'taki uygulama başına dil ayarına giden yolu göster.

**U-25 · (11) Gece yarısı**
- **Ben:** "Uygulama gece açık kaldı. Sabah Bugün ekranında hâlâ dünün tarihi vardı, geciken iş de güncellenmemişti."
- **Kanıt:** TodayView tarihi gövdede `Date()` ile hesaplıyor (`TodayView.swift:67`). Gün değişimi gözlemcisi yok (grep: `NSCalendarDayChanged` yok).
- **Önem:** önemli
- **Öneri:** Gün değişiminde ve saat dilimi değişiminde ekranlar tazelensin.
- [tıklayarak doğrulanamadı]

**U-26 · (8) Arşivlenmiş adla yeni marka**
- **Ben:** "Eski müşteriyi arşivlemiştim. Aynı adla yeniden eklemek istedim; 'zaten var' dedi ama listede yok."
- **Kanıt:** `insertBrand` arşivliler dahil bütün adlara bakıyor (`Store+Brands.swift:54-58`).
- **Önem:** önemli
- **Öneri:** Hata "Bu ad arşivde: Geri getir?" desin ve tek tıkla arşivden çıkarsın.

**U-27 · (9) Asistan hatası**
- **Ben:** "İnternet yokken sordum. Kırmızı hata çıktı, yazdığım soru kayboldu, 'Tekrar dene' yok."
- **Kanıt:** `send` taslağı baştan temizliyor (`AIChat.swift:~70`). Hata yalnız kırmızı metin olarak çıkıyor (`AIChatPanel.swift:~250`) ve yeniden gönderme düğmesi yok.
- **Önem:** önemli
- **Öneri:** Hatalı mesajda "Tekrar dene" olsun ve taslak geri yüklensin; anahtar hatasında "Ayarlar'da anahtarı düzelt" bağlantısı çıksın.
- [tıklayarak doğrulanamadı]

**U-28 · (14) Stüdyo kavramı**
- **Ben:** "Kenar çubuğunda 'Stüdyo' ve 'Stüdyoyu kur — Biz kimiz, ekip' gördüm. Ben tek kişiyim; ekip, şema, kıdem, 'Yapay zekâ çalışan', 'Yetenek' bana ne?"
- **Kanıt:** sirket-light.png (Hizmet, İnsan, Yapay zekâ çalışan, Yetenek, Bekleyen öneri kutucukları; Genel / Hizmetler / Ekip / Şema / Yetenekler) ve `CompanyView.swift:10-15` (Stajyer…Direktör).
- **Önem:** önemli (jargon)
- **Öneri:** Tek kişilik kullanıcı için "Kendi işlerim" adıyla sade başlasın; ekip, şema ve yetenek gelişmiş bölüm olarak gizlensin.

**U-29 · (14) Jargon yoğunluğu**
- **Ben:** "'Doğrulanmadı', 'Söz', 'Hafıza güncellemeleri', 'Bağlam boyutu (token): ~298', 'Token: ~25', 'Çıktı', 'İş kaydı' ne demek?"
- **Kanıt:** flow-light.png ("Doğrulanmadı 5", "Söz"), info-light.png (token sayıları), files-light.png ("Çıktı"), onay-todo.png ("Hafıza güncellemeleri").
- **Önem:** önemli
- **Öneri:** Token sayıları geliştirici ayrıntısına taşınsın; "Doğrulanmadı" yerine "Senin onayını bekleyen iş notu" gibi bir anlatım kullanılsın ve ilk görüşte açıklama ipucu verilsin.

**U-30 · (12) Kısayolları bulmak**
- **Ben:** "Kısayolların listesini aradım. Yardım menüsü bomboş."
- **Kanıt:** `CommandGroup(replacing: .help) {}` (`MarkaApp.swift:118`). ⌘1–⌘6 yalnız ipucunda yazıyor (`BrandView.swift:52`).
- **Önem:** önemli
- **Öneri:** Yardım menüsüne "Klavye kısayolları" sayfası ekle; ⌘K paletinde kısayolları göster.

**U-31 · (12) İki ayrı arama**
- **Ben:** "Kenar çubuğundaki 'Ara ⌘K' ile Bugün'deki 'Kayıtlarda ara ⌘F' farklı şeyler buluyor. ⌘K görev adını bulmuyor."
- **Kanıt:** bugun-light.png (iki arama kutusu). Palet yalnız marka, bölüm ve komut içeriyor (`CommandPalette.swift:26-46`).
- **Önem:** önemli
- **Öneri:** Tek arama olsun: ⌘K kayıtları da arasın.

**U-32 · (13) Çok pencere**
- **Ben:** "Dosya › Yeni Pencere ile iki pencere açtım. Birinde marka değiştirince öteki de değişti."
- **Kanıt:** `WindowGroup` tek `AppModel.shared` paylaşıyor (`MarkaApp.swift:26-31`; `selection` modelde). Ayrıca ⌘N "Yeni görev"e verilmiş (`:69`); sistemin "Yeni Pencere" ⌘N'iyle çakışma olasılığı var.
- **Önem:** önemli
- **Öneri:** Tek pencereli `Window` kullan ya da seçimi pencereye özel yap.
- [tıklayarak doğrulanamadı]

**U-33 · (10) 1000+ görev**
- **Ben:** "1000 görevi içe aktardım, zamanlayıcıyı başlattım. Görevler ekranı takılıyor."
- **Kanıt:** TodoView gövdesi her çizimde `store.todo`, `store.tasks` ve `store.projects` okuyor (`TodoView.swift:92, 100, 239-241`). Liste tembel değil (`VStack`, `:134`). Satırlar `app.elapsed`'i aynı gövdede okuduğu için sayaç her saniye bütün gövdeyi (ve sorguları) yeniden çalıştırabilir (`:446`).
- **Önem:** önemli
- **Öneri:** Satırı ayrı görünüm yap, sayacı yalnız çalışan satıra bağla, `LazyVStack` kullan.
- [ölçülmedi, tıklayarak doğrulanamadı]

**U-34 · (2) Asistan paneli yer kaplıyor**
- **Ben:** "Yapay zekâ bağlamadım ama sağdaki boş 'Yapay zekâyı bağla' paneli her bölümde ekranın üçte birini kaplıyor."
- **Kanıt:** flow / todo / files / finance / report-light.png. `showAssistant` varsayılanı `true` (`AppModel.swift:134, 205`).
- **Önem:** önemli
- **Öneri:** Anahtar yoksa panel varsayılan olarak kapalı olsun, araç çubuğundaki ✨ düğmesi davet etsin.

## D. Sürtünme

**U-35 · (1) Karşılama ekranı**
- **Ben:** "Karşılamada 'Verin Mac'inde saklanır' ve 'tek tıkla PDF' yazıyor. Neyin yapay zekâ gerektirdiğini anlamadım."
- **Kanıt:** `OnboardingView.swift:21-24`. "Burada onayla" ve "Asistana sor" maddeleri AI'ya bağlı; "Müşteriye raporla" ise AI'sız iş kaydı oluşturulamadığı için fiilen AI'ya bağlı (bkz. U-09).
- **Önem:** sürtünme
- **Öneri:** AI gerektiren maddeleri işaretle; karşılamadan bir tıkla anahtar ekleme yolu ver.
- [görüntü yok, kod]

**U-36 · (1) Örnek veri gerçek alana yazılıyor**
- **Ben:** "Önce örnek markayla gezdim, sonra kendi markamı ekledim. Örnek marka gerçek verimin arasında kaldı."
- **Kanıt:** `startSample` → `createSampleBrand` gerçek veri alanına yazıyor (`OnboardingView.swift:72-79`).
- **Önem:** sürtünme
- **Öneri:** İlk gerçek marka eklenince "Örnek markayı kaldırayım mı?" diye sor.

**U-37 · (4) Notlarda yeni satır**
- **Ben:** "Notlar alanında Enter'a bastım. Yeni satıra geçmek yerine kaydetti."
- **Kanıt:** `PanelField` dikey TextField + `.onSubmit(commit)` (`DetailPanel.swift:200-205`).
- **Önem:** sürtünme
- **Öneri:** Notlar için TextEditor kullan; Enter yeni satır olsun.
- [tıklayarak doğrulanamadı]

**U-38 · (4) Sorumlu rozeti**
- **Ben:** "Her görevin sağında daire içinde bir 'C' var. Ne olduğunu anlamadım."
- **Kanıt:** todo-light.png, todo-dark.png. Sorumlu baş harfi; yalnız ipucunda açıklanıyor (`TodoView.swift:498-509`).
- **Önem:** sürtünme
- **Öneri:** Sütun başlığı ya da adın tamamı göster; boşken hiç gösterme.

**U-39 · (4) Ayrıntı paneli listeyi kesiyor**
- **Ben:** "Görev panelini açınca liste yarıdan kesildi; başlıkları okuyamıyorum."
- **Kanıt:** todo-panel.png ("Sertifika görsellerini c…", "Müşteri yanıtı bekleyen iş…").
- **Önem:** sürtünme
- **Öneri:** Panel açıkken asistanı otomatik daralt ya da listeyi yeniden akıt.

**U-40 · (4) Yeni görev nereye gitti**
- **Ben:** "Yeni görev ekledim. Listede bulamadım; 'Diğer' grubunun en altına düşmüş."
- **Kanıt:** Projesiz görev "Diğer"e gidiyor, o grup en sonda (`TodoView.swift:237-251`); ekleme kartında proje seçimi yok.
- **Önem:** sürtünme
- **Öneri:** Eklenen satıra kaydır ve vurgula; kartta proje seçici olsun.
- [tıklayarak doğrulanamadı]

**U-41 · (4) Tercihler unutuluyor**
- **Ben:** "Sıralamayı 'Teslim tarihi' yaptım, Pano'ya geçtim. Marka değiştirip dönünce hepsi sıfırlanmış."
- **Kanıt:** `sort`, `mode` ve `collapsed` yalnız `@State` (`TodoView.swift:20-23`), tercihe yazılmıyor.
- **Önem:** sürtünme
- **Öneri:** Marka başına görünüm ve sıralama hatırlansın.
- [tıklayarak doğrulanamadı]

**U-42 · (5) Bağlantı adresi**
- **Ben:** "Bağlantı adresine 'ornek.com' yazdım, hata verdi."
- **Kanıt:** Yalnız http(s) şemasıyla başlayan adres kabul ediliyor (`Store+Sources.swift:151-152`).
- **Önem:** sürtünme
- **Öneri:** Şema yoksa `https://` kendiliğinden eklensin; bağlantı adı boşsa alan adından doldurulsun.

**U-43 · (5) Önizlemeler**
- **Ben:** "Dosyalar galerisinde küçük resimler bomboş; Markdown dosyası panelde '# Başlık' diye ham görünüyor."
- **Kanıt:** files-light.png (kartın tepesinde yalnız 2 küçük satır), flow-panel.png ("# Musteri Referanslari").
- **Önem:** sürtünme
- **Öneri:** Metin dosyalarında simge ve ilk satırlar gösterilsin, Markdown biçimlenmiş görünsün.

**U-44 · (5) Dosya arşivleme onaysız**
- **Ben:** "Panelde 'Arşivle' ile 'Aç' yan yana. Yanlışlıkla arşivledim."
- **Kanıt:** flow-panel.png; onay ya da ⌘Z yok (bkz. U-02).
- **Önem:** sürtünme
- **Öneri:** Arşivleme sonrası "Geri al" bildirimi göster.

**U-45 · (6) Rapor geçici dosyaları**
- **Ben:** "Her e-posta taslağında veri klasörüne bir PDF yazılıyormuş ve hiç silinmiyor."
- **Kanıt:** `workspace/Gecici/<marka> rapor vN.pdf` (`ReportsView.swift:286-290`); temizleyen kod yok (grep).
- **Önem:** sürtünme (gizlilik ve disk)
- **Öneri:** Gönderimden sonra ya da açılışta eski geçici PDF'ler silinsin.

**U-46 · (6) Gantt**
- **Ben:** "Gantt'ta çubuk yok, yalnız son tarih elması var. Hafta sütunları da '1–8 Eki' gibi 8 günlük."
- **Kanıt:** todo-gantt.png
- **Önem:** sürtünme
- **Öneri:** Başlangıç tarihi yoksa görünüm "Zaman çizelgesi" diye adlandırılsın; haftalar Pazartesi başlasın, 7 gün olsun.

**U-47 · (8) Şirket bilgileri**
- **Ben:** "Şirket › Genel'de bilgileri değiştirip başka sekmeye geçtim. Kaydet'e basmadığım için gitti mi, bilemedim."
- **Kanıt:** Şirket formu açık Kaydet düğmesi istiyor (`CompanyView.swift:265`); marka alanları ise kendiliğinden kaydediyor. Kaydedilmemiş değişiklik uyarısı bulamadım.
- **Önem:** sürtünme
- **Öneri:** Tek bir kayıt modeli olsun (otomatik kayıt).
- [tıklayarak doğrulanamadı]

**U-48 · (10) Görünüm ayarı**
- **Ben:** "Mac'im koyu modda, uygulama açık açıldı."
- **Kanıt:** `appearance` varsayılanı `"light"` (`AppModel.swift:85, 208`).
- **Önem:** sürtünme
- **Öneri:** Varsayılan "Sistem" olsun.

**U-49 · (10) Pencere 1100 px**
- **Ben:** "Pencereyi en küçüğe aldım. Araç çubuğunda uzun marka adı, 6 bölümlük seçici ve ✨ ile ··· birbirine sıkışıyor."
- **Kanıt:** min 1100 (`MarkaApp.swift:34`), bölüm seçici `minWidth: 440` (`BrandView.swift:51`), asistan en az 315 + sayfa en az 460. Bu genişlikte görüntü alamadım (betik sabit boyutla açıyor).
- **Önem:** sürtünme
- **Öneri:** Dar genişlikte ··· menüsü taşma menüsüne düşmesin; marka adı kısaltılsın.
- [tıklayarak doğrulanamadı]

## E. Kozmetik

**U-50 · (3) Sektör ve kişi kesiliyor**
- **Ben:** "Marka Bilgileri'nde sektör 'Yangın güvenl…', kişi 'Satın alma müd…' diye kesiliyor; Dosyalar alt başlığı da 'bağlant…'."
- **Kanıt:** info-light.png, files-light.png
- **Önem:** kozmetik
- **Öneri:** İki satıra izin ver ya da ipucunda tam metni göster.

**U-51 · (2) Özet ile Bugün kutucukları**
- **Ben:** "Özet'te 'Bu hafta biten', Bugün'de 'Bu hafta biten görev' yazıyor; Bugün'ün listesi ise 'Bu hafta yapılan'."
- **Kanıt:** bugun-light.png, flow-light.png
- **Önem:** kozmetik
- **Öneri:** Aynı kavrama tek ad ver.

**U-52 · (5) Örnek dosya adları**
- **Ben:** "Örnek dosya adları 'Musteri Referanslari', 'Egitim Senaryosu' diye Türkçe karaktersiz."
- **Kanıt:** files-light.png, flow-light.png
- **Önem:** kozmetik
- **Öneri:** Örnek veride Türkçe karakter kullan; kullanıcı dosyasında da başlık düzenlenebilsin.

**U-53 · (10) Ekran okuyucu tarihi**
- **Ben (VoiceOver):** "Son tarih '2026-10-19' diye okunuyor."
- **Kanıt:** `TodoView.swift:479` (`LF("Son tarih %@", d)`, ham gün dizesi)
- **Önem:** kozmetik
- **Öneri:** Okunurken yerel tarih biçimi kullanılsın.

**U-54 · (11) Hafta başlangıcı**
- **Ben:** "Hafta Pazartesi başlıyor, iyi. Ama İngilizce arayüzde de hep Pazartesi; ayarı yok."
- **Kanıt:** `firstWeekday = 2` sabit (`Status.swift:86`), todo-calendar.png ("Pzt…Paz")
- **Önem:** kozmetik
- **Öneri:** Sistem tercihi izlensin ya da Ayarlar'da seçilebilsin.

---

**Öne çıkan beş konu:**
1. Yapay zekâ yokken rapor boş kalıyor; iş kaydını elle oluşturmanın yolu yok (U-09).
2. Görev silinince faturalık süreler de siliniyor (U-01).
3. Arşivlenen dosya bir daha bulunamıyor (U-02).
4. Yanlış süre kaydı düzeltilemiyor (U-03).
5. Yeni markanın Özet'inde terminal ve `oneriler/` jargonu var (U-10).
