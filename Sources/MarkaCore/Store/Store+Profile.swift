import Foundation
import GRDB

extension Store {
    // MARK: Marka profili (0.3.0)

    /// Markanın yazılmış profil bölümleri (boş olanlar yoktur).
    public func profile(brandId: String) throws -> [ProfileSection: String] {
        try read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT section, body FROM brandProfile WHERE brandId = ?", arguments: [brandId])
            var out: [ProfileSection: String] = [:]
            for r in rows {
                if let key: String = r["section"], let section = ProfileSection(rawValue: key), let body: String = r["body"] { out[section] = body }
            }
            return out
        }
    }

    /// Bölümü yazar; boş metin bölümü siler. Her yazma denetim olayı bırakır; yalnız verilen markayı etkiler.
    public func setProfileSection(brandId: String, _ section: ProfileSection, body: String, actor: Actor = .user) throws {
        let clean = body.trimmed
        guard clean.count <= ProfileSection.maxLength else {
            throw MarkaError.validation(LF("Bölüm çok uzun (en çok %d).", ProfileSection.maxLength))
        }
        try writer.write { db in
            guard try Brand.fetchOne(db, key: brandId) != nil else { throw MarkaError.notFound(brandId) }
            let before = try String.fetchOne(db, sql: "SELECT body FROM brandProfile WHERE brandId = ? AND section = ?",
                                             arguments: [brandId, section.rawValue])
            if clean == (before ?? "") { return }
            if clean.isEmpty {
                try db.execute(sql: "DELETE FROM brandProfile WHERE brandId = ? AND section = ?", arguments: [brandId, section.rawValue])
            } else {
                try db.execute(sql: "INSERT OR REPLACE INTO brandProfile (brandId, section, body, updatedAt) VALUES (?, ?, ?, ?)",
                               arguments: [brandId, section.rawValue, clean, Date()])
            }
            try audit(db, actor: actor, brandId: brandId, entity: "brandProfile", entityId: brandId + "/" + section.rawValue,
                      action: clean.isEmpty ? "delete" : "set", before: before, after: clean.isEmpty ? nil : clean)
        }
    }

    /// Her bölümün son yazılma zamanı (yalnız yazılmış bölümler).
    public func profileUpdatedAt(brandId: String) throws -> [ProfileSection: Date] {
        try read { db in
            var out: [ProfileSection: Date] = [:]
            for r in try Row.fetchAll(db, sql: "SELECT section, updatedAt FROM brandProfile WHERE brandId = ?", arguments: [brandId]) {
                if let key: String = r["section"], let section = ProfileSection(rawValue: key), let at: Date = r["updatedAt"] { out[section] = at }
            }
            return out
        }
    }
}
