import Foundation
import Testing
@testable import MarkaCore

/// 0.2.1 U9: marka terminali oturumu gizleme, marka değiştirme, yer değiştirme ve yalıtım değişikliğinde yaşar; yalnız kabuk
/// bitince, marka arşivlenince ya da uygulama kapanınca biter.
@MainActor
@Suite struct TerminalOturumTests {
    /// Görünüm + süreç yerine sahte oturum (kimliğiyle karşılaştırılır).
    final class Sahte {}

    @Test func gizlemeMarkaDegistirmeVeYerDegistirmeOturumuBitirmezAyniOturumDoner() {
        let cache = TerminalSessionCache<Sahte>()
        let a1 = cache.session(for: "A", isolated: true) { Sahte() }
        let b1 = cache.session(for: "B", isolated: true) { Sahte() }
        #expect(a1 !== b1, "her markanın kendi oturumu")
        for olay in [TerminalEvent.hidden, .selectionChanged, .moved, .isolationChanged] {
            #expect(cache.handle(olay).isEmpty, "\(olay) hiçbir oturumu sonlandırmaz")
        }
        // Geri gelince aynı oturum (yeniden kurulmaz).
        #expect(cache.session(for: "A", isolated: true) { Sahte() } === a1)
        #expect(cache.session(for: "B", isolated: false) { Sahte() } === b1)
        #expect(cache.runningCount == 2)
    }

    @Test func kabuktanCikincaGorunumKalirSonrakiGosterimdeYenisiKurulur() {
        let cache = TerminalSessionCache<Sahte>()
        let a1 = cache.session(for: "A", isolated: true) { Sahte() }
        #expect(cache.handle(.shellExited(brandId: "A")).isEmpty, "süreç zaten bitti; sonlandırılacak bir şey yok")
        #expect(cache.info("A")?.running == false)
        #expect(cache.existing("A") === a1, "son çıktı okunabilsin diye görünüm yerinde")
        #expect(cache.runningCount == 0)
        let a2 = cache.session(for: "A", isolated: true) { Sahte() }
        #expect(a2 !== a1)
        #expect(cache.info("A")?.running == true)
    }

    @Test func markaArsivlenincePrunelaYalnizOnunOturumuSonlanir() {
        let cache = TerminalSessionCache<Sahte>()
        let a = cache.session(for: "A", isolated: true) { Sahte() }
        let b = cache.session(for: "B", isolated: true) { Sahte() }
        let biten = cache.prune(keeping: ["B"])
        #expect(biten.count == 1 && biten.first === a)
        #expect(cache.existing("A") == nil)
        #expect(cache.existing("B") === b)
        #expect(cache.handle(.brandRemoved(brandId: "yok")).isEmpty)
    }

    @Test func kapanistaCalisanVarsaTekSoruYoksaSoruYok() {
        let cache = TerminalSessionCache<Sahte>()
        #expect(cache.quitQuestionCount == nil)
        _ = cache.session(for: "A", isolated: true) { Sahte() }
        _ = cache.session(for: "B", isolated: true) { Sahte() }
        _ = cache.session(for: "C", isolated: true) { Sahte() }
        cache.handle(.shellExited(brandId: "C"))
        #expect(cache.quitQuestionCount == 2, "yalnız süren kabuklar sayılır")
        let biten = cache.handle(.appQuit)
        #expect(biten.count == 2)
        #expect(cache.quitQuestionCount == nil)
    }

    @Test func yalitimDegisinceAcikOturumEskiProfildeKalirYeniOturumYeniProfille() {
        let cache = TerminalSessionCache<Sahte>()
        let a = cache.session(for: "A", isolated: true) { Sahte() }
        cache.handle(.isolationChanged)
        #expect(cache.isolationDiffers("A", current: false), "başlıkta tek satır: oturum eski ayarla sürüyor")
        #expect(!cache.isolationDiffers("A", current: true))
        #expect(cache.session(for: "A", isolated: false) { Sahte() } === a, "açık oturum yeniden başlamaz")
        #expect(cache.info("A")?.isolated == true)
        cache.handle(.shellExited(brandId: "A"))
        #expect(!cache.isolationDiffers("A", current: false), "biten oturum için satır yok")
        _ = cache.session(for: "A", isolated: false) { Sahte() }
        #expect(cache.info("A")?.isolated == false, "yeni oturum yeni ayarla")
    }
}
