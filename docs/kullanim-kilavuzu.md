# Kullanım kılavuzu

Workspace AI 0.4.0 (eski adıyla Marka Çalışma Alanı / Brand Workspace) için ekran ekran anlatım. Kısa tanıtım için [README](../README.md). Burada yazılanlar kodda ve testlerde bulunan davranışlardır; gerçek pencerede tıklanarak tam denenmeyenler [bilinen sınırlar](bilinen-sinirlar.md) belgesindedir. Örneklerdeki adlar uydurmadır.

> Eski sürümlerdeki gömülü terminal 0.3.0'da kaldırıldı; yerine yan Asistan paneli geldi. 0.2.1 dönemine ait terminal anlatımı bu kılavuzdan çıkarıldı.

## Genel yapı

Pencerenin solunda **kenar çubuğu**, ortasında seçili ekran, sağında isteğe bağlı **Asistan paneli** (⌘J) bulunur. Kenar çubuğu üç parçadır:

- **Bugün** (⌘0): tüm etkin markalarda tek bakış.
- **Stüdyo** (⌘9): kendi şirketinin iş alanı.
- **Markalar**: her marka bir satırdır; onay bekleyen sayısı (öneriler + klasörde henüz eklenmemiş dosyalar) satırın yanında görünür. En altta *+ Marka* (⇧⌘N).

Arayüz Türkçe ve İngilizcedir. Görünüm modu (Açık / Koyu / Sistem) Görünüm menüsünden ya da Ayarlar'dan seçilir.

## Bugün

Tüm etkin markalarda (arşivlenenler hariç) dört liste: **Onay bekliyor** (marka, sayı, *İncele*), **Geciken**, **Bu hafta yapılan** ve **Karar bekleniyor** (müşteriden beklenen kararlar). Boş liste tek satır sade metinle söylenir. Her satır kaydın yerine götürür: marka açılır, ilgili sekmeye geçilir. Üstteki arama (⌘F) tüm markalarda kayıt başlıklarına bakar.

## Marka ekranı

Başlıkta marka adı; sağda Asistan düğmesi ve *···* menüsü. Sekmeler (⌘1 … ⌘6 sırasıyla):

### Özet (⌘1)
Markanın tek bakışlık özeti ve **Akış**: günlere göre, en yeni üstte (son 200 öğe), tek satırlık öğeler: iş kaydı (doğrulanmamışsa "Doğrulanmadı"), biten görev, not, dosya, kapanan söz / karar / talep ve onaylanan öneri. Satıra tıklayınca sağda ayrıntı paneli açılır; iş kaydı yalnız orada, içeriği görülerek doğrulanır. Onaylanan öneride *Geri al* vardır. Üstte *Not ekle*; dosya Akış'a sürüklenebilir ya da marka klasörüne konabilir (klasördeki dosya onay sayfasına düşer).

### Görevler (⌘2)
Tek liste: açık görevler, sözler, karar bekleyenler, açık talepler. Dört görünüm: **Liste**, **Pano** (durum sütunları; kartı sürükleyip bırakarak durum değiştirilir, ⌘Z geri alır), **Gantt** ve **Takvim** (aynı görevlerin zaman görünümü; teslim tarihine göre). Satır başındaki kutu tamamlar; satıra tıklayınca sağ panelde başlık, notlar, durum, son tarih ve sorumlu satır içinde düzenlenir, altta *Sil…* (onaylı). Tamamlananlar ⇧⌘H ile gösterilir/gizlenir. Ekleme alanı "Yeni görev — ↩" (⌘N de görev ekler); tür seçimiyle söz de eklenir.

**Zamanlayıcı:** satırdaki zamanlayıcı düğmesiyle o göreve süre tutulur. Çalışırken menü çubuğunda canlı süre görünür; çentikli MacBook'ta ayrıca çentikten sarkan küçük bir **çentik adası** gösterilir (Ayarlar › Zamanlayıcı › *Çentikte göster* ile kapatılır; *Çentikten gizle* sayacı durdurmaz). Çentiğin fiziksel görünümü gerçek donanımda denenmedi.

### Dosyalar (⌘3)
Markanın malzemeleri, belgeleri ve bağlantıları: Galeri ya da Liste görünümü, arama, *Dosya ekle*, *Bağlantı ekle*. Eklenenler markanın **değişmez kaynaklarıdır**: silinmez, yalnızca arşivlenir.

### Marka Bilgileri (⌘4)
Asistanın okuduğu ortak bağlam. Dört bölüm:

- **Profil:** marka ne yapıyor, ne satıyor, kimin için. Bölümler dolu/eksik gösterilir; doldurduğun bölümler asistanın bağlamına girir. *Yapay zekâ gözüyle bak* asistanın okuyacağı bağlamı gösterir (marka klasöründeki `BAGLAM.md` da bu bağlamdan yazılır). *Asistana sor* sohbette taslak çıkarır; kaydı sen yaparsın.
- **Hedefler:** görevlerin nedenini ve beklenen çıktıyı netleştirir. İlerleme çubukları bağlı görevlerin tamamlanmasını gösterir; ticari sonuç iddiası taşımaz.
- **Kişiler ve projeler:** kişi adı, rolü, iletişim bilgileri ve projeler (alan adı "Amaç"). Kişilerin iletişim bilgileri yapay zekâya gönderilen bağlama eklenmez.
- **Ayrıntılar ve izinler:** sektör, kısa tanım ve **AI izinleri** (Claude, Codex). İzin markaya özeldir ve varsayılan olarak kapalıdır; yalnız izin verdiğin sağlayıcıya o markanın içeriği gider.

### Finans (⌘5)
Danışmanlık ücreti, ödeme planı ve çalışma bütçesi: ödeme satırları (planlandı / bekliyor / tahsil edildi), bu ay tahsil edilen, bu ay beklenen, toplam bekleyen ve bu ay çalışma süresi. Danışmanlık ilişkisini **takip eder**; muhasebe, banka bağlantısı ya da otomatik tahsilat yapmaz.

### Rapor (⌘6)
Müşteriye ne gidecek: dönem menüsüyle (bu hafta, geçen hafta, bu ay, geçen ay) **doğrulanmış iş kayıtlarından** canlı önizleme. Her maddenin bir dayanağı vardır; maddeye tıklamak dayanağı açar. Durum *Taslak / Hazır*. Taslakta birincil düğme **Hazır, PDF al** (raporu hazır işaretler, filigransız PDF kaydeder; kaydetme panelinde vazgeçilirse taslak kalır), hazırken **PDF**. *···* menüsünde *Düzenle* ve *E-posta taslağı…* (Mail'de taslak açar, göndermez; otomatik gönderim yoktur). Markada Claude/Codex izni varsa *AI ile özet* kullanılabilir; dayanak göstermeyen cümle atılır. Doğrulanmamış iş kayıtları ve iş kaydı olmadan biten görevler önizlemenin üstünde tek satırda söylenir. Altta açılır **Geçmiş**: sürümler, paylaşımlar, markanın diğer raporları.

### *···* menüsü
Klasörü Finder'da göster, Dışa aktar…, Arşivle… ve onay sayfası.

## Onay sayfası (onayın tek yeri)

Onay bekleyen varsa sekmelerin üstünde "N onay bekliyor · İncele" bandı çıkar. Sayfada gruplu satırlar: Görevler, iş kayıtları, notlar, **Dosyalar** (marka klasöründe henüz eklenmemiş dosyalar) ve hafıza güncellemeleri. Satırlar varsayılan seçilidir; başlık ve son tarih düzeltilebilir. *Seçilenleri onayla (N)* **yalnız seçilenleri** uygular; **seçilmeyenler bekler** ve sayıda görünmeye devam eder. *Tümünü reddet…* ayrı ve onaylıdır. *Vazgeç* (Esc) hiçbir şey yapmaz. Onaylanan her öneri Akış'ta "Öneri onaylandı" satırı olur ve oradan *Geri al* ile geri alınır.

Menü çubuğu simgesi de bekleyen onayları marka başına gösterir ve ilgili markanın onay sayfasını açar.

## Asistan paneli (⌘J)

Sağdaki yan panel. Marka seçiliyken o markanın **kendi kayıtlarını okur** (görev, not, dosya, çalışma kayıtları, bilgi sayfaları) ve ne yapılacağını söyler. Sağlayıcı Ayarlar'da bağlanır: **Claude API anahtarı** (senden alınır; Keychain'de durur, kullanım başına ücretlidir) ya da isteğe bağlı **Codex** girişi. Marka için yapay zekâ izni kapalıysa panel izin ister (*İzin ver* / *Reddet*); izin verilmeden o markanın içeriği hiçbir sağlayıcıya gitmez.

- **Önerir, yazmaz.** Asistan yalnızca öneri araçlarını kullanır: görev, görevi tamamla, iş kaydı, marka kaydı (söz/talep/karar), çıktı dosyası, bilgi sayfası güncellemesi. Önerilen her şey onay sayfasına düşer; asistan veri tabanına kendisi yazamaz. Araçlar başka markanın kimliğini reddeder.
- **Ekip üyesi rolüyle sohbet.** "Kim olarak çalışsın?" ile ekipteki bir üyenin rolü seçilir; üyenin görev tarifi ve yetenekleri o sohbetin bağlamına girer. Rol yalnız tek marka sohbetinde kullanılır.
- **Tüm markalar sohbeti.** Genel bakış için tüm markalar kapsamı vardır.
- **Çalışan öner.** Ekibe yeni **yapay zekâ çalışan** önerisi (`calisan_oner`) **yalnız Stüdyo sohbetinde** verilebilir; insan eklenemez. Öneri onaylanınca ekibe girer, geri alınınca arşivlenir.

Canlı Claude yanıtı gerçek bir anahtarla denenmedi (bkz. bilinen sınırlar).

## Stüdyo

Kendi şirketin de bir iş alanıdır; marka ekranıyla aynı sekmeler vardır, yalnız *Marka Bilgileri* sekmesi **Şirket** adını alır. İlk açılışta şirket adıyla kurulur. *Şirket* sekmesi:

- **Genel:** ad, slogan, web sitesi, kuruluş, misyon. Bu bilgiler, yapay zekâya izin verdiğin her markanın bağlamına girer; müşteri verisi içermez.
- **Hizmetler:** sunduğun hizmetler (sürüyor / planlanan / durduruldu); yapay zekâ müşteriye ne sattığını buradan öğrenir.
- **Ekip:** insanlar ve **yapay zekâ çalışanlar** (ad, unvan, kıdem: stajyerden direktöre, bağlı olduğu kişi, görev tarifi, yetenekleri). Yapay zekâ çalışan **rol tanımıdır**: atandığı markanın yapay zekâ bağlamına girer, kendi başına çalışmaz; ürettiği her şey öneridir ve onayı sendedir. Arşivlenen üye şemadan çıkar ve astları onun yöneticisine bağlanır.
- **Şema:** ekibin organizasyon şeması.
- **Yetenekler:** yetenek kütüphanesi. Yetenek, çalışana verdiğin küçük bir çalışma yöntemidir (`SKILL.md` biçimi: `name` ve `description` başlığı + yönergeler). *Hazır paket yükle*, *SKILL.md içe aktar…* ya da *Yetenek ekle*; *SKILL.md kopyala* ile dışa verilir. **Yetenek yetki vermez:** yapay zekâ çalışan yeteneğiyle de yalnızca öneri üretir.

## Komut paleti (⌘K) ve menü çubuğu

- **⌘K:** marka, bölüm ya da komut ara ("Markaya git", *Görev ekle*, *Yeni marka…*, Asistanı göster/gizle, Bugün) ve "Yapay zekâya sor: Ne yapmalıyım?".
- **Menü çubuğu paneli:** Ayarlar › Genel › *Menü çubuğunda göster* ile açılır. Bekleyen onaylar marka başına listelenir; çalışan zamanlayıcıyı durdurabilirsin. Açıkken pencereyi kapatsan da uygulama çalışmaya devam eder. Panelin gerçek menü çubuğunda tıklanarak denenmediği bilinen sınırlarda yazılıdır.

## Marka klasörü ve `oneriler/` dosyaları

Her markanın bir klasörü vardır. Klasöre konan dosyalar onay sayfasına düşer. Uygulama ayrıca marka klasöründeki `oneriler/<tarih>-<konu>.json` dosyalarını da okuyup bekleyen öneriye çevirir (şema `BAGLAM.md` içinde; marka ekranı açıkken 3 saniyede bir taranır; işlenen dosya `oneriler/islenmis/` altına taşınır). Bu köprü 0.2.x'ten kalmadır; **eski** terminalin kaldırılmasıyla ilgisi yoktur, kendi terminalinde çalıştırdığın bir aracın bu klasöre yazması yeterlidir. Gerçek bir Claude Code/Codex CLI oturumunun bu dosyayı talimata uygun yazdığı denenmedi.

## Ayarlar (⌘,)

- **Genel:** Claude API anahtarı (*Kaydet ve doğrula*; kayıtlıysa *Kaldır*), Codex girişi (tarayıcıda; durum kendiliğinden yenilenir), zamanlayıcı (*Çentikte göster*), görünüm modu, menü çubuğu.
- **Veri:** konum (*Finder'da göster*), yedekler (*Şimdi yedekle*; her satırda *Geri yükle…*), arşivlenmiş markalar (*Arşivden çıkar*), eski görev listesini içe aktar, *Tanı bilgisini kopyala* (marka adı, içerik ve dosya yolu içermez; hiçbir yere kendiliğinden gönderilmez). Her gün ilk açılışta otomatik yedek alınır, son 14'ü saklanır; geri yüklemeden ve veri tabanı geçişinden önce mevcut veri ayrıca yedeklenir.

## Menü ve kısayollar

⌘0 Bugün · ⌘9 Stüdyo · ⌘1 … ⌘6 marka sekmeleri · ⌘J Asistan · ⌘K Komut paleti · ⌘F Ara · ⌘N Yeni görev · ⇧⌘N Yeni marka · ⇧⌘H Tamamlananları göster/gizle · ⌘, Ayarlar.

## Güvence kuralları (kodda zorunlu)

1. **Marka yalıtımı.** Her okuma ve yazma marka kimliğiyle kapsanır. Asistan araçları başka markanın kimliğini reddeder; oturumun markası sonradan değişmez (SQL tetikleyicisi). İzin verilmeyen sağlayıcıya istek gitmez.
2. **Kaynak değişmez.** Ham dosya ve not içeriği SQL tetikleyicisiyle değiştirilemez; yalnızca arşivlenir.
3. **AI veri değiştirmez, öneri üretir.** Öneriler kullanıcı onayıyla uygulanır ve geri alınabilir.
4. **Rapor maddesi dayanaksız olamaz.** Rapordaki "yapılan işler" yalnızca doğrulanmış iş kayıtlarından gelir; AI özet cümlesi geçerli madde referansı taşımıyorsa atılır.
5. **Her yazma denetim olayı bırakır.** Günlük otomatik yedek alınır; geri yüklemeden önce mevcut veri yedeklenir.
6. **İçerik Mac'ten yalnızca izin verilen sağlayıcıya gider.** Veriler Mac'te yerel saklanır; yapay zekâyı açtığın markanın içeriği, yalnız o marka için izin verdiğin sağlayıcıya (Anthropic/Codex) gönderilir. Tanı bilgisi yalnızca sürüm, macOS, mimari, dil, kayıt sayıları, AI bağlantı durumu, hataların türü ve beta ölçümlerini taşır; hata mesajı, marka adı, dosya/not metni, e-posta ve dosya yolu yazılmaz (test ayırt edici içerikle doğrular). Son 200 hata çalışma alanındaki `tani-kayitlari.json` dosyasında durur ve hiçbir yere kendiliğinden gönderilmez.
7. **Yapmadığımızı vaat etmeyiz.** Doğrulanmayan şey [bilinen sınırlar](bilinen-sinirlar.md) belgesinde ve README "Durum" bölümünde açıkça yazılır.

`oneriler/*.json` dosyası yalnızca bulunduğu markaya öneri olur (dosyadaki marka adı yok sayılır); sembolik bağ, marka klasörü dışını gösteren yol, 256 KB'tan büyük dosya, 50'den fazla öğe ve şema dışı değer reddedilir.
