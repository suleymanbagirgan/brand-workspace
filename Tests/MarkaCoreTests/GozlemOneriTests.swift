import Foundation
import GRDB
import Testing
@testable import MarkaCore

/// E-06: `gozlem_oner` aracı ve `createObservation` öneri türü. Yapay zekâ gözlemi yalnız önerir; insan onaylar, geri
/// alabilir. Adlar uydurmadır; bellek içi veri tabanı (gerçek veri, ağ, Keychain yok).
@Suite struct GozlemOneriTests {
    struct Kurulum {
        let store: Store
        let a: String, b: String
        let aKaynak1: String, aKaynak2: String, bKaynak: String
        var arac: ToolExecutor { ToolExecutor(store: store, scope: .brand(a), sessionId: nil) }
    }

    static func kur() throws -> Kurulum {
        let s = try makeStore()
        let a = try s.createBrand(name: "Deneme Yangın").id
        let b = try s.createBrand(name: "Kuzey Lojistik").id
        let k1 = try s.addTextSource(brandId: a, kind: .meeting, title: "Haftalık görüşme", body: "Teslim tarihi Kasım sonu").id
        let k2 = try s.addTextSource(brandId: a, kind: .note, title: "E-posta notu", body: "Teslim Aralık ortasına kaydı").id
        let kb = try s.addTextSource(brandId: b, kind: .note, title: "Bütçe notu", body: "GIZLI-BUTCE-KUZEY").id
        return Kurulum(store: s, a: a, b: b, aKaynak1: k1, aKaynak2: k2, bKaynak: kb)
    }

    static func gozlemSayisi(_ s: Store) throws -> Int {
        try s.read { db in try BrandObservation.fetchCount(db) }
    }

    /// Aracı çalıştırır ve oluşan öneriyi döndürür (hata dönerse test düşer).
    static func oner(_ k: Kurulum, _ gozlem: String, _ kaynaklar: [String], yerine: String? = nil) throws -> AIProposal {
        var girdi: [String: JSONValue] = ["gozlem": .string(gozlem), "kaynaklar": .array(kaynaklar.map { .string($0) })]
        if let yerine { girdi["yerine_gectigi_id"] = .string(yerine) }
        let r = k.arac.run(name: "gozlem_oner", input: .object(girdi))
        #expect(!r.isError, "\(r.text)")
        let id = try #require(r.event.refId)
        return try #require(try k.store.proposals(brandId: k.a).first { $0.id == id })
    }

    @Test func aracYalnizBekleyenOneriUretirUygulanmisSifirGozlemSifir() throws {
        let k = try Self.kur()
        let p = try Self.oner(k, "Teslim tarihi Kasım sonu.", [k.aKaynak1])
        #expect(p.kind == .createObservation && p.status == .pending && p.resultEntityId == nil)
        #expect(try k.store.proposals(brandId: k.a, status: .applied).isEmpty)
        #expect(try Self.gozlemSayisi(k.store) == 0)
        #expect(ToolCatalog.brandTools.first { $0.name == "gozlem_oner" }?.isProposal == true)
    }

    @Test func baskaMarkaKaynagindaAracHataDonerVeOneriOlusmaz() throws {
        let k = try Self.kur()
        let r = k.arac.run(name: "gozlem_oner", input: ["gozlem": "Bütçe belli.", "kaynaklar": [.string(k.bKaynak)]])
        #expect(r.isError)
        #expect(!r.text.contains("GIZLI-BUTCE-KUZEY"))
        // Çekirdek kapı da aynı kuralı uygular (araç atlanırsa bile).
        #expect(throws: MarkaError.brandScope) {
            try k.store.createProposal(sessionId: nil, brandId: k.a, kind: .createObservation, summary: "x",
                                       payload: ProposalPayload.CreateObservation(statement: "Bütçe belli.", evidenceSourceIds: [k.bKaynak]))
        }
        #expect(try k.store.proposals(brandId: k.a).isEmpty && k.store.proposals(brandId: k.b).isEmpty)
    }

    @Test func kaynaksizVeCokSatirliGozlemReddedilir() throws {
        let k = try Self.kur()
        #expect(k.arac.run(name: "gozlem_oner", input: ["gozlem": "Kaynaksız gözlem.", "kaynaklar": []]).isError)
        #expect(k.arac.run(name: "gozlem_oner", input: ["gozlem": "Birinci satır\nİkinci satır", "kaynaklar": [.string(k.aKaynak1)]]).isError)
        let uzun = String(repeating: "a", count: BrandObservation.maxStatementLength + 1)
        #expect(k.arac.run(name: "gozlem_oner", input: ["gozlem": .string(uzun), "kaynaklar": [.string(k.aKaynak1)]]).isError)
        #expect(k.arac.run(name: "gozlem_oner", input: ["gozlem": "Olmayan kaynak.", "kaynaklar": ["uydurma-kimlik"]]).isError)
        #expect(try k.store.proposals(brandId: k.a).isEmpty)
    }

    @Test func onaySonrasiTablodaBirSatirVeYapayZekaDenetimOlayi() throws {
        let k = try Self.kur()
        let p = try Self.oner(k, "Teslim tarihi Kasım sonu.", [k.aKaynak1, k.aKaynak1, k.aKaynak2])
        let uygulanan = try k.store.applyProposal(p.id)
        let gozlemler = try k.store.observations(brandId: k.a, includeInvalidated: true)
        #expect(gozlemler.count == 1)
        let o = try #require(gozlemler.first)
        #expect(uygulanan.status == .applied && uygulanan.resultEntityId == o.id)
        #expect(o.statement == "Teslim tarihi Kasım sonu." && o.evidenceCount == 2 && o.isValid)
        let iz = try k.store.auditTrail(entity: "observation", entityId: o.id)
        #expect(iz.count == 1 && iz[0].action == "create" && iz[0].actor == .ai && iz[0].brandId == k.a)
        #expect(try k.store.observations(brandId: k.b, includeInvalidated: true).isEmpty)
    }

    @Test func geriAlmaGozlemiSilerVeDenetimOlayiBirakir() throws {
        let k = try Self.kur()
        let p = try Self.oner(k, "Teslim tarihi Kasım sonu.", [k.aKaynak1])
        let rid = try #require(try k.store.applyProposal(p.id).resultEntityId)
        try k.store.revertProposal(p.id)
        #expect(try Self.gozlemSayisi(k.store) == 0)
        #expect(try k.store.proposals(brandId: k.a).first?.status == .reverted)
        let iz = try k.store.auditTrail(entity: "observation", entityId: rid)
        #expect(iz.contains { $0.action == "revertAI" && $0.actor == .user })
    }

    @Test func yerineGecenOnayEskiyiKapatirGeriAlmaYenidenAcar() throws {
        let k = try Self.kur()
        let eski = try k.store.addObservation(brandId: k.a, statement: "Teslim tarihi Kasım sonu.", evidenceSourceIds: [k.aKaynak1])
        let p = try Self.oner(k, "Teslim Aralık ortasına kaydı.", [k.aKaynak2], yerine: eski.id)
        // Öneri bekledikçe eski gözlem dokunulmadan geçerli kalır.
        #expect(try k.store.observations(brandId: k.a) == [eski])
        let yeniId = try #require(try k.store.applyProposal(p.id).resultEntityId)
        let tum = try k.store.observations(brandId: k.a, includeInvalidated: true)
        let kapali = try #require(tum.first { $0.id == eski.id })
        #expect(tum.count == 2)
        #expect(kapali.status == .superseded && kapali.supersededBy == yeniId && kapali.invalidatedAt != nil)
        #expect(kapali.statement == eski.statement)
        #expect(try k.store.observations(brandId: k.a).map(\.id) == [yeniId])

        try k.store.revertProposal(p.id)
        // Yeni gözlem silinir; eskisi aynı kimlik ve içerikle yeniden açılır.
        #expect(try k.store.observations(brandId: k.a, includeInvalidated: true) == [eski])
        let iz = try k.store.auditTrail(entity: "observation", entityId: eski.id).map(\.action)
        #expect(iz.contains("supersede") && iz.contains("revertAI"))
    }

    @Test func kullaniciSonradanDegistirdiyseGeriAlmaReddedilir() throws {
        let k = try Self.kur()
        let p = try Self.oner(k, "Teslim tarihi Kasım sonu.", [k.aKaynak1])
        let rid = try #require(try k.store.applyProposal(p.id).resultEntityId)
        let kullanicinki = try k.store.addSupersedingObservation(replacing: rid, brandId: k.a, statement: "Teslim Aralık ortası.",
                                                                 evidenceSourceIds: [k.aKaynak2])
        #expect(throws: MarkaError.self) { try k.store.revertProposal(p.id) }
        #expect(try k.store.proposals(brandId: k.a).first?.status == .applied)
        #expect(try k.store.observations(brandId: k.a).map(\.id) == [kullanicinki.id])
        #expect(try k.store.observations(brandId: k.a, includeInvalidated: true).count == 2)
    }

    @Test func baskaMarkaninYaDaKapatilmisGozleminYerineGecilemez() throws {
        let k = try Self.kur()
        let bKaynak = k.bKaynak
        let bGozlem = try k.store.addObservation(brandId: k.b, statement: "Kuzey gözlemi.", evidenceSourceIds: [bKaynak])
        let r = k.arac.run(name: "gozlem_oner", input: ["gozlem": "Yeni.", "kaynaklar": [.string(k.aKaynak1)],
                                                         "yerine_gectigi_id": .string(bGozlem.id)])
        #expect(r.isError && !r.text.contains("Kuzey gözlemi."))
        let eski = try k.store.addObservation(brandId: k.a, statement: "Eski.", evidenceSourceIds: [k.aKaynak1])
        _ = try k.store.addSupersedingObservation(replacing: eski.id, brandId: k.a, statement: "Daha yeni.", evidenceSourceIds: [k.aKaynak2])
        #expect(k.arac.run(name: "gozlem_oner", input: ["gozlem": "En yeni.", "kaynaklar": [.string(k.aKaynak1)],
                                                         "yerine_gectigi_id": .string(eski.id)]).isError)
        #expect(try k.store.proposals(brandId: k.a).isEmpty)
        #expect(try k.store.observations(brandId: k.b) == [bGozlem])
    }

    @Test func eskiGozlemOnaydanOnceKapanirsaOnayReddedilirVeHicbirSeyYazilmaz() throws {
        let k = try Self.kur()
        let eski = try k.store.addObservation(brandId: k.a, statement: "Teslim tarihi Kasım sonu.", evidenceSourceIds: [k.aKaynak1])
        let p = try Self.oner(k, "Teslim Aralık ortası.", [k.aKaynak2], yerine: eski.id)
        _ = try k.store.addSupersedingObservation(replacing: eski.id, brandId: k.a, statement: "Kullanıcı düzeltti.", evidenceSourceIds: [k.aKaynak2])
        let once = try k.store.observations(brandId: k.a, includeInvalidated: true)
        #expect(throws: MarkaError.self) { try k.store.applyProposal(p.id) }
        #expect(try k.store.observations(brandId: k.a, includeInvalidated: true) == once)
        #expect(try k.store.proposals(brandId: k.a).first { $0.id == p.id }?.status == .pending)
    }

    @Test func aracTumMarkalarKapsamindaSunulmazVeOneriYapamaz() throws {
        let k = try Self.kur()
        #expect(ToolCatalog.tools(for: .brand(k.a), store: k.store).contains { $0.name == "gozlem_oner" })
        #expect(!ToolCatalog.tools(for: .allBrands, store: k.store).contains { $0.name == "gozlem_oner" })
        let r = ToolExecutor(store: k.store, scope: .allBrands, sessionId: nil)
            .run(name: "gozlem_oner", input: ["gozlem": "x.", "kaynaklar": [.string(k.aKaynak1)]])
        #expect(r.isError)
        #expect(try k.store.proposals(brandId: k.a).isEmpty)
    }
}
