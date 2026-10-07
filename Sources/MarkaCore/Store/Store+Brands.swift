import Foundation
import GRDB

extension Store {
    // MARK: Markalar

    public func brands(includeArchived: Bool = false) throws -> [Brand] {
        try read { db in
            var q = Brand.all()
            if !includeArchived { q = q.filter(Column("status") == BrandStatus.active.rawValue) }
            return try q.fetchAll(db).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    /// Kullanıcının kendi şirketi (Stüdyo); kurulmamışsa `nil`.
    public func ownBrand() throws -> Brand? {
        try read { db in try Brand.filter(Column("isOwn") == true).fetchOne(db) }
    }

    public func brand(_ id: String) throws -> Brand {
        guard let b = try read({ db in try Brand.fetchOne(db, key: id) }) else { throw MarkaError.notFound(id) }
        return b
    }

    @discardableResult
    public func createBrand(name: String, summary: String = "", sector: String = "", isOwn: Bool = false, actor: Actor = .user) throws -> Brand {
        let clean = name.trimmed
        guard !clean.isEmpty else { throw MarkaError.validation(L("Marka adı boş olamaz.")) }
        return try writer.write { db in try insertBrand(db, name: clean, summary: summary, sector: sector, isOwn: isOwn, actor: actor) }
    }

    /// Stüdyoyu tek işlemde kurar (B7): kendi şirket markası + şirket profilinin adı. Ad sınırı başta denetlenir; var olan profilin
    /// diğer alanları (slogan, hakkımızda, misyon…) korunur. Herhangi bir adım başarısızsa hiçbir şey yazılmaz.
    @discardableResult
    public func createStudio(name: String, actor: Actor = .user) throws -> Brand {
        let clean = name.trimmed
        guard !clean.isEmpty else { throw MarkaError.validation(L("Marka adı boş olamaz.")) }
        guard clean.count <= 120 else { throw MarkaError.validation(LF("Ad çok uzun (en çok %d).", 120)) }
        return try writer.write { db in
            let brand = try insertBrand(db, name: clean, summary: "", sector: "", isOwn: true, actor: actor)
            let before = try CompanyProfile.fetchOne(db, key: CompanyProfile.singletonId)
            var profile = before ?? CompanyProfile()
            profile.id = CompanyProfile.singletonId
            profile.name = clean
            profile.updatedAt = Date()
            try profile.save(db)
            try audit(db, actor: actor, brandId: nil, entity: "company", entityId: profile.id,
                      action: before == nil ? "create" : "update", before: before, after: profile)
            return brand
        }
    }

    func insertBrand(_ db: Database, name clean: String, summary: String, sector: String, isOwn: Bool, actor: Actor) throws -> Brand {
        let existing = try String.fetchAll(db, sql: "SELECT name FROM brand")
        let tr = Locale(identifier: "tr_TR")
        if existing.contains(where: { $0.lowercased(with: tr) == clean.lowercased(with: tr) }) {
            throw MarkaError.validation(LF("“%@” adında bir marka zaten var.", clean))
        }
        if isOwn, try Brand.filter(Column("isOwn") == true).fetchOne(db) != nil { throw MarkaError.validation(L("Şirket zaten kurulmuş.")) }
        let brand = Brand(name: clean, summary: summary.trimmed, sector: sector.trimmed, isOwn: isOwn)
        try brand.insert(db)
        try BrandRules(brandId: brand.id, body: WikiRulesTemplate.defaultBody).insert(db)
        try audit(db, actor: actor, brandId: brand.id, entity: "brand", entityId: brand.id, action: "create",
                  before: Brand?.none, after: brand)
        return brand
    }

    public func updateBrand(_ brand: Brand, actor: Actor = .user) throws {
        guard !brand.name.trimmed.isEmpty else { throw MarkaError.validation(L("Marka adı boş olamaz.")) }
        try writer.write { db in
            guard let before = try Brand.fetchOne(db, key: brand.id) else { throw MarkaError.notFound(brand.id) }
            let tr = Locale(identifier: "tr_TR")
            let others = try String.fetchAll(db, sql: "SELECT name FROM brand WHERE id != ?", arguments: [brand.id])
            if others.contains(where: { $0.lowercased(with: tr) == brand.name.trimmed.lowercased(with: tr) }) {
                throw MarkaError.validation(LF("“%@” adında bir marka zaten var.", brand.name.trimmed))
            }
            var b = brand
            b.name = brand.name.trimmed
            // Kendi şirket işareti kullanıcı ya da AI güncellemesiyle değişmez (B5); yalnız `createBrand(isOwn:)`/`createStudio` koyar.
            b.isOwn = before.isOwn
            b.updatedAt = Date()
            try b.update(db)
            try audit(db, actor: actor, brandId: b.id, entity: "brand", entityId: b.id, action: "update", before: before, after: b)
        }
    }

    /// Arşivlenmiş markalar (Ayarlar › Veri › "Arşivlenmiş markalar").
    public func archivedBrands() throws -> [Brand] {
        try brands(includeArchived: true).filter { $0.status == .archived }
    }

    /// Markayı arşivler ya da arşivden çıkarır; veri silinmez, denetim olayı "update" olarak kalır.
    public func setBrandArchived(_ id: String, archived: Bool) throws {
        var b = try brand(id)
        if archived, b.isOwn { throw MarkaError.validation(L("Şirket arşivlenemez.")) }
        b.status = archived ? .archived : .active
        try updateBrand(b)
    }

    /// Logo dosyasını içerik adresli depoya kopyalar.
    public func setBrandLogo(_ id: String, fileURL: URL) throws {
        let stored = try FileVault(root: database.filesRoot).store(fileURL: fileURL)
        var b = try brand(id)
        b.logoPath = stored.relativePath
        try updateBrand(b)
    }

    public func setAIProviders(_ id: String, providers: Set<AIProviderKind>) throws {
        var b = try brand(id)
        b.aiProviders = providers.map(\.rawValue).sorted().joined(separator: ",")
        try updateBrand(b)
    }

    // MARK: Kişiler ve projeler

    public func contacts(brandId: String) throws -> [Contact] {
        try read { db in try Contact.filter(Column("brandId") == brandId).order(Column("name")).fetchAll(db) }
    }

    public func saveContact(_ contact: Contact) throws {
        guard !contact.name.trimmed.isEmpty else { throw MarkaError.validation(L("Kişi adı boş olamaz.")) }
        try writer.write { db in
            let before = try Contact.fetchOne(db, key: contact.id)
            if let before, before.brandId != contact.brandId { throw MarkaError.brandScope } // H2-06: markalar arası taşıma yok
            try contact.save(db)
            try audit(db, actor: .user, brandId: contact.brandId, entity: "contact", entityId: contact.id,
                      action: before == nil ? "create" : "update", before: before, after: contact)
        }
    }

    public func deleteContact(_ id: String) throws {
        try writer.write { db in
            guard let c = try Contact.fetchOne(db, key: id) else { return }
            try c.delete(db)
            try audit(db, actor: .user, brandId: c.brandId, entity: "contact", entityId: id, action: "delete",
                      before: c, after: Contact?.none)
        }
    }

    public func projects(brandId: String) throws -> [Project] {
        try read { db in try Project.filter(Column("brandId") == brandId).order(Column("createdAt").desc).fetchAll(db) }
    }

    public func saveProject(_ project: Project) throws {
        guard !project.name.trimmed.isEmpty else { throw MarkaError.validation(L("Proje adı boş olamaz.")) }
        if let d = project.dueDate, !DayString.isValid(d) { throw MarkaError.validation(L("Tarih geçersiz.")) }
        try writer.write { db in
            let before = try Project.fetchOne(db, key: project.id)
            if let before, before.brandId != project.brandId { throw MarkaError.brandScope } // H2-06: markalar arası taşıma yok
            try project.save(db)
            try audit(db, actor: .user, brandId: project.brandId, entity: "project", entityId: project.id,
                      action: before == nil ? "create" : "update", before: before, after: project)
        }
    }

    // MARK: Marka kayıtları

    public func records(brandId: String, kinds: [BrandRecordKind]? = nil) throws -> [BrandRecord] {
        try read { db in
            var q = BrandRecord.filter(Column("brandId") == brandId)
            if let kinds { q = q.filter(kinds.map(\.rawValue).contains(Column("kind"))) }
            return try q.order(Column("createdAt").desc).fetchAll(db)
        }
    }

    @discardableResult
    public func saveRecord(_ record: BrandRecord, actor: Actor = .user) throws -> BrandRecord {
        guard !record.title.trimmed.isEmpty else { throw MarkaError.validation(L("Başlık boş olamaz.")) }
        if let d = record.dueDate, !DayString.isValid(d) { throw MarkaError.validation(L("Tarih geçersiz.")) }
        return try writer.write { db in
            if let sid = record.sourceId {
                guard let s = try Source.fetchOne(db, key: sid), s.brandId == record.brandId else { throw MarkaError.brandScope }
            }
            let before = try BrandRecord.fetchOne(db, key: record.id)
            if let before, before.brandId != record.brandId { throw MarkaError.brandScope } // H2-06: markalar arası taşıma yok
            var r = record
            r.updatedAt = Date()
            if !r.isOpen, r.closedAt == nil { r.closedAt = Date() }
            if r.isOpen { r.closedAt = nil }
            try r.save(db)
            try audit(db, actor: actor, brandId: r.brandId, entity: "brandRecord", entityId: r.id,
                      action: before == nil ? "create" : "update", before: before, after: r)
            return r
        }
    }

    public func deleteRecord(_ id: String) throws {
        try writer.write { db in
            guard let r = try BrandRecord.fetchOne(db, key: id) else { return }
            try r.delete(db)
            try audit(db, actor: .user, brandId: r.brandId, entity: "brandRecord", entityId: id, action: "delete",
                      before: r, after: BrandRecord?.none)
        }
    }
}
