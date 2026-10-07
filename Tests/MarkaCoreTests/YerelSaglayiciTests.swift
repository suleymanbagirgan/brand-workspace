#if !MAS
import Foundation
import Testing
@testable import MarkaCore

/// Yerel model sunucusunun sahtesi: bu oturumdaki HER isteği yakalar, gerçek ağa hiçbir şey çıkmaz.
final class SahteYerelSunucu: URLProtocol, @unchecked Sendable {
    enum Yanit { case akis(String), durum(Int, String), yonlendir(String) }
    nonisolated(unsafe) static var yanit: Yanit = .akis("")
    nonisolated(unsafe) static var govdeler: [String] = []
    nonisolated(unsafe) static var adresler: [URL] = []
    static let lock = NSLock()

    static func sifirla(_ y: Yanit) { lock.withLock { yanit = y; govdeler = []; adresler = [] } }
    static var istekSayisi: Int { lock.withLock { adresler.count } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open(); var d = Data(); var buf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&buf, maxLength: 4096); if n <= 0 { break }; d.append(buf, count: n) }
            stream.close(); body = d
        }
        let y: Yanit = Self.lock.withLock {
            Self.govdeler.append(String(decoding: body ?? Data(), as: UTF8.self))
            if let u = request.url { Self.adresler.append(u) }
            return Self.yanit
        }
        let url = request.url!
        switch y {
        case .akis(let metin):
            let r = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["content-type": "text/event-stream"])!
            client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(metin.utf8))
        case .durum(let kod, let metin):
            let r = HTTPURLResponse(url: url, statusCode: kod, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(metin.utf8))
        case .yonlendir(let hedef):
            let r = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: ["Location": hedef])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: URL(string: hedef)!), redirectResponse: r)
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    static var oturum: URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [SahteYerelSunucu.self]
        return URLSession(configuration: c)
    }

    static func openAIAkisi(_ parcalar: [String]) -> String {
        parcalar.map { p -> String in
            let j: JSONValue = ["choices": [["delta": ["content": .string(p)]]]]
            return "data: \(j.compactString())\n\n"
        }.joined() + "data: {\"choices\":[],\"usage\":{\"prompt_tokens\":12,\"completion_tokens\":3}}\n\ndata: [DONE]\n\n"
    }
}

/// Kancadan motora ulaşmak için; tur başlamadan önce kullanıcının "Durdur"a basması.
struct OnceDurduranSaglayici: AIProvider {
    let inner: any AIProvider
    let ref: EngineRef
    var kind: AIProviderKind { inner.kind }
    var capabilities: AIProviderCapabilities { inner.capabilities }
    func sessionModel(settings: AISettings) -> String { inner.sessionModel(settings: settings) }
    func cancel(sessionId: String) async { await inner.cancel(sessionId: sessionId) }
    func runTurn(_ turn: AITurn, assistant: inout AIMessage) async throws {
        await ref.engine?.cancel(sessionId: ref.sessionId)
        try await inner.runTurn(turn, assistant: &assistant)
    }
}

/// E-03: yerel uç nokta sağlayıcısı. Hiçbir test gerçek ağa çıkmaz (`SahteYerelSunucu`).
@Suite(.serialized) struct YerelSaglayiciTests {
    func saglayici(_ adres: String = "http://127.0.0.1:11434", bicim: LocalEndpointFormat = .openAICompatible,
                   acik: Bool = true) throws -> LocalEndpointProvider {
        let c = try LocalEndpointConfig(baseURL: adres, format: bicim, model: "yerel-deneme", isEnabled: acik)
        return LocalEndpointProvider(config: c, kind: .anthropic, urlSession: SahteYerelSunucu.oturum)
    }

    func motor(_ store: Store, _ p: any AIProvider) throws -> ChatEngine {
        ChatEngine(store: store, codex: CodexAppServer(), folders: BrandFolders(root: try tempDir("folders"), store: store),
                   workspace: try tempDir("ws"), settings: AISettings(), anthropicKey: { nil }, urlSession: SahteYerelSunucu.oturum,
                   diagnostics: nil, providers: [p])
    }

    struct Ozet { var text = ""; var failures: [String] = [] }
    func gonder(_ e: ChatEngine, _ sessionId: String, _ text: String) async -> Ozet {
        var o = Ozet()
        for await ev in await e.send(sessionId: sessionId, text: text) {
            switch ev {
            case .textDelta(let t): o.text += t
            case .failed(let m): o.failures.append(m)
            default: break
            }
        }
        return o
    }

    @Test func geriDonguDisiAdresKurulumdaReddedilir() {
        let kotu = ["http://192.168.1.20:11434", "http://10.0.0.5", "http://ornek-sunucu.test", "http://localhost.evil.com",
                    "http://127.0.0.1@evil.com", "http://127.0.0.1.", "http://0x7f.0.0.1", "http://2130706433",
                    "http://127.0.0.2", "ftp://localhost", "file:///tmp/model", "localhost:11434", "", "http://kullanici@localhost"]
        for a in kotu {
            #expect(throws: MarkaError.self, "\(a)") {
                try LocalEndpointConfig(baseURL: a, format: .ollama, model: "m")
            }
        }
    }

    @Test func yalnizGeriDonguAdresleriKabulEdilirVeIstekAdresiDogru() throws {
        let a = try LocalEndpointConfig(baseURL: "http://127.0.0.1:11434", format: .ollama, model: "m")
        #expect(a.chatURL.absoluteString == "http://127.0.0.1:11434/api/chat")
        let b = try LocalEndpointConfig(baseURL: "http://[::1]:8080", format: .openAICompatible, model: "m")
        #expect(b.chatURL.absoluteString == "http://[::1]:8080/v1/chat/completions")
        let c = try LocalEndpointConfig(baseURL: "http://LOCALHOST:1234/v1", format: .openAICompatible, model: "m")
        #expect(c.chatURL.absoluteString == "http://LOCALHOST:1234/v1/chat/completions")
        #expect([a, b, c].allSatisfy { LocalEndpointConfig.isLoopback($0.chatURL) })
        #expect(throws: MarkaError.self) { try LocalEndpointConfig(baseURL: "http://localhost", format: .ollama, model: "  ") }
    }

    @Test func varsayilanKapaliVeKapaliykenHicIstekGitmez() async throws {
        let c = try LocalEndpointConfig(baseURL: "http://localhost:11434", format: .ollama, model: "m")
        #expect(c.isEnabled == false)
        SahteYerelSunucu.sifirla(.akis(SahteYerelSunucu.openAIAkisi(["x"])))
        let store = try makeStore()
        let b = try store.createBrand(name: "Deneme Yangın")
        try store.setAIProviders(b.id, providers: [.anthropic])
        let e = try motor(store, try saglayici(acik: false))
        let s = try await e.createSession(scope: .brand(b.id), provider: .anthropic, title: "x")
        let o = await gonder(e, s.id, "Merhaba")
        #expect(!o.failures.isEmpty)
        #expect(SahteYerelSunucu.istekSayisi == 0)
    }

    @Test func yeteneklerAracsizVeCihazUstu() throws {
        let p = try saglayici()
        #expect(p.capabilities.supportsTools == false)
        #expect(p.capabilities.onDevice == true)
        #expect(p.capabilities.needsAPIKey == false)
        #expect(p.sessionModel(settings: AISettings()) == "yerel-deneme")
    }

    @Test func openAIUyumluAkisSatirlariAyristirilir() throws {
        let f = LocalEndpointFormat.openAICompatible
        #expect(try LocalEndpointProvider.parseLine(#"data: {"choices":[{"delta":{"content":"Mer"}}]}"#, format: f) == [.text("Mer")])
        #expect(try LocalEndpointProvider.parseLine("data: [DONE]", format: f) == [.done])
        #expect(try LocalEndpointProvider.parseLine(#"data: {"choices":[],"usage":{"prompt_tokens":5,"completion_tokens":2}}"#, format: f)
                == [.usage(input: 5, output: 2)])
        #expect(try LocalEndpointProvider.parseLine(": yorum", format: f).isEmpty)
        #expect(try LocalEndpointProvider.parseLine("data: bozuk{", format: f).isEmpty)
        #expect(throws: MarkaError.self) { try LocalEndpointProvider.parseLine(#"data: {"error":{"message":"x"}}"#, format: f) }
    }

    @Test func ollamaAkisSatirlariAyristirilir() throws {
        let f = LocalEndpointFormat.ollama
        #expect(try LocalEndpointProvider.parseLine(#"{"message":{"role":"assistant","content":"Sel"},"done":false}"#, format: f) == [.text("Sel")])
        #expect(try LocalEndpointProvider.parseLine(#"{"message":{"content":""},"done":true,"prompt_eval_count":9,"eval_count":4}"#, format: f)
                == [.usage(input: 9, output: 4), .done])
        #expect(try LocalEndpointProvider.parseLine("", format: f).isEmpty)
        #expect(throws: MarkaError.self) { try LocalEndpointProvider.parseLine(#"{"error":"model yok"}"#, format: f) }
    }

    @Test func akisUctanUcaMetinVeKullanimKaydiUretirAracVerilmez() async throws {
        SahteYerelSunucu.sifirla(.akis(SahteYerelSunucu.openAIAkisi(["Mer", "haba", "."])))
        let store = try makeStore()
        let b = try store.createBrand(name: "Deneme Yangın")
        try store.setAIProviders(b.id, providers: [.anthropic])
        let e = try motor(store, try saglayici())
        let s = try await e.createSession(scope: .brand(b.id), provider: .anthropic, title: "x")
        let o = await gonder(e, s.id, "Selam")
        #expect(o.failures.isEmpty)
        #expect(o.text == "Merhaba.")
        #expect(SahteYerelSunucu.istekSayisi == 1)
        #expect(SahteYerelSunucu.adresler.allSatisfy { LocalEndpointConfig.isLoopback($0) })
        let govde = try JSONValue.parse(try #require(SahteYerelSunucu.govdeler.first))
        #expect(govde["tools"] == nil)
        #expect(govde["model"]?.string == "yerel-deneme")
        let stored = try await e.messages(sessionId: s.id)
        #expect(stored.last?.text == "Merhaba.")
        #expect(try store.proposals(sessionId: s.id).isEmpty)
    }

    @Test func iptaldenSonraYeniIstekSayisiSifir() async throws {
        SahteYerelSunucu.sifirla(.akis(SahteYerelSunucu.openAIAkisi(["Gitmemeli"])))
        let store = try makeStore()
        let b = try store.createBrand(name: "Deneme Yangın")
        try store.setAIProviders(b.id, providers: [.anthropic])
        let ref = EngineRef()
        let e = try motor(store, OnceDurduranSaglayici(inner: try saglayici(), ref: ref))
        ref.engine = e
        let s = try await e.createSession(scope: .brand(b.id), provider: .anthropic, title: "x")
        ref.sessionId = s.id
        let o = await gonder(e, s.id, "Başla")
        #expect(SahteYerelSunucu.istekSayisi == 0)
        #expect(!o.text.contains("Gitmemeli"))
    }

    @Test func istekGovdesindeBaskaMarkaIcerigiYok() async throws {
        SahteYerelSunucu.sifirla(.akis(SahteYerelSunucu.openAIAkisi(["Tamam."])))
        let store = try makeStore()
        let a = try store.createBrand(name: "Kuzey Lojistik")
        let bb = try store.createBrand(name: "Örnek Kafe Zinciri")
        try store.setAIProviders(a.id, providers: [.anthropic])
        try store.setAIProviders(bb.id, providers: [.anthropic])
        _ = try store.addTextSource(brandId: a.id, kind: .note, title: "KUZEY-NOTU-A", body: "Kuzey teklif notu")
        _ = try store.addTextSource(brandId: bb.id, kind: .note, title: "GIZLI-BASLIK-B", body: "GIZLI-BUTCE-B")
        let e = try motor(store, try saglayici())
        let s = try await e.createSession(scope: .brand(a.id), provider: .anthropic, title: "x")
        _ = await gonder(e, s.id, "Durumu özetle")
        let govde = SahteYerelSunucu.govdeler.joined()
        #expect(SahteYerelSunucu.istekSayisi == 1)
        #expect(govde.contains("Kuzey Lojistik"))   // olumlu denetim: kendi markası gidiyor
        for yasak in ["Örnek Kafe Zinciri", "GIZLI-BASLIK-B", "GIZLI-BUTCE-B", bb.id] {
            #expect(govde.components(separatedBy: yasak).count - 1 == 0, "\(yasak)")
        }
    }

    @Test func yonlendirmeIzlenmezVeDisAdreseIstekGitmez() async throws {
        SahteYerelSunucu.sifirla(.yonlendir("http://dis-sunucu.test/topla"))
        let store = try makeStore()
        let b = try store.createBrand(name: "Deneme Yangın")
        try store.setAIProviders(b.id, providers: [.anthropic])
        let e = try motor(store, try saglayici())
        let s = try await e.createSession(scope: .brand(b.id), provider: .anthropic, title: "x")
        let o = await gonder(e, s.id, "Selam")
        #expect(!o.failures.isEmpty)
        #expect(SahteYerelSunucu.adresler.allSatisfy { LocalEndpointConfig.isLoopback($0) })
        #expect(!SahteYerelSunucu.adresler.contains { $0.host == "dis-sunucu.test" })
    }

    @Test func sunucuHatasiMesajaIcerikTasimaz() async throws {
        SahteYerelSunucu.sifirla(.durum(500, "GIZLI-SUNUCU-GOVDESI"))
        let store = try makeStore()
        let b = try store.createBrand(name: "Deneme Yangın")
        try store.setAIProviders(b.id, providers: [.anthropic])
        let e = try motor(store, try saglayici(bicim: .ollama))
        let s = try await e.createSession(scope: .brand(b.id), provider: .anthropic, title: "x")
        let o = await gonder(e, s.id, "Selam")
        #expect(!o.failures.isEmpty)
        #expect(!o.failures.joined().contains("GIZLI-SUNUCU-GOVDESI"))
        #expect(SahteYerelSunucu.adresler.first?.path == "/api/chat")
    }

    /// Kaynak düzeyi: sağlayıcı süreç başlatmaz ve tamamı `#if !MAS` içindedir.
    @Test func kaynakSurecBaslatmazVeYalnizMASDisindaDerlenir() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let src = try String(contentsOf: root.appending(path: "Sources/MarkaCore/AI/LocalEndpointProvider.swift"), encoding: .utf8)
        let kod = src.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
        #expect(src.hasPrefix("#if !MAS"))
        #expect(src.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("#endif"))
        for yasak in ["Process(", "NSTask", "/bin/zsh", "posix_spawn", "NSWorkspace"] { #expect(!kod.contains(yasak), "\(yasak)") }
    }
}
#endif
