import Foundation
import Testing
@testable import MarkaCore

/// Kayıtlı SSE yanıtlarını sırayla döndüren sahte HTTP katmanı.
final class MockAnthropic: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responses: [String] = []
    nonisolated(unsafe) static var requests: [JSONValue] = []
    nonisolated(unsafe) static var headers: [[String: String]] = []
    nonisolated(unsafe) static var urls: [URL] = []
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { ["api.anthropic.com", "vekil.test"].contains(request.url?.host) }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open(); var d = Data(); var buf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&buf, maxLength: 4096); if n <= 0 { break }; d.append(buf, count: n) }
            stream.close(); body = d
        }
        if let body, let json = try? JSONValue.parse(body) { Self.requests.append(json) }
        Self.headers.append(request.allHTTPHeaderFields ?? [:])
        if let url = request.url { Self.urls.append(url) }
        let sse = Self.responses.isEmpty ? "" : Self.responses.removeFirst()
        Self.lock.unlock()
        let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["content-type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(sse.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    static func sse(_ events: [JSONValue]) -> String {
        events.map { "event: \($0["type"]?.string ?? "")\ndata: \($0.compactString())\n\n" }.joined()
    }
}

@Suite(.serialized) struct AITests {
    func engine(store: Store) -> ChatEngine {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockAnthropic.self]
        return ChatEngine(store: store, codex: CodexAppServer(), folders: BrandFolders(root: try! tempDir("folders"), store: store),
                          workspace: try! tempDir("ws"), settings: AISettings(), anthropicKey: { "test-anahtar" }, urlSession: URLSession(configuration: config))
    }

    @Test func izinVerilmeyenSaglayiciyaOturumAcilamaz() async throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Gizli")
        let e = engine(store: store)
        await #expect(throws: MarkaError.self) { try await e.createSession(scope: .brand(b.id), provider: .anthropic, title: "x") }
        try store.setAIProviders(b.id, providers: [.codex])
        await #expect(throws: MarkaError.self) { try await e.createSession(scope: .brand(b.id), provider: .anthropic, title: "x") }
    }

    @Test func akisAracDongusuOneriVeGecmis() async throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Örnek Yangın")
        let other = try store.createBrand(name: "Diğer Marka")
        try store.addTextSource(brandId: other.id, kind: .note, title: "Diğer gizli", body: "teklif bütçesi gizli")
        try store.setAIProviders(b.id, providers: [.anthropic])
        let src = try store.addTextSource(brandId: b.id, kind: .clientRequest, title: "Teklif talebi", body: "42 yangın dolabı için teklif istendi.")

        MockAnthropic.requests = []
        MockAnthropic.responses = [
            MockAnthropic.sse([
                ["type": "message_start", "message": ["model": "claude-opus-5", "usage": ["input_tokens": 1000, "output_tokens": 1]]],
                ["type": "content_block_start", "index": 0, "content_block": ["type": "thinking", "thinking": "", "signature": ""]],
                ["type": "content_block_delta", "index": 0, "delta": ["type": "signature_delta", "signature": "imza"]],
                ["type": "content_block_stop", "index": 0],
                ["type": "content_block_start", "index": 1, "content_block": ["type": "text", "text": ""]],
                ["type": "content_block_delta", "index": 1, "delta": ["type": "text_delta", "text": "Kaynağa "]],
                ["type": "content_block_delta", "index": 1, "delta": ["type": "text_delta", "text": "bakıyorum."]],
                ["type": "content_block_stop", "index": 1],
                ["type": "content_block_start", "index": 2, "content_block": ["type": "tool_use", "id": "tu_1", "name": "kaynak_ara", "input": [:]]],
                ["type": "content_block_delta", "index": 2, "delta": ["type": "input_json_delta", "partial_json": "{\"sorgu\": \"te"]],
                ["type": "content_block_delta", "index": 2, "delta": ["type": "input_json_delta", "partial_json": "klif\"}"]],
                ["type": "content_block_stop", "index": 2],
                ["type": "content_block_start", "index": 3, "content_block": ["type": "tool_use", "id": "tu_2", "name": "gorev_oner", "input": [:]]],
                ["type": "content_block_delta", "index": 3, "delta": ["type": "input_json_delta", "partial_json": "{\"baslik\": \"Teklifi kontrol et\", \"son_tarih\": \"2026-09-19\"}"]],
                ["type": "content_block_stop", "index": 3],
                ["type": "message_delta", "delta": ["stop_reason": "tool_use"], "usage": ["output_tokens": 120]],
                ["type": "message_stop"],
            ]),
            MockAnthropic.sse([
                ["type": "message_start", "message": ["model": "claude-opus-5", "usage": ["input_tokens": 300, "cache_read_input_tokens": 900, "output_tokens": 1]]],
                ["type": "content_block_start", "index": 0, "content_block": ["type": "text", "text": ""]],
                ["type": "content_block_delta", "index": 0, "delta": ["type": "text_delta", "text": "Görev önerdim."]],
                ["type": "content_block_stop", "index": 0],
                ["type": "message_delta", "delta": ["stop_reason": "end_turn"], "usage": ["output_tokens": 20]],
                ["type": "message_stop"],
            ]),
        ]
        let e = engine(store: store)
        let session = try await e.createSession(scope: .brand(b.id), provider: .anthropic, title: "Yeni oturum")
        var text = ""
        var eventTitles: [String] = []
        for await ev in await e.send(sessionId: session.id, text: "Teklifi tamamla") {
            switch ev {
            case .textDelta(let t): text += t
            case .event(let r): eventTitles.append(r.title)
            case .failed(let m): Issue.record("Beklenmeyen hata: \(m)")
            default: break
            }
        }
        #expect(text.contains("Kaynağa bakıyorum.") && text.contains("Görev önerdim."))
        #expect(eventTitles.contains { $0.contains("Arandı") })
        let proposals = try store.proposals(sessionId: session.id)
        #expect(proposals.map(\.kind) == [.createTask])
        #expect(proposals.first?.status == .pending)

        // İkinci istekte araç sonucu doğru kimlikle döndü; başka markanın kaynağı sızmadı.
        #expect(MockAnthropic.requests.count == 2)
        let second = MockAnthropic.requests[1]
        let msgs = second["messages"]?.array ?? []
        let toolResults = msgs.last?["content"]?.array ?? []
        #expect(toolResults.map { $0["tool_use_id"]?.string } == ["tu_1", "tu_2"])
        #expect(toolResults.first?["content"]?.string?.contains(src.id) == true)
        #expect(second.compactString().contains("Diğer gizli") == false)
        #expect(second["system"]?.string?.contains("Örnek Yangın") == true)
        #expect(second["fallbacks"]?.string == "default")

        // Kalıcı geçmiş: kullanıcı + asistan; ham bloklar (thinking imzası dahil) sonraki tura aynen döner.
        let stored = try await e.messages(sessionId: session.id)
        #expect(stored.map(\.role) == [.user, .assistant])
        #expect(stored[1].state == .complete)
        #expect(stored[1].costMicros > 0)
        let rebuilt = try await e.history(sessionId: session.id, excludingLastUser: false)
        #expect(rebuilt.count == 4) // kullanıcı, asistan(araç), kullanıcı(araç sonucu), asistan
        #expect(rebuilt[1].compactString().contains("imza"))
        let usage = try store.read { db in try UsageEntry.fetchAll(db) }
        #expect(usage.count == 2)
        #expect(usage.allSatisfy { $0.brandId == b.id && $0.costMicros != nil })
    }

    static func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockAnthropic.self]
        return URLSession(configuration: config)
    }

    static let kisaYanit = MockAnthropic.sse([
        ["type": "message_start", "message": ["model": "m", "usage": ["input_tokens": 10, "output_tokens": 1]]],
        ["type": "content_block_start", "index": 0, "content_block": ["type": "text", "text": ""]],
        ["type": "content_block_delta", "index": 0, "delta": ["type": "text_delta", "text": "Tamam."]],
        ["type": "content_block_stop", "index": 0],
        ["type": "message_delta", "delta": ["stop_reason": "end_turn"], "usage": ["output_tokens": 2]],
    ])

    // Belge: effort Haiku 4.5'te desteklenmez (platform.claude.com/docs/en/build-with-claude/effort);
    // Haiku adaptive thinking almaz (about-claude/models/overview: "Extended"); fallbacks beta başlığıyla (api/beta/messages/create).
    @Test func haikuIstegiDesteklenmeyenAlanGondermez() async throws {
        MockAnthropic.requests = []; MockAnthropic.headers = []
        MockAnthropic.responses = [Self.kisaYanit,
            #"{"type":"message","content":[{"type":"text","text":"{}"}],"stop_reason":"end_turn","usage":{"input_tokens":5,"output_tokens":1}}"#]
        let c = AnthropicClient(apiKey: "k", model: "claude-haiku-4-5-20251001", effort: "low", maxTokensCap: 1024, session: Self.mockSession())
        _ = try await c.streamTurn(system: "s", messages: [["role": "user", "content": "x"]], tools: ToolCatalog.brandTools, onText: { _ in })
        _ = try await c.completeJSON(system: "s", user: "x", schema: ["type": "object", "additionalProperties": false, "properties": [:], "required": []])
        #expect(MockAnthropic.requests.count == 2)
        for body in MockAnthropic.requests {
            #expect(body["output_config"]?["effort"] == nil)
            #expect(body["thinking"] == nil)
            #expect(body["fallbacks"] == nil)
            #expect(body["max_tokens"]?.int == 1024)
        }
        #expect(MockAnthropic.requests[1]["output_config"]?["format"]?["type"]?.string == "json_schema")
        #expect(MockAnthropic.headers.allSatisfy { $0["anthropic-beta"] == nil && $0["anthropic-version"] == "2023-06-01" })
    }

    @Test func opus5IstegiEffortDusunmeVeYedekModelTasir() async throws {
        MockAnthropic.requests = []; MockAnthropic.headers = []
        MockAnthropic.responses = [Self.kisaYanit]
        let c = AnthropicClient(apiKey: "k", model: "claude-opus-5", effort: "xhigh", maxTokensCap: 64_000, session: Self.mockSession())
        _ = try await c.streamTurn(system: "s", messages: [["role": "user", "content": "x"]], tools: [], onText: { _ in })
        let body = try #require(MockAnthropic.requests.first)
        #expect(body["output_config"]?["effort"]?.string == "xhigh")
        #expect(body["thinking"]?["type"]?.string == "adaptive")
        #expect(body["fallbacks"]?.string == "default")
        #expect(body["max_tokens"]?.int == 32000) // sınır varsayılandan büyükse varsayılan kalır
        #expect(MockAnthropic.headers.first?["anthropic-beta"] == "server-side-fallback-2026-07-01")
    }

    @Test func anahtarDogrulamaSayilanTokeniDondurur() async throws {
        MockAnthropic.requests = []; MockAnthropic.urls = []
        MockAnthropic.responses = [#"{"input_tokens": 14}"#]
        let n = try await AnthropicClient(apiKey: "k", model: "claude-haiku-4-5-20251001", session: Self.mockSession()).verifyKey()
        #expect(n == 14)
        #expect(MockAnthropic.urls.first?.path == "/v1/messages/count_tokens")
        #expect(MockAnthropic.requests.first?["model"]?.string == "claude-haiku-4-5-20251001")
    }

    @Test func sohbetAyarlariTokenSiniriVeAdresiIstemciyeGecer() async throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "A")
        try store.setAIProviders(b.id, providers: [.anthropic])
        MockAnthropic.requests = []; MockAnthropic.urls = []
        MockAnthropic.responses = [Self.kisaYanit]
        let e = ChatEngine(store: store, codex: CodexAppServer(), folders: BrandFolders(root: try tempDir("folders"), store: store),
                           workspace: try tempDir("ws"),
                           settings: AISettings(anthropicModel: "claude-haiku-4-5-20251001", anthropicEffort: "medium", anthropicMaxTokens: 512,
                                                anthropicBaseURL: URL(string: "https://vekil.test")!),
                           anthropicKey: { "k" }, urlSession: Self.mockSession())
        let session = try await e.createSession(scope: .brand(b.id), provider: .anthropic, title: "x")
        for await ev in await e.send(sessionId: session.id, text: "merhaba") {
            if case .failed(let m) = ev { Issue.record("Beklenmeyen hata: \(m)") }
        }
        #expect(MockAnthropic.urls.first?.host == "vekil.test")
        #expect(MockAnthropic.requests.first?["max_tokens"]?.int == 512)
        #expect(MockAnthropic.requests.first?["output_config"] == nil)
    }

    @Test func baskaMarkaKimligiIleAracReddedilir() throws {
        let store = try makeStore()
        let a = try store.createBrand(name: "A")
        let b = try store.createBrand(name: "B")
        let srcB = try store.addTextSource(brandId: b.id, kind: .note, title: "B gizli", body: "gizli")
        let exec = ToolExecutor(store: store, scope: .brand(a.id), sessionId: nil)
        let r = exec.run(name: "kaynak_oku", input: ["kaynak_id": .string(srcB.id)])
        #expect(r.isError)
        #expect(!r.text.contains("gizli\n"))
        let r2 = exec.run(name: "genel_bakis", input: [:])
        #expect(r2.isError) // marka kapsamında tüm markalar aracı yok
        let all = ToolExecutor(store: store, scope: .allBrands, sessionId: nil, allowedBrandIds: [a.id])
        #expect(all.run(name: "kaynak_ara", input: ["sorgu": "gizli"]).text == "Sonuç yok.")
        #expect(all.run(name: "gorev_oner", input: ["baslik": "x"]).isError)
    }

    @Test func bilgiDerleyiciGecersizIddiayiReddeder() throws {
        let store = try makeStore()
        let a = try store.createBrand(name: "A")
        let b = try store.createBrand(name: "B")
        let srcA = try store.addTextSource(brandId: a.id, kind: .meeting, title: "Toplantı", body: "Karar verici Ayşe")
        let srcB = try store.addTextSource(brandId: b.id, kind: .note, title: "B", body: "x")
        let json: JSONValue = ["sayfalar": [
            ["sayfa_id": "", "tur": "person", "baslik": "Ayşe", "govde": "Karar verici", "baglantilar": [],
             "iddialar": [["metin": "Karar verici", "kaynak_id": .string(srcA.id), "durum": "current", "not": ""]]],
            ["sayfa_id": "", "tur": "goal", "baslik": "Sızıntı", "govde": "x", "baglantilar": [],
             "iddialar": [["metin": "Başka marka", "kaynak_id": .string(srcB.id), "durum": "current", "not": ""]]],
            ["sayfa_id": "", "tur": "goal", "baslik": "Uydurma", "govde": "x", "baglantilar": [],
             "iddialar": [["metin": "Kaynaksız", "kaynak_id": "", "durum": "current", "not": ""]]],
        ]]
        let usage = UsageEntry(provider: .anthropic, model: "claude-opus-5", sessionId: nil, brandId: a.id, purpose: "wiki", inputTokens: 1, outputTokens: 1, costMicros: 0)
        let out = try KnowledgeCompiler(store: store).apply(json: json, brandId: a.id, usage: usage)
        #expect(out.proposedRevisions.count == 1)
        #expect(out.rejected.count == 2)
        #expect(try store.pendingRevisions(brandId: a.id).count == 1)
        #expect(try store.wikiPages(brandId: a.id).first?.currentRevisionId == nil) // onaylanmadan güncel değil
    }

    @Test func betaOlcumleri() throws {
        let store = try makeStore()
        let start = Date().addingTimeInterval(-3600)
        try store.setSetting(BetaMetrics.firstLaunchKey, ISO8601DateFormatter().string(from: start))
        let b = try store.createBrand(name: "B")
        try store.addTextSource(brandId: b.id, kind: .note, title: "n", body: "x")
        let p = try store.createProposal(sessionId: nil, brandId: b.id, kind: .createTask, summary: "x", payload: ProposalPayload.CreateTask(title: "x"))
        try store.rejectProposal(p.id)
        let m = try BetaMetrics.compute(store: store)
        #expect((m.setupMinutes ?? 0) > 59 && (m.setupMinutes ?? 0) < 61)
        #expect(m.proposalsRejected == 1)
        #expect(m.activeDaysLast14 == 1)
        #expect(!m.shareableSummary.contains("B\n"))
    }

    @Test func codexDurunceSurenTurAsiliKalmaz() async throws {
        let server = CodexAppServer()
        let state = CodexTurnState()
        await server.register(threadId: "t1", notifications: { await state.handle($0, emit: { _ in }) }, requests: { _, _ in [:] })
        await server.stop()
        let outcome = await state.waitForCompletion()
        #expect(outcome.status == "failed")
        #expect(outcome.error?.isEmpty == false)
    }

    @Test func maliyetTahmini() {
        #expect(PriceTable.costMicros(model: "claude-opus-5", input: 1_000_000, output: 0, cacheRead: 0, cacheWrite: 0) == 5_000_000)
        #expect(PriceTable.costMicros(model: "claude-sonnet-5", input: 0, output: 1_000_000, cacheRead: 1_000_000, cacheWrite: 0) == 10_200_000)
        #expect(PriceTable.costMicros(model: "bilinmeyen", input: 1, output: 1, cacheRead: 0, cacheWrite: 0) == nil)
    }

    @Test func klasorFarkiEklenenVeDegisenDosyalar() throws {
        let before: [String: BrandFolders.FileState] = ["a.md": .init(modified: Date(timeIntervalSince1970: 1), size: 1), "b.md": .init(modified: Date(timeIntervalSince1970: 1), size: 1)]
        let after: [String: BrandFolders.FileState] = ["a.md": .init(modified: Date(timeIntervalSince1970: 2), size: 3), "c.md": .init(modified: Date(timeIntervalSince1970: 1), size: 1)]
        let d = BrandFolders.diff(before: before, after: after)
        #expect(d.map(\.path) == ["a.md", "c.md", "b.md"])
        #expect(d.map(\.change) == ["modified", "added", "deleted"])
    }
}
