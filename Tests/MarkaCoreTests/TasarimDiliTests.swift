import Foundation
import Testing

/// H2-04 / H2-05: tek tasarım dili. Arayüz kaynağını tarar: yazı rolü sayısı, sabit yazı boyutu tavanı, okunabilirlik tabanı,
/// köşe yarıçapı ve simge ölçeği `Design.swift` token'larından gelir.
@Suite struct TasarimDiliTests {
    static let kok = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let uygulama = kok.appendingPathComponent("Sources/MarkaApp")

    static func dosyalar() throws -> [(ad: String, metin: String)] {
        try FileManager.default.contentsOfDirectory(at: uygulama, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
    }

    /// `Design.swift` içindeki `enum <ad> {` bloğunun `static let` satırları.
    static func tokenlar(_ ad: String) throws -> [String] {
        let metin = try String(contentsOf: uygulama.appendingPathComponent("Design.swift"), encoding: .utf8)
        guard let bas = metin.range(of: "enum \(ad) {") else { return [] }
        let govde = metin[bas.upperBound...]
        let son = govde.range(of: "\n    }")?.lowerBound ?? govde.endIndex
        return govde[..<son].split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("static let") }
    }

    static func eslesmeler(_ desen: String, _ metin: String) throws -> [String] {
        let rx = try NSRegularExpression(pattern: desen)
        return rx.matches(in: metin, range: NSRange(metin.startIndex..., in: metin)).compactMap { m in
            Range(m.range(at: m.numberOfRanges > 1 ? 1 : 0), in: metin).map { String(metin[$0]) }
        }
    }

    @Test func yaziRoluEnCokAltiTokenVeEnKucukRolOnBirPunto() throws {
        let roller = try Self.tokenlar("Font")
        #expect(!roller.isEmpty && roller.count <= 6, "yazı rolü sayısı \(roller.count)")
        // macOS'ta .caption/.caption2/.footnote 10 pt: rol tabanı 11 pt (.subheadline) altına inmez.
        for r in roller { #expect(![".caption", ".footnote"].contains { r.contains($0) }, "11 pt altı rol: \(r)") }
    }

    @Test func sabitYaziBoyutuAltmisTavaniniAsmazVeHerBiriGerekceTasir() throws {
        var toplam = 0
        for (ad, metin) in try Self.dosyalar() {
            let satirlar = metin.components(separatedBy: "\n")
            for (i, s) in satirlar.enumerated() where s.contains(".font(.system(size") {
                toplam += s.components(separatedBy: ".font(.system(size").count - 1
                let gerekce = s.contains("sabit-boyut:") || (i > 0 && satirlar[i - 1].contains("sabit-boyut:"))
                #expect(gerekce, "\(ad):\(i + 1) sabit yazı boyutu gerekçe yorumu (sabit-boyut:) taşımıyor")
            }
        }
        #expect(toplam <= 60, "sabit yazı boyutu \(toplam) > 60")
    }

    @Test func dokuzPuntoVeAltiYaziYok() throws {
        for (ad, metin) in try Self.dosyalar() {
            for boyut in try Self.eslesmeler(#"\.system\(size: *([0-9]+(?:\.[0-9]+)?)"#, metin) {
                #expect((Double(boyut) ?? 0) > 9, "\(ad): \(boyut) pt yazı")
            }
        }
    }

    @Test func koseYaricapiEnCokUcTokendanGelir() throws {
        let yaricaplar = try Self.tokenlar("Radius")
        #expect(!yaricaplar.isEmpty && yaricaplar.count <= 3, "yarıçap token sayısı \(yaricaplar.count)")
        for (ad, metin) in try Self.dosyalar() {
            #expect(try Self.eslesmeler(#"cornerRadius: *[0-9]"#, metin).isEmpty, "\(ad): sayısal cornerRadius")
            #expect(try Self.eslesmeler(#"\.card\([^)]*radius: *[0-9]"#, metin).isEmpty, "\(ad): sayısal kart yarıçapı")
        }
    }

    @Test func simgeOlcegiEnCokDortDeger() throws {
        let simgeler = try Self.tokenlar("Icon")
        #expect(!simgeler.isEmpty && simgeler.count <= 4, "simge ölçeği \(simgeler.count)")
    }
}
