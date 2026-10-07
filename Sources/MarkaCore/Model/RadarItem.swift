import Foundation
import GRDB

/// E-21 (docs/entegrasyon-plani-30.md): marka radarı maddesi. Kullanıcının elle eklediği rakip ya da sektör bağlantısı ve
/// notu; tarih ve etiketle. İnternet taraması yoktur, bağlantının içeriği çekilmez: kullanıcı ne eklediyse o vardır.
///
/// Radar maddesi **müşteri kaynağı değildir**: `source` tablosunda durmaz, rapora (kural 4), tanı sayılarına ve gözlem
/// kanıtına girmez. Yapay zekâ `radar_listele` ile yalnız okur; radardan çıkan fikir bekleyen öneri olarak düşer.
/// Metni üçüncü taraf içeriğidir: yapay zekâya `ToolResultFrame` içinde, tek satıra indirilmiş olarak gider.
public struct RadarItem: Codable, Sendable, Hashable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "radarItem"
    /// Başlık sınırı (karakter).
    public static let maxTitleLength = 200
    /// Not sınırı (karakter).
    public static let maxNoteLength = 2_000
    /// Etiket sınırı (karakter).
    public static let maxTagLength = 40

    public var id: String
    public var brandId: String
    public var title: String
    /// `LinkAddress.normalize` ile doğrulanmış http(s) adresi; yalnız not olan maddede boş.
    public var url: String?
    public var note: String
    public var tag: String
    public var createdAt: Date
    public var archivedAt: Date?

    public init(id: String = newID(), brandId: String, title: String, url: String? = nil, note: String = "", tag: String = "",
                createdAt: Date = Date(), archivedAt: Date? = nil) {
        self.id = id; self.brandId = brandId; self.title = title; self.url = url; self.note = note; self.tag = tag
        self.createdAt = createdAt; self.archivedAt = archivedAt
    }

    public var isArchived: Bool { archivedAt != nil }

    /// "Radarı özetle" isteminin metni. Asistan yalnız öneri üretir; radar maddesi kaynak ya da gözlem kanıtı sayılmaz.
    public static let summaryPrompt = "radar_listele ile bu markanın radarını oku. Öne çıkan rakip ve sektör hareketlerini kısaca özetle. Takip etmeye değer olanları görev önerisi (gorev_oner) olarak ekle. Radar maddeleri müşteri kaynağı değildir: rapor maddesi ya da gözlem kanıtı olarak kullanma; bir gözlem önermek istersen yalnız bu markanın kaynaklarına dayan. Bağlantıların içeriğini bilmiyorsun, yalnız kullanıcının yazdığı başlık ve notu kullan."
}
