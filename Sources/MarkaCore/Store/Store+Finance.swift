import Foundation
import GRDB

extension Store {
    // MARK: Finans (0.3.0)

    /// Markanın finans kayıtları: önce tarihliler (tarihe göre), tarihsizler sonda.
    public func financeEntries(brandId: String, kind: FinanceKind? = nil) throws -> [FinanceEntry] {
        try read { db in
            var q = FinanceEntry.filter(Column("brandId") == brandId)
            if let kind { q = q.filter(Column("kind") == kind.rawValue) }
            return try q.fetchAll(db).sorted { a, b in
                switch (a.date, b.date) {
                case let (x?, y?): x == y ? a.createdAt < b.createdAt : x < y
                case (_?, nil): true
                case (nil, _?): false
                default: a.createdAt < b.createdAt
                }
            }
        }
    }

    /// Ekler ya da günceller (aynı kimlik). Başlık boş olamaz, tutar negatif olamaz, tarih `yyyy-MM-dd` olmalıdır.
    @discardableResult
    public func saveFinanceEntry(_ entry: FinanceEntry, actor: Actor = .user) throws -> FinanceEntry {
        var e = entry
        e.title = entry.title.trimmed
        e.note = entry.note.trimmed
        guard !e.title.isEmpty else { throw MarkaError.validation(L("Başlık boş olamaz.")) }
        guard e.title.count <= 200 else { throw MarkaError.validation(LF("Başlık çok uzun (en çok %d).", 200)) }
        if let m = e.amountMinor, m < 0 { throw MarkaError.validation(L("Tutar negatif olamaz.")) }
        if let d = e.date, DayString.date(d) == nil { throw MarkaError.validation(L("Tarih geçersiz.")) }
        e.status = e.kind == .payment ? (e.status ?? .planned) : nil
        e.updatedAt = Date()
        return try writer.write { db in
            guard try Brand.fetchOne(db, key: e.brandId) != nil else { throw MarkaError.notFound(e.brandId) }
            let before = try FinanceEntry.fetchOne(db, key: e.id)
            if let before, before.brandId != e.brandId { throw MarkaError.notFound(e.id) }
            try e.save(db)
            try audit(db, actor: actor, brandId: e.brandId, entity: "financeEntry", entityId: e.id,
                      action: before == nil ? "create" : "update", before: before, after: e)
            return e
        }
    }

    public func deleteFinanceEntry(_ id: String, actor: Actor = .user) throws {
        try writer.write { db in
            guard let before = try FinanceEntry.fetchOne(db, key: id) else { throw MarkaError.notFound(id) }
            try before.delete(db)
            try audit(db, actor: actor, brandId: before.brandId, entity: "financeEntry", entityId: id,
                      action: "delete", before: before, after: FinanceEntry?.none)
        }
    }
}
