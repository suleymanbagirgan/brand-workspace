import Foundation
import GRDB

extension Store {
    // MARK: Marka radarı (E-21)

    /// Markanın radar maddeleri, en yeni önce. Varsayılan yalnız arşivlenmemiş maddeler. Yalnız `brandId` markasına ait
    /// satırlar okunur.
    public func radarItems(brandId: String, includeArchived: Bool = false) throws -> [RadarItem] {
        try read { db in
            var q = RadarItem.filter(Column("brandId") == brandId)
            if !includeArchived { q = q.filter(Column("archivedAt") == nil) }
            return try q.order(Column("createdAt").desc, Column("id")).fetchAll(db)
        }
    }

    /// Radara elle madde ekler: bağlantı, not ya da ikisi. Adres `LinkAddress.normalize` ile doğrulanır (yalnız http/https);
    /// başlık boşsa alan adı kullanılır. Bağlantının içeriği çekilmez. Yapay zekâ radara yazamaz (radarı kullanıcı besler).
    /// Denetim olayı bırakır.
    @discardableResult
    public func addRadarItem(brandId: String, title: String, address: String = "", note: String = "", tag: String = "",
                             actor: Actor = .user) throws -> RadarItem {
        guard actor != .ai else {
            throw MarkaError.validation(L("Yapay zekâ radara madde ekleyemez; radarı kullanıcı besler."))
        }
        var url: String?
        if !address.trimmed.isEmpty {
            guard let normalized = LinkAddress.normalize(address) else {
                throw MarkaError.validation(L("Geçerli bir bağlantı gir (https://…)."))
            }
            url = normalized
        }
        let cleanNote = note.trimmed
        let name = ContextBuilder.oneLine(title).trimmed.isEmpty
            ? (url.flatMap(LinkAddress.suggestedTitle(for:)) ?? "") : ContextBuilder.oneLine(title).trimmed
        guard !name.isEmpty else { throw MarkaError.validation(L("Radar maddesine bir başlık ya da bağlantı gir.")) }
        guard name.count <= RadarItem.maxTitleLength else {
            throw MarkaError.validation(LF("Başlık çok uzun (en çok %d).", RadarItem.maxTitleLength))
        }
        guard cleanNote.count <= RadarItem.maxNoteLength else {
            throw MarkaError.validation(LF("Not çok uzun (en çok %d).", RadarItem.maxNoteLength))
        }
        let cleanTag = ContextBuilder.oneLine(tag).trimmed
        guard cleanTag.count <= RadarItem.maxTagLength else {
            throw MarkaError.validation(LF("Etiket çok uzun (en çok %d).", RadarItem.maxTagLength))
        }
        return try writer.write { db in
            guard try Brand.fetchOne(db, key: brandId) != nil else { throw MarkaError.notFound(brandId) }
            let item = RadarItem(brandId: brandId, title: name, url: url, note: cleanNote, tag: cleanTag)
            try item.insert(db)
            let saved = try RadarItem.fetchOne(db, key: item.id) ?? item
            try audit(db, actor: actor, brandId: brandId, entity: "radarItem", entityId: saved.id, action: "create",
                      before: RadarItem?.none, after: saved)
            return saved
        }
    }

    /// Radar maddesini arşivler ya da arşivden çıkarır (silinmez). Madde bu markaya ait olmalı. Denetim olayı bırakır.
    @discardableResult
    public func setRadarItemArchived(_ id: String, brandId: String, archived: Bool, actor: Actor = .user) throws -> RadarItem {
        guard actor != .ai else {
            throw MarkaError.validation(L("Yapay zekâ radar maddesini değiştiremez; radarı kullanıcı besler."))
        }
        return try writer.write { db in
            guard var item = try RadarItem.fetchOne(db, key: id) else { throw MarkaError.notFound(id) }
            guard item.brandId == brandId else { throw MarkaError.brandScope }
            guard item.isArchived != archived else { return item }
            let before = item
            item.archivedAt = archived ? Date() : nil
            try item.update(db)
            let saved = try RadarItem.fetchOne(db, key: id) ?? item
            try audit(db, actor: actor, brandId: brandId, entity: "radarItem", entityId: id,
                      action: archived ? "archive" : "restore", before: before, after: saved)
            return saved
        }
    }
}
