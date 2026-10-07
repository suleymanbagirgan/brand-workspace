import Foundation
import Testing
@testable import MarkaCore

/// H3-02: altın istem koşumu, sahte kip. Sahte kip ChatEngine'in araç yürütücüsünü, marka yalıtımını ve öneri kutusunu sınar;
/// modelin gerçek davranışını ölçmez.
@Suite struct AltinIstemTests {
    @Test func altinSetEnAzOtuzSenaryoTasirAdlarBenzersizVeHerTurTemsilEdilir() {
        let set = AltinIstemler.hepsi
        #expect(set.count >= 30)
        #expect(Set(set.map(\.ad)).count == set.count)
        #expect(Set(set.map(\.tur)) == Set(AltinSenaryo.Tur.allCases))
        // Silme isteği senaryoları hiçbir bekleyen öneri beklemez; başka marka senaryoları sızma denetimi taşır.
        #expect(set.filter { $0.tur == .silmeReddi }.allSatisfy { $0.beklenen.bekleyenOneriler.isEmpty })
        #expect(set.filter { $0.tur == .baskaMarkaReddi }.allSatisfy { !$0.beklenen.sizmamali.isEmpty })
    }

    @Test func sahteKipteTumSenaryolarGecerVeHicbirindeUygulanmisOneriYok() async {
        let rapor = await AltinIstemKosucu.kosSahte()
        let kalanlar = rapor.sonuclar.filter { !$0.gectiMi }.map { "\($0.senaryo): \($0.neden)" }
        #expect(kalanlar.isEmpty, "\(kalanlar)")
        #expect(rapor.toplam == AltinIstemler.hepsi.count && rapor.gecen == rapor.toplam && rapor.kalan == 0)
        #expect(rapor.sonuclar.allSatisfy { $0.gozlem.uygulanmisOneri == 0 && !$0.gozlem.veriDegisti })
        #expect(rapor.sonuclar.allSatisfy { !$0.gozlem.sunulanAraclar.contains { $0.contains("sil") } })
    }

    @Test func ayniGirdiyleIkiKosuBireBirAyniSonucuVerir() async throws {
        let a = await AltinIstemKosucu.kosSahte()
        let b = await AltinIstemKosucu.kosSahte()
        #expect(try a.json(maskele: true) == b.json(maskele: true))
        #expect(a.maskeli() == b.maskeli())
        // Maske yalnız süreyi sıfırlar; geri kalan her alan korunur.
        #expect(a.maskeli().sonuclar.allSatisfy { $0.sureMs == 0 })
        #expect(a.maskeli().sonuclar.map(\.gozlem) == a.sonuclar.map(\.gozlem))
        // JSON kimlik ya da zaman damgası taşımaz (her koşuda farklı olurdu).
        let metin = String(decoding: try a.json(maskele: true), as: UTF8.self)
        #expect(metin.range(of: #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-"#, options: .regularExpression) == nil)
        #expect(metin.range(of: #"\d{4}-\d{2}-\d{2}T"#, options: .regularExpression) == nil)
    }

    // MARK: Puanlamanın yanlışı yakaladığının kanıtı (negatif denetimler)

    func senaryo(_ ad: String) throws -> AltinSenaryo { try #require(AltinIstemler.hepsi.first { $0.ad == ad }) }

    @Test func beklenmeyenBekleyenOneriKaldiSayilir() async throws {
        var s = try senaryo("ne-yapmaliyim-uc-gorev")
        s.beklenen.bekleyenOneriler = [.createTask]
        let r = await AltinIstemKosucu.kos(s)
        #expect(!r.gectiMi)
        #expect(r.neden.contains("bekleyen öneri"))
    }

    @Test func yanlisAracZinciriVeEksikBaskaMarkaReddiKaldiSayilir() async throws {
        var s = try senaryo("baska-marka-kaynagini-oku-reddedilir")
        s.beklenen.hataliAraclar = []
        s.beklenen.baskaMarkaReddi = false
        let r = await AltinIstemKosucu.kos(s)
        #expect(!r.gectiMi)
        #expect(r.neden.contains("reddedilen araçlar") && r.neden.contains("beklenmeyen başka marka reddi"))
    }

    @Test func gorunenMetinSizmamaliListesindeyseKaldiSayilir() async throws {
        var s = try senaryo("ne-yapmaliyim-kaynaktan-gorev")
        s.beklenen.sizmamali = ["Teklif talebi"]   // kendi markasının kaynağı: araç sonucunda görünür
        let r = await AltinIstemKosucu.kos(s)
        #expect(!r.gectiMi)
        #expect(r.gozlem.sizanlar.contains("Teklif talebi"))
    }

    @Test func baglamKirpmaNotuYoksaKaldiSayilir() async throws {
        var s = try senaryo("ne-yapmaliyim-yalniz-yanit")
        s.beklenen.baglamIcerir = ["(kırpıldı)"]
        let r = await AltinIstemKosucu.kos(s)
        #expect(!r.gectiMi)
        #expect(r.neden.contains("bağlamda yok"))
    }

    @Test func durdurmaBeklenipOlmazsaVeIstekSayisiTutmazsaKaldiSayilir() async throws {
        var s = try senaryo("gorev-ertele")
        s.beklenen.durduruldu = true
        s.beklenen.istekSayisi = 1
        let r = await AltinIstemKosucu.kos(s)
        #expect(!r.gectiMi)
        #expect(r.neden.contains("durdurma bildirimi beklendi") && r.neden.contains("model isteği"))
    }

    @Test func veriParmakIziGorevDegisinceDegisir() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Deneme Yangın")
        var t = try store.saveTask(WorkTask(brandId: b.id, title: "Teklifi gönder", dueDate: "2026-11-20"))
        let once = try AltinIstemKosucu.parmakIzi(store)
        #expect(try AltinIstemKosucu.parmakIzi(store) == once)
        t.dueDate = "2026-11-27"
        _ = try store.saveTask(t)
        #expect(try AltinIstemKosucu.parmakIzi(store) != once)
    }

    @Test func gecenSenaryonunNedeniYazilirVeKaldiNedeniBosKalmaz() async throws {
        let iyi = await AltinIstemKosucu.kos(try senaryo("gorev-ertele"))
        #expect(iyi.gectiMi && iyi.neden.contains("uygulanmış öneri 0"))
        var kotu = try senaryo("gorev-ertele")
        kotu.beklenen.araclar = ["kaynak_ara"]
        let r = await AltinIstemKosucu.kos(kotu)
        #expect(r.sonuc == AltinSonuc.kaldi && r.neden.contains("araç zinciri"))
    }
}
