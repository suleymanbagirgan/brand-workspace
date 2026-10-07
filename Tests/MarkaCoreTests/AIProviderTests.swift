import Foundation
import Testing
@testable import MarkaCore

/// Testler için sahte sağlayıcı: kayıtlı turları sırayla oynatır, araç çağrısı üretebilir, çağrıları sayar.
/// Her "model isteği"nden önce gerçek sağlayıcılar gibi `turn.checkCancellation()` çağırır; araçları ChatEngine'in
/// yürütücüsüne (`turn.callTool`) verir, kendisi çalıştırmaz.
final class FakeProvider: AIProvider, @unchecked Sendable {
    enum Step: Sendable {
        case text(String)
        case tool(String, JSONValue)
        /// Adım sırasında çalışacak kanca (ör. kullanıcının "Durdur"a basması).
        case hook(@Sendable () async -> Void)
    }

    let kind: AIProviderKind
    let capabilities: AIProviderCapabilities
    private let lock = NSLock()
    private var rounds: [[Step]]
    private var _requestCount = 0
    private var _cancelCount = 0
    private var _offeredTools: [[String]] = []
    private var _toolResults: [ToolResult] = []

    init(kind: AIProviderKind = .anthropic, supportsTools: Bool = true, rounds: [[Step]]) {
        self.kind = kind
        self.capabilities = AIProviderCapabilities(supportsTools: supportsTools, contextTokens: 4096, onDevice: true, needsAPIKey: false)
        self.rounds = rounds
    }

    var requestCount: Int { lock.withLock { _requestCount } }
    var cancelCount: Int { lock.withLock { _cancelCount } }
    var offeredTools: [[String]] { lock.withLock { _offeredTools } }
    var toolResults: [ToolResult] { lock.withLock { _toolResults } }

    func sessionModel(settings: AISettings) -> String { "sahte-model" }
    func cancel(sessionId: String) async { lock.withLock { _cancelCount += 1 } }

    private func nextRound(tools: [ToolSpec]) -> [Step]? {
        lock.withLock {
            guard !rounds.isEmpty else { return nil }
            _requestCount += 1
            _offeredTools.append(tools.map(\.name))
            return rounds.removeFirst()
        }
    }

    func runTurn(_ turn: AITurn, assistant: inout AIMessage) async throws {
        while true {
            try turn.checkCancellation()
            guard let round = nextRound(tools: turn.tools) else { break }
            for step in round {
                switch step {
                case .text(let t):
                    assistant.text += t
                    turn.emit(.textDelta(t))
                case .tool(let name, let input):
                    let r = await turn.callTool(name, input)
                    lock.withLock { _toolResults.append(r) }
                    turn.emit(.event(r.event))
                case .hook(let h):
                    await h()
                }
            }
        }
    }
}

/// Kancadan motora ulaşmak için (motor sağlayıcıdan sonra kurulur).
final class EngineRef: @unchecked Sendable {
    var engine: ChatEngine?
    var sessionId = ""
}

@Suite struct AIProviderTests {
    func engine(store: Store, providers: [any AIProvider]) throws -> ChatEngine {
        ChatEngine(store: store, codex: CodexAppServer(), folders: BrandFolders(root: try tempDir("folders"), store: store),
                   workspace: try tempDir("ws"), settings: AISettings(), anthropicKey: { nil }, urlSession: .shared,
                   diagnostics: nil, providers: providers)
    }

    struct TurOzeti { var text = ""; var titles: [String] = []; var failures: [String] = [] }

    func gonder(_ e: ChatEngine, _ sessionId: String, _ text: String) async -> TurOzeti {
        var o = TurOzeti()
        for await ev in await e.send(sessionId: sessionId, text: text) {
            switch ev {
            case .textDelta(let t): o.text += t
            case .event(let r): o.titles.append(r.title)
            case .failed(let m): o.failures.append(m)
            default: break
            }
        }
        return o
    }

    @Test func sahteSaglayiciAracDongusuOneriUretirVeGecmisiKaydeder() async throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Deneme Yangın")
        try store.setAIProviders(b.id, providers: [.anthropic])
        let src = try store.addTextSource(brandId: b.id, kind: .clientRequest, title: "Teklif talebi", body: "42 yangın dolabı için teklif istendi.")
        let fake = FakeProvider(rounds: [
            [.text("Kaynağa bakıyorum."), .tool("kaynak_ara", ["sorgu": "teklif"]), .tool("gorev_oner", ["baslik": "Teklifi kontrol et"])],
            [.text("Görev önerdim.")],
        ])
        let e = try engine(store: store, providers: [fake])
        let session = try await e.createSession(scope: .brand(b.id), provider: .anthropic, title: "Yeni oturum")
        #expect(session.model == "sahte-model")
        let o = await gonder(e, session.id, "Teklifi tamamla")
        #expect(o.failures.isEmpty)
        #expect(fake.requestCount == 2)
        #expect(o.text == "Kaynağa bakıyorum.Görev önerdim.")
        #expect(fake.toolResults.count == 2 && fake.toolResults.allSatisfy { !$0.isError })
        #expect(fake.toolResults.first?.text.contains(src.id) == true)
        #expect(fake.offeredTools.first?.contains("gorev_oner") == true)
        #expect(try store.proposals(sessionId: session.id).map(\.kind) == [.createTask])
        let stored = try await e.messages(sessionId: session.id)
        #expect(stored.map(\.role) == [.user, .assistant])
        #expect(stored[1].state == .complete)
        #expect(stored[1].eventsJSON.contains("Teklifi kontrol et"))
    }

    @Test func sahteSaglayicidaBaskaMarkaKimligiAracYurutucudeReddedilir() async throws {
        let store = try makeStore()
        let a = try store.createBrand(name: "Kuzey Lojistik")
        let b = try store.createBrand(name: "Örnek Kafe Zinciri")
        try store.setAIProviders(a.id, providers: [.anthropic])
        try store.setAIProviders(b.id, providers: [.anthropic])
        let srcB = try store.addTextSource(brandId: b.id, kind: .note, title: "B gizli", body: "GIZLI-BUTCE-B")
        let fake = FakeProvider(rounds: [[.tool("kaynak_oku", ["kaynak_id": .string(srcB.id)])], [.text("Tamam.")]])
        let e = try engine(store: store, providers: [fake])
        let session = try await e.createSession(scope: .brand(a.id), provider: .anthropic, title: "x")
        _ = await gonder(e, session.id, "B'nin kaynağını oku")
        let r = try #require(fake.toolResults.first)
        #expect(r.isError)
        #expect(!r.text.contains("GIZLI-BUTCE-B"))
        let stored = try await e.messages(sessionId: session.id)
        #expect(!stored.map(\.eventsJSON).joined().contains("GIZLI-BUTCE-B"))
        #expect(try store.proposals(brandId: a.id).isEmpty && store.proposals(brandId: b.id).isEmpty)
    }

    /// A-19: araç turları arasında durdurma → yeni sağlayıcı isteği 0, yeni öneri 0.
    @Test func iptalSonrasiYeniSaglayiciIstegiVeYeniOneriYok() async throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Deneme Yangın")
        try store.setAIProviders(b.id, providers: [.anthropic])
        let ref = EngineRef()
        let fake = FakeProvider(rounds: [
            [.tool("gorev_oner", ["baslik": "Birinci"]),
             .hook({ await ref.engine?.cancel(sessionId: ref.sessionId) }),
             .tool("gorev_oner", ["baslik": "İkinci"])],
            [.tool("gorev_oner", ["baslik": "Üçüncü"]), .text("Bitti.")],
        ])
        let e = try engine(store: store, providers: [fake])
        ref.engine = e
        let session = try await e.createSession(scope: .brand(b.id), provider: .anthropic, title: "x")
        ref.sessionId = session.id
        let o = await gonder(e, session.id, "Görevleri öner")
        #expect(fake.requestCount == 1)              // durdurmadan sonra yeni istek yok
        #expect(fake.cancelCount == 1)               // sağlayıcı tarafında da durduruldu
        #expect(try store.proposals(sessionId: session.id).map(\.summary).count == 1)   // yalnız durdurmadan önceki öneri
        #expect(fake.toolResults.last?.isError == true)
        #expect(o.titles.contains(L("Durduruldu")))
        #expect(!o.text.contains("Bitti."))
        let stored = try await e.messages(sessionId: session.id)
        #expect(stored.last?.state == .partial)
        #expect(await e.isRunning(sessionId: session.id) == false)
    }

    /// AI veri değiştirmez: araç döngüsü yalnız bekleyen öneri bırakır; görev oluşmaz, uygulanmış öneri yoktur.
    @Test func sahteSaglayiciTuruUygulanmisOneriBirakmaz() async throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Deneme Yangın")
        try store.setAIProviders(b.id, providers: [.anthropic])
        let fake = FakeProvider(rounds: [[
            .tool("gorev_oner", ["baslik": "Teklif hazırla"]),
            .tool("calisma_kaydi_oner", ["baslik": "Teklif yazıldı", "ne_istendi": "Teklif", "ne_yapildi": "Taslak hazırlandı"]),
        ], [.text("Önerdim.")]])
        let e = try engine(store: store, providers: [fake])
        let session = try await e.createSession(scope: .brand(b.id), provider: .anthropic, title: "x")
        _ = await gonder(e, session.id, "Öner")
        let proposals = try store.proposals(sessionId: session.id)
        #expect(proposals.count == 2 && proposals.contains { $0.kind == .createWorkLog })
        #expect(proposals.allSatisfy { $0.status == .pending })
        #expect(try store.recentlyAppliedProposals(brandId: b.id).isEmpty)
        #expect(try store.tasks(brandId: b.id).isEmpty)
    }

    @Test func aracDesteklemeyenSaglayiciAracsizTurCalistirir() async throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Deneme Yangın")
        try store.setAIProviders(b.id, providers: [.anthropic])
        let fake = FakeProvider(supportsTools: false, rounds: [[.text("Araçsız yanıt."), .tool("gorev_oner", ["baslik": "Sızmamalı"])]])
        let e = try engine(store: store, providers: [fake])
        let session = try await e.createSession(scope: .brand(b.id), provider: .anthropic, title: "x")
        let o = await gonder(e, session.id, "merhaba")
        #expect(o.failures.isEmpty)
        #expect(fake.offeredTools == [[]])
        #expect(fake.toolResults.first?.isError == true)
        #expect(try store.proposals(sessionId: session.id).isEmpty)
        #expect(try await e.messages(sessionId: session.id).last?.state == .complete)
    }

    @Test func kayitliOlmayanSaglayiciReddedilirVeIstekGitmez() async throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Deneme Yangın")
        try store.setAIProviders(b.id, providers: [.anthropic, .codex])
        let fake = FakeProvider(kind: .anthropic, rounds: [[.text("x")]])
        let e = try engine(store: store, providers: [fake])
        await #expect(throws: MarkaError.self) { _ = try await e.createSession(scope: .brand(b.id), provider: .codex, title: "x") }
        // Eski veri tabanından gelen (kayıtta sağlayıcısı olmayan) oturum.
        let s = AISession(brandId: b.id, scope: .brand, provider: .codex, model: "codex", title: "x")
        try store.write { db in try s.insert(db) }
        let o = await gonder(e, s.id, "merhaba")
        #expect(o.failures == [L("Bu sağlayıcı bu sürümde kullanılamaz.")])
        #expect(fake.requestCount == 0)
        #expect(try await e.messages(sessionId: s.id).last?.state == .failed)
    }

    @Test func saglayiciKaydiTekYerdeSecerVeYetenekleriBildirir() throws {
        let anthropic = AnthropicProvider(anthropicKey: { nil }, urlSession: .shared)
        #expect(anthropic.capabilities == AIProviderCapabilities(supportsTools: true, contextTokens: nil, onDevice: false, needsAPIKey: true))
        let codex = CodexProvider(isolation: BrandIsolation(workspace: try tempDir("ws"), folders: BrandFolders(root: try tempDir("f"), store: try makeStore())))
        #expect(codex.capabilities.supportsTools && !codex.capabilities.needsAPIKey && !codex.capabilities.onDevice)
        let registry = AIProviderRegistry([anthropic, codex])
        #expect(try registry.provider(for: .anthropic).kind == .anthropic)
        #expect(try registry.provider(for: .codex).kind == .codex)
        #expect(throws: MarkaError.self) { try AIProviderRegistry([anthropic]).provider(for: .codex) }
        #expect(anthropic.sessionModel(settings: AISettings(anthropicModel: "claude-haiku-4-5")) == "claude-haiku-4-5")
        #expect(codex.sessionModel(settings: AISettings()) == "codex")
    }
}
