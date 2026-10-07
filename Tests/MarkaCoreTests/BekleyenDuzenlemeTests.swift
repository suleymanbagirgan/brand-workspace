import Foundation
import Testing
@testable import MarkaCore

@MainActor
struct BekleyenDuzenlemeTests {
    @Test func kapanistaBekleyenDuzenlemeKaydedilir() {
        let defter = PendingEdits()
        var kaydedilen: [String] = []
        defter.register(UUID()) { kaydedilen.append("not") }
        defter.register(UUID()) { kaydedilen.append("başlık") }
        #expect(defter.count == 2)
        #expect(defter.flushAll() == 2)   // willTerminate ≥ 1 kaydet çağrısı
        #expect(kaydedilen == ["not", "başlık"])
        #expect(defter.count == 0)
    }

    @Test func kendiKaydedenAlanKapanistaIkinciKezKaydetmez() {
        let defter = PendingEdits()
        let id = UUID()
        var sayi = 0
        defter.register(id) { sayi += 1 }
        defter.clear(id)   // alan Enter/odak kaybıyla kendi kaydetti
        #expect(defter.flushAll() == 0)
        #expect(sayi == 0)
    }

    @Test func ayniKimlikTekGirisKalirSonKapanisCalisir() {
        let defter = PendingEdits()
        let id = UUID()
        var son = ""
        defter.register(id) { son = "ilk" }
        defter.register(id) { son = "son" }
        #expect(defter.count == 1)
        #expect(defter.flushAll() == 1)
        #expect(son == "son")
    }

    @Test func tekAlanFlushYalnizOnuKaydeder() {
        let defter = PendingEdits()
        let a = UUID(), b = UUID()
        var cagrilan: [String] = []
        defter.register(a) { cagrilan.append("a") }
        defter.register(b) { cagrilan.append("b") }
        #expect(defter.flush(a))
        #expect(!defter.flush(a))
        #expect(cagrilan == ["a"])
        #expect(defter.count == 1)
    }
}
