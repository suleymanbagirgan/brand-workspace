import Foundation
import Testing

/// Kural 7 (yapmadığımızı vaat etmeyiz): belgede kanıt diye gösterilen test adı gerçekten var mı, 7 kuralın hepsi haritada mı.
/// Desen `BelgeTutarlilikTests` ile aynı: belge dosyası okunur, kural denetlenir.
@Suite struct KuralTestHaritasiTests {
    private func kok() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
    private func oku(_ yol: String) throws -> String {
        try String(contentsOf: kok().appendingPathComponent(yol), encoding: .utf8)
    }

    /// Backtick içindeki Türkçe camelCase test adları; `Dosya.ad` biçiminde önek atılır.
    /// Test adı ölçütü: küçük harfle başlar, yalnız harf/rakam/alt çizgi, en az 3 büyük harf (`brandTeam` gibi kod adlarını eler).
    private func testAdlari(_ metin: String) -> [String] {
        var adlar: [String] = []
        var kalan = Substring(metin.replacingOccurrences(of: "```", with: ""))
        while let a = kalan.firstIndex(of: "`") {
            let sonrasi = kalan.index(after: a)
            guard let b = kalan[sonrasi...].firstIndex(of: "`") else { break }
            var ad = String(kalan[sonrasi..<b])
            kalan = kalan[kalan.index(after: b)...]
            if let nokta = ad.firstIndex(of: "."), ad[ad.startIndex].isUppercase, !ad[..<nokta].contains(" ") {
                ad = String(ad[ad.index(after: nokta)...])
            }
            guard let ilk = ad.first, ilk.isLowercase, ad.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }),
                  ad.filter({ $0.isUppercase }).count >= 3 else { continue }
            adlar.append(ad)
        }
        return adlar
    }

    private func testKaynaklari() throws -> String {
        let klasor = kok().appendingPathComponent("Tests")
        var hepsi = ""
        let gez = FileManager.default.enumerator(at: klasor, includingPropertiesForKeys: nil)
        while let u = gez?.nextObject() as? URL {
            guard u.pathExtension == "swift" else { continue }
            hepsi += (try? String(contentsOf: u, encoding: .utf8)) ?? ""
            hepsi += "\n"
        }
        return hepsi
    }

    private func belgeBolumu(_ yol: String, baslik: String?) throws -> String {
        let metin = try oku(yol)
        guard let baslik else { return metin }
        let r = try #require(metin.range(of: baslik), "\(yol): '\(baslik)' bölümü yok")
        return String(metin[r.lowerBound...])
    }

    @Test func denetimBelgesindekiHerKanitTestiMevcut() throws {
        let kaynak = try testKaynaklari()
        let belgeler: [(String, String?, Int)] = [
            ("docs/kural-test-haritasi.md", nil, 20),
            ("docs/guvence-denetimi-gizlilik.md", "## Düzeltme durumu", 8),
            ("docs/guvence-denetimi-yalitim.md", "## Düzeltme durumu", 20),
        ]
        for (yol, baslik, enAz) in belgeler {
            let adlar = Set(testAdlari(try belgeBolumu(yol, baslik: baslik)))
            #expect(adlar.count >= enAz, "\(yol): beklenenden az test adı bulundu (\(adlar.count)); ayrıştırma bozulmuş olabilir")
            let eksik = adlar.filter { ad in
                kaynak.range(of: #"func \#(ad)\b"#, options: .regularExpression) == nil
            }.sorted()
            #expect(eksik.isEmpty, "\(yol): Tests/ içinde bulunamayan test adı: \(eksik)")
        }
    }

    @Test func kuralTestHaritasiYediKuraliKapsar() throws {
        let kurallar = try oku("CLAUDE.md")
            .split(separator: "\n").filter { $0.range(of: #"^[1-9]\. \*\*"#, options: .regularExpression) != nil }
        #expect(kurallar.count == 7, "CLAUDE.md'deki bozulamaz kural sayısı 7 değil: \(kurallar.count)")
        let satirlar = try oku("docs/kural-test-haritasi.md").split(separator: "\n").map(String.init)
        for no in 1...7 {
            let satir = satirlar.first { $0.hasPrefix("| \(no) |") }
            #expect(satir != nil, "Haritada kural \(no) satırı yok")
            #expect(!testAdlari(satir ?? "").isEmpty, "Haritada kural \(no) için test adı yok")
        }
        #expect(satirlar.filter { $0.range(of: #"^\| [1-9] \|"#, options: .regularExpression) != nil }.count == 7)
    }
}
