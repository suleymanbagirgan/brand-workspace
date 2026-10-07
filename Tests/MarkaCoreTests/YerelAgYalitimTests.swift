#if !MAS
import Foundation
import Testing
@testable import MarkaCore

/// E-24: oturumdaki HER isteği yakalayan sahte ağ; gerçek ağa hiçbir şey çıkmaz. `YerelSaglayiciTests`'ten ayrı sınıftır
/// (iki takımın paylaşılan durumu birbirini bozmasın).
final class AgGozlemcisi: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var adresler: [URL] = []
    nonisolated(unsafe) static var yanit = ""
    static let lock = NSLock()

    static func sifirla(_ yanit: String) { lock.withLock { adresler = []; Self.yanit = yanit } }
    static var anaMakineler: [String] { lock.withLock { adresler.compactMap { $0.host(percentEncoded: false) } } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let metin: String = Self.lock.withLock { if let u = request.url { Self.adresler.append(u) }; return Self.yanit }
        let r = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["content-type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(metin.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    static var oturum: URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [AgGozlemcisi.self]
        return URLSession(configuration: c)
    }
}

@Suite(.serialized) struct YerelAgYalitimTests {
    func motor(_ store: Store, ayar: AISettings = AISettings(), saglayicilar: [any AIProvider]? = nil) throws -> ChatEngine {
        ChatEngine(store: store, codex: CodexAppServer(), folders: BrandFolders(root: try tempDir("folders"), store: store),
                   workspace: try tempDir("ws"), settings: ayar, anthropicKey: { "test-anahtar" }, urlSession: AgGozlemcisi.oturum,
                   diagnostics: nil, providers: saglayicilar)
    }

    func tur(_ e: ChatEngine, _ s: AISession) async {
        for await _ in await e.send(sessionId: s.id, text: "Merhaba") {}
    }

    @Test func yerelTurdaGeriDonguDisiAnaMakineIstegiSifirdir() async throws {
        let openAI = "data: {\"choices\":[{\"delta\":{\"content\":\"Selam\"}}]}\n\ndata: [DONE]\n\n"
        AgGozlemcisi.sifirla(openAI)
        let store = try makeStore()
        let b = try store.createBrand(name: "Deneme Yangın")
        try store.setAIProviders(b.id, providers: [.local])
        let ayar = AISettings(localBaseURL: "http://127.0.0.1:11434", localModel: "yerel-deneme")
        let e = try motor(store, ayar: ayar, saglayicilar: [LocalSettingsProvider(urlSession: AgGozlemcisi.oturum)])
        let s = try await e.createSession(scope: .brand(b.id), provider: .local, title: "x")
        await tur(e, s)
        #expect(AgGozlemcisi.adresler.count == 1)
        #expect(AgGozlemcisi.adresler.allSatisfy { LocalEndpointConfig.isLoopback($0) })
        #expect(AgGozlemcisi.anaMakineler.filter { !["127.0.0.1", "localhost", "::1"].contains($0) }.isEmpty)
    }

    @Test func anthropicTurundaYalnizApiAnthropicComaIstekGider() async throws {
        AgGozlemcisi.sifirla("data: {\"type\":\"message_stop\"}\n\n")
        let store = try makeStore()
        let b = try store.createBrand(name: "Deneme Yangın")
        try store.setAIProviders(b.id, providers: [.anthropic])
        let e = try motor(store, saglayicilar: [AnthropicProvider(anthropicKey: { "test-anahtar" }, urlSession: AgGozlemcisi.oturum)])
        let s = try await e.createSession(scope: .brand(b.id), provider: .anthropic, title: "x")
        await tur(e, s)
        #expect(!AgGozlemcisi.anaMakineler.isEmpty)
        #expect(Set(AgGozlemcisi.anaMakineler) == ["api.anthropic.com"])
    }

    @Test func rozetMetniSaglayiciYeteneginiOnDeviceDanTuretir() async throws {
        let store = try makeStore()
        let e = try motor(store)   // varsayılan kayıt: Anthropic + Codex + yerel
        let yerel = try #require(e.badge(for: .local))
        let bulut = try #require(e.badge(for: .anthropic))
        let codex = try #require(e.badge(for: .codex))
        #expect(yerel.onDevice && yerel.text == L("Bu Mac'te çalışıyor"))
        #expect(!bulut.onDevice && bulut.text == AIProviderKind.anthropic.displayName)
        #expect(!codex.onDevice && codex.text == AIProviderKind.codex.displayName)
        // Metin yeteneğe bağlıdır: aynı tür, yeteneği değişince rozeti değişir (sabit metin değil).
        #expect(ProviderBadge.make(kind: .anthropic, onDevice: true).text == yerel.text)
        #expect(ProviderBadge.make(kind: .local, onDevice: false).text == AIProviderKind.local.displayName)
        // Ölçülmemiş vaat yok.
        for r in [yerel, bulut, codex] {
            let hepsi = (r.text + r.detail).lowercased()
            #expect(!hepsi.contains("garanti") && !hepsi.contains("hiç dışarı") && !hepsi.contains("asla"))
        }
    }

    @Test func kayitsizSaglayiciIcinRozetYoktur() async throws {
        let store = try makeStore()
        let e = try motor(store, saglayicilar: [AnthropicProvider(anthropicKey: { nil }, urlSession: AgGozlemcisi.oturum)])
        #expect(e.badge(for: .local) == nil)
        #expect(e.badge(for: .anthropic) != nil)
    }
}
#endif
