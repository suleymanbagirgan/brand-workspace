import Foundation
import GRDB
import Testing
@testable import MarkaCore

/// E-01: kanıt sayılı marka gözlemi. Adlar uydurmadır; bellek içi veri tabanı (gerçek veri, ağ, Keychain yok).
@Suite struct GozlemTests {
    struct Kurulum {
        let store: Store
        let a: String, b: String
        let aKaynak1: String, aKaynak2: String, bKaynak: String
    }

    static func kur() throws -> Kurulum {
        let s = try makeStore()
        let a = try s.createBrand(name: "Deneme Yangın").id
        let b = try s.createBrand(name: "Kuzey Lojistik").id
        let k1 = try s.addTextSource(brandId: a, kind: .meeting, title: "Haftalık görüşme", body: "Rapor kısa olsun dendi").id
        let k2 = try s.addTextSource(brandId: a, kind: .note, title: "E-posta notu", body: "Yine kısa rapor istendi").id
        let kb = try s.addTextSource(brandId: b, kind: .note, title: "Rakip notu", body: "Kuzey Lojistik gizli bilgi").id
        return Kurulum(store: s, a: a, b: b, aKaynak1: k1, aKaynak2: k2, bKaynak: kb)
    }

    @Test func gozlemKanitSayisiylaOlusurVeDenetimOlayiBirakir() throws {
        let k = try Self.kur()
        let o = try k.store.addObservation(brandId: k.a, statement: "  Müşteri kısa rapor ister  ",
                                           evidenceSourceIds: [k.aKaynak1, k.aKaynak2, k.aKaynak1])
        #expect(o.statement == "Müşteri kısa rapor ister")
        #expect(o.evidenceSourceIds == [k.aKaynak1, k.aKaynak2] && o.evidenceCount == 2)
        #expect(o.status == .active && o.invalidatedAt == nil && o.supersededBy == nil)
        let iz = try k.store.auditTrail(entity: "observation", entityId: o.id)
        #expect(iz.count == 1 && iz[0].action == "create" && iz[0].actor == .user && iz[0].brandId == k.a)
        // Kalıcı satır JSON dizisiyle geri okunur.
        #expect(try k.store.observations(brandId: k.a) == [o])
    }

    @Test func yapayZekaGozlemiDogrudanYazamaz() throws {
        let k = try Self.kur()
        #expect(throws: MarkaError.self) {
            try k.store.addObservation(brandId: k.a, statement: "Müşteri kısa rapor ister", evidenceSourceIds: [k.aKaynak1], actor: .ai)
        }
        let eski = try k.store.addObservation(brandId: k.a, statement: "Rapor uzun olabilir", evidenceSourceIds: [k.aKaynak1])
        #expect(throws: MarkaError.self) {
            try k.store.addSupersedingObservation(replacing: eski.id, brandId: k.a, statement: "Rapor kısa olmalı",
                                                  evidenceSourceIds: [k.aKaynak2], actor: .ai)
        }
        #expect(try k.store.observations(brandId: k.a, includeInvalidated: true).map(\.id) == [eski.id])
        #expect(try k.store.read { db in try AuditEvent.filter(Column("entity") == "observation" && Column("actor") == "ai").fetchCount(db) } == 0)
    }

    @Test func yapayZekaYalnizAyniMarkadakiOnayliOneriKimligiyleGecer() throws {
        let k = try Self.kur()
        let oneriA = try k.store.createProposal(sessionId: nil, brandId: k.a, kind: .createTask, summary: "Gözlem önerisi",
                                                payload: ProposalPayload.CreateTask(title: "Önerilen görev"))
        let oneriB = try k.store.createProposal(sessionId: nil, brandId: k.b, kind: .createTask, summary: "Başka marka",
                                                payload: ProposalPayload.CreateTask(title: "Başka görev"))
        func yaz(_ pid: String?) throws -> BrandObservation {
            try k.store.write { db in
                try k.store.insertObservation(db, brandId: k.a, statement: "Müşteri kısa rapor ister", evidenceSourceIds: [k.aKaynak1],
                                              actor: .ai, approvedProposalId: pid)
            }
        }
        #expect(throws: MarkaError.validation(L("Yapay zekâ gözlemi doğrudan yazamaz; gözlem öneri olarak gelir ve onayla eklenir."))) { try yaz(nil) }
        #expect(throws: MarkaError.self) { try yaz("olmayan-oneri") }
        #expect(throws: MarkaError.brandScope) { try yaz(oneriB.id) }
        let o = try yaz(oneriA.id)
        #expect(try k.store.auditTrail(entity: "observation", entityId: o.id).first?.actor == .ai)
    }

    @Test func bosKanitBosCumleVeCokSatirliCumleReddedilir() throws {
        let k = try Self.kur()
        #expect(throws: MarkaError.validation(L("Gözlem en az bir kaynağa dayanmalı."))) {
            try k.store.addObservation(brandId: k.a, statement: "Müşteri kısa rapor ister", evidenceSourceIds: [])
        }
        #expect(throws: MarkaError.validation(L("Gözlem en az bir kaynağa dayanmalı."))) {
            try k.store.addObservation(brandId: k.a, statement: "Müşteri kısa rapor ister", evidenceSourceIds: ["  ", ""])
        }
        #expect(throws: MarkaError.self) { try k.store.addObservation(brandId: k.a, statement: "   ", evidenceSourceIds: [k.aKaynak1]) }
        #expect(throws: MarkaError.self) {
            try k.store.addObservation(brandId: k.a, statement: "Birinci cümle.\nİkinci satır", evidenceSourceIds: [k.aKaynak1])
        }
        #expect(throws: MarkaError.self) {
            try k.store.addObservation(brandId: k.a, statement: String(repeating: "a", count: BrandObservation.maxStatementLength + 1),
                                       evidenceSourceIds: [k.aKaynak1])
        }
        #expect(throws: MarkaError.self) {
            try k.store.addObservation(brandId: k.a, statement: "Müşteri kısa rapor ister", evidenceSourceIds: ["olmayan-kaynak"])
        }
        #expect(try k.store.observations(brandId: k.a, includeInvalidated: true).isEmpty)
        #expect(try k.store.read { db in try AuditEvent.filter(Column("entity") == "observation").fetchCount(db) } == 0)
    }

    @Test func baskaMarkaninKaynaginaDayananGozlemReddedilir() throws {
        let k = try Self.kur()
        #expect(throws: MarkaError.brandScope) {
            try k.store.addObservation(brandId: k.a, statement: "Rakip kısa rapor ister", evidenceSourceIds: [k.aKaynak1, k.bKaynak])
        }
        let eski = try k.store.addObservation(brandId: k.a, statement: "Rapor uzun olabilir", evidenceSourceIds: [k.aKaynak1])
        #expect(throws: MarkaError.brandScope) {
            try k.store.addSupersedingObservation(replacing: eski.id, brandId: k.a, statement: "Rapor kısa olmalı", evidenceSourceIds: [k.bKaynak])
        }
        // Başka markanın gözlemi bu markanın kimliğiyle kapatılamaz.
        #expect(throws: MarkaError.brandScope) {
            try k.store.addSupersedingObservation(replacing: eski.id, brandId: k.b, statement: "Kuzey gözlemi", evidenceSourceIds: [k.bKaynak])
        }
        #expect(try k.store.observations(brandId: k.a).map(\.id) == [eski.id])
        #expect(try k.store.observations(brandId: k.b, includeInvalidated: true).isEmpty)
    }

    @Test func yerineGecmeEskisiniSilmezKapatirGecmisKorunur() throws {
        let k = try Self.kur()
        let eski = try k.store.addObservation(brandId: k.a, statement: "Rapor uzun olabilir", evidenceSourceIds: [k.aKaynak1])
        let yeni = try k.store.addSupersedingObservation(replacing: eski.id, brandId: k.a, statement: "Rapor kısa olmalı",
                                                         evidenceSourceIds: [k.aKaynak1, k.aKaynak2])
        #expect(yeni.evidenceCount == 2 && yeni.isValid)
        #expect(try k.store.observations(brandId: k.a).map(\.id) == [yeni.id])
        let gecmis = try k.store.observations(brandId: k.a, includeInvalidated: true)
        #expect(Set(gecmis.map(\.id)) == [eski.id, yeni.id])
        let kapali = try #require(gecmis.first { $0.id == eski.id })
        #expect(kapali.statement == "Rapor uzun olabilir" && kapali.evidenceSourceIds == [k.aKaynak1])
        #expect(kapali.status == .superseded && kapali.supersededBy == yeni.id && kapali.invalidatedAt == yeni.validFrom)
        let iz = try k.store.auditTrail(entity: "observation", entityId: eski.id)
        #expect(iz.map(\.action).sorted() == ["create", "supersede"])
        // Kapatılmış gözlemin yerine ikinci kez geçilemez.
        #expect(throws: MarkaError.self) {
            try k.store.addSupersedingObservation(replacing: eski.id, brandId: k.a, statement: "Üçüncü sürüm", evidenceSourceIds: [k.aKaynak2])
        }
        #expect(throws: MarkaError.notFound("olmayan")) {
            try k.store.addSupersedingObservation(replacing: "olmayan", brandId: k.a, statement: "Yok", evidenceSourceIds: [k.aKaynak2])
        }
    }

    @Test func gozlemlerBaskaMarkayiHicDondurmez() throws {
        let k = try Self.kur()
        let oa = try k.store.addObservation(brandId: k.a, statement: "Deneme Yangın kısa rapor ister", evidenceSourceIds: [k.aKaynak1])
        let ob = try k.store.addObservation(brandId: k.b, statement: "Kuzey Lojistik gizli bilgi", evidenceSourceIds: [k.bKaynak])
        let obYeni = try k.store.addSupersedingObservation(replacing: ob.id, brandId: k.b, statement: "Kuzey Lojistik yeni gizli bilgi",
                                                           evidenceSourceIds: [k.bKaynak])
        for kapali in [false, true] {
            let sonuc = try k.store.observations(brandId: k.a, includeInvalidated: kapali)
            #expect(sonuc.map(\.id) == [oa.id])
            let duz = String(describing: sonuc)
            #expect(!duz.contains("Kuzey") && !duz.contains(k.b) && !duz.contains(ob.id) && !duz.contains(obYeni.id) && !duz.contains(k.bKaynak))
        }
        #expect(Set(try k.store.observations(brandId: k.b, includeInvalidated: true).map(\.id)) == [ob.id, obYeni.id])
        #expect(try k.store.observations(brandId: "olmayan-marka", includeInvalidated: true).isEmpty)
    }

    @Test func gozlemIcerigiVeritabanindaDegistirilemezKapaliGozlemYenidenAcilamaz() throws {
        let k = try Self.kur()
        let o = try k.store.addObservation(brandId: k.a, statement: "Rapor uzun olabilir", evidenceSourceIds: [k.aKaynak1])
        #expect(throws: (any Error).self) {
            try k.store.write { db in try db.execute(sql: "UPDATE observation SET statement = 'üzerine yazıldı' WHERE id = ?", arguments: [o.id]) }
        }
        #expect(throws: (any Error).self) {
            try k.store.write { db in try db.execute(sql: "UPDATE observation SET brandId = ? WHERE id = ?", arguments: [k.b, o.id]) }
        }
        _ = try k.store.addSupersedingObservation(replacing: o.id, brandId: k.a, statement: "Rapor kısa olmalı", evidenceSourceIds: [k.aKaynak2])
        #expect(throws: (any Error).self) {
            try k.store.write { db in
                try db.execute(sql: "UPDATE observation SET status = 'active', invalidatedAt = NULL, supersededBy = NULL WHERE id = ?", arguments: [o.id])
            }
        }
        #expect(try k.store.observations(brandId: k.a, includeInvalidated: true).first { $0.id == o.id }?.statement == "Rapor uzun olabilir")
    }

    @Test func v10MigrationBellekIciVeritabanindaTabloyuVeTetikleyiciyiKurar() throws {
        let store = try makeStore()
        #expect(AppDatabase.migrationIdentifiers.contains("v10_gozlemler"))
        let (sutunlar, tetik, uygulandi) = try store.read { db in
            (Set(try db.columns(in: "observation").map(\.name)),
             try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'trigger' AND tbl_name = 'observation'"),
             try AppDatabase.migrator.appliedIdentifiers(db))
        }
        #expect(sutunlar == ["id", "brandId", "statement", "evidenceSourceIds", "evidenceCount", "status", "validFrom",
                             "invalidatedAt", "supersededBy", "createdAt"])
        #expect(tetik == ["observation_immutable"])
        #expect(uygulandi.contains("v10_gozlemler"))
        // Kurulan tabloya yazılır ve okunur.
        let a = try store.createBrand(name: "Örnek Kafe Zinciri").id
        let k = try store.addTextSource(brandId: a, kind: .note, title: "Not", body: "Sentetik").id
        _ = try store.addObservation(brandId: a, statement: "Sabah kampanyası iyi gider", evidenceSourceIds: [k])
        #expect(try store.read { db in try BrandObservation.fetchCount(db) } == 1)
    }
}
