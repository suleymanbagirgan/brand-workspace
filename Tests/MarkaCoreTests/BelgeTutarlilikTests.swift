import Foundation
import Testing

/// Belgelerin bayatlayan ya da abartılı iddiaları (kural 7: yapmadığımızı vaat etmeyiz).
/// Desen `SurumTests` ile aynı: belge dosyası okunur, kural denetlenir.
@Suite struct BelgeTutarlilikTests {
    private func kok() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
    private func oku(_ yol: String) throws -> String {
        try String(contentsOf: kok().appendingPathComponent(yol), encoding: .utf8)
    }
    private let belgeler = ["README.md", "docs/bilinen-sinirlar.md"]

    /// Sayıyı belgeye elle yazmak bayatlıyordu (belge 200, gerçek 255): belge sayı taşımaz, sayım `scripts/test.sh`'tedir.
    @Test func belgelerdeSabitTestSayisiYok() throws {
        let kalip = try Regex(#"(?i)\b\d+\s+(@Test\s+)?test(ler|i)?\b"#)
        for yol in belgeler {
            let metin = try oku(yol)
            for (no, satir) in metin.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                #expect(satir.firstMatch(of: kalip) == nil, "\(yol):\(no + 1) sabit test sayısı içeriyor; sayı bayatlar, yazma: \(satir)")
            }
        }
    }

    @Test func belgelerdeMutlakGizlilikIfadesiYok() throws {
        let yasak = [
            "Mac'te kalır", "Mac’te kalır", "Mac'te durur", "Mac’te durur", "Mac'ten çıkmaz", "Mac’ten çıkmaz",
            "verin sende", "veriniz sizde", "stays on this Mac", "never leaves", "data stays", "Veri yalnız bu Mac",
        ]
        for yol in belgeler {
            let metin = try oku(yol).lowercased()
            for ifade in yasak {
                #expect(!metin.contains(ifade.lowercased()), "\(yol) mutlak gizlilik ifadesi içeriyor: \(ifade)")
            }
        }
    }

    /// E-27: kalite ilkeleri belgesinde adı geçen betik ve dosyalar var olmalı (bayat bağlantı yok).
    @Test func kaliteIlkeleriBelgesindeAdiGecenYollarVar() throws {
        let metin = try oku("docs/kalite-ilkeleri.md")
        let kalip = try Regex(#"`([^`\s]+/[^`\s]+)`"#)
        let yollar = metin.matches(of: kalip).map { String($0.output[1].substring ?? "") }
        #expect(!yollar.isEmpty)
        for yol in yollar {
            #expect(FileManager.default.fileExists(atPath: kok().appendingPathComponent(yol).path), "docs/kalite-ilkeleri.md var olmayan yolu anıyor: \(yol)")
        }
    }
}
