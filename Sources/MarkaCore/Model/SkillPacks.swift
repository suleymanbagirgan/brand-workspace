import Foundation

public struct SkillPack: Sendable, Identifiable {
    public struct Item: Sendable { public let name: String; public let title: String; public let description: String; public let body: String }
    public let key: String
    public let title: String
    public let summary: String
    public let skills: [Item]
    public var id: String { key }
}

/// Hazır yetenek paketleri. Metinler bu uygulamaya aittir; yapıdaki ilke (küçük, bağımsız, "ne zaman kullanılır" diyen yetenekler)
/// açık ajan-yeteneği ekosisteminden esinlenmiştir.
public enum SkillPacks {
    public static let all: [SkillPack] = [marketing, product, method]

    public static let marketing = SkillPack(key: "pazarlama", title: "Pazarlama ve büyüme", summary: "SEO, metin, dönüşüm, reklam, bülten, satış görüşmesi.", skills: [
        .init(name: "seo-denetimi", title: "SEO denetimi",
              description: "Bir sayfanın ya da sitenin arama görünürlüğünü denetler. Yeni sayfa yayınlanırken veya trafik düşünce kullan.",
              body: "1. Sayfanın tek bir ana niyeti olduğunu doğrula; başlık (title) ve ana başlık (H1) bu niyeti söylemeli.\n2. Başlık 60, açıklama 155 karakteri aşmasın; her sayfada benzersiz olsun.\n3. Başlık hiyerarşisini, görsel alt metinlerini ve iç bağlantıları kontrol et.\n4. Yavaş açılan ya da mobilde bozuk sayfayı ayrıca işaretle.\n5. Bulguları önem sırasıyla listele; her biri için tek cümlelik düzeltme öner. Ölçemediğin sayıyı tahmin etme."),
        .init(name: "metin-yazarligi", title: "Metin yazarlığı",
              description: "Web sitesi, bülten ya da reklam için müşterinin ses tonunda ilk taslak yazar. Taslak istendiğinde kullan.",
              body: "1. Önce marka profilindeki ses tonu ve hedef kitleyi oku; yoksa sor.\n2. Tek mesaj seç: okuyan ne yapsın?\n3. Fayda önce, özellik sonra; abartı ve kanıtsız iddia yok.\n4. İki ayrı sürüm ver (kısa ve uzun); her birinin altına varsayımlarını yaz.\n5. Taslaktır: insan okumadan müşteriye gitmez."),
        .init(name: "donusum-iyilestirme", title: "Dönüşüm iyileştirme",
              description: "Bir sayfanın ziyaretçiyi eyleme çevirme oranını artıracak değişiklikler önerir. Form, teklif sayfası veya satış sayfası için kullan.",
              body: "1. Sayfanın tek hedef eylemini yaz (form gönder, ara, satın al).\n2. Eylemin önündeki engelleri sırala: belirsiz başlık, çok alan, güven eksikliği, gizli düğme.\n3. Her engel için tek bir deneyebilir değişiklik öner; aynı anda üçten fazlasını değiştirme.\n4. Değişikliğin neyi ölçerek başarılı sayılacağını yaz.\n5. Elinde veri yoksa bunu açıkça söyle."),
        .init(name: "reklam-plani", title: "Reklam planı",
              description: "Bütçe, hedef kitle ve mesajla bir reklam kampanyası planı çıkarır. Yeni reklam vermeden önce kullan.",
              body: "1. Hedefi tek cümle yaz (örn. ayda 20 nitelikli başvuru).\n2. Kitleyi ve kanalı gerekçeyle seç; her kanal için ayrı küçük bütçe.\n3. En fazla üç mesaj varyantı; her biri bir fayda söylesin.\n4. İlk iki hafta için ölçüt belirle: tıklama maliyeti, başvuru maliyeti, başvuru kalitesi.\n5. Bütçeyi onay almadan harcama önerisi olarak sun; harcama kararı insanındır."),
        .init(name: "bulten-dizisi", title: "Bülten dizisi",
              description: "Yeni müşteriye ya da potansiyel müşteriye giden 3-5 e-postalık hoş geldin dizisi taslağı hazırlar.",
              body: "1. Dizinin amacını yaz (tanıştır, güven ver, görüşme iste).\n2. Her e-posta tek fikir taşısın; konu satırı 50 karakteri geçmesin.\n3. Aralıkları öner (1., 3., 7. gün).\n4. Her e-postanın sonunda tek bir eylem çağrısı olsun.\n5. Gönderim insan onayından geçer."),
        .init(name: "musteri-gorusmesi-hazirligi", title: "Müşteri görüşmesi hazırlığı",
              description: "Yeni bir potansiyel müşteriyle görüşmeden önce gündem, sorular ve teklif taslağı iskeleti hazırlar.",
              body: "1. Elindeki notlardan firmayı üç cümlede özetle; bilmediğini bilmediğin olarak işaretle.\n2. Görüşme amacını ve çıkmasını istediğin kararı yaz.\n3. Dinlemeye yönelik 6 soru hazırla (sorun, takvim, bütçe, karar vericiler).\n4. Hizmetlerimizden hangisinin neden uyduğunu eşle.\n5. Görüşme sonrası için görev önerileri çıkar (teklif, takip e-postası)."),
    ])

    public static let product = SkillPack(key: "yazilim-tasarim", title: "Yazılım ve tasarım", summary: "Kod incelemesi, erişilebilirlik, arayüz metni, test planı, sürüm notu.", skills: [
        .init(name: "kod-incelemesi", title: "Kod incelemesi",
              description: "Bir değişikliği doğruluk, güvenlik ve okunabilirlik açısından inceler. Birleştirmeden önce kullan.",
              body: "1. Değişikliğin amacını bir cümleyle yaz; kodun yaptığı bununla uyuşuyor mu?\n2. Sınır durumlarını ve hata yollarını ara.\n3. Gizli bilgi, yetki ve girdi doğrulaması için ayrı bak.\n4. Bulguları kritik / önemli / öneri diye ayır; her birine dosya ve satır ver.\n5. Düzeltmeyi uygulama; öner."),
        .init(name: "erisilebilirlik-denetimi", title: "Erişilebilirlik denetimi",
              description: "Bir ekranı klavye, ekran okuyucu, kontrast ve yazı boyutu açısından denetler. Yeni ekran bitince kullan.",
              body: "1. Yalnız klavyeyle bütün eylemlere ulaşılıyor mu?\n2. Her kontrolün anlamlı bir etiketi var mı?\n3. Metin kontrastı yeterli mi (normal metin için en az 4,5:1)?\n4. Yazı büyüyünce düzen bozuluyor mu?\n5. Hareketi azalt tercihine uyuluyor mu?\nBulguları ekran adıyla listele."),
        .init(name: "arayuz-metni", title: "Arayüz metni",
              description: "Düğme, boş durum, hata ve onay metinlerini sade ve tutarlı yazar.",
              body: "1. Düğme fiil olsun (“Kaydet”, “Gönder”), belirsiz “Tamam” olmasın.\n2. Hata mesajı ne olduğunu ve sıradaki adımı söylesin; suçlamasın.\n3. Boş durum ne yapılacağını söylesin.\n4. Aynı kavram için tek kelime kullan.\n5. Abartı ve söz verilmeyen şey yok."),
        .init(name: "test-plani", title: "Test planı",
              description: "Bir özellik için neyin, nasıl doğrulanacağını listeler. Geliştirmeye başlamadan önce kullan.",
              body: "1. Özelliğin kabul ölçütlerini ölçülebilir cümlelerle yaz.\n2. Her ölçüt için en az bir test: normal yol, sınır, hata.\n3. Elle bakılacakları ayrı listele.\n4. Hangi veriyle test edileceğini belirt; gerçek müşteri verisi kullanma.\n5. Geçmeyen testleri saklama; raporla."),
        .init(name: "surum-notu", title: "Sürüm notu",
              description: "Yapılan işlerden müşteriye veya ekibe giden sade sürüm notu çıkarır.",
              body: "1. Yalnızca doğrulanmış işleri yaz; yapılmayanı vaat etme.\n2. Kullanıcıya görünen değişiklikleri önce, iç değişiklikleri sonra yaz.\n3. Her madde bir cümle olsun.\n4. Bilinen sınırları ayrı bir başlıkta açıkça belirt."),
    ])

    public static let method = SkillPack(key: "calisma-yontemi", title: "Çalışma yöntemi", summary: "Plan → öneri → kontrol; kaynaklı araştırma.", skills: [
        .init(name: "once-plan-sonra-oner", title: "Önce plan, sonra öner",
              description: "Karmaşık bir iş istendiğinde doğrudan öneri üretmek yerine önce kısa plan çıkarır, sonra küçük öneriler halinde sunar.",
              body: "1. İsteği kendi cümlenle tekrar et; belirsiz yeri sor.\n2. Üç-beş adımlık plan yaz; her adımın nasıl doğrulanacağını ekle.\n3. Planı kullanıcıya göster; onaylanmadan öneri üretme.\n4. Her adımı ayrı, küçük ve geri alınabilir öneri olarak sun.\n5. Sonunda neyin yapıldığını, neyin kaldığını söyle."),
        .init(name: "kaynakli-arastirma", title: "Kaynaklı araştırma",
              description: "Bir soruyu yalnızca kaynağı gösterilebilen bilgiyle yanıtlar. Rakip, pazar veya teknik araştırma için kullan.",
              body: "1. Soruyu tek cümleye indir.\n2. Her bilgi için kaynak adı ve konumu yaz.\n3. Kaynağı olmayan bilgiyi “doğrulanamadı” diye işaretle.\n4. Çelişen kaynakları ayrı göster.\n5. Sonucu üç maddeye özetle; tahmini gerçek gibi yazma."),
    ])
}
