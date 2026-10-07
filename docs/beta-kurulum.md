# Workspace AI — beta kurulum rehberi

> **Durum (2026-10-04): beta henüz yapılmadı.** Uygulama 0.4.0 ve geliştirme aşamasındadır; katılımcıya paket gönderilmedi. Bu rehber, beta başladığında kullanılacak taslaktır. Hedef dağıtım Mac App Store'dur ([dağıtım kararı](dagitim-ve-saglayicilar.md)); aşağıdaki Gatekeeper adımları yalnız App Store dışı, ad-hoc imzalı beta paketi içindir. Uygulama terminal içermez: yapay zekâ, yan **Asistan** panelindedir.

Bu rehber beta katılımcısı içindir. Teknik bilgi gerekmez; adımları sırayla izle.
Takıldığın her yerde bize yaz — takıldığın yer bizim için ölçümdür.

## Gerekenler

- **macOS 14 (Sonoma) veya daha yenisi.** Sürümünü görmek için: Apple menüsü › Bu Mac Hakkında.
- **Apple Silicon işlemcili Mac** (M1, M2, M3, M4 …). Aynı pencerede "Çip: Apple M…" yazıyorsa uygundur.
  "İşlemci: Intel" yazıyorsa bu beta paketi o Mac'te açılmaz; bize haber ver.
- Sana gönderilen `MarkaCalismaAlani-0.4.0.dmg` dosyası (sürüm numarası farklı olabilir).

## 1. Kurulum

1. İndirdiğin `MarkaCalismaAlani-….dmg` dosyasına çift tıkla. Bir pencere açılır; içinde **Workspace AI** uygulaması
   ve **Applications** (Uygulamalar) klasörünün kısayolu vardır.
2. **Workspace AI** simgesini sürükleyip **Applications** kısayolunun üzerine bırak. Kopyalama birkaç saniye sürer.
3. Pencereyi kapat. Finder'ın kenar çubuğunda disk görüntüsünün adının yanındaki ⏏ (çıkar) düğmesine bas.
   İstersen `.dmg` dosyasını artık silebilirsin.

Uygulamayı disk görüntüsünün içinden değil, **Uygulamalar** klasöründen aç. Disk görüntüsü çıkarılınca içindeki uygulama
da kaybolur ve Gatekeeper izni kalıcı olarak kaydedilmez.

## 2. İlk açılış (Gatekeeper uyarısı)

Beta paketi henüz Apple tarafından onaylanmış (notarize edilmiş) bir geliştirici kimliğiyle imzalı değil. Bu yüzden macOS
ilk açılışta uygulamayı engeller ve "Apple, bu uygulamanın kötü amaçlı yazılım içermediğini doğrulayamadı" benzeri bir uyarı
gösterir. Bu beklenen bir durumdur; bir kez izin verdikten sonra uygulama normal açılır.

> Paket Developer ID ile imzalanıp notarize edilmişse bu bölümü atla: uygulamaya çift tıklaman yeterli, uyarı çıkmaz
> (en fazla "İnternetten indirildi, açmak istiyor musun?" sorusu gelir; **Aç**'a bas).

### macOS 14 (Sonoma)

1. Finder'da **Uygulamalar** klasörünü aç (Launchpad'den değil).
2. **Workspace AI** simgesine **sağ tıkla** (ya da Kontrol tuşuna basılı tutarak tıkla) ve menüden **Aç**'ı seç.
3. Çıkan uyarıda **Aç**'a bas.

Alternatif: Uygulamayı açmayı bir kez dene, sonra Apple menüsü › **Sistem Ayarları** › **Gizlilik ve Güvenlik**
bölümünde aşağı kaydırıp **Yine de Aç**'a bas.

### macOS 15 (Sequoia) ve sonrası

macOS 15'te sağ tık › Aç yolu artık uyarıyı geçmez. Şöyle yap:

1. **Uygulamalar** klasöründe **Workspace AI**'a çift tıkla. Uyarı çıkar; **Bitti**'ye bas
   (**Çöp Sepetine Taşı**'ya basma).
2. Apple menüsü › **Sistem Ayarları** › kenar çubuğunda **Gizlilik ve Güvenlik** (gerekirse kenar çubuğunu aşağı kaydır).
3. Sağ tarafta **Güvenlik** başlığına kadar aşağı kaydır. "Workspace AI engellendi…" satırının yanındaki
   **Yine de Aç** düğmesine bas. Bu düğme uygulamayı açmayı denedikten sonra **yaklaşık bir saat** görünür; görmüyorsan
   1. adımı tekrarla.
4. Mac'inin giriş parolasını gir ve **Tamam**'a bas. Uyarı son bir kez çıkar; **Aç**'a bas.

Bundan sonra uygulama bir istisna olarak kaydedilir ve normal şekilde çift tıklayarak açılır.

**"Hasarlı ve açılamıyor" uyarısı görürsen** bu adımlar işe yaramaz; uygulamayı Çöp Sepeti'ne taşı ve bize yaz.
Paketi yeniden göndeririz.

Apple'ın resmi açıklamaları (18 Eylül 2026'da kontrol edildi):
- macOS 14 (sağ tık › Aç ve Yine de Aç): https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/14.0/mac/14.0
- macOS 15 (Sistem Ayarları › Gizlilik ve Güvenlik › Yine de Aç): https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/15.0/mac/15.0
- Genel: "Safely open apps on your Mac" — https://support.apple.com/en-us/102445

## 3. İlk kullanım

1. İlk açılışta yalnızca ilk markanın adı sorulur.
2. Yapay zekâ **isteğe bağlıdır** ve varsayılan olarak kapalıdır. Kullanmak için **Ayarlar… (⌘,) › Genel** bölümüne kendi **Claude API anahtarını** gir (anahtar sende kalır, Keychain'de saklanır; uygulama anahtar aramaz ya da kendiliğinden bulmaz). Claude.ai Pro/Max aboneliği bağlanamaz; yalnız API anahtarı çalışır.
3. Ardından asistanı kullanmak istediğin markada izni aç: **Marka Bilgileri › Ayrıntılar ve izinler**. İzin markaya özeldir; izin vermediğin markanın içeriği hiçbir sağlayıcıya gitmez.
4. Sağdaki **Asistan** panelini ⌘J ile aç; "Ne yapmalıyım?" ya da "Cuma teslimi için görev aç" yaz. Asistan veri değiştirmez, **öneri** üretir; öneriler onay sayfasına düşer, onaylayınca uygulanır ve Akış'tan geri alınabilir.
5. Kendi şirketin için **Stüdyo**'yu kurabilir; ekip ve yetenek tanımlayıp bir ekip üyesinin rolüyle sohbet edebilirsin. Şirket profili, ekip ve yetenek metinleri yalnız Stüdyo'ya aynı sağlayıcı için izin verdiysen yapay zekâ bağlamına girer.
6. Codex (ChatGPT girişi) **opsiyoneldir** ve yalnız App Store dışı beta paketinde bulunur; Mac App Store sürümünde olmayacaktır. Codex açıksa komutlar sana sormadan çalışabilir ve internete çıkabilir; ayrıntı [bilinen sınırlar](bilinen-sinirlar.md).

Canlı Claude yanıtı gerçek bir anahtarla henüz denenmedi (bilinen sınır); ilk gerçek denemeleri sen yapacaksın, takıldığın yeri bize yaz.

## 4. Verin nerede durur

Veriler bu Mac'te **yerel saklanır**; bizim bir sunucumuz yok. **Yapay zekâyı açtığın markanın içeriği** (marka özeti, asistanın okuduğu kaynakların metni ve konuşma) yalnız o marka için **izin verdiğin sağlayıcıya** (Anthropic ya da, kullanırsan, Codex) gönderilir; izin vermediğin markadan hiçbir şey gitmez. Tanı bilgisi ve beta ölçümleri marka adı ya da içerik taşımaz ve kendiliğinden gönderilmez.

Veri iki yerde durur, ikisini de **Workspace AI › Ayarlar… › Veri › Konum** bölümündeki **Finder'da göster** düğmesiyle açabilirsin:

| Ne | Nerede |
|---|---|
| Veri tabanı, eklenen dosyalar ve otomatik yedekler | `~/Library/Application Support/MarkaCalismaAlani` |
| Marka klasörleri (varsa `BAGLAM.md`, `CLAUDE.md`, `AGENTS.md`) | Belgeler › `Marka Çalışma Alanı` |

`~/Library` klasörü Finder'da gizlidir. Açmak için Finder'da **Git › Klasöre Git…** (⇧⌘G) seçip
`~/Library/Application Support/MarkaCalismaAlani` yaz ve Return'e bas.

**iCloud notu:** Marka klasörleri Belgeler altında durur. Mac'inde "Masaüstü ve Belgeler klasörleri" iCloud eşitlemesi açıksa, bu klasörlerdeki dosyalar (Codex izni verdiğin markalarda yazılan `BAGLAM.md` marka bağlamı dahil) iCloud'a eşitlenebilir. Bunu istemiyorsan eşitlemeyi kapat ya da markada Codex iznini verme. Çekirdek veri (veri tabanı) `~/Library` altındadır ve bu eşitlemenin kapsamında değildir.

Claude API anahtarı girdiysen o, macOS **Anahtar Zinciri**'nde (`com.markacalismaalani.app` adıyla) saklanır; dosya
olarak yazılmaz.

## 5. Yedekleme

- Uygulama her gün ilk açılışta **otomatik yedek** alır ve son 14 otomatik yedeği saklar. Bu yedekler de
  `~/Library/Application Support/MarkaCalismaAlani/Yedekler` içindedir, yani **aynı diskte** durur.
- Başka bir diskte duran bir yedek için: **Ayarlar… › Veri › Yedekler** listesindeki yedek klasörünü Finder'da kopyala (harici disk ya da bulut klasörü); tek bir markayı ayrıca marka ekranındaki ··· menüsünden **Dışa aktar** ile dışarı alabilirsin. Önemli bir teslimden önce bunu yapmanı öneririz.
- **Şimdi yedekle** anında bir yedek alır; **Geri yükle…** bir yedeğe döner (geri yüklemeden önce mevcut veri ayrıca
  yedeklenir).
- Time Machine kullanıyorsan yukarıdaki iki konum da onun kapsamındadır.

## 6. Beta ölçümlerini ve tanı bilgisini paylaşma

Uygulama hiçbir şeyi kendiliğinden göndermez. Paylaşmak sana kalır:

- **Beta ölçümleri:** **Workspace AI › Ayarlar… › Veri › Tanı bilgisi** bölümünde **Tanı bilgisini kopyala**'ya bas
  (ölçümler tanı bilgisinin sonundadır), sonra bize gönderdiğin e-postaya ya da mesaja yapıştır (⌘V). Ölçümlerde yalnızca sayılar vardır (ilk kullanıma kadar geçen süre, rapor
  hazırlama süresi, AI önerisi sayıları, aktif gün); marka adı veya içerik yoktur. Yapıştırmadan önce okuyabilirsin.
- **Bir hata olduğunda:** Ayarlar'daki **Tanı bilgisini kopyala** düğmesine bas ve çıkan metni hatayı nasıl yaşadığını
  anlatan birkaç cümleyle birlikte bize gönder. Tanı bilgisi uygulama sürümünü, macOS sürümünü ve son hataların türünü
  içerir; marka adı, kaynak metni ya da dosya yolu içermez.

## 7. Kaldırma

> **Önce yedek al.** Aşağıdaki 3. ve 4. adımlar tüm markalarını, kaynaklarını, raporlarını ve otomatik yedeklerini
> **kalıcı olarak** siler. Veriyi saklamak istiyorsan önce yedek klasörünü (**Ayarlar… › Veri › Yedekler**) harici bir
> yere kopyala, marka klasörlerindeki dosyalardan ihtiyacın olanları da kopyala.

1. Uygulamadan çık: **Workspace AI › Workspace AI'dan Çık** (⌘Q).
2. Finder › **Uygulamalar** klasöründe **Workspace AI**'ı Çöp Sepeti'ne sürükle.
   Yalnızca bunu yaparsan verin yerinde kalır; uygulamayı yeniden kurduğunda kaldığın yerden devam edersin.
3. Uygulama verisini silmek için: Finder'da **Git › Klasöre Git…** (⇧⌘G) › `~/Library/Application Support/MarkaCalismaAlani`
   yaz, açılan klasörün bir üstüne çıkıp **MarkaCalismaAlani** klasörünü Çöp Sepeti'ne taşı.
4. Marka klasörlerini silmek için: **Belgeler** › **Marka Çalışma Alanı** klasörünü Çöp Sepeti'ne taşı. Burada kendi
   ürettiğin dosyalar vardır; emin değilsen bu adımı atla.
5. İsteğe bağlı: Uygulama ayarları `~/Library/Preferences/com.markacalismaalani.app.plist` dosyasındadır; silebilirsin.
   Claude API anahtarı girdiysen **Anahtar Zinciri Erişimi** uygulamasında `com.markacalismaalani.app` diye arat ve
   bulunan kaydı sil.
6. Çöp Sepeti'ni boşalttığında silme kalıcı olur.
