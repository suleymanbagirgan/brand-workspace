import Foundation
import GRDB
import Testing
@testable import MarkaCore

#if !MAS
/// E-11'in kendi sahte yerel sunucusu (E-03'ün `SahteYerelSunucu`'su ile durum paylaşmaz; paralel koşuda karışmaz).
/// Bu oturumdaki HER isteği yakalar; gerçek ağa hiçbir şey çıkmaz.
final class KayitSahteSunucu: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var durum = 200
    nonisolated(unsafe) static var govde = ""
    nonisolated(unsafe) static var adresler: [URL] = []
    nonisolated(unsafe) static var yontemler: [String] = []
    static let lock = NSLock()

    static func sifirla(durum d: Int = 200, govde g: String = "") {
        lock.withLock { durum = d; govde = g; adresler = []; yontemler = [] }
    }
    static var istekler: [URL] { lock.withLock { adresler } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (d, g): (Int, String) = Self.lock.withLock {
            if let u = request.url { Self.adresler.append(u) }
            Self.yontemler.append(request.httpMethod ?? "GET")
            return (Self.durum, Self.govde)
        }
        let r = HTTPURLResponse(url: request.url!, statusCode: d, httpVersion: nil, headerFields: ["content-type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(g.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    static var oturum: URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [KayitSahteSunucu.self]
        return URLSession(configuration: c)
    }
}
#endif

/// E-11: yerel sağlayıcının kaydı, marka izni, tercih doğrulaması ve MAS davranışı. Hiçbir test gerçek ağa çıkmaz.
@Suite(.serialized) struct YerelSaglayiciKayitTests {
    /// Kalıcı yazmayan tercih deposu (ekran çizimi kapsamı: yalnız bellek).
    func bellekTercih() -> PreferenceStore {
        PreferenceStore(scope: PreferenceScope(kind: .snapshot, suiteName: nil, keychainSuffix: ".test"))
    }

    let yerelAyar = AISettings(localBaseURL: "http://127.0.0.1:11434", localModel: "yerel-deneme")

    #if !MAS
    func motor(_ store: Store, settings: AISettings, providers: [any AIProvider]?) throws -> ChatEngine {
        ChatEngine(store: store, codex: CodexAppServer(), folders: BrandFolders(root: try tempDir("folders"), store: store),
                   workspace: try tempDir("ws"), settings: settings, anthropicKey: { nil }, urlSession: KayitSahteSunucu.oturum,
                   diagnostics: nil, providers: providers)
    }

    func gonder(_ e: ChatEngine, _ sessionId: String, _ mesaj: String) async -> (text: String, failures: [String]) {
        var text = "", failures: [String] = []
        for await ev in await e.send(sessionId: sessionId, text: mesaj) {
            switch ev {
            case .textDelta(let t): text += t
            case .failed(let m): failures.append(m)
            default: break
            }
        }
        return (text, failures)
    }

    @Test func markaIzniYokkenYerelOturumAcilmazVeIzinVarsayilanKapali() async throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Deneme Yangın")
        #expect(!(try store.brand(b.id)).allows(.local))   // varsayılan: izin yok
        let e = try motor(store, settings: yerelAyar, providers: [LocalSettingsProvider(urlSession: KayitSahteSunucu.oturum)])
        await #expect(throws: MarkaError.self) { try await e.createSession(scope: .brand(b.id), provider: .local, title: "x") }
        // Yalnız başka sağlayıcıya izin vermek yerel izni açmaz.
        try store.setAIProviders(b.id, providers: [.anthropic])
        await #expect(throws: MarkaError.self) { try await e.createSession(scope: .brand(b.id), provider: .local, title: "x") }
        // Tüm markalar kapsamında izinsiz marka kapsama girmez.
        let tumu = try await e.allowedBrandIds(scope: .allBrands, provider: .local)
        #expect(tumu.isEmpty)
        // Açık izinle açılır; model adı ayardan gelir.
        try store.setAIProviders(b.id, providers: [.anthropic, .local])
        let s = try await e.createSession(scope: .brand(b.id), provider: .local, title: "x")
        #expect(s.provider == .local && s.model == "yerel-deneme")
    }

    @Test func ayarlanmamisYerelModelleOturumAcilmaz() async throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Kuzey Lojistik")
        try store.setAIProviders(b.id, providers: [.local])
        let e = try motor(store, settings: AISettings(), providers: nil)
        await #expect(throws: MarkaError.self) { try await e.createSession(scope: .brand(b.id), provider: .local, title: "x") }
    }

    @Test func dogrudanDagitimdaYerelSaglayiciKayitliVeSecilebilir() async throws {
        let store = try makeStore()
        let e = try motor(store, settings: yerelAyar, providers: nil)
        let p = try await e.registry.provider(for: .local)
        #expect(p.kind == .local)
        #expect(!p.capabilities.supportsTools && !p.capabilities.needsAPIKey)
        #expect(AIProviderKind.selectable.contains(.local) && AIProviderKind.local.isSelectable)
        // E-03'ün sağlayıcısı artık varsayılan olarak `.local` türündedir (testleri başka tür verebilir).
        let c = try LocalEndpointConfig(baseURL: "http://localhost:8080", format: .ollama, model: "m")
        #expect(LocalEndpointProvider(config: c).kind == .local)
        #expect(AIProviderKind.local.displayName == L("Bu Mac'teki model"))
    }

    @Test func izinliYerelOturumYalnizGeriDonguyeAkarVeKullanimYerelYazilir() async throws {
        KayitSahteSunucu.sifirla(govde: "data: {\"choices\":[{\"delta\":{\"content\":\"Merhaba\"}}]}\n\ndata: [DONE]\n\n")
        let store = try makeStore()
        let b = try store.createBrand(name: "Örnek Kafe Zinciri")
        try store.setAIProviders(b.id, providers: [.local])
        let e = try motor(store, settings: yerelAyar, providers: [LocalSettingsProvider(urlSession: KayitSahteSunucu.oturum)])
        let s = try await e.createSession(scope: .brand(b.id), provider: .local, title: "x")
        let o = await gonder(e, s.id, "selam")
        #expect(o.failures.isEmpty && o.text == "Merhaba")
        #expect(KayitSahteSunucu.istekler.map(\.absoluteString) == ["http://127.0.0.1:11434/v1/chat/completions"])
        let kullanim = try store.read { db in try UsageEntry.fetchAll(db) }
        #expect(kullanim.map(\.provider) == [.local])
    }

    /// MAS derlemesinin kaydında yerel sağlayıcı yoktur. Eski veri tabanından gelen `.local` oturumu o kayıtla hata verir
    /// ve hiçbir istek gönderilmez (MAS kaydı burada yalnız Anthropic sahtesiyle kurulur).
    @Test func eskiVeriTabanindakiYerelOturumMasKaydindaHataVerir() async throws {
        KayitSahteSunucu.sifirla()
        let store = try makeStore()
        let b = try store.createBrand(name: "Deneme Yangın")
        try store.setAIProviders(b.id, providers: [.anthropic, .local])
        let eski = AISession(brandId: b.id, scope: .brand, provider: .local, model: "yerel-deneme", title: "eski")
        try store.write { db in try eski.insert(db) }
        let fake = FakeProvider(kind: .anthropic, rounds: [[.text("olmamalı")]])
        let e = try motor(store, settings: yerelAyar, providers: [fake])
        let o = await gonder(e, eski.id, "selam")
        #expect(!o.failures.isEmpty)
        #expect(o.text.isEmpty && fake.requestCount == 0 && KayitSahteSunucu.istekler.isEmpty)
    }

    @Test func baglantiDenemesiYalnizGeriDonguyeIcerikGondermedenGider() async throws {
        KayitSahteSunucu.sifirla(durum: 200, govde: "{\"data\":[]}")
        try await LocalModelPreferences.testConnection(address: "http://[::1]:8080", urlSession: KayitSahteSunucu.oturum)
        #expect(KayitSahteSunucu.istekler.map(\.absoluteString) == ["http://[::1]:8080/v1/models"])
        #expect(KayitSahteSunucu.lock.withLock { KayitSahteSunucu.yontemler } == ["GET"])

        KayitSahteSunucu.sifirla()
        await #expect(throws: MarkaError.self) {
            try await LocalModelPreferences.testConnection(address: "http://192.168.1.20:11434", urlSession: KayitSahteSunucu.oturum)
        }
        #expect(KayitSahteSunucu.istekler.isEmpty)

        KayitSahteSunucu.sifirla(durum: 500)
        await #expect(throws: MarkaError.self) {
            try await LocalModelPreferences.testConnection(address: "http://127.0.0.1:11434", urlSession: KayitSahteSunucu.oturum)
        }
    }

    @Test func geriDonguDisiAdresTercihlereYazilmaz() throws {
        let p = bellekTercih()
        for kotu in ["http://192.168.1.20:11434", "http://localhost.evil.com", "http://127.0.0.1@evil.com", "ftp://localhost", ""] {
            #expect(throws: MarkaError.self, "\(kotu)") { try LocalModelPreferences.save(address: kotu, model: "m", to: p) }
            #expect(p.string(forKey: LocalModelPreferences.addressKey) == nil)
            #expect(p.string(forKey: LocalModelPreferences.modelKey) == nil)
        }
        // Boş model adı da yazılmaz.
        #expect(throws: MarkaError.self) { try LocalModelPreferences.save(address: "http://127.0.0.1:11434", model: "  ", to: p) }
        #expect(LocalModelPreferences.load(p) == nil)

        // Geçerli kayıt yazılır; ardından gelen kötü adres eskisini bozmaz.
        try LocalModelPreferences.save(address: " http://127.0.0.1:11434 ", model: " yerel-deneme ", to: p)
        #expect(LocalModelPreferences.load(p) == .init(address: "http://127.0.0.1:11434", model: "yerel-deneme"))
        #expect(throws: MarkaError.self) { try LocalModelPreferences.save(address: "http://10.0.0.5", model: "m", to: p) }
        #expect(LocalModelPreferences.load(p)?.address == "http://127.0.0.1:11434")

        // Tercihe dışarıdan yazılmış geri döngü dışı adres okunurken yok sayılır.
        p.set("http://10.0.0.5:11434", forKey: LocalModelPreferences.addressKey)
        #expect(LocalModelPreferences.load(p) == nil)
        LocalModelPreferences.clear(p)
        #expect(p.string(forKey: LocalModelPreferences.modelKey) == nil)
    }
    #endif

    /// MAS derlemesinin seçilebilir listesinde `.local` yok (E-25'ten beri: Anthropic + Apple cihaz üstü). Testler doğrudan dağıtım derlemesinde
    /// koştuğu için MAS dalı kaynaktan denetlenir; `swift build -Xswiftc -DMAS` ayrıca derlenir (kapının MAS adımı).
    @Test func masKipindeSecilebilirlerdeYerelYok() throws {
        #if MAS
        #expect(AIProviderKind.selectable == [.anthropic, .apple])
        #expect(!AIProviderKind.local.isSelectable)
        #else
        let kok = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let flavor = try String(contentsOf: kok.appending(path: "Sources/MarkaCore/BuildFlavor.swift"), encoding: .utf8)
        // E-25: MAS listesi derleme türüne göre saf işlevden gelir; MAS kipi doğrudan denetlenir.
        #expect(flavor.contains("selectable(mas: BuildFlavor.isMAS)"))
        #expect(AIProviderKind.selectable(mas: true) == [.anthropic, .apple])
        #expect(!AIProviderKind.selectable(mas: true).contains(.local))
        // Kayıt eklemesi yalnız `#if !MAS` içinde: MAS başlatıcısının kaydında yerel sağlayıcı yok.
        let motor = try String(contentsOf: kok.appending(path: "Sources/MarkaCore/AI/ChatEngine.swift"), encoding: .utf8)
        let masInit = try #require(motor.components(separatedBy: "/// MAS derlemesi: Codex süreci").dropFirst().first?
            .components(separatedBy: "#endif").first)
        #expect(!masInit.contains("LocalSettingsProvider"))
        #endif
    }
}
