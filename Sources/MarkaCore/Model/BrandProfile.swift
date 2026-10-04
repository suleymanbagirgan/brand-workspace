import Foundation
import GRDB

/// Marka profilinin bölümleri (0.3.0): terminaldeki yapay zekânın her oturumda okuduğu bağlam. "Markayı tanı" (özet) ve sektör
/// `Brand` üzerinde durur; buradakiler kullanıcının yazdığı serbest metinlerdir. Boş bölüm bağlama girmez; hiçbir bölüm
/// kendiliğinden doldurulmaz.
public enum ProfileSection: String, Codable, Sendable, CaseIterable, Identifiable {
    case audience, positioning, voice, scope, competitors, constraints, success
    public var id: String { rawValue }

    /// Arayüzde görünen ad.
    public var title: String {
        switch self {
        case .audience: L("Hedef kitle")
        case .positioning: L("Konumlandırma ve fark")
        case .voice: L("İletişim dili")
        case .scope: L("Çalışma kapsamı")
        case .competitors: L("Rakipler ve referanslar")
        case .constraints: L("Kısıtlar ve dikkat edilecekler")
        case .success: L("Başarı ölçütleri")
        }
    }

    /// Yazmaya yardım eden sorular (yalnız arayüzde; bağlama girmez).
    public var prompt: String {
        switch self {
        case .audience: L("Kim satın alır? Hangi sorunu çözüyor? Müşterisi kendini nasıl tarif eder?")
        case .positioning: L("Rakiplerden nasıl ayrışıyor? Marka vaadi tek cümlede ne?")
        case .voice: L("Ton nasıl: samimi mi resmî mi? Nasıl hitap edilir? Hangi ifadeler kullanılır, hangilerinden kaçınılır?")
        case .scope: L("Ne yapıyoruz, ne yapmıyoruz? Teslimatlar ve çalışma ritmi nedir? Onayı kim verir?")
        case .competitors: L("Başlıca rakipler kimler? Beğenilen ya da örnek alınan markalar hangileri?")
        case .constraints: L("Yasal ya da sektörel kısıtlar, hassas konular, asla yapılmayacaklar neler?")
        case .success: L("Bu işte iyi sonuç neye benzer? Hangi sayıya ya da işarete bakılıyor?")
        }
    }

    /// BAGLAM.md başlığı: dil ayarından bağımsız, sabit Türkçe.
    var contextTitle: String {
        switch self {
        case .audience: "Hedef kitle"
        case .positioning: "Konumlandırma ve fark"
        case .voice: "İletişim dili"
        case .scope: "Çalışma kapsamı"
        case .competitors: "Rakipler ve referanslar"
        case .constraints: "Kısıtlar ve dikkat edilecekler"
        case .success: "Başarı ölçütleri"
        }
    }

    /// Bir bölümün en uzun metni.
    public static let maxLength = 4000
}
