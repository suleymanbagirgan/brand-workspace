import Foundation
import Testing
@testable import MarkaCore

/// U-07 (H1-04b): satır içi düzenleyiciler (profil metni, sektör, şirket formu) kapanışta kayıt defteri üzerinden kaydedilir.
@MainActor
struct BekleyenDuzenlemeKapanisTests {
    @Test func vazgecEdilenTaslakKapanistaKaydedilmez() {
        let defter = PendingEdits()
        let id = UUID()
        var kaydedilen = 0
        defter.register(id) { kaydedilen += 1 }
        defter.clear(id)   // Vazgeç / Esc
        #expect(defter.flushAll() == 0)
        #expect(kaydedilen == 0)
    }

    @Test func ayniKimlikIkinciKayitOncekiniEzerVeGuncelMetniKaydeder() {
        let defter = PendingEdits()
        let id = UUID()
        var taslak = "a"
        var kaydedilen: [String] = []
        defter.register(id) { kaydedilen.append("eski") }
        taslak = "abc"
        defter.register(id) { kaydedilen.append(taslak) }   // her değişimde yeniden kayıt
        defter.flushAll()
        #expect(kaydedilen == ["abc"])
    }

    @Test func kaydedilenAlanKapanistaTekrarKaydedilmez() {
        let defter = PendingEdits()
        let id = UUID()
        var sayi = 0
        let kaydet = { defter.clear(id); sayi += 1 }   // alanın kendi kaydı kaydı siler
        defter.register(id, save: kaydet)
        kaydet()
        defter.flushAll()
        #expect(sayi == 1)
    }

    @Test func birdenCokBekleyenAlanFlushAllDaHepsiKaydedilir() {
        let defter = PendingEdits()
        var kaydedilen: [String] = []
        for ad in ["profil", "sektör", "şirket"] { defter.register(UUID()) { kaydedilen.append(ad) } }
        #expect(defter.flushAll() == 3)
        #expect(kaydedilen == ["profil", "sektör", "şirket"])
        #expect(defter.count == 0)
    }

    @Test func birAlaninKaydiBasarisizOlsaDigerleriKaydedilir() {
        // Kaydet kapanışları hata fırlatmaz: hatayı kendi içinde yakalar (app.perform); defter yine de sürer.
        let defter = PendingEdits()
        var kaydedilen: [String] = []
        defter.register(UUID()) { kaydedilen.append("ilk") }
        defter.register(UUID()) { enum H: Error { case x }; _ = try? { throw H.x }() as Void }   // hatalı kayıt
        defter.register(UUID()) { kaydedilen.append("son") }
        #expect(defter.flushAll() == 3)
        #expect(kaydedilen == ["ilk", "son"])
    }

    @Test func kaydetSirasindaBaskaAlaniSilenKapanisDefteriBozmaz() {
        let defter = PendingEdits()
        let a = UUID(), b = UUID()
        var kaydedilen: [String] = []
        defter.register(a) { defter.clear(b); kaydedilen.append("a") }
        defter.register(b) { kaydedilen.append("b") }
        #expect(defter.flushAll() == 1)
        #expect(kaydedilen == ["a"])
    }
}
