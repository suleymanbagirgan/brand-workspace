import Foundation
import GRDB

/// Yerelleştirilmiş metin (uygulama paketindeki Localizable.strings; anahtar Türkçe metnin kendisi).
public func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: .main, comment: "")
}

/// Biçimli yerelleştirilmiş metin.
public func LF(_ key: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(key, bundle: .main, comment: ""), locale: Locale.current, arguments: args)
}

public enum MarkaError: LocalizedError, Equatable {
    case validation(String)
    case notFound(String)
    case brandScope
    case providerNotAllowed(brand: String, provider: String)
    case sourceImmutable
    case timerAlreadyRunning
    case incompatibleBackup(String)
    case ai(String)

    public var errorDescription: String? {
        switch self {
        case .validation(let m): m
        case .notFound(let what): LF("Kayıt bulunamadı: %@", what)
        case .brandScope: L("Bu kayıt oturumun markasına ait değil. Başka markanın verisi kullanılamaz.")
        case .providerNotAllowed(let brand, let provider):
            LF("%1$@ markasının verisinin %2$@ sağlayıcısına gönderilmesine izin verilmemiş. Marka ayarlarından izin verebilirsin.", brand, provider)
        case .sourceImmutable: L("Dosya ve notlar değiştirilemez. Yeni not ekleyebilir ya da bunu arşivleyebilirsin.")
        case .timerAlreadyRunning: L("Başka bir görevde sayaç çalışıyor.")
        case .incompatibleBackup(let m): LF("Yedek bu sürümle uyumlu değil: %@", m)
        case .ai(let m): m
        }
    }
}

/// Tüm yazmaların geçtiği kapı. Her mutasyon tek işlemdir ve denetim olayı yazar.
public final class Store: Sendable {
    public let database: AppDatabase
    public var writer: any DatabaseWriter { database.writer }

    public init(database: AppDatabase) {
        self.database = database
    }

    public func read<T>(_ block: (Database) throws -> T) throws -> T {
        try writer.read(block)
    }

    /// Eşzamanlı yazma (async bağlamlarda GRDB'nin async aşırı yüklemesini seçmemek için).
    public func write<T>(_ block: (Database) throws -> T) throws -> T {
        try writer.write(block)
    }

    // MARK: Denetim

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func json<T: Encodable>(_ value: T?) -> String? {
        guard let value else { return nil }
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) }
    }

    @discardableResult
    func audit<B: Encodable, A: Encodable>(_ db: Database, actor: Actor, brandId: String?, entity: String,
                                             entityId: String, action: String, before: B?, after: A?) throws -> AuditEvent {
        let event = AuditEvent(actor: actor, brandId: brandId, entity: entity, entityId: entityId, action: action,
                               beforeJSON: Self.json(before), afterJSON: Self.json(after))
        try event.insert(db)
        return event
    }

    public func auditTrail(entity: String, entityId: String) throws -> [AuditEvent] {
        try read { db in
            try AuditEvent.filter(Column("entity") == entity && Column("entityId") == entityId)
                .order(Column("at").desc).fetchAll(db)
        }
    }

    // MARK: Ayarlar

    public func setting(_ key: String) throws -> String? {
        try read { db in try String.fetchOne(db, sql: "SELECT value FROM setting WHERE key = ?", arguments: [key]) }
    }

    public func setSetting(_ key: String, _ value: String) throws {
        try writer.write { db in
            try db.execute(sql: "INSERT INTO setting(key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                           arguments: [key, value])
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
