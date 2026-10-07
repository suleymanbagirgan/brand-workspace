import Foundation
import GRDB
import Testing
@testable import MarkaCore

/// H3-03: sessiz hata yok. Yakalanan hata ya ekranda görünür ya da yedek değerle sürer ama içeriksiz tanı kaydına düşer.
@Suite struct SessizHataTests {
    static let gizli = "GizliMarkaXYZ sirMetin123"

    /// Kayıt satırında, kayıt yapısının herhangi bir alanında gizli içerik yok.
    static func icerikYok(_ log: DiagnosticsLog) -> Bool {
        log.entries().allSatisfy { e in !e.line.contains("GizliMarka") && !"\(e)".contains("GizliMarka") && !e.line.contains("sirMetin") }
    }

    @Test func basarisizOkumaYedekDegerDonerVeHataIceriksizKaydedilir() {
        let log = DiagnosticsLog(url: nil)
        let sonuc = log.value(or: [Int](), context: "deneme.oku") { () throws -> [Int] in throw MarkaError.validation(Self.gizli) }
        #expect(sonuc.isEmpty)
        #expect(log.entries().count == 1)
        #expect(log.entries().first?.context == "deneme.oku")
        #expect(log.entries().first?.caseName == "validation")
        #expect(Self.icerikYok(log))
    }

    @Test func basariliOkumaVeYanEtkiKayitBirakmaz() {
        let log = DiagnosticsLog(url: nil)
        #expect(log.value(or: 0, context: "deneme.oku") { 7 } == 7)
        #expect(log.attempt(context: "deneme.yaz") {})
        #expect(log.entries().isEmpty)
    }

    @Test func basarisizYanEtkiFalseDonerVeKaydaGecer() {
        let log = DiagnosticsLog(url: nil)
        let tamam = log.attempt(context: "ilk-acilis.isaret") { throw CocoaError(.fileWriteNoPermission) }
        #expect(!tamam)
        #expect(log.entries().map(\.context) == ["ilk-acilis.isaret"])
        #expect(log.entries().first?.code.hasPrefix(NSCocoaErrorDomain) == true)
    }

    @Test func gorunurHataKullaniciyaAciklamaVerirTaniyaMesajYazmaz() {
        let log = DiagnosticsLog(url: nil)
        let hata = MarkaError.validation(Self.gizli)
        let f = log.visible(hata, title: L("Geri alınamadı"), context: "finans.sil.geri")
        #expect(f.title == L("Geri alınamadı"))
        // Kullanıcı hatanın kendi açıklamasını görür (ekrana yalnız ekranda kalır) ...
        #expect(f.message == hata.errorDescription)
        // ... tanı kaydına yalnız tür, yer ve kod düşer.
        #expect(log.entries().map(\.context) == ["finans.sil.geri"])
        #expect(Self.icerikYok(log))
    }

    @Test func gecersizBaglamAnahtariYolTasiyamaz() {
        let log = DiagnosticsLog(url: nil)
        _ = log.visible(CocoaError(.fileNoSuchFile), title: "x", context: NSHomeDirectory() + "/\(Self.gizli).pdf")
        #expect(log.entries().first?.context == "gecersiz-baglam")
        #expect(Self.icerikYok(log))
    }

    @Test func iptalEdilenIsGorunurHataOlsaDaTaniKaydiBirakmaz() {
        let log = DiagnosticsLog(url: nil)
        _ = log.visible(CancellationError(), title: "x", context: "deneme.iptal")
        #expect(!log.attempt(context: "deneme.iptal") { throw CancellationError() })
        #expect(log.entries().isEmpty)
    }

    @Test func yanitKaydedilemezseKullaniciyaHataOlayiGosterilirVeTaniyaYalnizTurDuser() async throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Kuzey Lojistik")
        try store.setAIProviders(b.id, providers: [.anthropic])
        let log = DiagnosticsLog(url: nil)
        let engine = ChatEngine(store: store, codex: CodexAppServer(), folders: BrandFolders(root: try tempDir("f"), store: store),
                                workspace: try tempDir("ws"), settings: AISettings(), anthropicKey: { nil }, diagnostics: log)
        let s = try await engine.createSession(scope: .brand(b.id), provider: .anthropic, title: "x")
        // Asistan yanıtının yazılması veri tabanında reddedilir (disk dolu / kilit benzetimi).
        try store.write { db in
            try db.execute(sql: """
                CREATE TEMP TRIGGER yanitYazmaReddi BEFORE INSERT ON aiMessage WHEN NEW.role = 'assistant'
                BEGIN SELECT RAISE(ABORT, 'GizliMarkaXYZ'); END
                """)
        }
        var olaylar: [ChatEventRecord] = []
        var bitti = false
        for await ev in await engine.send(sessionId: s.id, text: "merhaba") {
            if case .event(let e) = ev { olaylar.append(e) }
            if case .finished = ev { bitti = true }
        }
        let kayitHatasi = olaylar.first { $0.refId == ChatEngine.unsavedReplyRef }
        #expect(kayitHatasi?.kind == .error)
        #expect(kayitHatasi?.title == L("Yanıt kaydedilemedi"))
        #expect(bitti)
        #expect(log.entries().contains { $0.context == "ai.yanit.kaydet" && $0.type == "GRDB.DatabaseError" })
        #expect(Self.icerikYok(log))
        // Yanıt gerçekten saklanmadı; kullanıcı mesajı duruyor.
        #expect(try await engine.messages(sessionId: s.id).map(\.role) == [.user])
    }

    @Test func kaynaktaSessizHataKalibiYok() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dir = root.appendingPathComponent("Sources")
        let bos = try NSRegularExpression(pattern: #"onError:\s*\{\s*_\s*in\s*\}|catch\s*(let\s+\w+\s*)?\{\s*\}"#)
        var bulunan: [String] = []
        let files = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        for f in files where f.pathExtension == "swift" {
            let text = try String(contentsOf: f, encoding: .utf8)
            if bos.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil { bulunan.append(f.lastPathComponent) }
        }
        #expect(!files.isEmpty)
        #expect(bulunan.isEmpty, "Sessiz hata kalıbı: \(bulunan)")
    }
}
