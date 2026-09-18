import Foundation
import Testing
@testable import MarkaCore

/// D8: renk kontrastı WCAG AA (metin ≥ 4.5:1).
@Suite struct KontrastTests {
    @Test func wcagFormuluBilinenDegerleriVerir() {
        let white = Palette.RGB(0xFFFFFF), black = Palette.RGB(0x000000)
        #expect(abs(Palette.contrast(white, black) - 21) < 0.001)
        #expect(abs(Palette.contrast(white, white) - 1) < 0.001)
        // Eski açık görünüm vurgusu (#D15C1A) beyaz üzerinde AA altındaydı; formül bunu yakalamalı.
        #expect(Palette.contrast(Palette.RGB(0xD15C1A), white) < 4.5)
        // Eski koyu görünüm dolgulu düğmesi (#F5853D) beyaz yazıyla ~2.5:1.
        #expect(Palette.contrast(Palette.RGB(0xF5853D), white) < 3)
    }

    @Test func metinRenkleriHerYuzeydeVeSeciliSatirZemindeAAyiGecer() {
        let black = Palette.RGB(0x000000), white = Palette.RGB(0xFFFFFF)
        for (name, pair) in Palette.textColors {
            for (mode, color, surfaces, ink) in [("açık", pair.light, Palette.lightSurfaces, black), ("koyu", pair.dark, Palette.darkSurfaces, white)] {
                for surface in surfaces {
                    let plain = Palette.contrast(color, surface)
                    let selected = Palette.contrast(color, ink.over(surface, alpha: Palette.selectionAlpha))
                    #expect(plain >= 4.5, "\(name) \(mode) \(color) / \(surface): \(plain)")
                    #expect(selected >= 4.5, "\(name) \(mode) seçili satır \(color) / \(surface): \(selected)")
                }
            }
        }
    }

    @Test func dolguluDugmedeBeyazYaziAAyiGecer() {
        let white = Palette.RGB(0xFFFFFF)
        for color in [Palette.accentFill.light, Palette.accentFill.dark] {
            #expect(Palette.contrast(white, color) >= 4.5, "beyaz / \(color)")
        }
        // Dolgu, koyu içerik zemininde metin dışı öğe eşiğini (≥ 3:1) geçer. Koyu pencere zemininde (#323232) hem beyaz
        // yazıya ≥ 4.5 hem zemine ≥ 3 aynı anda sağlanamaz (parlaklık aralığı boş); orada beyaz yazı önceliklidir.
        #expect(Palette.contrast(Palette.accentFill.dark, Palette.darkSurfaces[0]) >= 3)
    }
}

/// D5: rapor özetinde sağlayıcı seçimi ve doğru sebep.
@Suite struct OzetSaglayiciTests {
    @Test func anahtarYokkenSebepIzinDegilAnahtarEksikligidir() {
        let c = SummaryProviderChoice.choose(allowsAnthropic: true, hasAnthropicKey: false, allowsCodex: false)
        #expect(c == .missingAnthropicKey)
        #expect(!c.isAvailable)
        #expect(c.unavailableReason == "Claude API anahtarı eklenmemiş.")
    }

    @Test func izinVeAnahtarDurumunaGoreSaglayiciSecilir() {
        #expect(SummaryProviderChoice.choose(allowsAnthropic: true, hasAnthropicKey: true, allowsCodex: true) == .anthropic)
        // Anahtar yoksa ama Codex'e izin varsa Codex kullanılır.
        #expect(SummaryProviderChoice.choose(allowsAnthropic: true, hasAnthropicKey: false, allowsCodex: true) == .codex)
        #expect(SummaryProviderChoice.choose(allowsAnthropic: false, hasAnthropicKey: true, allowsCodex: true) == .codex)
        let none = SummaryProviderChoice.choose(allowsAnthropic: false, hasAnthropicKey: true, allowsCodex: false)
        #expect(none == .notAllowed)
        #expect(none.unavailableReason?.contains("izin verilmemiş") == true)
        #expect(SummaryProviderChoice.anthropic.unavailableReason == nil && SummaryProviderChoice.codex.isAvailable)
    }
}
