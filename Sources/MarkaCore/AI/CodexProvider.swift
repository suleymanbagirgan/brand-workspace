#if !MAS
import Foundation

/// OpenAI Codex App Server sağlayıcısı (yalnız doğrudan dağıtım). Kapsam başına ayrı, yalıtımlı Codex süreci tutar;
/// tur döngüsü sunucudadır, araç çağrıları `item/tool/call` isteğiyle ChatEngine'in yürütücüsüne döner.
actor CodexProvider: AIProvider {
    nonisolated let kind = AIProviderKind.codex
    nonisolated let capabilities = AIProviderCapabilities(supportsTools: true, contextTokens: nil, onDevice: false, needsAPIKey: false)
    let isolation: BrandIsolation

    private var codexTurns: [String: (key: String, server: CodexAppServer, thread: String, turn: String)] = [:]
    /// Kapsam başına ayrı, yalıtımlı Codex süreci (profil kapsamın klasörünü açar, diğerlerini kapatır).
    private var codexServers: [String: CodexAppServer] = [:]
    private var codexServerUse: [String: Date] = [:]
    /// Sohbet turu dışında süren işler (rapor özeti, bilgi derleme: `completeJSON`). Bu süreç boştaki sayılıp durdurulmamalı.
    private var structuredBusy: [String: Int] = [:]
    /// Aynı anda açık tutulan yalıtımlı Codex süreci üst sınırı; en uzun süredir boştaki durdurulur.
    static let maxCodexServers = 4

    let diagnostics: DiagnosticsLog?

    init(isolation: BrandIsolation, diagnostics: DiagnosticsLog? = nil) { self.isolation = isolation; self.diagnostics = diagnostics }

    nonisolated func sessionModel(settings: AISettings) -> String { settings.codexModel ?? "codex" }

    // MARK: Yalıtımlı Codex süreçleri

    static func serverKey(_ scope: SessionScope) -> String {
        switch scope {
        case .brand(let id): "marka:" + id
        case .allBrands: "tum-markalar"
        }
    }

    /// Kapsamın yalıtımlı Codex süreci; gerekirse başlatılır. Profil başlatma anında üretilir ve ölçülerek doğrulanır.
    func codexServer(for scope: SessionScope) async throws -> CodexAppServer {
        let key = Self.serverKey(scope)
        let server: CodexAppServer
        if let existing = codexServers[key] {
            server = existing
        } else {
            let isolation = isolation
            server = CodexAppServer(isolation: { binary in try isolation.codexIsolation(scope: scope, codexBinary: binary) },
                                    diagnostics: diagnostics)
            codexServers[key] = server
        }
        codexServerUse[key] = Date()
        await evictIdleServers(keeping: key)
        try await server.start()
        return server
    }

    func retainCodexServer(for scope: SessionScope) async throws -> CodexAppServer {
        let server = try await codexServer(for: scope)
        structuredBusy[Self.serverKey(scope), default: 0] += 1
        return server
    }

    func releaseCodexServer(for scope: SessionScope) {
        let key = Self.serverKey(scope)
        if let n = structuredBusy[key], n > 1 { structuredBusy[key] = n - 1 } else { structuredBusy[key] = nil }
    }

    private func evictIdleServers(keeping key: String) async {
        let busy = Set(codexTurns.values.map(\.key)).union(structuredBusy.keys).union([key])
        while codexServers.count > Self.maxCodexServers,
              let victim = codexServerUse.filter({ !busy.contains($0.key) }).min(by: { $0.value < $1.value })?.key {
            let s = codexServers.removeValue(forKey: victim)
            codexServerUse[victim] = nil
            await s?.stop()
        }
    }

    func stopCodexServers() async {
        let all = codexServers
        codexServers.removeAll()
        codexServerUse.removeAll()
        for (_, s) in all { await s.stop() }
    }

    func cancel(sessionId: String) async {
        if let t = codexTurns[sessionId] { try? await t.server.interrupt(threadId: t.thread, turnId: t.turn) }
    }

    // MARK: Tur

    func runTurn(_ turn: AITurn, assistant: inout AIMessage) async throws {
        let session = turn.session, scope = turn.scope, store = turn.store, folders = turn.folders, emit = turn.emit
        let codex = try await codexServer(for: scope)
        if try await codex.account() == nil {
            // Süreç girişten önce başlamış olabilir; giriş dosyası yeniden okunsun diye bir kez yeniden başlatılır.
            await codex.stop()
            try await codex.start()
            guard try await codex.account() != nil else {
                throw MarkaError.ai(AIErrorKind.codexLoginMissingMessage)   // H3-04: sınıflandırma bu metinle eşleşir
            }
        }
        let cwd = try folders.folder(for: scope)
        if case .brand(let b) = scope { try folders.writeContextFile(brandId: b) }
        let instructions = try ContextBuilder(store: store).turnPrompt(session: session, scope: scope, allowedBrandIds: turn.allowedBrandIds,
                                                                       provider: .codex, responseLength: turn.settings.responseLength) + """

        # Codex çalışma kuralları
        - Çalışma klasörün: \(cwd.path). Yalnızca bu klasörde dosya oluştur veya değiştir; çıktıları `ciktilar/` altına koy.
        - Diğer marka klasörleri ve uygulama verisi işletim sistemi düzeyinde kapalıdır; bu klasör dışına yazma reddedilir. Reddedilen işlemi başka yoldan deneme.
        - Uygulama verisini değiştirmek için yalnızca sana verilen *_oner araçlarını kullan.
        """
        var threadId = session.providerThreadId
        if let existing = threadId, await codex.needsResume(existing) {
            do {
                try await codex.resumeThread(existing, cwd: cwd, developerInstructions: instructions)
            } catch {
                // Kayıt kapsamın Codex dizininde yok (ör. 0.1.0'da ortak ~/.codex'te açılmış iş parçacığı): yenisi açılır.
                // Uygulamadaki sohbet geçmişi korunur; Codex önceki turları hatırlamaz.
                threadId = nil
                emit(.event(ChatEventRecord(kind: .notice, title: L("Codex oturumu yeniden başlatıldı"),
                                            detail: L("Önceki Codex kaydı bu markanın yalıtımlı alanında bulunamadı; Codex önceki mesajları hatırlamayabilir."))))
            }
        }
        if threadId == nil {
            var model = turn.settings.codexModel
            if model == nil { model = try await codex.models().first(where: \.isDefault)?.id }
            guard let model else { throw MarkaError.ai(L("Codex model listesi alınamadı.")) }
            let id = try await codex.startThread(cwd: cwd, model: model, developerInstructions: instructions, tools: turn.tools)
            threadId = id
            try store.write { db in
                var s = session
                s.providerThreadId = id
                s.model = model
                try s.update(db)
            }
        }
        let thread = threadId!
        let before = folders.snapshot(cwd)
        let collector = CodexTurnState()
        let callTool = turn.callTool, approvals = turn.approvals
        await codex.register(threadId: thread, notifications: { note in
            await collector.handle(note, emit: emit)
        }, requests: { method, params in
            await Self.handleRequest(method: method, params: params, callTool: callTool, approvals: approvals, emit: emit)
        })
        defer { Task { await codex.unregister(threadId: thread) } }
        let turnId = try await codex.startTurn(threadId: thread, text: turn.text)
        codexTurns[session.id] = (Self.serverKey(scope), codex, thread, turnId)
        defer { codexTurns[session.id] = nil }
        let outcome = await collector.waitForCompletion()
        assistant.text = outcome.text
        assistant.inputTokens = outcome.inputTokens
        assistant.outputTokens = outcome.outputTokens
        if outcome.inputTokens > 0 || outcome.outputTokens > 0 {
            let usage = UsageEntry(provider: .codex, model: session.model, sessionId: session.id, brandId: session.brandId, purpose: "chat",
                                   inputTokens: outcome.inputTokens, outputTokens: outcome.outputTokens, cacheReadTokens: outcome.cachedTokens, costMicros: nil)
            try store.write { db in try usage.insert(db) }
            emit(.usage(usage))
        }
        for change in BrandFolders.diff(before: before, after: folders.snapshot(cwd)) {
            emit(.event(ChatEventRecord(kind: .fileChange, title: change.path, detail: cwd.appendingPathComponent(change.path).path,
                                        status: change.change, refId: change.path)))
        }
        if outcome.status == "failed" {
            // H3-04: Codex hata metni yalnız türe eşlenir; sohbet paneli metni değil türün mesajını gösterir.
            let text = outcome.error ?? L("Codex turu başarısız oldu.")
            throw AIServiceError(kind: AIErrorClassifier.classify(codexMessage: text), technicalMessage: text)
        }
        if outcome.status == "interrupted" { throw CancellationError() }
    }

    private static func handleRequest(method: String, params: JSONValue, callTool: @Sendable (String, JSONValue) async -> ToolResult,
                                      approvals: ApprovalBroker, emit: @escaping @Sendable (AIEvent) -> Void) async -> JSONValue {
        switch method {
        case "item/tool/call":
            let r = await callTool(params["tool"]?.string ?? "", params["arguments"] ?? .object([:]))
            emit(.event(r.event))
            return ["success": .bool(!r.isError), "contentItems": [["type": "inputText", "text": .string(r.text)]]]
        case "item/commandExecution/requestApproval", "item/fileChange/requestApproval":
            let isCommand = method.contains("command")
            let request = ApprovalRequest(
                id: newID(), kind: isCommand ? .command : .fileChange,
                title: isCommand ? L("Komut çalıştırma izni") : L("Dosya değişikliği izni"),
                detail: isCommand ? (params["command"]?.string ?? "") : (params["grantRoot"]?.string ?? L("Çalışma klasöründe dosya değişikliği")),
                reason: params["reason"]?.string ?? "")
            emit(.event(ChatEventRecord(id: request.id, kind: .approval, title: request.title, detail: request.detail, status: "pending")))
            let decision = await approvals.wait(id: request.id) { emit(.approvalNeeded(request)) }
            emit(.eventUpdated(ChatEventRecord(id: request.id, kind: .approval, title: request.title, detail: request.detail, status: decision.rawValue)))
            return ["decision": .string(decision.rawValue)]
        default:
            return ["decision": "decline"]
        }
    }
}

actor CodexTurnState {
    struct Outcome: Sendable {
        var text: String
        var status: String
        var error: String?
        var inputTokens: Int
        var outputTokens: Int
        var cachedTokens: Int
    }
    private var messages: [String: String] = [:]
    private var order: [String] = []
    private var outcome = Outcome(text: "", status: "inProgress", inputTokens: 0, outputTokens: 0, cachedTokens: 0)
    private var done = false
    private var waiters: [CheckedContinuation<Outcome, Never>] = []

    func handle(_ note: JSONValue, emit: @Sendable (AIEvent) -> Void) {
        let method = note["method"]?.string ?? ""
        let p = note["params"] ?? .null
        switch method {
        case "item/agentMessage/delta":
            let id = p["itemId"]?.string ?? ""
            if messages[id] == nil {
                if !order.isEmpty { emit(.textDelta("\n\n")) }
                order.append(id)
            }
            let d = p["delta"]?.string ?? ""
            messages[id, default: ""] += d
            emit(.textDelta(d))
        case "item/started":
            let item = p["item"] ?? .null
            switch item["type"]?.string {
            case "commandExecution":
                emit(.event(ChatEventRecord(id: item["id"]?.string ?? newID(), kind: .command, title: L("Komut"),
                                            detail: item["command"]?.string ?? "", status: "running")))
            case "fileChange":
                let paths = (item["changes"]?.array ?? []).compactMap { $0["path"]?.string }.joined(separator: ", ")
                emit(.event(ChatEventRecord(id: item["id"]?.string ?? newID(), kind: .fileChange, title: L("Dosya değişikliği"), detail: paths, status: "running")))
            default: break
            }
        case "item/completed":
            let item = p["item"] ?? .null
            switch item["type"]?.string {
            case "agentMessage":
                let id = item["id"]?.string ?? ""
                if messages[id] == nil { order.append(id) }
                messages[id] = item["text"]?.string ?? messages[id]
            case "commandExecution":
                emit(.eventUpdated(ChatEventRecord(id: item["id"]?.string ?? newID(), kind: .command, title: L("Komut"),
                                                   detail: item["command"]?.string ?? "", status: item["status"]?.string ?? "completed")))
            case "fileChange":
                let paths = (item["changes"]?.array ?? []).compactMap { $0["path"]?.string }.joined(separator: ", ")
                emit(.eventUpdated(ChatEventRecord(id: item["id"]?.string ?? newID(), kind: .fileChange, title: L("Dosya değişikliği"),
                                                   detail: paths, status: item["status"]?.string ?? "completed")))
            default: break
            }
        case "thread/tokenUsage/updated":
            let last = p["tokenUsage"]?["last"] ?? .null
            outcome.inputTokens += last["inputTokens"]?.int ?? 0
            outcome.outputTokens += last["outputTokens"]?.int ?? 0
            outcome.cachedTokens += last["cachedInputTokens"]?.int ?? 0
        case "turn/completed":
            outcome.status = p["turn"]?["status"]?.string ?? "completed"
            outcome.error = p["turn"]?["error"]?["message"]?.string
            outcome.text = order.compactMap { messages[$0] }.joined(separator: "\n\n")
            done = true
            for w in waiters { w.resume(returning: outcome) }
            waiters.removeAll()
        default: break
        }
    }

    func waitForCompletion() async -> Outcome {
        if done { return outcome }
        return await withCheckedContinuation { waiters.append($0) }
    }
}
#endif
