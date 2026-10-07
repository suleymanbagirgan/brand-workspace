import Foundation
import Testing

/// E-04: `scripts/tasarim-denetimi.py` örnek ihlal dosyasında altı türün her birini yakalar; çıkış kodu eşiğe bağlıdır.
/// Betik kapıya bağlı değildir (E-15 bağlar). Python 3 yoksa test sessizce geçmez, açıkça kırılır.
@Suite struct TasarimDenetimiBetikTests {
    static let kok = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func calistir(_ argumanlar: [String]) throws -> (cikis: Int32, yazi: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        p.arguments = [kok.appendingPathComponent("scripts/tasarim-denetimi.py").path] + argumanlar
        let boru = Pipe()
        p.standardOutput = boru
        p.standardError = boru
        try p.run()
        let veri = boru.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: veri, as: UTF8.self))
    }

    static func sayilar(_ yazi: String) -> [String: Int] {
        var s: [String: Int] = [:]
        for satir in yazi.split(separator: "\n") {
            let parca = satir.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parca.count == 2, let n = Int(parca[1]) { s[parca[0]] = n }
        }
        return s
    }

    @Test func tasarimDenetimiOrnekDosyadaAltiIhlalTuruYakalarVeEsigeGoreCikar() throws {
        let ornek = Self.kok.appendingPathComponent("Tests/Fixtures/tasarim-ihlal/OrnekIhlal.swift.txt").path
        let siki = try Self.calistir([ornek])
        let s = Self.sayilar(siki.yazi)
        for tur in ["sabit-renk", "sabit-yazi", "kose", "metin-L", "simge-dugme", "bosluk"] {
            #expect((s[tur] ?? 0) >= 1, "\(tur) yakalanmadı:\n\(siki.yazi)")
        }
        #expect(siki.cikis == 1)
        // Gerekçeli sabit boyut, etiketli simge düğmesi, L(…) ve belirteç kullanımı sayılmaz: tür başına tam sayılar.
        #expect(s["sabit-yazi"] == 1)
        #expect(s["simge-dugme"] == 1)
        #expect(s["metin-L"] == 1)
        let gevsek = try Self.calistir(["--esik", "\(s["toplam"] ?? 0)", ornek])
        #expect(gevsek.cikis == 0)
    }
}
