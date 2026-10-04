import Foundation
import Testing
@testable import MarkaCore

@Suite struct FinansTests {
    @Test func turkceTutarYazimiKurusaCevrilir() {
        #expect(Money.parseMinor("45.000") == 4_500_000)
        #expect(Money.parseMinor("45000") == 4_500_000)
        #expect(Money.parseMinor("45.000,50") == 4_500_050)
        #expect(Money.parseMinor("12,5") == 1_250)
        #expect(Money.parseMinor("₺ 1.250") == 125_000)
        #expect(Money.parseMinor("1250 TL") == 125_000)
        #expect(Money.parseMinor("abc") == nil)
        #expect(Money.parseMinor("-5") == nil)
        #expect(Money.parseMinor("") == nil)
        #expect(Money.parseMinor("1,234,5") == nil)
    }

    @Test func tutarBicimlenir() {
        #expect(Money.format(minor: 4_500_000).contains("45.000"))
        #expect(Money.format(minor: 4_500_000).contains("₺"))
        #expect(Money.format(minor: 1_250).contains("12,50"))
    }

    @Test func kayitYazilirGuncellenirVeSilinirDenetimIle() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Deneme Yangın")
        var p = try store.saveFinanceEntry(FinanceEntry(brandId: b.id, kind: .payment, title: "Ekim danışmanlık hizmeti", amountMinor: 4_500_000, date: "2026-10-05"))
        #expect(p.status == .planned)
        p.status = .collected
        _ = try store.saveFinanceEntry(p)
        #expect(try store.financeEntries(brandId: b.id).first?.status == .collected)
        let trail = try store.auditTrail(entity: "financeEntry", entityId: p.id)
        #expect(trail.map(\.action).sorted() == ["create", "update"])
        try store.deleteFinanceEntry(p.id)
        #expect(try store.financeEntries(brandId: b.id).isEmpty)
        #expect(try store.auditTrail(entity: "financeEntry", entityId: p.id).count == 3)
    }

    @Test func butceSatiriDurumTasimazVeDogrulamaCalisir() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Deneme Yangın")
        let e = try store.saveFinanceEntry(FinanceEntry(brandId: b.id, kind: .budget, title: "Fotoğraf çekimi", amountMinor: 1_200_000, status: .collected))
        #expect(e.status == nil)
        #expect(throws: (any Error).self) { try store.saveFinanceEntry(FinanceEntry(brandId: b.id, kind: .budget, title: "  ")) }
        #expect(throws: (any Error).self) { try store.saveFinanceEntry(FinanceEntry(brandId: b.id, kind: .budget, title: "x", amountMinor: -1)) }
        #expect(throws: (any Error).self) { try store.saveFinanceEntry(FinanceEntry(brandId: b.id, kind: .payment, title: "x", date: "5 Ekim")) }
        #expect(throws: (any Error).self) { try store.saveFinanceEntry(FinanceEntry(brandId: "yok", kind: .budget, title: "x")) }
    }

    @Test func finansKayitlariMarkalarArasiKarismaz() throws {
        let store = try makeStore()
        let a = try store.createBrand(name: "Deneme Yangın")
        let b = try store.createBrand(name: "Kuzey Lojistik")
        _ = try store.saveFinanceEntry(FinanceEntry(brandId: a.id, kind: .payment, title: "A ödemesi", amountMinor: 100, date: "2026-10-05"))
        #expect(try store.financeEntries(brandId: b.id).isEmpty)
        // Başka markanın kaydını o markaya taşımak reddedilir.
        var moved = try #require(try store.financeEntries(brandId: a.id).first)
        moved.brandId = b.id
        #expect(throws: (any Error).self) { try store.saveFinanceEntry(moved) }
        #expect(try store.financeEntries(brandId: b.id).isEmpty)
    }
}
