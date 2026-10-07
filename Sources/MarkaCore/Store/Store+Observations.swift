import Foundation
import GRDB

extension Store {
    // MARK: Kanıt sayılı marka gözlemi (E-01)

    /// Markanın gözlemleri, en yeni önce. Varsayılan yalnız geçerli (kapatılmamış) gözlemler; `includeInvalidated` ile
    /// kapatılmış geçmiş de döner. Yalnız `brandId` markasına ait satırlar okunur.
    public func observations(brandId: String, includeInvalidated: Bool = false) throws -> [BrandObservation] {
        try read { db in
            var q = BrandObservation.filter(Column("brandId") == brandId)
            if !includeInvalidated { q = q.filter(Column("status") == ObservationStatus.active.rawValue && Column("invalidatedAt") == nil) }
            return try q.order(Column("validFrom").desc, Column("createdAt").desc, Column("id")).fetchAll(db)
        }
    }

    /// Yeni gözlem ekler. Yalnız onay yolundan çağrılır: `actor` doğrudan `.ai` olamaz (yapay zekâ öneri üretir, insan
    /// onaylar). Kanıt boş olamaz; her kaynak bu markaya ait olmalı. Denetim olayı bırakır.
    @discardableResult
    public func addObservation(brandId: String, statement: String, evidenceSourceIds: [String],
                               actor: Actor = .user) throws -> BrandObservation {
        try writer.write { db in
            try insertObservation(db, brandId: brandId, statement: statement, evidenceSourceIds: evidenceSourceIds,
                                  actor: actor, approvedProposalId: nil)
        }
    }

    /// Yeni kanıtla eski gözlemin yerine geçen gözlem ekler. Eski gözlem silinmez ve metni değişmez: `superseded` olur,
    /// `invalidatedAt` ve `supersededBy` ile kapatılır. Eski gözlem bu markaya ait ve hâlâ geçerli olmalı. Tek işlem.
    @discardableResult
    public func addSupersedingObservation(replacing oldId: String, brandId: String, statement: String,
                                          evidenceSourceIds: [String], actor: Actor = .user) throws -> BrandObservation {
        try writer.write { db in
            guard var old = try BrandObservation.fetchOne(db, key: oldId) else { throw MarkaError.notFound(oldId) }
            guard old.brandId == brandId else { throw MarkaError.brandScope }
            guard old.isValid else { throw MarkaError.validation(L("Bu gözlem zaten kapatılmış; yerine yalnız geçerli bir gözlem geçebilir.")) }
            let new = try insertObservation(db, brandId: brandId, statement: statement, evidenceSourceIds: evidenceSourceIds,
                                            actor: actor, approvedProposalId: nil)
            let before = old
            old.status = .superseded
            old.invalidatedAt = new.validFrom
            old.supersededBy = new.id
            try old.update(db)
            try audit(db, actor: actor, brandId: brandId, entity: "observation", entityId: old.id, action: "supersede",
                      before: before, after: old)
            return new
        }
    }

    /// E-12: kullanıcı geçerli bir gözlemi "artık geçerli değil" diye kapatır. Gözlem silinmez, metni ve kanıtı değişmez;
    /// yalnız `invalidatedAt` dolar (`supersededBy` boş kalır: yerine yeni gözlem geçmedi). Bu bir kullanıcı eylemidir:
    /// yapay zekâ gözlem kapatamaz. Gözlem bu markaya ait ve hâlâ geçerli olmalı. Denetim olayı bırakır.
    @discardableResult
    public func invalidateObservation(_ id: String, brandId: String, actor: Actor = .user) throws -> BrandObservation {
        guard actor != .ai else {
            throw MarkaError.validation(L("Yapay zekâ gözlemi kapatamaz; kapatma kullanıcı eylemidir."))
        }
        return try writer.write { db in
            guard var o = try BrandObservation.fetchOne(db, key: id) else { throw MarkaError.notFound(id) }
            guard o.brandId == brandId else { throw MarkaError.brandScope }
            guard o.isValid else { throw MarkaError.validation(L("Bu gözlem zaten kapatılmış.")) }
            let before = o
            o.invalidatedAt = Date()
            try o.update(db)
            let saved = try BrandObservation.fetchOne(db, key: id) ?? o
            try audit(db, actor: actor, brandId: brandId, entity: "observation", entityId: id, action: "invalidate",
                      before: before, after: saved)
            return saved
        }
    }

    /// Gözlem yazmanın tek kapısı (işlem içinde). `.ai` yalnız onaylanmış bir önerinin uygulanması sırasında, o önerinin
    /// kimliğiyle ve aynı markada geçer (onay yolu; E-06 bağlar). Doğrudan `.ai` çağrısı reddedilir.
    @discardableResult
    func insertObservation(_ db: Database, brandId: String, statement: String, evidenceSourceIds: [String],
                           actor: Actor, approvedProposalId: String?) throws -> BrandObservation {
        if actor == .ai {
            guard let pid = approvedProposalId,
                  let owner = try String.fetchOne(db, sql: "SELECT brandId FROM aiProposal WHERE id = ?", arguments: [pid]) else {
                throw MarkaError.validation(L("Yapay zekâ gözlemi doğrudan yazamaz; gözlem öneri olarak gelir ve onayla eklenir."))
            }
            guard owner == brandId else { throw MarkaError.brandScope }
        }
        guard try Brand.fetchOne(db, key: brandId) != nil else { throw MarkaError.notFound(brandId) }
        let text = statement.trimmed
        guard !text.isEmpty else { throw MarkaError.validation(L("Gözlem boş olamaz.")) }
        guard !text.contains(where: \.isNewline) else { throw MarkaError.validation(L("Gözlem tek cümle olmalı; satır sonu içeremez.")) }
        guard text.count <= BrandObservation.maxStatementLength else {
            throw MarkaError.validation(LF("Gözlem çok uzun (en çok %d).", BrandObservation.maxStatementLength))
        }
        var seen = Set<String>()
        let ids = evidenceSourceIds.map(\.trimmed).filter { !$0.isEmpty && seen.insert($0).inserted }
        guard !ids.isEmpty else { throw MarkaError.validation(L("Gözlem en az bir kaynağa dayanmalı.")) }
        guard ids.count <= BrandObservation.maxEvidence else {
            throw MarkaError.validation(LF("Bir gözlem en çok şu kadar kaynağa dayanabilir: %d", BrandObservation.maxEvidence))
        }
        for id in ids {
            guard let owner = try String.fetchOne(db, sql: "SELECT brandId FROM source WHERE id = ?", arguments: [id]) else {
                throw MarkaError.notFound(id)
            }
            guard owner == brandId else { throw MarkaError.brandScope }
        }
        let now = Date()
        let o = BrandObservation(brandId: brandId, statement: text, evidenceSourceIds: ids, validFrom: now, createdAt: now)
        try o.insert(db)
        // Saklanan satır döner (tarih veri tabanı hassasiyetiyle); sonraki karşılaştırmalar kayıtla birebir tutar.
        let saved = try BrandObservation.fetchOne(db, key: o.id) ?? o
        try audit(db, actor: actor, brandId: brandId, entity: "observation", entityId: saved.id, action: "create",
                  before: BrandObservation?.none, after: saved)
        return saved
    }
}
