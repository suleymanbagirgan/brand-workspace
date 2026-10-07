import Foundation

/// Anthropic Messages API sağlayıcısı: akışlı istek + araç döngüsü (en çok 16 model isteği). Ham HTTP `AnthropicClient`'ta.
struct AnthropicProvider: AIProvider {
    let kind = AIProviderKind.anthropic
    let capabilities = AIProviderCapabilities(supportsTools: true, contextTokens: nil, onDevice: false, needsAPIKey: true)
    let anthropicKey: @Sendable () -> String?
    let urlSession: URLSession

    func sessionModel(settings: AISettings) -> String { settings.anthropicModel }

    /// Görev iptali yeterli: akış `Task.checkCancellation` ile kesilir, sunucu tarafında durdurulacak bir şey yok.
    func cancel(sessionId: String) async {}

    /// Kalıcı mesajlardan Messages API geçmişi. Tamamlanmış asistan mesajının ham blokları (düşünme imzası dahil) aynen döner.
    static func history(_ messages: [AIMessage], excludingLastUser: Bool) -> [JSONValue] {
        var msgs = messages
        if excludingLastUser, msgs.last?.role == .user { msgs.removeLast() }
        var out: [JSONValue] = []
        for m in msgs {
            switch m.role {
            case .user:
                out.append(["role": "user", "content": [["type": "text", "text": .string(m.text)]]])
            case .assistant:
                if m.state == .complete, !m.rawJSON.isEmpty, let arr = try? JSONValue.parse(m.rawJSON).array, !arr.isEmpty {
                    out.append(contentsOf: arr)
                } else if !m.text.isEmpty {
                    out.append(["role": "assistant", "content": [["type": "text", "text": .string(m.text)]]])
                }
            }
        }
        return out
    }

    func runTurn(_ turn: AITurn, assistant: inout AIMessage) async throws {
        let session = turn.session, store = turn.store, settings = turn.settings, emit = turn.emit
        guard let key = anthropicKey(), !key.isEmpty else {
            throw MarkaError.ai(AIErrorKind.anthropicKeyMissingMessage)   // H3-04: sınıflandırma bu metinle eşleşir
        }
        var client = AnthropicClient(apiKey: key, model: session.model, effort: settings.anthropicEffort,
                                     maxTokensCap: settings.responseLength.maxTokensCap(existing: settings.anthropicMaxTokens), session: urlSession)
        if let url = settings.anthropicBaseURL { client.baseURL = url }
        let system = try ContextBuilder(store: store).turnPrompt(session: session, scope: turn.scope, allowedBrandIds: turn.allowedBrandIds,
                                                                 provider: .anthropic, responseLength: settings.responseLength)
        var messages = Self.history(try turn.storedMessages(), excludingLastUser: false)
        let tools = turn.tools
        var turnRaw: [JSONValue] = []
        var fullText = ""
        let textBox = TextBox()
        for iteration in 0..<16 {
            try turn.checkCancellation()
            if iteration > 0, !fullText.isEmpty, !fullText.hasSuffix("\n") {
                fullText += "\n\n"
                emit(.textDelta("\n\n"))
            }
            let result = try await client.streamTurn(system: system, messages: messages, tools: tools) { piece in
                textBox.append(piece)
                emit(.textDelta(piece))
            }
            fullText += textBox.drain()
            assistant.text = fullText
            let cost = PriceTable.costMicros(model: result.model, input: result.inputTokens, output: result.outputTokens,
                                             cacheRead: result.cacheReadTokens, cacheWrite: result.cacheWriteTokens)
            let usage = UsageEntry(provider: .anthropic, model: result.model, sessionId: session.id, brandId: session.brandId, purpose: "chat",
                                   inputTokens: result.inputTokens, outputTokens: result.outputTokens,
                                   cacheReadTokens: result.cacheReadTokens, cacheWriteTokens: result.cacheWriteTokens, costMicros: cost)
            try store.write { db in try usage.insert(db) }
            assistant.inputTokens += result.inputTokens + result.cacheReadTokens + result.cacheWriteTokens
            assistant.outputTokens += result.outputTokens
            assistant.costMicros += cost ?? 0
            emit(.usage(usage))

            var content = result.content
            if result.stopReason != "tool_use", content.contains(where: { $0["type"]?.string == "tool_use" }) {
                // Yarım kalan araç çağrısı sonucu olmadan geçmişe girerse oturum bozulur; çıkarılır.
                content.removeAll { $0["type"]?.string == "tool_use" }
                if content.isEmpty { content = [["type": "text", "text": .string(L("(yanıt kesildi)"))]] }
                emit(.event(ChatEventRecord(kind: .notice, title: L("Yarım kalan araç çağrısı atlandı"))))
            }
            let assistantMsg: JSONValue = ["role": "assistant", "content": .array(content)]
            messages.append(assistantMsg)
            turnRaw.append(assistantMsg)

            if result.stopReason == "refusal" {
                emit(.event(ChatEventRecord(kind: .notice, title: L("Model isteği reddetti"), detail: L("Claude güvenlik sınıflandırıcısı bu isteği yanıtlamadı."))))
                break
            }
            if result.stopReason == "max_tokens" {
                emit(.event(ChatEventRecord(kind: .notice, title: L("Yanıt uzunluk sınırına ulaştı"), detail: L("Devam etmesini isteyebilirsin."))))
            }
            let toolUses = result.content.filter { $0["type"]?.string == "tool_use" }
            guard result.stopReason == "tool_use", !toolUses.isEmpty else { break }
            var toolResults: [JSONValue] = []
            for use in toolUses {
                let name = use["name"]?.string ?? ""
                let id = use["id"]?.string ?? ""
                let input = use["input"] ?? .object([:])
                let r: ToolResult
                if input["_gecersiz_json"] != nil {
                    r = ToolResult(text: "HATA: araç girdisi geçerli JSON değil; tekrar dene.", isError: true,
                                   event: ChatEventRecord(kind: .error, title: LF("Araç girdisi okunamadı: %@", name), status: "error"))
                } else {
                    r = await turn.callTool(name, input)
                }
                emit(.event(r.event))
                toolResults.append(["type": "tool_result", "tool_use_id": .string(id), "content": .string(r.text), "is_error": .bool(r.isError)])
            }
            let resultMsg: JSONValue = ["role": "user", "content": .array(toolResults)]
            messages.append(resultMsg)
            turnRaw.append(resultMsg)
        }
        // Sonu araç sonucu olan tur geçmişte tutarlı kalsın diye kaydedilir; bir sonraki kullanıcı mesajı birleşir.
        assistant.rawJSON = JSONValue.array(turnRaw).compactString()
    }
}
