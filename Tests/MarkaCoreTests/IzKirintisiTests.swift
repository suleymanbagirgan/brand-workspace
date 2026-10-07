import Foundation
import Testing
@testable import MarkaCore

/// E-05: yerel kara kutu. İz kırıntısı içeriksizdir, yalnız bellekte durur ve Tanı raporunda "son_adimlar" olarak görünür.
@Suite struct IzKirintisiTests {
    static let marka = "GizliMarkaXYZ"
    static let govde = "sirMetin123"
    static let eposta = "gizli.kisi@ornek-sirket.com"
    static var evYolu: String { NSHomeDirectory() + "/Belgeler/\(marka) sözleşme \(govde).pdf" }
    static let anahtar = "sk-ant-SAHTE-DENEME-0000"

    func bosAnlik() -> DiagnosticSnapshot {
        DiagnosticSnapshot.collect(store: nil, log: DiagnosticsLog(url: nil), anthropicKeyPresent: false, codex: .bilinmiyor)
    }

    @Test func tamponEllideSinirliEnEskiAtilir() {
        let iz = Breadcrumbs()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        for i in 0..<75 { iz.record(screen: "ekran-\(i)", action: "ac", at: t0.addingTimeInterval(Double(i))) }
        let kayitlar = iz.entries()
        #expect(Breadcrumbs.capacity == 50)
        #expect(kayitlar.count == 50)
        #expect(kayitlar.first?.fields[.ekran] == "ekran-25")
        #expect(kayitlar.last?.fields[.ekran] == "ekran-74")
    }

    @Test func izinliAnahtarDisindakiAlanlarAtilir() {
        let k = Breadcrumb(raw: [
            "ekran": "sohbet", "eylem": "gonder", "saglayici": "anthropic", "sure_ms": "820",
            "mesaj": Self.govde, "marka": Self.marka, "yol": Self.evYolu, "anahtar": Self.anahtar, "EKRAN": "sohbet",
        ])
        #expect(Set(k.fields.keys) == Set(BreadcrumbField.allCases))
        #expect(k.fields.count == 4)
        #expect(k.line.hasSuffix("ekran=sohbet eylem=gonder saglayici=anthropic sure_ms=820"))
        for gizli in [Self.govde, Self.marka, Self.anahtar, "mesaj", "yol", "anahtar"] {
            #expect(!k.line.contains(gizli), "Kırıntıda izinsiz alan var: \(gizli)")
        }
    }

    /// İzinli alanda bile içerik taşıyan değer süzülmez, tümden atılır.
    @Test func icerikTasiyanDegerIzinliAlandaBileYazilmaz() {
        for kotu in [Self.marka, Self.marka.lowercased() + " ", Self.evYolu, Self.eposta, "toplantı", "a b", "../x", "", String(repeating: "a", count: 41), "1ekran"] {
            #expect(Breadcrumb(raw: ["ekran": kotu]).fields.isEmpty, "Geçmemeliydi: \(kotu)")
            #expect(Breadcrumb(raw: ["eylem": kotu]).fields.isEmpty, "Geçmemeliydi: \(kotu)")
        }
        for kotu in ["openai", Self.marka, "Anthropic", ""] {
            #expect(Breadcrumb(raw: ["saglayici": kotu]).fields.isEmpty)
        }
        for kotu in ["-1", "12a", "1e3", " 5", "05", "9999999999", Self.govde] {
            #expect(Breadcrumb(raw: ["sure_ms": kotu]).fields.isEmpty, "Süre geçmemeliydi: \(kotu)")
        }
        for kind in AIProviderKind.allCases {
            #expect(Breadcrumb(raw: ["saglayici": kind.rawValue]).fields[.saglayici] == kind.rawValue)
        }
        #expect(Breadcrumb(raw: ["ekran": "ayarlar.tani", "sure_ms": "0"]).fields.count == 2)
    }

    @Test func hicGecerliAlaniKalmayanKirintiKaydedilmez() {
        let iz = Breadcrumbs()
        iz.record(["mesaj": Self.govde, "ekran": Self.evYolu])
        iz.record(screen: Self.marka, action: Self.eposta)
        #expect(iz.entries().isEmpty)
        iz.record(screen: Self.marka, action: "gonder")
        #expect(iz.entries().count == 1)
        #expect(iz.entries().first?.fields == [.eylem: "gonder"])
    }

    /// Kanıt (G2, `GizlilikTests` deseni): ayırt edici marka adı ve içerik kırıntıya her yoldan verilse de raporda 0 kez geçer.
    @Test func taniRaporundaMarkaAdiVeIcerikSifirKezGecer() {
        let iz = Breadcrumbs()
        let gomulu = "\(Self.marka) \(Self.govde) \(Self.eposta) \(Self.evYolu) \(Self.anahtar)"
        iz.record(screen: "sohbet", action: "gonder", provider: .anthropic, durationMs: 820)
        iz.record(["ekran": gomulu, "eylem": "onayla", "metin": gomulu, "saglayici": gomulu, "sure_ms": gomulu])
        iz.record(["ekran": Self.marka, "eylem": Self.govde, Self.marka: "sohbet"])
        iz.record(screen: "rapor", action: gomulu, provider: .codex)

        let metin = DiagnosticReport.render(bosAnlik(), now: Date(), breadcrumbs: iz.entries())
        for gizli in [Self.marka, Self.govde, Self.eposta, Self.anahtar, "@", NSHomeDirectory(), "/Users/", "Belgeler", NSUserName(), "sözleşme", "metin="] {
            #expect(metin.components(separatedBy: gizli).count - 1 == 0, "Tanı raporunda içerik var: \(gizli)")
        }
        #expect(metin.contains("son_adimlar (3, yeniden eskiye):"))
        #expect(metin.contains("ekran=sohbet eylem=gonder saglayici=anthropic sure_ms=820"))
        #expect(metin.contains("eylem=onayla"))
        #expect(metin.contains("ekran=rapor saglayici=codex"))
    }

    @Test func raporSonAdimlariYenidenEskiyeVeEnCokElliYazar() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let kirintilar = (0..<60).map { Breadcrumb(at: t0.addingTimeInterval(Double($0)), screen: "e\($0)", action: "ac") }
        let metin = DiagnosticReport.render(bosAnlik(), now: t0, breadcrumbs: kirintilar)
        #expect(metin.contains("son_adimlar (50, yeniden eskiye):"))
        #expect(metin.contains("ekran=e59 ") && metin.contains("ekran=e10 ") && !metin.contains("ekran=e9 "))
        #expect(metin.range(of: "ekran=e59 ")!.lowerBound < metin.range(of: "ekran=e10 ")!.lowerBound)
        // Kırıntı verilmeyen çağrı (mevcut çağrı noktaları) bölümü boş gösterir.
        let bos = DiagnosticReport.render(bosAnlik(), now: t0)
        #expect(bos.contains("son_adimlar (0, yeniden eskiye):\n  —"))
    }

    /// Uygulama yeniden açılınca tampon boş başlar: kırıntının kalıcı deposu yoktur, kaynakta disk/tercih/ağ yazma çağrısı bulunmaz.
    @Test func yeniTamponBosBaslarVeDiskeYazilmaz() throws {
        let onceki = Breadcrumbs()
        onceki.record(screen: "sohbet", action: "gonder")
        #expect(onceki.entries().count == 1)
        #expect(Breadcrumbs().entries().isEmpty)

        let kaynak = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/MarkaCore/Status/Breadcrumbs.swift")
        let kod = try String(contentsOf: kaynak, encoding: .utf8)
        for yasak in ["FileManager", "write(to", "contentsOf", "UserDefaults", "URLSession", "URLRequest", "Process(", "fopen", "Keychain", "SecItem", "os_log", "Logger(", "print(", "NSLog"] {
            #expect(!kod.contains(yasak), "Kırıntı kaynağında kalıcı/ağ çağrısı var: \(yasak)")
        }
    }
}
