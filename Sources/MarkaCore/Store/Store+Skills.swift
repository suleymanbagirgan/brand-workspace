import Foundation
import GRDB

extension Store {
    // MARK: Yetenek kütüphanesi (0.4.0)

    public func skills() throws -> [Skill] {
        try read { db in
            try Skill.fetchAll(db).sorted {
                $0.pack != $1.pack ? ($0.pack.isEmpty ? "~" : $0.pack) < ($1.pack.isEmpty ? "~" : $1.pack)
                    : $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending
            }
        }
    }

    /// Ekler ya da günceller. Ad `küçük-harf-tire` olmalı (en çok 64), tanım boş olamaz (en çok 1024), ad tekildir.
    /// Köken (E-07) bu yoldan yazılmaz: güncellemede mevcut kaydınki korunur; yeni kayıt `pack` doluysa hazır paket
    /// (gövde özetiyle), değilse elle yazılmış sayılır.
    @discardableResult
    public func saveSkill(_ skill: Skill, actor: Actor = .user) throws -> Skill {
        try persistSkill(skill, provenance: nil, actor: actor)
    }

    /// İçe aktarım kökeni: kaynak türü ve tarih. Özet kayıt anında, sadeleştirilmiş gövdeden hesaplanır.
    private struct SkillProvenance { var origin: SkillOrigin; var importedAt: Date }

    private func persistSkill(_ skill: Skill, provenance: SkillProvenance?, actor: Actor) throws -> Skill {
        var s = skill
        s.name = skill.name.trimmed; s.title = skill.title.trimmed; s.description = skill.description.trimmed; s.body = skill.body.trimmed
        guard !s.name.isEmpty, s.name.count <= 64, s.name == SkillMarkdown.slug(s.name) else {
            throw MarkaError.validation(L("Yetenek adı küçük harf, rakam ve tireden oluşmalı (en çok 64 karakter)."))
        }
        guard !s.description.isEmpty else { throw MarkaError.validation(L("Tanım boş olamaz.")) }
        guard s.description.count <= 1024 else { throw MarkaError.validation(LF("Tanım çok uzun (en çok %d).", 1024)) }
        guard s.body.count <= 20_000 else { throw MarkaError.validation(LF("Yönergeler çok uzun (en çok %d).", 20_000)) }
        s.updatedAt = Date()
        return try writer.write { db in
            if let other = try Skill.filter(Column("name") == s.name && Column("id") != s.id).fetchOne(db) {
                throw MarkaError.validation(LF("“%@” adında bir yetenek zaten var.", other.name))
            }
            let before = try Skill.fetchOne(db, key: s.id)
            if let before { s.createdAt = before.createdAt }
            if let provenance {
                s.origin = provenance.origin.rawValue; s.importedAt = provenance.importedAt
                s.contentHash = Skill.digest(body: s.body)
            } else if let before {
                s.origin = before.origin; s.contentHash = before.contentHash; s.importedAt = before.importedAt
            } else if !s.pack.isEmpty {
                s.origin = SkillOrigin.pack.rawValue; s.contentHash = Skill.digest(body: s.body); s.importedAt = nil
            } else {
                s.origin = SkillOrigin.manual.rawValue; s.contentHash = ""; s.importedAt = nil
            }
            try s.save(db)
            try audit(db, actor: actor, brandId: nil, entity: "skill", entityId: s.id,
                      action: before == nil ? "create" : "update", before: before, after: s)
            return s
        }
    }

    public func deleteSkill(_ id: String, actor: Actor = .user) throws {
        try writer.write { db in
            guard let before = try Skill.fetchOne(db, key: id) else { throw MarkaError.notFound(id) }
            try before.delete(db)
            try audit(db, actor: actor, brandId: nil, entity: "skill", entityId: id, action: "delete", before: before, after: Skill?.none)
        }
    }

    /// SKILL.md metninden yetenek ekler. Biçim hatalıysa açıklayıcı hata verir. Köken `file:<dosya adı>` (yalnız son yol
    /// bileşeni), içe aktarma tarihi ve gövde özeti saklanır (E-07).
    @discardableResult
    public func importSkill(markdown: String, fileName: String = "", actor: Actor = .user) throws -> Skill {
        guard let parsed = SkillMarkdown.parse(markdown) else {
            throw MarkaError.validation(L("SKILL.md biçimi okunamadı: başta --- arasında name ve description satırları olmalı."))
        }
        let name = SkillMarkdown.slug(parsed.name)
        return try persistSkill(Skill(name: name, title: parsed.name == name ? "" : parsed.name, description: parsed.description, body: parsed.body),
                                provenance: .init(origin: .file(SkillOrigin.cleanName(fileName)), importedAt: Date()), actor: actor)
    }

    /// E-02 önizlemesi kullanıcı onaylandıktan sonra kaydeder (E-07). Köken `folder:<klasör adı>`, içe aktarma tarihi ve gövde
    /// özeti yazılır. Önizleme "güncelleme" ise mevcut kayıt (kimlik, paket anahtarı, oluşturma tarihi) korunarak ezilir;
    /// önizlemeden sonra kayıt silindiyse ya da ad başka kayda geçtiyse açıklayıcı hata verir.
    @discardableResult
    public func importSkillBundle(_ preview: SkillBundlePreview, folderName: String = "", actor: Actor = .user) throws -> Skill {
        let existing = try skills()
        if let id = preview.existingId {
            guard let old = existing.first(where: { $0.id == id }), old.name == preview.name else {
                throw MarkaError.validation(L("Önizlemeden sonra kütüphane değişti; paketi yeniden seç."))
            }
        }
        return try persistSkill(preview.skill(existing: existing),
                                provenance: .init(origin: .folder(SkillOrigin.cleanName(folderName)), importedAt: Date()), actor: actor)
    }

    /// Hazır paketi yükler. Zaten var olan yetenekler olduğu gibi kalır (yaptığın düzenleme ezilmez). Eklenen sayısını döner.
    @discardableResult
    public func installSkillPack(_ pack: SkillPack, actor: Actor = .user) throws -> Int {
        var added = 0
        for item in pack.skills {
            if try read({ db in try Skill.filter(Column("name") == item.name).fetchOne(db) }) != nil { continue }
            _ = try saveSkill(Skill(name: item.name, title: item.title, description: item.description, body: item.body, pack: pack.key), actor: actor)
            added += 1
        }
        return added
    }

    /// Üyenin yetenek listesindeki adlarla eşleşen kütüphane kayıtları (eşleşmeyenler serbest metin yetenektir).
    func librarySkills(for member: TeamMember) throws -> [Skill] {
        let names = Set(member.skills)
        guard !names.isEmpty else { return [] }
        return try read { db in try Skill.filter(names.contains(Column("name"))).fetchAll(db) }
    }
}
