import Foundation
import GRDB

/// Gözlemin yaşam durumu. Gözlem silinmez ve üzerine yazılmaz: yeni kanıt eskisini kapatır (`superseded`).
public enum ObservationStatus: String, Codable, Sendable, CaseIterable {
    case active, superseded
}

/// E-01: kanıt sayılı marka gözlemi. Yapay zekânın (ya da kullanıcının) bir marka hakkında öğrendiği tek cümlelik şey;
/// dayandığı kaynak kimlikleri ve kanıt sayısıyla saklanır. Yeni kanıt eskisini `invalidatedAt` ile kapatır, böylece
/// "ne zaman neyi biliyorduk" geçmişi kaybolmaz. Gözlem yalnız onay yolundan doğar (`Store.addObservation`).
/// İçeriği tanıya, günlüğe ya da ölçüme girmez.
public struct BrandObservation: Codable, Sendable, Hashable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "observation"
    /// Tek cümle sınırı (karakter).
    public static let maxStatementLength = 500
    /// Bir gözlemin dayanabileceği en çok kaynak sayısı.
    public static let maxEvidence = 50

    public var id: String
    public var brandId: String
    public var statement: String
    /// Dayanak kaynak kimlikleri (tekil, verilen sırayla); veri tabanında JSON dizi olarak durur.
    public var evidenceSourceIds: [String]
    public var evidenceCount: Int
    public var status: ObservationStatus
    public var validFrom: Date
    public var invalidatedAt: Date?
    /// Bu gözlemi kapatan yeni gözlemin kimliği.
    public var supersededBy: String?
    public var createdAt: Date

    public init(id: String = newID(), brandId: String, statement: String, evidenceSourceIds: [String],
                status: ObservationStatus = .active, validFrom: Date = Date(), invalidatedAt: Date? = nil,
                supersededBy: String? = nil, createdAt: Date = Date()) {
        self.id = id; self.brandId = brandId; self.statement = statement; self.evidenceSourceIds = evidenceSourceIds
        self.evidenceCount = evidenceSourceIds.count; self.status = status; self.validFrom = validFrom
        self.invalidatedAt = invalidatedAt; self.supersededBy = supersededBy; self.createdAt = createdAt
    }

    /// Şu an geçerli mi (kapatılmamış).
    public var isValid: Bool { status == .active && invalidatedAt == nil }
}
