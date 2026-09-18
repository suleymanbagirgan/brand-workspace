import Foundation
import Testing
@testable import MarkaCore

/// Kendi açıklaması içerik taşıyan hata (değersiz vakada bile ad yerine açıklama dönerdi).
private enum SizintiHatasi: Error, CustomStringConvertible {
    case duz
    case yol(String)
    var description: String { "GizliMarkaXYZ sirMetin123" }
}

/// (a) Mirror'ı kendisi kuran hata: vaka etiketi yerine içerik döndürür.
private enum YansiyanHata: Error, CustomReflectable {
    case a(String)
    var customMirror: Mirror {
        switch self { case .a(let s): Mirror(self, children: [(label: s, value: 0)], displayStyle: .enum) }
    }
}

/// (b) Değersiz vakası olan ama açıklamasını akışa kendisi yazan hata.
private enum AkisHatasi: Error, TextOutputStreamable {
    case duz
    func write<T: TextOutputStream>(to target: inout T) { target.write(DiagnosticsTests.marka) }
}

/// (d) Alan adını çalışma anında içerikten üreten hata.
private struct DinamikAlanHatasi: CustomNSError {
    static var errorDomain: String { "Foundation.\(DiagnosticsTests.marka)" }
    var errorCode: Int { 3 }
}

/// (e) Genel tip argümanı içerik taşıyan hata.
private struct SarmalHata<T>: Error {}
private enum GizliMarkaXYZ {}

@Suite(.serialized) struct DiagnosticsTests {
    static let marka = "GizliMarkaXYZ"
    static let govde = "sirMetin123"
    static let eposta = "gizli.kisi@ornek-sirket.com"
    static var evYolu: String { NSHomeDirectory() + "/Belgeler/\(marka) sözleşme \(govde).pdf" }

    /// Kanıt: ayırt edici içerik veri alanında ve hata mesajlarında dururken tanı metninde hiçbiri geçmez.
    @Test func taniMetniMarkaIcerikEpostaVeYolSizdirmaz() async throws {
        let store = try makeStore()
        let brand = try store.createBrand(name: Self.marka, summary: "\(Self.govde) özeti", sector: "Gizli sektör")
        try store.setAIProviders(brand.id, providers: [.anthropic])
        try store.addTextSource(brandId: brand.id, kind: .meeting, title: "\(Self.marka) toplantısı", body: "Gövde: \(Self.govde)")
        try store.saveContact(Contact(brandId: brand.id, name: "Gizli Kişi", email: Self.eposta))
        try store.saveTask(WorkTask(brandId: brand.id, title: "\(Self.marka) için \(Self.govde)"))

        let log = DiagnosticsLog(url: try tempDir("tani").appendingPathComponent(DiagnosticsLog.fileName))

        // 1. Gerçek dosya hatası: ev dizininde, adı içerik taşıyan ve var olmayan bir dosya (userInfo yolu taşır).
        do {
            try store.addFileSource(brandId: brand.id, fileURL: URL(fileURLWithPath: Self.evYolu))
            Issue.record("Olmayan dosya eklenmemeliydi")
        } catch { log.record(error, context: "kaynak.dosya") }
        // 2-6. Mesajına içerik gömülmüş uygulama ve sistem hataları.
        let gomulu = "\(Self.marka) \(Self.govde) \(Self.eposta) \(Self.evYolu)"
        log.record(MarkaError.validation(gomulu), context: "rapor.pdf")
        log.record(MarkaError.providerNotAllowed(brand: Self.marka, provider: gomulu), context: "ai.bilgi.derleme")
        log.record(NSError(domain: Self.marka, code: 7, userInfo: [NSLocalizedDescriptionKey: gomulu, NSFilePathErrorKey: Self.evYolu]),
                   context: "yedek.elle")
        log.record(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: gomulu)), context: "iceaktarim.joi")
        log.record(SizintiHatasi.duz, context: "WorkView:53")
        log.record(SizintiHatasi.yol(gomulu), context: "WorkView:54")
        // Bağlam anahtarı olarak içerik verilse de anahtar geçersiz sayılır, süzülmüş parçası bile yazılmaz.
        log.record(MarkaError.brandScope, context: Self.evYolu)

        // 7. AI sağlayıcı hatası: sohbet motoru içerik taşıyan bir turda başarısız olur.
        let engine = ChatEngine(store: store, codex: CodexAppServer(), folders: BrandFolders(root: try tempDir("folders"), store: store),
                                workspace: try tempDir("ws"), settings: AISettings(), anthropicKey: { nil }, diagnostics: log)
        let session = try await engine.createSession(scope: .brand(brand.id), provider: .anthropic, title: Self.marka)
        var failed = false
        for await ev in await engine.send(sessionId: session.id, text: gomulu) { if case .failed = ev { failed = true } }
        #expect(failed)

        let entries = log.entries()
        #expect(entries.count == 9)
        #expect(entries.last?.context == "ai.anthropic.akis")
        #expect(entries.last?.type == "MarkaCore.MarkaError" && entries.last?.caseName == "ai")
        #expect(entries.contains { $0.context == "rapor.pdf" && $0.caseName == "validation" })
        #expect(entries.contains { $0.context == "kaynak.dosya" && $0.code.hasPrefix("NSCocoaErrorDomain") })
        #expect(entries.contains { $0.context == "iceaktarim.joi" && $0.caseName == "dataCorrupted" })
        #expect(entries.contains { $0.context == "yedek.elle" && $0.code == "özel 7" })
        #expect(entries.contains { $0.context == "WorkView:53" && $0.caseName == nil })
        #expect(entries.contains { $0.context == "WorkView:54" && $0.caseName == "yol" })
        #expect(entries.contains { $0.context == "gecersiz-baglam" && $0.caseName == "brandScope" })

        let snapshot = DiagnosticSnapshot.collect(store: store, log: log, anthropicKeyPresent: true, codex: .girissiz)
        let text = DiagnosticReport.render(snapshot, now: Date())
        let dosya = try String(contentsOf: log.url!, encoding: .utf8)
        for metin in [text, dosya] {
            for gizli in [Self.marka, Self.govde, Self.eposta, "@", NSHomeDirectory(), "/Users/", "Users", "Belgeler", "sman", "sözleşme", "Gizli Kişi", "Gizli sektör"] {
                #expect(!metin.contains(gizli), "Tanı çıktısında içerik var: \(gizli)")
            }
        }
        // Beklenen içeriksiz bilgi yerinde.
        #expect(text.contains("surum: \(MarkaCoreVersion.string)"))
        #expect(text.contains("marka: 1 (arsivli: 0)"))
        #expect(text.contains("kaynak: 1 · gorev: 1 · rapor: 0"))
        #expect(text.contains("ai_anthropic: anahtar var · izinli marka: 1"))
        #expect(text.contains("ai_codex: girissiz · izinli marka: 0"))
        #expect(text.contains("ai.anthropic.akis  MarkaCore.MarkaError.ai"))
        #expect(text.contains("rapor.pdf  MarkaCore.MarkaError.validation"))
        #expect(text.contains("beta ölçümleri"))
        print("--- sentetik tanı metni ---\n\(text)\n---")
    }

    @Test func taniGunluguSon200KaydiTutarVeDosyadanYukler() throws {
        let url = try tempDir("tani").appendingPathComponent(DiagnosticsLog.fileName)
        let log = DiagnosticsLog(url: url)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for i in 0..<250 { log.record(MarkaError.timerAlreadyRunning, context: "kayit.\(i)", at: start.addingTimeInterval(Double(i))) }
        log.record(CancellationError(), context: "iptal")
        #expect(log.entries().count == DiagnosticsLog.capacity)
        #expect(log.entries().first?.context == "kayit.50")
        let reloaded = DiagnosticsLog(url: url)
        #expect(reloaded.entries() == log.entries())

        // Metne yalnızca en yeni 20 kayıt, yeniden eskiye yazılır.
        let snapshot = DiagnosticSnapshot.collect(store: nil, log: reloaded, anthropicKeyPresent: false, codex: .bilinmiyor)
        let text = DiagnosticReport.render(snapshot, now: start)
        #expect(text.contains("son_hatalar (20/200"))
        #expect(text.contains("kayit.249") && text.contains("kayit.230") && !text.contains("kayit.229"))
        #expect(text.range(of: "kayit.249")!.lowerBound < text.range(of: "kayit.230")!.lowerBound)
        #expect(text.contains("MarkaCore.MarkaError.timerAlreadyRunning"))
        #expect(text.contains("ai_anthropic: anahtar yok"))
    }

    /// Kanıt (G2): kendi yansımasını, açıklamasını ya da alan adını kodla üreten ve genel tip argümanı taşıyan hatalarda
    /// süzgeç tipin ürettiği metne güvenmez; "GizliMarkaXYZ" hiçbir alana geçmez.
    @Test func taniSuzgeciOzelYansimaAciklamaAlanVeGenelTipteIcerikSizdirmaz() throws {
        let hatalar: [(String, Error)] = [
            ("a.yansima", YansiyanHata.a(Self.marka)),
            ("b.akis", AkisHatasi.duz),
            ("c.onek", NSError(domain: "NS\(Self.marka)", code: 1)),
            ("c.alt", NSError(domain: NSCocoaErrorDomain, code: 4, userInfo: [NSUnderlyingErrorKey: NSError(domain: "com.apple.\(Self.marka)", code: 2)])),
            ("d.dinamik", DinamikAlanHatasi()),
            ("e.genel", SarmalHata<GizliMarkaXYZ>()),
        ]
        let log = DiagnosticsLog(url: nil)
        for (baglam, hata) in hatalar { log.record(hata, context: baglam) }
        let e = Dictionary(uniqueKeysWithValues: log.entries().map { ($0.context, $0) })
        for entry in e.values {
            #expect(!entry.line.contains(Self.marka), "Tanı kaydında içerik var: \(entry.line)")
        }
        #expect(e["a.yansima"]?.caseName == nil)
        #expect(e["b.akis"]?.caseName == nil)
        #expect(e["c.onek"]?.code == "özel 1")
        #expect(e["c.alt"]?.code == "NSCocoaErrorDomain 4 ← özel 2")
        #expect(e["d.dinamik"]?.code == "özel 3")
        #expect(e["e.genel"]?.type == "MarkaCoreTests.SarmalHata")
        #expect(e["e.genel"]?.code.hasPrefix("özel") == true)
        // Bilinen alanlar ve Swift hatalarının tip adıyla aynı alanı yazılmaya devam eder.
        let bilinen = DiagnosticEntry(error: URLError(.notConnectedToInternet), context: "ag")
        #expect(bilinen.code == "NSURLErrorDomain \(URLError.notConnectedToInternet.rawValue)")
        #expect(DiagnosticEntry(error: MarkaError.brandScope, context: "x").code.hasPrefix("MarkaCore.MarkaError "))
        let decoding = DiagnosticEntry(error: DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: Self.marka)), context: "x")
        #expect(decoding.type == "Swift.DecodingError" && decoding.code.hasPrefix("NSCocoaErrorDomain ") && decoding.caseName == "dataCorrupted")
        #expect(DiagnosticEntry(error: SarmalHata<Int>(), context: "x").code.hasPrefix("özel "))
    }

    /// Kanıt (G2): tanı dosyası uygulama dışında içerikle yazılmış olsa bile yüklenirken yeniden süzülür.
    @Test func dosyadanYuklenenKayitlarYenidenSuzulur() throws {
        let url = try tempDir("tani").appendingPathComponent(DiagnosticsLog.fileName)
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        let kirli = [
            DiagnosticEntry(at: at, context: "\(NSHomeDirectory())/\(Self.marka).pdf", type: "MarkaCore.\(Self.marka) sözleşme",
                            caseName: "\(Self.marka) \(Self.govde)", code: "\(Self.marka) 7 ← NS\(Self.marka) 2"),
            DiagnosticEntry(at: at, context: "rapor.pdf", type: "MarkaCoreTests.Sarmal<\(Self.marka)>", caseName: Self.eposta,
                            code: "Foundation.\(Self.marka) 3"),
            DiagnosticEntry(at: at, context: "kayit", type: "?", caseName: nil, code: Self.evYolu),
        ]
        let temiz = DiagnosticEntry(at: at, context: "ai.anthropic.akis", type: "MarkaCore.MarkaError", caseName: "ai",
                                    code: "MarkaCore.MarkaError 7 ← NSURLErrorDomain -1009")
        try DiagnosticsLog.encoder.encode(kirli + [temiz]).write(to: url)

        let log = DiagnosticsLog(url: url)
        let entries = log.entries()
        #expect(entries.count == 4)
        #expect(entries.last == temiz, "temiz kayıt olduğu gibi kalmalı")
        #expect(entries[0].context == "gecersiz-baglam" && entries[0].type == "?" && entries[0].caseName == nil && entries[0].code == "özel 7 ← özel 2")
        #expect(entries[1].type == "MarkaCoreTests.Sarmal" && entries[1].caseName == nil && entries[1].code == "özel 3")
        #expect(entries[2].code == "özel 0")
        let text = DiagnosticReport.render(DiagnosticSnapshot.collect(store: nil, log: log, anthropicKeyPresent: false, codex: .bilinmiyor), now: at)
        for gizli in [Self.marka, Self.govde, Self.eposta, "@", NSHomeDirectory(), "Belgeler", "sözleşme"] {
            #expect(!text.contains(gizli), "Yüklenen tanı kaydında içerik var: \(gizli)")
        }
    }
}
