import Testing
@testable import MarkaCore

/// H2-02 (U-11, U-34, T-12): anahtar yokken basılan "Yapay zekâya sor" istemi sonra kendiliğinden gönderilmez,
/// başka markaya gitmez; asistan paneli sağlayıcı yokken kapalı başlar.
@Suite struct BekleyenIstemTests {
    /// Panelin davranışını taklit eder: paneldeki marka için yuvadan alınanı "gönderir" (gönderim sayacı ve hedef marka).
    private struct SahteGonderici {
        var gonderilen: [PendingPrompt] = []
        mutating func paneliAc(_ yuva: inout PendingPromptSlot, marka: String, saglayiciHazir: Bool) {
            if let p = yuva.take(brandId: marka, providerReady: saglayiciHazir) { gonderilen.append(p) }
        }
    }

    @Test func saglayiciYokkenIstemBekletilmezVeHicGonderilmez() {
        var yuva = PendingPromptSlot()
        var g = SahteGonderici()
        let bekletildi = yuva.request("Ne yapmalıyım?", brandId: "kuzey", providerReady: false)
        #expect(bekletildi == false)
        #expect(yuva.pending == nil)
        // Ertesi gün anahtar eklendi, aynı marka açıldı: hiçbir şey gönderilmez.
        g.paneliAc(&yuva, marka: "kuzey", saglayiciHazir: true)
        #expect(g.gonderilen.isEmpty)
    }

    @Test func saglayiciYokkenTuketmeDenemesiIstemiGondermedenSiler() {
        var yuva = PendingPromptSlot()
        var g = SahteGonderici()
        yuva.request("Ne yapmalıyım?", brandId: "kuzey", providerReady: true)
        // Gönderilmeden önce anahtar silindi: panel sağlayıcısız açıldı.
        g.paneliAc(&yuva, marka: "kuzey", saglayiciHazir: false)
        #expect(yuva.pending == nil)
        // Anahtar geri geldi: eski istem kendiliğinden gitmez.
        g.paneliAc(&yuva, marka: "kuzey", saglayiciHazir: true)
        #expect(g.gonderilen.isEmpty)
    }

    @Test func markaDegisinceBekleyenIstemGonderilmez() {
        var yuva = PendingPromptSlot()
        var g = SahteGonderici()
        yuva.request("Ne yapmalıyım?", brandId: "kuzey", providerReady: true)
        yuva.brandChanged(to: "deneme-yangin")
        #expect(yuva.pending == nil)
        g.paneliAc(&yuva, marka: "deneme-yangin", saglayiciHazir: true)
        g.paneliAc(&yuva, marka: "kuzey", saglayiciHazir: true)
        #expect(g.gonderilen.count == 0)
    }

    @Test func baskaMarkaIstegiBaskaMarkayaGitmez() {
        var yuva = PendingPromptSlot()
        var g = SahteGonderici()
        yuva.request("Kuzey için özet", brandId: "kuzey", providerReady: true)
        // Marka değişimi bildirilmeden başka markanın paneli tüketmeye çalışırsa: gönderilmez ve silinir.
        g.paneliAc(&yuva, marka: "ornek-kafe", saglayiciHazir: true)
        #expect(g.gonderilen.isEmpty)
        #expect(yuva.pending == nil)
        // Sonradan asıl marka açılınca da kendiliğinden gitmez.
        g.paneliAc(&yuva, marka: "kuzey", saglayiciHazir: true)
        #expect(g.gonderilen.isEmpty)
    }

    @Test func saglayiciHazirVeAyniMarkadaIstemBirKezTuketilir() {
        var yuva = PendingPromptSlot()
        var g = SahteGonderici()
        let bekletildi = yuva.request("  Ne yapmalıyım?  ", brandId: "kuzey", providerReady: true)
        #expect(bekletildi)
        yuva.brandChanged(to: "kuzey")   // aynı marka: silinmez
        g.paneliAc(&yuva, marka: "kuzey", saglayiciHazir: true)
        g.paneliAc(&yuva, marka: "kuzey", saglayiciHazir: true)
        #expect(g.gonderilen == [PendingPrompt(brandId: "kuzey", text: "Ne yapmalıyım?")])
    }

    @Test func saglayiciYokkenYeniIstekEskiBekleyeniDeSiler() {
        var yuva = PendingPromptSlot()
        yuva.request("Eski", brandId: "kuzey", providerReady: true)
        yuva.request("Yeni", brandId: "kuzey", providerReady: false)
        #expect(yuva.pending == nil)
        yuva.request("Bir", brandId: "kuzey", providerReady: true)
        yuva.providerLost()
        #expect(yuva.pending == nil)
        let bosBekletildi = yuva.request("   ", brandId: "kuzey", providerReady: true)
        #expect(bosBekletildi == false)
    }

    @Test func asistanPaneliSaglayiciYokkenKapaliBaslarBilincliSecimHatirlanir() {
        #expect(AssistantPanelDefault.isOpen(savedChoice: nil, providerConnected: false) == false)
        #expect(AssistantPanelDefault.isOpen(savedChoice: nil, providerConnected: true) == true)
        #expect(AssistantPanelDefault.isOpen(savedChoice: "1", providerConnected: false) == true)
        #expect(AssistantPanelDefault.isOpen(savedChoice: "0", providerConnected: true) == false)
    }
}
