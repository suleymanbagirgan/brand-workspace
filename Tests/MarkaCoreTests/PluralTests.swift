import Foundation
import Testing

/// İngilizce çoğul kuralları gerçek Foundation çözümlemesiyle denetlenir (uygulamayı çalıştırmadan).
/// Depodaki `Resources/en.lproj` geçici, yalnızca İngilizce yerelleştirmeli bir pakete kopyalanır.
@Suite struct PluralTests {
    static func englishBundle() throws -> Bundle {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = try tempDir("cogul").appendingPathComponent("Deneme.bundle")
        let resources = root.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: repo.appendingPathComponent("Resources/en.lproj"), to: resources.appendingPathComponent("en.lproj"))
        let info: [String: Any] = ["CFBundleIdentifier": "deneme.cogul", "CFBundleDevelopmentRegion": "en", "CFBundleLocalizations": ["en"]]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: root.appendingPathComponent("Contents/Info.plist"))
        return try #require(Bundle(url: root))
    }

    static func format(_ bundle: Bundle, _ key: String, _ args: [CVarArg]) -> String {
        String(format: bundle.localizedString(forKey: key, value: nil, table: nil), locale: Locale(identifier: "en"), arguments: args)
    }

    @Test func ingilizceSayaclarTekilVeCogulBicimiDogruSecer() throws {
        let b = try Self.englishBundle()
        let cases: [(String, [CVarArg], String)] = [
            ("%1$d görev ve %2$d süre kaydı aktarıldı, %3$d marka oluşturuldu. Daha önce aktarılmış %4$d görev atlandı.", [1, 3, 1, 0],
             "Imported 1 task and 3 time entries, created 1 brand. Skipped 0 previously imported tasks."),
            ("%d öneri onay bekliyor", [1], "1 suggestion awaiting approval"),
            ("%d öneri onay bekliyor", [3], "3 suggestions awaiting approval"),
            ("%1$@, %2$d öneri onay bekliyor", ["ABC", 2], "ABC, 2 suggestions awaiting approval"),
            ("%d bozuk olay satırı atlandı", [1], "Skipped 1 malformed event line"),
            ("%d görevde 12 saati aşan süre var (açık unutulmuş sayaç olabilir; aktarım sonrası kontrol et)", [1],
             "1 task has more than 12 hours logged (possibly a forgotten timer; review after import)"),
            ("%d görevde 12 saati aşan süre var (açık unutulmuş sayaç olabilir; aktarım sonrası kontrol et)", [3],
             "3 tasks have more than 12 hours logged (possibly a forgotten timer; review after import)"),
            ("%d kaynaklı iddia", [1], "1 sourced claim"),
            ("%d tutarsız durum (status esas alınır)", [1], "1 inconsistent state (status takes precedence)"),
            ("%d süre kaydı", [1], "1 time entry"),
            ("%d görev", [2], "2 tasks"),
        ]
        for (key, args, expected) in cases {
            #expect(Self.format(b, key, args) == expected)
        }
    }

    /// stringsdict'teki her kural 1 için tekil, 2 için çoğul üretir; biçim artığı ("%", "#@") kalmaz.
    @Test func tumCogulKurallariCozulur() throws {
        let b = try Self.englishBundle()
        let url = try #require(b.url(forResource: "Localizable", withExtension: "stringsdict"))
        let dict = try #require(NSDictionary(contentsOf: url) as? [String: Any])
        // 0.2.1'de kalkan ekranların (sohbet, sayaç, kaynak kartı, Ayarlar › Kullanım, yedek satırındaki sayımlar) çoğul
        // metinleri silindi; kalan kurallar bu kadar.
        #expect(dict.count >= 12)
        for key in dict.keys {
            let specs = try NSRegularExpression(pattern: "%(?:\\d+\\$)?(@|d)").matches(in: key, range: NSRange(key.startIndex..., in: key))
            func args(_ n: Int) -> [CVarArg] {
                specs.map { m -> CVarArg in
                    if (key as NSString).substring(with: m.range).hasSuffix("@") { return "X" }
                    return n
                }
            }
            let one = Self.format(b, key, args(1)), many = Self.format(b, key, args(2))
            #expect(one != key, "Çevrilmedi: \(key)")
            #expect(one.contains("1") && many.contains("2"), "Sayı yok: \(one) / \(many)")
            #expect(one.replacingOccurrences(of: "1", with: "2") != many, "Tekil/çoğul aynı: \(key) → \(one)")
            #expect(!one.contains("%") && !one.contains("#@") && !many.contains("%") && !many.contains("#@"), "Biçim artığı: \(one)")
        }
    }
}
