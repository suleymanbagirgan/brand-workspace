import Foundation

/// Hazır ekip şablonu içindeki tek bir yapay zekâ rol tarifi. Çalışan bir süreç değil rol tanımıdır;
/// sağlayıcı ve model kullanıcıya bırakılır (şablon bir sağlayıcıya içerik göndermez).
public struct TeamTemplateRole: Sendable, Hashable {
    public let name: String
    public let title: String
    public let level: MemberLevel
    public let department: String
    /// Görev tarifi (rol tanımı). Özgün Türkçe metin.
    public let charter: String
    /// Bağlı yetenek adları. Kütüphanede yoksa serbest metin yetenek olarak kalır.
    public let skills: [String]
}

/// Stüdyo'da kurulabilen hazır ekip şablonu. Kurmak ekip oluşturmaz; her rol için onay bekleyen bir "çalışan önerisi" üretir.
public struct TeamTemplate: Sendable, Hashable, Identifiable {
    public let key: String
    public let title: String
    public let summary: String
    public let roles: [TeamTemplateRole]
    public var id: String { key }
}

/// Hazır ekip şablonları. Metinler bu uygulamaya aittir; "küçük ve tek işi olan roller" ilkesi açık ekosistemden esinlenmiştir.
public enum TeamTemplates {
    public static let all: [TeamTemplate] = [agency, soloConsultant, contentDesk]

    public static let agency = TeamTemplate(
        key: "ajans-cekirdek", title: "Ajans çekirdek ekibi",
        summary: "Strateji, metin, SEO ve rapor: dört küçük yapay zekâ rolü.",
        roles: [
            .init(name: "Strateji Analisti", title: "Strateji analisti", level: .senior, department: "Strateji",
                  charter: "Markanın hedefini, kitlesini ve elindeki kaynakları okuyup bir sonraki adım için gerekçeli seçenekler önerir. Kaynağı olmayan iddiayı varsayım diye işaretler; karar insanındır.",
                  skills: ["once-plan-sonra-oner", "kaynakli-arastirma"]),
            .init(name: "Metin Yazarı", title: "Metin yazarı", level: .mid, department: "İçerik",
                  charter: "Marka profilindeki ses tonunda taslak metin yazar. Her taslağın altına varsayımlarını ekler; insan okumadan hiçbir metin dışarı çıkmaz.",
                  skills: ["metin-yazarligi"]),
            .init(name: "SEO Denetçisi", title: "SEO denetçisi", level: .mid, department: "Büyüme",
                  charter: "Sayfaların arama görünürlüğünü denetler, bulguları önem sırasıyla listeler. Ölçemediği sayıyı tahmin etmez.",
                  skills: ["seo-denetimi"]),
            .init(name: "Rapor Hazırlayıcı", title: "Rapor hazırlayıcı", level: .junior, department: "Raporlama",
                  charter: "Doğrulanmış çalışma kayıtlarından müşteri raporu taslağı derler. Dayanağı olmayan madde eklemez.",
                  skills: ["rapor-hazirlama"]),
        ])

    public static let soloConsultant = TeamTemplate(
        key: "tek-kisilik-danisman", title: "Tek kişilik danışman",
        summary: "Yalnız çalışan danışman için iki yardımcı rol: araştırma ve toparlama.",
        roles: [
            .init(name: "Araştırma Yardımcısı", title: "Araştırma yardımcısı", level: .junior, department: "Araştırma",
                  charter: "Eklenen kaynaklardan soruya yanıt arar ve her bulgunun kaynağını gösterir. Bulamadığını bulamadım diye söyler.",
                  skills: ["kaynakli-arastirma"]),
            .init(name: "Haftalık Toparlayıcı", title: "Haftalık toparlayıcı", level: .junior, department: "Operasyon",
                  charter: "Haftanın görevlerini, kararlarını ve bekleyen işlerini özetler; unutulan takipleri görev önerisi olarak sunar.",
                  skills: ["once-plan-sonra-oner"]),
        ])

    public static let contentDesk = TeamTemplate(
        key: "icerik-masasi", title: "İçerik masası",
        summary: "Bülten, reklam ve arayüz metni için üç rol.",
        roles: [
            .init(name: "Bülten Editörü", title: "Bülten editörü", level: .mid, department: "İçerik",
                  charter: "Bülten ve e-posta dizisi taslakları hazırlar; her e-posta tek fikir taşır. Gönderim insan onayındadır.",
                  skills: ["bulten-dizisi", "metin-yazarligi"]),
            .init(name: "Reklam Planlayıcı", title: "Reklam planlayıcı", level: .mid, department: "Büyüme",
                  charter: "Bütçe ve hedefe göre reklam planı taslağı çıkarır. Harcama kararı vermez, öneri olarak sunar.",
                  skills: ["reklam-plani"]),
            .init(name: "Arayüz Metni Editörü", title: "Arayüz metni editörü", level: .junior, department: "Tasarım",
                  charter: "Düğme, etiket ve hata mesajı metinlerini kısa, tutarlı ve açık hâle getirmeyi önerir.",
                  skills: ["arayuz-metni"]),
        ])
}
