import Foundation

/// Anthropic Messages API istemcisi (resmî Swift SDK olmadığı için ham HTTP + SSE).
/// Kimlik: kullanıcının kendi API anahtarı (Keychain). Claude.ai tüketici oturumu kullanılmaz.
public struct AnthropicClient: Sendable {
    public var apiKey: String
    public var model: String
    public var effort: String?
    /// Verilirse her isteğin `max_tokens` değeri bununla sınırlanır (doğrulama aracında maliyeti düşük tutmak için).
    public var maxTokensCap: Int?
    public var baseURL: URL
    public var session: URLSession

    public init(apiKey: String, model: String = PriceTable.defaultAnthropicModel, effort: String? = nil, maxTokensCap: Int? = nil,
                baseURL: URL = URL(string: "https://api.anthropic.com")!, session: URLSession = .shared) {
        self.apiKey = apiKey; self.model = model; self.effort = effort; self.maxTokensCap = maxTokensCap
        self.baseURL = baseURL; self.session = session
    }

    public struct TurnResult: Sendable {
        public var content: [JSONValue]
        public var stopReason: String
        public var model: String
        public var inputTokens: Int
        public var outputTokens: Int
        public var cacheReadTokens: Int
        public var cacheWriteTokens: Int
    }

    func request(body: JSONValue, stream: Bool) throws -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent("v1/messages"))
        req.httpMethod = "POST"
        req.timeoutInterval = 600
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        if stream { req.setValue("text/event-stream", forHTTPHeaderField: "accept") }
        if model.hasPrefix("claude-opus-5") {
            // Güvenlik sınıflandırıcısı reddederse Anthropic'in önerdiği modele sunucu tarafında devret.
            req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        req.httpBody = try body.data()
        return req
    }

    func baseBody(system: String, messages: [JSONValue], maxTokens: Int) -> [String: JSONValue] {
        let limit = maxTokensCap.map { min($0, maxTokens) } ?? maxTokens
        var body: [String: JSONValue] = [
            "model": .string(model),
            "max_tokens": .number(Double(limit)),
            "system": .string(system),
            "messages": .array(messages),
            "cache_control": ["type": "ephemeral"],
        ]
        if PriceTable.price(for: model)?.supportsAdaptiveThinking == true {
            body["thinking"] = ["type": "adaptive"]
        }
        // Effort'u desteklemeyen modele (Haiku 4.5) göndermek 400 döndürür; o modelde ayar yok sayılır.
        if let effort, PriceTable.price(for: model)?.supportsEffort == true { body["output_config"] = ["effort": .string(effort)] }
        if model.hasPrefix("claude-opus-5") { body["fallbacks"] = "default" }
        return body
    }

    /// Akışlı istek. Metin parçaları `onText` ile gelir; tamamlanan içerik blokları döner.
    public func streamTurn(system: String, messages: [JSONValue], tools: [ToolSpec], maxTokens: Int = 32000,
                           onText: @Sendable (String) -> Void) async throws -> TurnResult {
        var body = baseBody(system: system, messages: messages, maxTokens: maxTokens)
        body["stream"] = true
        if !tools.isEmpty {
            body["tools"] = .array(tools.map {
                ["name": .string($0.name), "description": .string($0.description), "input_schema": $0.schema, "eager_input_streaming": true]
            })
        }
        let req = try request(body: .object(body), stream: true)
        let (bytes, response) = try await session.bytes(for: req)
        guard let http = response as? HTTPURLResponse else { throw MarkaError.ai(L("Sunucudan geçersiz yanıt.")) }
        if http.statusCode != 200 {
            var data = Data()
            for try await b in bytes { data.append(b) }
            throw apiError(status: http.statusCode, data: data)
        }

        var blocks: [Int: [String: JSONValue]] = [:]
        var partialJSON: [Int: String] = [:]
        var result = TurnResult(content: [], stopReason: "", model: model, inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0)
        var eventName = ""
        for try await line in bytes.lines {
            try Task.checkCancellation()
            if line.hasPrefix("event:") { eventName = line.dropFirst(6).trimmingCharacters(in: .whitespaces); continue }
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let event = try? JSONValue.parse(payload) else { continue }
            let type = event["type"]?.string ?? eventName
            switch type {
            case "message_start":
                if let m = event["message"] {
                    result.model = m["model"]?.string ?? model
                    Self.applyUsage(m["usage"], to: &result)
                }
            case "content_block_start":
                guard let i = event["index"]?.int, let b = event["content_block"]?.object else { continue }
                blocks[i] = b
                if b["type"]?.string == "tool_use" { partialJSON[i] = "" }
                if b["type"]?.string == "text", let t = b["text"]?.string, !t.isEmpty { onText(t) }
            case "content_block_delta":
                guard let i = event["index"]?.int, let d = event["delta"], var block = blocks[i] else { continue }
                func append(_ key: String, _ piece: String?) {
                    block[key] = .string((block[key]?.string ?? "") + (piece ?? ""))
                }
                switch d["type"]?.string {
                case "text_delta":
                    append("text", d["text"]?.string)
                    onText(d["text"]?.string ?? "")
                case "thinking_delta": append("thinking", d["thinking"]?.string)
                case "signature_delta": append("signature", d["signature"]?.string)
                case "input_json_delta": partialJSON[i, default: ""] += d["partial_json"]?.string ?? ""
                case "citations_delta":
                    if let c = d["citation"] { block["citations"] = .array((block["citations"]?.array ?? []) + [c]) }
                default: break
                }
                blocks[i] = block
            case "content_block_stop":
                guard let i = event["index"]?.int else { continue }
                if let raw = partialJSON[i] {
                    // Araç girdisi: ayrıştırılamazsa boş nesne bırakılır; yürütücü eksik alanı hata olarak döner.
                    blocks[i]?["input"] = (raw.isEmpty ? .object([:]) : ((try? JSONValue.parse(raw)) ?? .object(["_gecersiz_json": .string(raw)])))
                }
            case "message_delta":
                if let r = event["delta"]?["stop_reason"]?.string { result.stopReason = r }
                Self.applyUsage(event["usage"], to: &result)
            case "error":
                throw MarkaError.ai(event["error"]?["message"]?.string.map { Self.truncated(redacted($0), limit: Self.jsonMessageLimit) } ?? L("Akış sırasında hata oluştu."))
            default: break
            }
        }
        result.content = blocks.keys.sorted().compactMap { blocks[$0].map(JSONValue.object) }
        return result
    }

    static func applyUsage(_ u: JSONValue?, to r: inout TurnResult) {
        guard let u else { return }
        if let v = u["input_tokens"]?.int, v > 0 { r.inputTokens = v }
        if let v = u["output_tokens"]?.int, v > 0 { r.outputTokens = v }
        if let v = u["cache_read_input_tokens"]?.int, v > 0 { r.cacheReadTokens = v }
        if let v = u["cache_creation_input_tokens"]?.int, v > 0 { r.cacheWriteTokens = v }
    }

    /// Yapılandırılmış JSON çıktısı (bilgi derleme, rapor özeti).
    public func completeJSON(system: String, user: String, schema: JSONValue, maxTokens: Int = 16000) async throws -> (JSONValue, TurnResult) {
        var body = baseBody(system: system, messages: [["role": "user", "content": .string(user)]], maxTokens: maxTokens)
        var oc = body["output_config"]?.object ?? [:]
        oc["format"] = ["type": "json_schema", "schema": schema]
        body["output_config"] = .object(oc)
        let req = try request(body: .object(body), stream: false)
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw MarkaError.ai(L("Sunucudan geçersiz yanıt.")) }
        guard http.statusCode == 200 else { throw apiError(status: http.statusCode, data: data) }
        let msg = try JSONValue.parse(data)
        var result = TurnResult(content: msg["content"]?.array ?? [], stopReason: msg["stop_reason"]?.string ?? "",
                                model: msg["model"]?.string ?? model, inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0)
        Self.applyUsage(msg["usage"], to: &result)
        if result.stopReason == "refusal" { throw MarkaError.ai(L("Model isteği güvenlik nedeniyle reddetti.")) }
        if result.stopReason == "max_tokens" { throw MarkaError.ai(L("Yanıt uzunluk sınırına takıldı; daha küçük bir kaynakla dene.")) }
        let text = result.content.filter { $0["type"]?.string == "text" }.compactMap { $0["text"]?.string }.joined()
        guard let json = try? JSONValue.parse(text) else { throw MarkaError.ai(L("Model geçerli JSON döndürmedi.")) }
        return (json, result)
    }

    /// Sunucu hatasını kullanıcıya gösterilecek mesaja çevirir. Sunucu (ya da araya giren bir vekil) hata gövdesinde
    /// isteği yansıtabilir: mesajdaki anahtar karartılır, JSON olmayan ham gövde kısaltılır. Bu mesaj uygulamada uyarıya,
    /// doğrulama aracında terminale ve özet tabloya düşer.
    func apiError(status: Int, data: Data) -> MarkaError {
        let message: String
        if let m = (try? JSONValue.parse(data))?["error"]?["message"]?.string {
            message = Self.truncated(redacted(m), limit: Self.jsonMessageLimit)
        } else {
            message = Self.truncated(redacted(String(decoding: data, as: UTF8.self)), limit: Self.rawBodyLimit)
        }
        switch status {
        case 401: return .ai(L("Claude API anahtarı geçersiz. Ayarlar › Genel'den anahtarı kontrol et."))
        case 403: return .ai(LF("Claude erişimi reddetti: %@", message))
        case 429: return .ai(L("Claude hız sınırına takıldı. Biraz sonra tekrar dene."))
        case 529, 500...599: return .ai(L("Claude geçici olarak yanıt veremiyor. Biraz sonra tekrar dene."))
        default: return .ai(LF("Claude hatası (%1$d): %2$@", status, message))
        }
    }

    /// JSON olmayan ham gövdeden gösterilecek en çok karakter.
    static let rawBodyLimit = 200
    /// API'nin `error.message` alanından gösterilecek en çok karakter.
    static let jsonMessageLimit = 500
    static let redactionMark = "[anahtar gizlendi]"

    /// Metindeki API anahtarını (ve anahtar biçimindeki her `sk-ant-…` dizisini) karartır.
    func redacted(_ text: String) -> String {
        var out = text
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.count >= 8 { out = out.replacingOccurrences(of: key, with: Self.redactionMark) }
        return out.replacingOccurrences(of: #"sk-ant-[A-Za-z0-9_\-]+"#, with: Self.redactionMark, options: .regularExpression)
    }

    static func truncated(_ text: String, limit: Int) -> String {
        let flat = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
    }

    /// Anahtarı doğrulamak için en küçük istek (token sayma; ücretsiz). Sayılan giriş token'ını döndürür.
    @discardableResult
    public func verifyKey() async throws -> Int {
        var req = URLRequest(url: baseURL.appendingPathComponent("v1/messages/count_tokens"))
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONValue.object(["model": .string(model), "messages": [["role": "user", "content": "test"]]]).data()
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw apiError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
        }
        return (try? JSONValue.parse(data))?["input_tokens"]?.int ?? 0
    }
}
