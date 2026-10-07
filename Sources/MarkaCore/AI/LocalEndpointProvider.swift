#if !MAS
import Foundation

// MARK: - Yerel uç nokta sağlayıcısı (E-03)
//
// Kullanıcının bu Mac'te kendisinin çalıştırdığı bir model sunucusuna (OpenAI uyumlu `/v1/chat/completions` ya da
// Ollama biçimli `/api/chat`) bağlanır. Fikir antirez/ds4, ollama ve osaurus desenlerinden; uygulama özgündür.
//
// Güvence:
// - Yalnız geri döngü adresi: `127.0.0.1`, `::1`, `localhost`. Başka her adres kurulumda reddedilir; istekten hemen önce
//   ve yanıt geldiğinde (yönlendirme) yeniden denetlenir. Yönlendirme izlenmez, sistem vekil sunucusu kullanılmaz.
// - Varsayılan KAPALI (`LocalEndpointConfig.isEnabled == false`) ve bu dalgada `AIProviderRegistry`'ye eklenmez.
// - Sunucu başlatılmaz (`Process` yok); kullanıcının kurulu ikilisi çalıştırılmaz.
// - İlk sürüm araçsızdır (`supportsTools == false`): model veri değiştiremez, öneri aracı da almaz.
// - Tamamı `#if !MAS`: sandbox'ta geri döngüye çıkış ölçülmedi (E-29 araştırır).

/// Yerel sunucunun istek/yanıt biçimi.
enum LocalEndpointFormat: String, Sendable, CaseIterable {
    /// `POST <taban>/v1/chat/completions`, SSE (`data: {…}` … `data: [DONE]`).
    case openAICompatible
    /// `POST <taban>/api/chat`, satır başına bir JSON nesnesi (`done: true` ile biter).
    case ollama
}

/// Yerel uç nokta ayarı. Kurulum yalnız geri döngü adresinde başarılı olur.
struct LocalEndpointConfig: Sendable, Equatable {
    /// Kabul edilen tek ana makine adları (küçük harfe çevrilerek karşılaştırılır).
    static let allowedHosts: Set<String> = ["127.0.0.1", "::1", "localhost"]

    let baseURL: URL
    let format: LocalEndpointFormat
    let model: String
    /// Varsayılan kapalı: açık değilken tur hiç istek göndermeden reddedilir.
    var isEnabled: Bool

    init(baseURL: String, format: LocalEndpointFormat, model: String, isEnabled: Bool = false) throws {
        self.baseURL = try Self.validatedLoopbackURL(baseURL)
        let m = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !m.isEmpty else { throw MarkaError.validation(L("Yerel model adı boş olamaz.")) }
        self.format = format
        self.model = m
        self.isEnabled = isEnabled
    }

    /// Adres yalnız `http`/`https`, kullanıcı bilgisi yok ve ana makine tam olarak izinli kümedeyse kabul edilir.
    /// `localhost.evil.com`, `127.0.0.1.`, `0x7f.0.0.1`, `192.168.x.x` ve `kullanici@` biçimleri reddedilir.
    static func validatedLoopbackURL(_ text: String) throws -> URL {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw), isLoopback(url) else {
            throw MarkaError.validation(L("Yerel model adresi yalnız bu Mac olabilir (127.0.0.1, ::1 ya da localhost)."))
        }
        return url
    }

    static func isLoopback(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false), c.user == nil, c.password == nil else { return false }
        guard var host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty else { return false }
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        return allowedHosts.contains(host)
    }

    /// Sohbet isteğinin tam adresi.
    var chatURL: URL {
        switch format {
        case .openAICompatible:
            let base = baseURL.path.hasSuffix("/v1") || baseURL.path.hasSuffix("/v1/") ? baseURL : baseURL.appending(path: "v1")
            return base.appending(path: "chat/completions")
        case .ollama:
            return baseURL.appending(path: "api/chat")
        }
    }
}

/// Akıştan okunan tek parça.
enum LocalStreamPiece: Sendable, Equatable {
    case text(String)
    case usage(input: Int, output: Int)
    case done
}

/// Yerel model sunucusu sağlayıcısı. `AIProvider` uygular; bu dalgada kayda eklenmez (E-11 ayar ve kaydı bağlar).
struct LocalEndpointProvider: AIProvider {
    /// Varsayılan `.local` (E-11). Kayıtta `LocalSettingsProvider` (ChatEngine.swift) bu türle kurar; E-03 testleri başka tür verebilir.
    let kind: AIProviderKind
    let capabilities = AIProviderCapabilities(supportsTools: false, contextTokens: nil, onDevice: true, needsAPIKey: false)
    let config: LocalEndpointConfig
    let urlSession: URLSession

    init(config: LocalEndpointConfig, kind: AIProviderKind = .local, urlSession: URLSession = LocalEndpointProvider.makeSession()) {
        self.config = config
        self.kind = kind
        self.urlSession = urlSession
    }

    /// Önbelleksiz, çerezsiz, sistem vekil sunucusunu kullanmayan oturum (geri döngü trafiği vekile gitmez).
    static func makeSession() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.connectionProxyDictionary = [:]
        c.urlCache = nil
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.timeoutIntervalForRequest = 120
        return URLSession(configuration: c)
    }

    func sessionModel(settings: AISettings) -> String { config.model }

    /// Görev iptali yeterli: akış kesilir; yerel sunucuda durdurulacak oturum yok.
    func cancel(sessionId: String) async {}

    /// Kalıcı mesajlardan düz metin geçmişi (araç blokları yok; boş metin atlanır).
    static func history(_ messages: [AIMessage]) -> [JSONValue] {
        messages.compactMap { m in
            guard !m.text.isEmpty else { return nil }
            return ["role": .string(m.role == .user ? "user" : "assistant"), "content": .string(m.text)]
        }
    }

    func requestBody(system: String, messages: [AIMessage]) -> JSONValue {
        var list: [JSONValue] = [["role": "system", "content": .string(system)]]
        list.append(contentsOf: Self.history(messages))
        var body: [String: JSONValue] = ["model": .string(config.model), "messages": .array(list), "stream": true]
        if config.format == .openAICompatible { body["stream_options"] = ["include_usage": true] }
        return .object(body)
    }

    /// Akışın bir satırını çözer. Tanınmayan ya da boş satır boş dizi döner; sunucu hatası fırlatılır (içerik taşımadan).
    static func parseLine(_ line: String, format: LocalEndpointFormat) throws -> [LocalStreamPiece] {
        let s = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return [] }
        switch format {
        case .openAICompatible:
            guard s.hasPrefix("data:") else { return [] }
            let payload = s.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { return [.done] }
            guard let json = try? JSONValue.parse(payload) else { return [] }
            if json["error"] != nil { throw MarkaError.ai(L("Yerel model sunucusu hata bildirdi.")) }
            var out: [LocalStreamPiece] = []
            if let piece = json["choices"]?.array?.first?["delta"]?["content"]?.string, !piece.isEmpty { out.append(.text(piece)) }
            if let u = json["usage"], let i = u["prompt_tokens"]?.int, let o = u["completion_tokens"]?.int { out.append(.usage(input: i, output: o)) }
            return out
        case .ollama:
            guard let json = try? JSONValue.parse(s) else { return [] }
            if json["error"] != nil { throw MarkaError.ai(L("Yerel model sunucusu hata bildirdi.")) }
            var out: [LocalStreamPiece] = []
            if let piece = json["message"]?["content"]?.string, !piece.isEmpty { out.append(.text(piece)) }
            if json["done"]?.bool == true {
                out.append(.usage(input: json["prompt_eval_count"]?.int ?? 0, output: json["eval_count"]?.int ?? 0))
                out.append(.done)
            }
            return out
        }
    }

    func runTurn(_ turn: AITurn, assistant: inout AIMessage) async throws {
        guard config.isEnabled else { throw MarkaError.ai(L("Yerel model sağlayıcısı kapalı.")) }
        try turn.checkCancellation()
        let url = config.chatURL
        guard LocalEndpointConfig.isLoopback(url) else {
            throw MarkaError.validation(L("Yerel model adresi yalnız bu Mac olabilir (127.0.0.1, ::1 ya da localhost)."))
        }
        let session = turn.session
        let system = try ContextBuilder(store: turn.store).turnPrompt(session: session, scope: turn.scope,
                                                                      allowedBrandIds: turn.allowedBrandIds, provider: kind,
                                                                      responseLength: turn.settings.responseLength)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try requestBody(system: system, messages: try turn.storedMessages()).data()

        try turn.checkCancellation()
        let (bytes, response) = try await urlSession.bytes(for: request, delegate: RedirectRefuser())
        // Yönlendirme izlenmez; yine de son adres geri döngü değilse hiçbir yanıt okunmaz.
        guard let http = response as? HTTPURLResponse, let finalURL = http.url, LocalEndpointConfig.isLoopback(finalURL) else {
            throw MarkaError.ai(L("Yerel model sunucusu bu Mac dışına yönlendirdi; istek durduruldu."))
        }
        guard (200..<300).contains(http.statusCode) else {
            throw MarkaError.ai(LF("Yerel model sunucusu yanıt vermedi. HTTP durumu: %d", http.statusCode))
        }
        var text = "", input = 0, output = 0
        lines: for try await line in bytes.lines {
            try turn.checkCancellation()
            for piece in try Self.parseLine(line, format: config.format) {
                switch piece {
                case .text(let t):
                    text += t
                    assistant.text = text
                    turn.emit(.textDelta(t))
                case .usage(let i, let o):
                    input = i; output = o
                case .done:
                    break lines
                }
            }
        }
        assistant.text = text
        assistant.inputTokens += input
        assistant.outputTokens += output
        // Maliyet bilinmiyor (yerel donanım): nil. Kayıt içerik taşımaz, yalnız sayılar.
        let usage = UsageEntry(provider: kind, model: config.model, sessionId: session.id, brandId: session.brandId, purpose: "chat",
                               inputTokens: input, outputTokens: output, costMicros: nil)
        try turn.store.write { db in try usage.insert(db) }
        turn.emit(.usage(usage))
    }
}

/// Her yönlendirmeyi reddeder: yerel sunucu isteği başka bir adrese taşıyamaz.
final class RedirectRefuser: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? { nil }
}
#endif
