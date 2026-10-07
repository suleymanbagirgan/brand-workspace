import Foundation
import GRDB

public struct AISettings: Sendable, Hashable {
    public var anthropicModel: String
    public var anthropicEffort: String?
    public var codexModel: String?
    /// Anthropic isteklerinin `max_tokens` üst sınırı; nil ise istemcinin varsayılanı. Doğrulama aracı maliyeti sınırlamak için kullanır.
    public var anthropicMaxTokens: Int?
    /// Varsayılan dışı API adresi (yalnızca doğrulama aracı; uygulama kullanmaz).
    public var anthropicBaseURL: URL?
    /// Bu Mac'teki model (E-11): geri döngü adresi ve model adı. İkisi de yoksa yerel sağlayıcı ayarlanmamıştır.
    /// Yalnız `LocalModelPreferences` doğrulayarak doldurur; MAS derlemesinde kullanılmaz.
    public var localBaseURL: String?
    public var localModel: String?
    /// Yanıt uzunluğu (E-20): istem parçasını ve Anthropic `max_tokens` tavanını belirler.
    public var responseLength: ResponseLength
    public init(anthropicModel: String = PriceTable.defaultAnthropicModel, anthropicEffort: String? = nil, codexModel: String? = nil,
                anthropicMaxTokens: Int? = nil, anthropicBaseURL: URL? = nil, localBaseURL: String? = nil, localModel: String? = nil,
                responseLength: ResponseLength = .normal) {
        self.anthropicModel = anthropicModel; self.anthropicEffort = anthropicEffort; self.codexModel = codexModel
        self.anthropicMaxTokens = anthropicMaxTokens; self.anthropicBaseURL = anthropicBaseURL
        self.localBaseURL = localBaseURL; self.localModel = localModel; self.responseLength = responseLength
    }
}

/// Sohbet motoru: sağlayıcı izni, bağlam, araç yürütme, onaylar, iptal ve kalıcı geçmiş. Modelle konuşma `AIProvider`'dadır
/// (`AnthropicProvider`, `CodexProvider`); hangi sağlayıcının çalışacağı yalnız `AIProviderRegistry`'den seçilir.
public actor ChatEngine {
    public static let anthropicKeyAccount = "anthropic-api-key"
    /// Yanıt saklanamadığında olaya yazılan tür (`refId`) ve açıklama (H3-03).
    public static let unsavedReplyRef = "yanit-kaydedilemedi"
    static var unsavedReplyDetail: String { L("Yanıt bu oturuma kaydedilemedi; oturumu yeniden açtığında görünmeyebilir. Gerekirse metni şimdi kopyala.") }

    let store: Store
    #if !MAS
    /// Yalıtımsız Codex süreci: yalnızca hesap, giriş ve model listesi. Tur çalıştırmaz.
    public let codex: CodexAppServer
    public let isolation: BrandIsolation
    /// Yalıtımlı Codex süreçlerinin sahibi (sohbet turu + rapor/bilgi derleme süreçleri).
    let codexProvider: CodexProvider
    #endif
    let folders: BrandFolders
    var settings: AISettings
    let registry: AIProviderRegistry
    private let approvals = ApprovalBroker()
    private var running: [String: Task<Void, Never>] = [:]
    private var cancellations: [String: TurnCancellation] = [:]
    let anthropicKey: @Sendable () -> String?
    let urlSession: URLSession
    /// Sağlayıcı hataları buraya içeriksiz kaydedilir (tür + yer; mesaj değil).
    let diagnostics: DiagnosticsLog?
    /// E-30: tur sonunda içeriksiz iz buraya yazılır (bellek içi, diske yazılmaz). Testler kendi tamponunu verir.
    var turnTraces: TurnTraces = .shared
    func useTurnTraces(_ traces: TurnTraces) { turnTraces = traces }

    #if !MAS
    public init(store: Store, codex: CodexAppServer, folders: BrandFolders, workspace: URL, settings: AISettings,
                anthropicKey: @escaping @Sendable () -> String? = { Keychain.load(account: ChatEngine.anthropicKeyAccount) },
                urlSession: URLSession = .shared, diagnostics: DiagnosticsLog? = nil) {
        self.init(store: store, codex: codex, folders: folders, workspace: workspace, settings: settings, anthropicKey: anthropicKey,
                  urlSession: urlSession, diagnostics: diagnostics, providers: nil)
    }

    /// `providers` verilirse (testler) sağlayıcı kaydı yalnız bunlardan oluşur; `nil` ise Anthropic + Codex.
    init(store: Store, codex: CodexAppServer, folders: BrandFolders, workspace: URL, settings: AISettings,
         anthropicKey: @escaping @Sendable () -> String?, urlSession: URLSession, diagnostics: DiagnosticsLog?, providers: [any AIProvider]?) {
        self.store = store; self.codex = codex; self.folders = folders; self.settings = settings
        let isolation = BrandIsolation(workspace: workspace, folders: folders)
        self.isolation = isolation
        self.anthropicKey = anthropicKey; self.urlSession = urlSession; self.diagnostics = diagnostics
        let codexProvider = CodexProvider(isolation: isolation, diagnostics: diagnostics)
        self.codexProvider = codexProvider
        // E-11: yerel sağlayıcı yalnız doğrudan dağıtımda kayıtlı; ayarı her turda `AISettings`'ten okunur.
        self.registry = AIProviderRegistry(providers ?? [AnthropicProvider(anthropicKey: anthropicKey, urlSession: urlSession), codexProvider,
                                                         LocalSettingsProvider(), AppleFoundationModelsProvider()])   // E-25: Apple cihaz üstü
    }
    #else
    /// MAS derlemesi: Codex süreci ve seatbelt yalıtımı yok; yalnız Anthropic.
    public init(store: Store, folders: BrandFolders, workspace: URL, settings: AISettings,
                anthropicKey: @escaping @Sendable () -> String? = { Keychain.load(account: ChatEngine.anthropicKeyAccount) },
                urlSession: URLSession = .shared, diagnostics: DiagnosticsLog? = nil) {
        self.init(store: store, folders: folders, workspace: workspace, settings: settings, anthropicKey: anthropicKey,
                  urlSession: urlSession, diagnostics: diagnostics, providers: nil)
    }

    init(store: Store, folders: BrandFolders, workspace: URL, settings: AISettings,
         anthropicKey: @escaping @Sendable () -> String?, urlSession: URLSession, diagnostics: DiagnosticsLog?, providers: [any AIProvider]?) {
        self.store = store; self.folders = folders; self.settings = settings
        self.anthropicKey = anthropicKey; self.urlSession = urlSession; self.diagnostics = diagnostics
        self.registry = AIProviderRegistry(providers ?? [AnthropicProvider(anthropicKey: anthropicKey, urlSession: urlSession),
                                                         AppleFoundationModelsProvider()])   // E-25: MAS'ta da (ağ/süreç yok)
    }
    #endif

    #if !MAS
    // MARK: Yalıtımlı Codex süreçleri (CodexProvider'a iletilir)

    /// Kapsamın yalıtımlı Codex süreci; gerekirse başlatılır. Profil başlatma anında üretilir ve ölçülerek doğrulanır.
    public func codexServer(for scope: SessionScope) async throws -> CodexAppServer {
        try await codexProvider.codexServer(for: scope)
    }

    /// Yapılandırılmış iş (rapor özeti/bilgi derleme) süresince kapsamın Codex sürecini alır ve "meşgul" işaretler; iş bitince
    /// `releaseCodexServer` çağrılmalı (boştaki süreç durdurma bu süreci öldürmesin). Süren derleme turu böyle korunur.
    public func retainCodexServer(for scope: SessionScope) async throws -> CodexAppServer {
        try await codexProvider.retainCodexServer(for: scope)
    }

    public func releaseCodexServer(for scope: SessionScope) async {
        await codexProvider.releaseCodexServer(for: scope)
    }

    /// Tüm yalıtımlı Codex süreçlerini durdurur (çıkış yapıldığında ya da çalışma alanı kapanırken).
    public func stopCodexServers() async {
        await codexProvider.stopCodexServers()
    }
    #endif

    public func update(settings: AISettings) { self.settings = settings }

    public func sessions(scope: SessionScope) throws -> [AISession] {
        try store.read { db in
            switch scope {
            case .brand(let id): try AISession.filter(Column("brandId") == id).order(Column("updatedAt").desc).fetchAll(db)
            case .allBrands: try AISession.filter(Column("scope") == AIScope.allBrands.rawValue).order(Column("updatedAt").desc).fetchAll(db)
            }
        }
    }

    public func messages(sessionId: String) throws -> [AIMessage] { try Self.messages(store: store, sessionId: sessionId) }

    static func messages(store: Store, sessionId: String) throws -> [AIMessage] {
        try store.read { db in try AIMessage.filter(Column("sessionId") == sessionId).order(Column("createdAt")).fetchAll(db) }
    }

    /// Kapsamda kullanılabilecek markalar (sağlayıcı izni olanlar).
    func allowedBrandIds(scope: SessionScope, provider: AIProviderKind) throws -> Set<String> {
        switch scope {
        case .brand(let id):
            let b = try store.brand(id)
            guard b.allows(provider) else { throw MarkaError.providerNotAllowed(brand: b.name, provider: provider.displayName) }
            return [id]
        case .allBrands:
            return Set(try store.brands().filter { $0.allows(provider) }.map(\.id))
        }
    }

    /// `memberId` verilirse oturum o yapay zekâ çalışanın rolüyle çalışır. Yalnız marka kapsamında; çalışan etkin, yapay zekâ türünde
    /// ve bu markaya atanmış olmalıdır (başka markanın ekibi seçilemez).
    public func createSession(scope: SessionScope, provider: AIProviderKind, title: String, memberId: String? = nil) throws -> AISession {
        // MAS derlemesinde Codex oluşturulamaz (doğrudan dağıtımda her sağlayıcı seçilebilir; bu denetim orada hep geçer).
        guard provider.isSelectable else { throw MarkaError.ai(L("Bu sağlayıcı bu sürümde kullanılamaz.")) }
        _ = try allowedBrandIds(scope: scope, provider: provider)
        #if !MAS
        if provider == .local { _ = try LocalSettingsProvider.config(settings) }   // E-11: ayarsız yerel oturum açılmaz
        #endif
        // E-25: Apple modeli kullanılamıyorsa (macOS 26 yok, Apple Intelligence kapalı…) oturum açılmaz; neden söylenir.
        if let apple = (try? registry.provider(for: provider)) as? AppleFoundationModelsProvider { try apple.requireAvailable() }
        if let memberId {
            guard case .brand(let brandId) = scope else { throw MarkaError.validation(L("Çalışan rolü yalnız tek marka sohbetinde kullanılır.")) }
            _ = try ContextBuilder(store: store).persona(memberId: memberId, brandId: brandId)
            // Görev tarifi ve yetenekler şirket verisidir: Stüdyo bu sağlayıcıya izin vermiyorsa rol açılmaz (B1/O1).
            guard ContextBuilder(store: store).companyDataAllowed(brandId: brandId, provider: provider) else {
                throw MarkaError.validation(L("Çalışan rolü şirket verisi taşır; Stüdyo'nun AI izni bu sağlayıcıyı içermiyor."))
            }
        }
        let model = try registry.provider(for: provider).sessionModel(settings: settings)
        let s: AISession
        switch scope {
        case .brand(let id): s = AISession(brandId: id, scope: .brand, provider: provider, model: model, title: title, memberId: memberId)
        case .allBrands: s = AISession(brandId: nil, scope: .allBrands, provider: provider, model: model, title: title)
        }
        try store.write { db in try s.insert(db) }
        return s
    }

    public func respond(approvalId: String, decision: ApprovalDecision) {
        approvals.resolve(id: approvalId, decision: decision)
    }

    /// Süren turu durdurur: görev iptal edilir, tur işaretlenir (yeni model isteği ve yeni araç çağrısı olmaz) ve sağlayıcı
    /// kendi tarafında durdurulur (Codex `turn/interrupt`).
    public func cancel(sessionId: String) async {
        running[sessionId]?.cancel()
        cancellations[sessionId]?.cancel()
        for provider in registry.all { await provider.cancel(sessionId: sessionId) }
    }

    public func isRunning(sessionId: String) -> Bool { running[sessionId] != nil }

    /// Mesaj gönderir; olaylar akış olarak döner. Bitince mesaj kalıcı olarak kaydedilir.
    public func send(sessionId: String, text: String) -> AsyncStream<AIEvent> {
        if running[sessionId] != nil {
            return AsyncStream { c in
                c.yield(.failed(L("Bu oturumda yanıt sürüyor. Bitmesini bekle veya durdur.")))
                c.yield(.finished(stopReason: "busy"))
                c.finish()
            }
        }
        let cancellation = TurnCancellation()
        cancellations[sessionId] = cancellation
        return AsyncStream { continuation in
            let task = Task {
                await self.runTurn(sessionId: sessionId, text: text, cancellation: cancellation, emit: { continuation.yield($0) })
                continuation.finish()
                self.finishRun(sessionId)
            }
            running[sessionId] = task
            continuation.onTermination = { _ in }
        }
    }

    private func finishRun(_ sessionId: String) {
        running[sessionId] = nil
        cancellations[sessionId] = nil
    }

    private func runTurn(sessionId: String, text: String, cancellation: TurnCancellation, emit: @escaping @Sendable (AIEvent) -> Void) async {
        let clean = text.trimmed
        guard !clean.isEmpty else { return }
        var assistant = AIMessage(sessionId: sessionId, role: .assistant, text: "", state: .partial)
        var events: [ChatEventRecord] = []
        let recorder = EventRecorder()
        var context = "ai.oturum.akis"
        var providerKind: AIProviderKind?
        // E-30: içeriksiz tur izi (süre, araç adı sayacı, belirteç, sonuç türü).
        let traceStart = ContinuousClock.now
        let traceCollector = TurnTraceCollector()
        var outcome = TurnOutcome.tamam
        do {
            guard let session = try store.read({ db in try AISession.fetchOne(db, key: sessionId) }) else { throw MarkaError.notFound(sessionId) }
            context = "ai.\(session.provider.rawValue).akis"
            providerKind = session.provider
            let scope = SessionScope(session: session)
            let allowed = try allowedBrandIds(scope: scope, provider: session.provider)
            let userMessage = AIMessage(sessionId: sessionId, role: .user, text: clean)
            try store.write { db in
                try userMessage.insert(db)
                var s = session
                s.updatedAt = Date()
                if s.title.isEmpty || s.title == L("Yeni oturum") { s.title = String(clean.prefix(60)) }
                try s.update(db)
            }
            assistant.createdAt = Date().addingTimeInterval(0.001)
            let wrappedEmit: @Sendable (AIEvent) -> Void = { event in
                recorder.record(event)
                traceCollector.observe(event)
                emit(event)
            }
            // Kayıtlı olmayan sağlayıcı (ör. MAS derlemesinde eski veri tabanından gelen Codex oturumu) burada reddedilir.
            let provider = try registry.provider(for: session.provider)
            var turn = makeTurn(session: session, scope: scope, allowed: allowed, text: clean, provider: provider,
                                cancellation: cancellation, emit: wrappedEmit)
            let runTool = turn.callTool
            turn.callTool = { name, input in traceCollector.tool(name); return await runTool(name, input) }   // E-30: yalnız ad
            try await provider.runTurn(turn, assistant: &assistant)
            assistant.state = Task.isCancelled ? .partial : .complete
            if Task.isCancelled { outcome = .durduruldu }
        } catch is CancellationError {
            outcome = .durduruldu
            assistant.state = .partial
            emit(.event(ChatEventRecord(kind: .notice, title: L("Durduruldu"), detail: L("Yanıt yarıda kesildi; öneriler uygulanmadı."))))
        } catch {
            assistant.state = assistant.text.isEmpty ? .failed : .partial
            // H3-04: hata türe eşlenir; kullanıcı yalnız türün güvenli mesajını görür (ham gövde/anahtar yok). Tür olayın
            // `refId`'sinde taşınır (panel "Tekrar dene"/"Ayarlar'ı aç" kararını buradan verir). Sınıflandırılmış sağlayıcı
            // hatasında tanı günlüğüne yalnız tür yazılır.
            let failure = AIFailure(error: error, provider: providerKind)
            outcome = .hata(failure.kind)
            diagnostics?.record(error is AIServiceError ? failure.kind : error, context: context)
            let message = failure.message
            let record = ChatEventRecord(kind: .error, title: L("Hata"), detail: message, status: "error", refId: failure.kind.rawValue)
            emit(.event(record))
            emit(.failed(message))
            recorder.record(.event(record))
        }
        events = recorder.events()
        let traceDuration = ContinuousClock.now - traceStart
        turnTraces.record(traceCollector.trace(
            provider: providerKind, durationMs: Int(traceDuration.components.seconds * 1000 + traceDuration.components.attoseconds / 1_000_000_000_000_000),
            proposalCount: events.filter { $0.kind == .proposal }.count, outcome: outcome))
        assistant.eventsJSON = Store.json(events) ?? "[]"
        if assistant.state != .complete { assistant.rawJSON = "" }
        let final = assistant
        do { try store.write { db in try final.insert(db) } } catch {
            // Yanıt ekranda kalır ama saklanamadı: kullanıcı görsün (oturum yeniden açılınca yanıt olmaz). Kayda yalnız tür.
            diagnostics?.record(error, context: "ai.yanit.kaydet")
            emit(.event(ChatEventRecord(kind: .error, title: L("Yanıt kaydedilemedi"), detail: Self.unsavedReplyDetail,
                                        status: "error", refId: Self.unsavedReplyRef)))
        }
        emit(.finished(stopReason: final.state.rawValue))
    }

    /// Sağlayıcıya verilecek tur. Araç yürütücü marka kimliğini ve kapsamı denetler (başka markanın kimliği reddedilir); araç
    /// yalnız sağlayıcıya sunulduysa (yetenek) ve tur durdurulmadıysa çalışır. Araçlar veri yazmaz, öneri üretir.
    private func makeTurn(session: AISession, scope: SessionScope, allowed: Set<String>, text: String, provider: any AIProvider,
                          cancellation: TurnCancellation, emit: @escaping @Sendable (AIEvent) -> Void) -> AITurn {
        let tools = provider.capabilities.supportsTools ? ToolCatalog.tools(for: scope, store: store) : []
        let toolsOffered = provider.capabilities.supportsTools
        let executor = ToolExecutor(store: store, scope: scope, sessionId: session.id, allowedBrandIds: allowed)
        let callTool: @Sendable (String, JSONValue) async -> ToolResult = { name, input in
            if cancellation.isCancelled {
                return ToolResult(text: "HATA: kullanıcı yanıtı durdurdu; araç çalıştırılmadı.", isError: true,
                                  event: ChatEventRecord(kind: .notice, title: L("Durduruldu"), detail: L("Yanıt yarıda kesildi; öneriler uygulanmadı.")))
            }
            // Araç desteği olmayan sağlayıcıya araç verilmedi; yine de gelen çağrı çalıştırılmaz.
            guard toolsOffered else {
                return ToolResult(text: "HATA: bu sağlayıcıyla araç kullanılamaz; araç çalıştırılmadı.", isError: true,
                                  event: ChatEventRecord(kind: .error, title: L("Hata"), detail: name, status: "error"))
            }
            return executor.run(name: name, input: input)
        }
        return AITurn(session: session, scope: scope, allowedBrandIds: allowed, text: text, settings: settings, tools: tools,
                      store: store, folders: folders, approvals: approvals, cancellation: cancellation, emit: emit, callTool: callTool)
    }

    /// Anthropic geçmişi (testler ve doğrulama aracı için; asıl kurucu `AnthropicProvider.history`).
    func history(sessionId: String, excludingLastUser: Bool) throws -> [JSONValue] {
        AnthropicProvider.history(try messages(sessionId: sessionId), excludingLastUser: excludingLastUser)
    }
}

#if !MAS
// MARK: - Bu Mac'teki model (E-11)

/// Kayıttaki yerel sağlayıcı. Adres ve model adını her turda `AISettings`'ten okur ve `LocalEndpointProvider`'a (E-03) devreder:
/// yalnız geri döngü, araçsız, sunucu başlatmaz. Marka × sağlayıcı izni ChatEngine'de denetlenir (varsayılan kapalı).
struct LocalSettingsProvider: AIProvider {
    let kind = AIProviderKind.local
    let capabilities = AIProviderCapabilities(supportsTools: false, contextTokens: nil, onDevice: true, needsAPIKey: false)
    var urlSession: URLSession = LocalEndpointProvider.makeSession()

    /// Ayardan uç nokta yapılandırması; ayar yoksa ya da adres geri döngü değilse hata (istek gönderilmez).
    static func config(_ settings: AISettings) throws -> LocalEndpointConfig {
        guard let base = settings.localBaseURL, let model = settings.localModel else {
            throw MarkaError.ai(L("Bu Mac'teki model ayarlanmadı. Ayarlar › Genel'den adres ve model adı gir."))
        }
        return try LocalEndpointConfig(baseURL: base, format: .openAICompatible, model: model, isEnabled: true)
    }

    func sessionModel(settings: AISettings) -> String { settings.localModel ?? "" }
    func cancel(sessionId: String) async {}

    func runTurn(_ turn: AITurn, assistant: inout AIMessage) async throws {
        let provider = LocalEndpointProvider(config: try Self.config(turn.settings), kind: kind, urlSession: urlSession)
        try await provider.runTurn(turn, assistant: &assistant)
    }
}

/// Bu Mac'teki model tercihleri (`PreferenceStore` üzerinden; `UserDefaults.standard` kullanılmaz).
/// Geri döngü dışı adres ya da boş model adı hiç yazılmaz; okurken de yeniden denetlenir.
public enum LocalModelPreferences {
    static let addressKey = "localModelAddress"
    static let modelKey = "localModelName"

    public struct Value: Sendable, Equatable {
        public var address: String
        public var model: String
    }

    /// Kayıtlı ve hâlâ geçerli ayar; yoksa ya da kayıt bozuksa `nil`.
    public static func load(_ preferences: PreferenceStore) -> Value? {
        guard let address = preferences.string(forKey: addressKey), let model = preferences.string(forKey: modelKey),
              let config = try? LocalEndpointConfig(baseURL: address, format: .openAICompatible, model: model) else { return nil }
        return Value(address: config.baseURL.absoluteString, model: config.model)
    }

    /// Doğrular ve yazar. Doğrulama başarısızsa hiçbir anahtara dokunmadan hata fırlatır.
    @discardableResult
    public static func save(address: String, model: String, to preferences: PreferenceStore) throws -> Value {
        let config = try LocalEndpointConfig(baseURL: address, format: .openAICompatible, model: model)
        let value = Value(address: config.baseURL.absoluteString, model: config.model)
        preferences.set(value.address, forKey: addressKey)
        preferences.set(value.model, forKey: modelKey)
        return value
    }

    public static func clear(_ preferences: PreferenceStore) {
        preferences.set(nil, forKey: addressKey)
        preferences.set(nil, forKey: modelKey)
    }

    /// "Bağlantıyı dene": `GET <adres>/v1/models` (içerik göndermez). Yalnız geri döngü; yönlendirme izlenmez.
    /// Sunucu yanıt verirse döner, vermezse hata fırlatır. Sunucuyu başlatmaz.
    public static func testConnection(address: String) async throws {
        try await testConnection(address: address, urlSession: LocalEndpointProvider.makeSession())
    }

    static func testConnection(address: String, urlSession: URLSession) async throws {
        let base = try LocalEndpointConfig.validatedLoopbackURL(address)
        let v1 = base.path.hasSuffix("/v1") || base.path.hasSuffix("/v1/") ? base : base.appending(path: "v1")
        let url = v1.appending(path: "models")
        guard LocalEndpointConfig.isLoopback(url) else {
            throw MarkaError.validation(L("Yerel model adresi yalnız bu Mac olabilir (127.0.0.1, ::1 ya da localhost)."))
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        let response: URLResponse
        do {
            (_, response) = try await urlSession.data(for: request, delegate: RedirectRefuser())
        } catch {
            throw MarkaError.ai(L("Bu Mac'teki model sunucusuna bağlanılamadı. Sunucunun çalıştığını ve adresi denetle."))
        }
        guard let http = response as? HTTPURLResponse, let finalURL = http.url, LocalEndpointConfig.isLoopback(finalURL) else {
            throw MarkaError.ai(L("Yerel model sunucusu bu Mac dışına yönlendirdi; istek durduruldu."))
        }
        guard (200..<300).contains(http.statusCode) else {
            throw MarkaError.ai(LF("Yerel model sunucusu yanıt vermedi. HTTP durumu: %d", http.statusCode))
        }
    }
}
#endif
