# Marka Çalışma Alanı — beta kurulum rehberi

Bu rehber beta katılımcısı içindir. Teknik bilgi gerekmez; adımları sırayla izle.
Takıldığın her yerde bize yaz — takıldığın yer bizim için ölçümdür.

## Gerekenler

- **macOS 14 (Sonoma) veya daha yenisi.** Sürümünü görmek için: Apple menüsü › Bu Mac Hakkında.
- **Apple Silicon işlemcili Mac** (M1, M2, M3, M4 …). Aynı pencerede "Çip: Apple M…" yazıyorsa uygundur.
  "İşlemci: Intel" yazıyorsa bu beta paketi o Mac'te açılmaz; bize haber ver.
- Sana gönderilen `MarkaCalismaAlani-0.2.0.dmg` dosyası (sürüm numarası farklı olabilir).

## 1. Kurulum

1. İndirdiğin `MarkaCalismaAlani-….dmg` dosyasına çift tıkla. Bir pencere açılır; içinde **Marka Çalışma Alanı** uygulaması
   ve **Applications** (Uygulamalar) klasörünün kısayolu vardır.
2. **Marka Çalışma Alanı** simgesini sürükleyip **Applications** kısayolunun üzerine bırak. Kopyalama birkaç saniye sürer.
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
2. **Marka Çalışma Alanı** simgesine **sağ tıkla** (ya da Kontrol tuşuna basılı tutarak tıkla) ve menüden **Aç**'ı seç.
3. Çıkan uyarıda **Aç**'a bas.

Alternatif: Uygulamayı açmayı bir kez dene, sonra Apple menüsü › **Sistem Ayarları** › **Gizlilik ve Güvenlik**
bölümünde aşağı kaydırıp **Yine de Aç**'a bas.

### macOS 15 (Sequoia) ve sonrası

macOS 15'te sağ tık › Aç yolu artık uyarıyı geçmez. Şöyle yap:

1. **Uygulamalar** klasöründe **Marka Çalışma Alanı**'na çift tıkla. Uyarı çıkar; **Bitti**'ye bas
   (**Çöp Sepetine Taşı**'ya basma).
2. Apple menüsü › **Sistem Ayarları** › kenar çubuğunda **Gizlilik ve Güvenlik** (gerekirse kenar çubuğunu aşağı kaydır).
3. Sağ tarafta **Güvenlik** başlığına kadar aşağı kaydır. "Marka Çalışma Alanı engellendi…" satırının yanındaki
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

## 3. Verin nerede durur

Verin bu Mac'te durur; bizim bir sunucumuz yok. Yalnızca AI ile çalıştığında, o markada izin verdiğin sağlayıcıya
(Claude ya da Codex) o konuşmanın içeriği gider. Veri iki yerde durur, ikisini de **Marka Çalışma Alanı ›
Ayarlar… › Veri › Konumlar** bölümünde **Göster** düğmesiyle Finder'da açabilirsin:

| Ne | Nerede |
|---|---|
| Veri tabanı, eklenen dosyalar ve otomatik yedekler | `~/Library/Application Support/MarkaCalismaAlani` |
| Marka klasörleri (AI ve terminalle ürettiğin dosyalar, `BAGLAM.md`) | Belgeler › `Marka Çalışma Alanı` |

`~/Library` klasörü Finder'da gizlidir. Açmak için Finder'da **Git › Klasöre Git…** (⇧⌘G) seçip
`~/Library/Application Support/MarkaCalismaAlani` yaz ve Return'e bas.

Claude API anahtarı girdiysen o, macOS **Anahtar Zinciri**'nde (`com.markacalismaalani.app` adıyla) saklanır; dosya
olarak yazılmaz.

## 4. Yedekleme

- Uygulama her gün ilk açılışta **otomatik yedek** alır ve son 14 otomatik yedeği saklar. Bu yedekler de
  `~/Library/Application Support/MarkaCalismaAlani/Yedekler` içindedir, yani **aynı diskte** durur.
- Başka bir diskte duran bir yedek için: **Ayarlar… › Veri › Yedekler › Başka konuma yedekle…** ve harici bir disk
  ya da bulut klasörü seç. Önemli bir teslimden önce bunu yapmanı öneririz.
- **Şimdi yedekle** anında bir yedek alır; **Geri yükle…** bir yedeğe döner (geri yüklemeden önce mevcut veri ayrıca
  yedeklenir).
- Time Machine kullanıyorsan yukarıdaki iki konum da onun kapsamındadır.

## 5. Beta ölçümlerini ve tanı bilgisini paylaşma

Uygulama hiçbir şeyi kendiliğinden göndermez. Paylaşmak sana kalır:

- **Beta ölçümleri:** **Marka Çalışma Alanı › Ayarlar… › Veri › Tanı bilgisi** bölümünde **Tanı bilgisini kopyala**'ya bas
  (ölçümler tanı bilgisinin sonundadır), sonra bize gönderdiğin e-postaya ya da mesaja yapıştır (⌘V). Ölçümlerde yalnızca sayılar vardır (ilk kurulum süresi, rapor
  hazırlama süresi, AI önerisi sayıları, aktif gün); marka adı veya içerik yoktur. Yapıştırmadan önce okuyabilirsin.
- **Bir hata olduğunda:** Ayarlar'daki **Tanı bilgisini kopyala** düğmesine bas ve çıkan metni hatayı nasıl yaşadığını
  anlatan birkaç cümleyle birlikte bize gönder. Tanı bilgisi uygulama sürümünü, macOS sürümünü ve son hataların türünü
  içerir; marka adı, kaynak metni ya da dosya yolu içermez.

## 6. Kaldırma

> **Önce yedek al.** Aşağıdaki 3. ve 4. adımlar tüm markalarını, kaynaklarını, raporlarını ve otomatik yedeklerini
> **kalıcı olarak** siler. Veriyi saklamak istiyorsan önce **Ayarlar… › Veri › Başka konuma yedekle…** ile harici bir
> yere yedek al ve marka klasörlerindeki dosyalardan ihtiyacın olanları kopyala.

1. Uygulamadan çık: **Marka Çalışma Alanı › Marka Çalışma Alanı'ndan Çık** (⌘Q).
2. Finder › **Uygulamalar** klasöründe **Marka Çalışma Alanı**'nı Çöp Sepeti'ne sürükle.
   Yalnızca bunu yaparsan verin yerinde kalır; uygulamayı yeniden kurduğunda kaldığın yerden devam edersin.
3. Uygulama verisini silmek için: Finder'da **Git › Klasöre Git…** (⇧⌘G) › `~/Library/Application Support/MarkaCalismaAlani`
   yaz, açılan klasörün bir üstüne çıkıp **MarkaCalismaAlani** klasörünü Çöp Sepeti'ne taşı.
4. Marka klasörlerini silmek için: **Belgeler** › **Marka Çalışma Alanı** klasörünü Çöp Sepeti'ne taşı. Burada kendi
   ürettiğin dosyalar vardır; emin değilsen bu adımı atla.
5. İsteğe bağlı: Uygulama ayarları `~/Library/Preferences/com.markacalismaalani.app.plist` dosyasındadır; silebilirsin.
   Claude API anahtarı girdiysen **Anahtar Zinciri Erişimi** uygulamasında `com.markacalismaalani.app` diye arat ve
   bulunan kaydı sil.
6. Çöp Sepeti'ni boşalttığında silme kalıcı olur.
