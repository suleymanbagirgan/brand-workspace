import Foundation
import GRDB
import Testing
@testable import MarkaCore

/// H1-05: arşivlenen dosya geri bulunur ve arşivden çıkarılır. Arşivden çıkarma yalnız `archivedAt`'ı değiştirir (kural 2),
/// denetim olayı bırakır (kural 5) ve görünen markayla kapsanır (kural 1).
@Suite struct ArsivGeriAlTests {
    private func auditActions(_ store: Store, entityId: String) throws -> [AuditEvent] {
        try store.writer.read { db in
            try AuditEvent.filter(Column("entity") == "source" && Column("entityId") == entityId).order(Column("at")).fetchAll(db)
        }
    }

    @Test func arsivdenCikarmaDenetimOlayiBirakir() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Deneme Yangın")
        let s = try store.addTextSource(brandId: b.id, kind: .note, title: "Teklif notu", body: "Yangın dolabı fiyatı soruldu.")
        try store.setSourceArchived(s.id, brandId: b.id, archived: true)
        try store.setSourceArchived(s.id, brandId: b.id, archived: false)
        let events = try auditActions(store, entityId: s.id)
        #expect(events.map(\.action) == ["create", "archive", "unarchive"])
        let unarchive = try #require(events.last)
        #expect(unarchive.brandId == b.id)
        #expect(unarchive.actor == .user)
    }

    @Test func arsivdenCikarmaHamKaynagiDegistirmez() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Kuzey Lojistik")
        let added = try store.addTextSource(brandId: b.id, kind: .meeting, title: "Görüşme", body: "Depo kirası konuşuldu.")
        // Veritabanından okunan hâli (tarih hassasiyeti saklanan değerle aynı olsun).
        let s = try store.source(added.id)
        try store.setSourceArchived(s.id, brandId: b.id, archived: true)
        try store.setSourceArchived(s.id, brandId: b.id, archived: false)
        let after = try store.source(s.id)
        #expect(after.archivedAt == nil)
        #expect(after.body == s.body)
        #expect(after.sha256 == s.sha256)
        #expect(after.title == s.title)
        #expect(after.capturedAt == s.capturedAt)
        #expect(after.byteSize == s.byteSize)
        // Tetikleyici arşivden çıkarılmış kaynakta da içerik değişikliğini reddetmeye devam eder.
        #expect(throws: (any Error).self) {
            try store.writer.write { db in try db.execute(sql: "UPDATE source SET body = 'değişti' WHERE id = ?", arguments: [s.id]) }
        }
        #expect(throws: (any Error).self) {
            try store.writer.write { db in
                try db.execute(sql: "UPDATE source SET archivedAt = NULL, title = 'yeni ad' WHERE id = ?", arguments: [s.id])
            }
        }
        #expect(try store.source(s.id).title == "Görüşme")
    }

    @Test func baskaMarkaninKaynagiArsivdenCikarilamaz() throws {
        let store = try makeStore()
        let a = try store.createBrand(name: "Deneme Yangın")
        let other = try store.createBrand(name: "Örnek Kafe Zinciri")
        let s = try store.addTextSource(brandId: a.id, kind: .note, title: "Not", body: "İçerik")
        try store.setSourceArchived(s.id, brandId: a.id, archived: true)
        #expect(throws: MarkaError.brandScope) {
            try store.setSourceArchived(s.id, brandId: other.id, archived: false)
        }
        #expect(throws: MarkaError.brandScope) {
            try store.setSourceArchived(s.id, brandId: other.id, archived: true)
        }
        #expect(try store.source(s.id).archivedAt != nil, "başka marka adına yapılan çağrı hiçbir şey yazmaz")
        #expect(try auditActions(store, entityId: s.id).map(\.action) == ["create", "archive"])
    }

    @Test func arsivlemeGeriAlinabilir() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Deneme Yangın")
        let s = try store.addTextSource(brandId: b.id, kind: .note, title: "Brif", body: "Kampanya brifi")
        try store.setSourceArchived(s.id, brandId: b.id, archived: true)
        #expect(try store.sources(brandId: b.id).isEmpty)
        // "Geri al" ve ⌘Z aynı çağrıyı yapar: arşivden çıkar.
        try store.setSourceArchived(s.id, brandId: b.id, archived: false)
        #expect(try store.sources(brandId: b.id).map(\.id) == [s.id])
        // Aynı duruma ikinci çağrı yazmaz (yinelenen denetim olayı yok).
        try store.setSourceArchived(s.id, brandId: b.id, archived: false)
        #expect(try auditActions(store, entityId: s.id).map(\.action) == ["create", "archive", "unarchive"])
    }

    @Test func arsivlenmisKaynakVarsayilanListedeVeAramadaGorunmez() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Kuzey Lojistik")
        let kept = try store.addTextSource(brandId: b.id, kind: .note, title: "Açık not", body: "forklift bakımı planı")
        let gone = try store.addTextSource(brandId: b.id, kind: .note, title: "Eski not", body: "forklift kiralama teklifi")
        try store.setSourceArchived(gone.id, brandId: b.id, archived: true)
        #expect(try store.sources(brandId: b.id).map(\.id) == [kept.id])
        let hits = try store.search("forklift", brandId: b.id)
        #expect(hits.contains { $0.id == kept.id })
        #expect(!hits.contains { $0.id == gone.id })
        #expect(!(try store.searchToday("Eski not")).contains { $0.ref.id == gone.id })
        // Arşivden çıkınca yeniden aranır.
        try store.setSourceArchived(gone.id, brandId: b.id, archived: false)
        #expect(try store.search("forklift", brandId: b.id).contains { $0.id == gone.id })
    }

    @Test func arsivlenenlerListesiYalnizGorunenMarkayiGosterir() throws {
        let store = try makeStore()
        let a = try store.createBrand(name: "Deneme Yangın")
        let other = try store.createBrand(name: "Örnek Kafe Zinciri")
        let mine = try store.addTextSource(brandId: a.id, kind: .note, title: "Bizim arşiv", body: "a")
        let active = try store.addTextSource(brandId: a.id, kind: .note, title: "Bizim etkin", body: "b")
        let theirs = try store.addTextSource(brandId: other.id, kind: .note, title: "Onların arşivi", body: "c")
        try store.setSourceArchived(mine.id, brandId: a.id, archived: true)
        try store.setSourceArchived(theirs.id, brandId: other.id, archived: true)
        // Dosyalar › Arşivlenenler ile aynı okuma: includeArchived ve arşiv damgası olanlar.
        let archived = try store.sources(brandId: a.id, includeArchived: true).filter { $0.archivedAt != nil }
        #expect(archived.map(\.id) == [mine.id])
        #expect(try store.sources(brandId: a.id, includeArchived: true).allSatisfy { $0.brandId == a.id })
        #expect(try store.sources(brandId: a.id, includeArchived: true).map(\.id).contains(active.id))
    }
}
