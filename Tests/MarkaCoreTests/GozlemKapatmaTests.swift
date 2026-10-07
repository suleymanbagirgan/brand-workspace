import Foundation
import GRDB
import Testing
@testable import MarkaCore

/// E-12: kullanıcının bir gözlemi "artık geçerli değil" diye kapatması. Adlar uydurmadır; bellek içi veri tabanı
/// (gerçek veri, ağ, Keychain yok).
@Suite struct GozlemKapatmaTests {
    struct Kurulum {
        let store: Store
        let a: String, b: String
        let aKaynak: String, bKaynak: String
    }

    static func kur() throws -> Kurulum {
        let s = try makeStore()
        let a = try s.createBrand(name: "Deneme Yangın").id
        let b = try s.createBrand(name: "Örnek Kafe Zinciri").id
        let ka = try s.addTextSource(brandId: a, kind: .meeting, title: "Haftalık görüşme", body: "Teslim Kasım sonu").id
        let kb = try s.addTextSource(brandId: b, kind: .note, title: "Menü notu", body: "Yeni menü Ocak'ta").id
        return Kurulum(store: s, a: a, b: b, aKaynak: ka, bKaynak: kb)
    }

    @Test func kapatmaDenetimOlayiBirakirVeIcerikDegismez() throws {
        let k = try Self.kur()
        let o = try k.store.addObservation(brandId: k.a, statement: "Teslim tarihi Kasım sonu.", evidenceSourceIds: [k.aKaynak])
        let kapali = try k.store.invalidateObservation(o.id, brandId: k.a)
        #expect(kapali.invalidatedAt != nil && kapali.supersededBy == nil && !kapali.isValid)
        #expect(kapali.statement == o.statement && kapali.evidenceSourceIds == o.evidenceSourceIds && kapali.validFrom == o.validFrom)
        let iz = try k.store.auditTrail(entity: "observation", entityId: o.id)
        let kapatma = try #require(iz.first { $0.action == "invalidate" })
        #expect(kapatma.actor == .user && kapatma.brandId == k.a)
        // Gözlem silinmez: geçmişte durur.
        #expect(try k.store.observations(brandId: k.a, includeInvalidated: true).map(\.id) == [o.id])
    }

    @Test func baskaMarkaninGozlemiKapatilamaz() throws {
        let k = try Self.kur()
        let ob = try k.store.addObservation(brandId: k.b, statement: "Yeni menü Ocak'ta çıkar.", evidenceSourceIds: [k.bKaynak])
        #expect(throws: MarkaError.brandScope) { try k.store.invalidateObservation(ob.id, brandId: k.a) }
        #expect(try k.store.observations(brandId: k.b).map(\.id) == [ob.id])
        #expect(try k.store.auditTrail(entity: "observation", entityId: ob.id).allSatisfy { $0.action != "invalidate" })
    }

    @Test func kapatilanGozlemGecerliListedenVeBaglamdanDuser() throws {
        let k = try Self.kur()
        let kalan = try k.store.addObservation(brandId: k.a, statement: "Rapor kısa olmalı.", evidenceSourceIds: [k.aKaynak])
        let giden = try k.store.addObservation(brandId: k.a, statement: "Teslim tarihi Kasım sonu.", evidenceSourceIds: [k.aKaynak])
        try k.store.invalidateObservation(giden.id, brandId: k.a)
        // Varsayılan okuma (bağlamın ve ekranın okuduğu geçerli gözlemler) kapatılanı döndürmez.
        #expect(try k.store.observations(brandId: k.a).map(\.id) == [kalan.id])
        let baglam = try ContextBuilder(store: k.store).brandContext(brandId: k.a)
        // E-16: bağlam gözlemleri okur; kontrol boşuna geçemez: geçerli gözlem marka belleği bloğunda VAR, kapatılan YOK.
        #expect(baglam.contains("<kaynak_icerigi arac=\"marka_bellegi\">"))
        #expect(baglam.contains("Rapor kısa olmalı.") && baglam.contains("id=\(kalan.id)"))
        #expect(!baglam.contains("Teslim tarihi Kasım sonu.") && !baglam.contains(giden.id))
    }

    @Test func kapatilmisGozlemYenidenKapatilamazVeYapayZekaKapatamaz() throws {
        let k = try Self.kur()
        let o = try k.store.addObservation(brandId: k.a, statement: "Teslim tarihi Kasım sonu.", evidenceSourceIds: [k.aKaynak])
        #expect(throws: MarkaError.self) { try k.store.invalidateObservation(o.id, brandId: k.a, actor: .ai) }
        #expect(try k.store.observations(brandId: k.a).map(\.id) == [o.id])
        try k.store.invalidateObservation(o.id, brandId: k.a)
        #expect(throws: MarkaError.self) { try k.store.invalidateObservation(o.id, brandId: k.a) }
        #expect(throws: MarkaError.notFound("yok")) { try k.store.invalidateObservation("yok", brandId: k.a) }
        #expect(try k.store.auditTrail(entity: "observation", entityId: o.id).filter { $0.action == "invalidate" }.count == 1)
    }

    @Test func kullanicininKapattigiOnayliGozlemGeriAlinamaz() throws {
        let k = try Self.kur()
        let p = try k.store.createProposal(sessionId: nil, brandId: k.a, kind: .createObservation, summary: "Gözlem",
                                           payload: ProposalPayload.CreateObservation(statement: "Teslim tarihi Kasım sonu.",
                                                                                      evidenceSourceIds: [k.aKaynak]))
        let uygulanan = try k.store.applyProposal(p.id)
        let gid = try #require(uygulanan.resultEntityId)
        try k.store.invalidateObservation(gid, brandId: k.a)
        #expect(throws: MarkaError.self) { try k.store.revertProposal(p.id) }
        #expect(try k.store.observations(brandId: k.a, includeInvalidated: true).map(\.id) == [gid])
    }
}
