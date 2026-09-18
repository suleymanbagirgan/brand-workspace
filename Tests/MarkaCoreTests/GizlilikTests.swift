import Foundation
import Testing
@testable import MarkaCore

/// Kayıtlı durum kodu ve gövdeyle yanıt veren sahte HTTP katmanı. Gelen isteği sayar; hata gövdesi, bir vekilin ya da
/// sunucunun yapabileceği gibi isteğin anahtarını ve gövdesini yansıtabilir.
final class KayitliYanit: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 400
    nonisolated(unsafe) static var body: (_ key: String, _ requestBody: String) -> String = { _, _ in "" }
    nonisolated(unsafe) static var requestCount = 0
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "kayitli.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open(); var d = Data(); var buf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&buf, maxLength: 4096); if n <= 0 { break }; d.append(buf, count: n) }
            stream.close(); data = d
        }
        Self.lock.lock()
        Self.requestCount += 1
        let out = Self.body(request.value(forHTTPHeaderField: "x-api-key") ?? "", String(decoding: data ?? Data(), as: UTF8.self))
        let status = Self.status
        Self.lock.unlock()
        let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["content-type": "application/json"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(out.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    static var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [KayitliYanit.self]
        return URLSession(configuration: config)
    }
}

@Suite(.serialized) struct GizlilikTests {
    static let anahtar = "sk-ant-SAHTE-DENEME-0000"
    static let gizliIcerik = "GizliMarkaXYZ"

    func client(key: String = anahtar) -> AnthropicClient {
        AnthropicClient(apiKey: key, model: "claude-haiku-4-5-20251001", baseURL: URL(string: "https://kayitli.test")!, session: KayitliYanit.session)
    }

    func mesaj(_ body: () async throws -> Void) async -> String {
        do { try await body(); return "" } catch { return (error as? LocalizedError)?.errorDescription ?? "\(error)" }
    }

    /// Kanıt (G3): sunucu hata gövdesinde anahtarı ve istek gövdesini yansıtsa da kullanıcıya gösterilen mesajda anahtar yok;
    /// akışlı, JSON ve anahtar doğrulama yollarının üçünde de.
    @Test func apiHataMesajiAnahtariYansitmaz() async throws {
        KayitliYanit.status = 400
        KayitliYanit.body = { key, req in
            let m = "YANSIMA key=\(key) body=\(req.prefix(80))"
            return String(decoding: try! JSONValue.object(["type": "error", "error": ["type": "invalid_request_error", "message": .string(m)]]).data(), as: UTF8.self)
        }
        let c = client()
        let akis = await mesaj { _ = try await c.streamTurn(system: Self.gizliIcerik, messages: [["role": "user", "content": "x"]], tools: [], onText: { _ in }) }
        let json = await mesaj { _ = try await c.completeJSON(system: "s", user: "u", schema: ["type": "object"]) }
        KayitliYanit.status = 403
        let dogrula = await mesaj { try await c.verifyKey() }
        for m in [akis, json, dogrula] {
            #expect(m.contains("YANSIMA"), "hata mesajı yine de gösterilmeli: \(m)")
            #expect(!m.contains(Self.anahtar) && !m.contains("SAHTE-DENEME"), "mesajda anahtar var: \(m)")
            #expect(m.contains(AnthropicClient.redactionMark))
        }

        // Anahtar `sk-ant-` biçiminde olmasa da (vekil anahtarı) karartılır.
        KayitliYanit.status = 400
        let vekil = "vekil-anahtari-7f3a9c"
        let m = await mesaj { _ = try await client(key: vekil).completeJSON(system: "s", user: "u", schema: ["type": "object"]) }
        #expect(m.contains("YANSIMA") && !m.contains(vekil))
    }

    /// Kanıt (G3): JSON olmayan ham gövde (ör. vekilin HTML sayfası) kısaltılır; içinde anahtar geçse de yazılmaz.
    @Test func jsonOlmayanHamGovdeKisaltilirVeAnahtarKarartilir() async throws {
        KayitliYanit.status = 400
        KayitliYanit.body = { key, req in "<html>Vekil hatası key=\(key) " + req + String(repeating: " dolgu", count: 500) + "</html>" }
        let m = await mesaj { _ = try await client().completeJSON(system: Self.gizliIcerik, user: "u", schema: ["type": "object"]) }
        #expect(m.contains("Vekil hatası"))
        #expect(!m.contains(Self.anahtar))
        #expect(!m.contains("</html>"), "ham gövde kısaltılmadı")
        #expect(m.count < AnthropicClient.rawBodyLimit + 60, "mesaj çok uzun: \(m.count)")
    }

    /// Kanıt (G3): akışın ortasında gelen `error` olayındaki yansıma da karartılır.
    @Test func akisHataOlayiAnahtariYansitmaz() async throws {
        KayitliYanit.status = 200
        KayitliYanit.body = { key, _ in "event: error\ndata: {\"type\":\"error\",\"error\":{\"type\":\"overloaded_error\",\"message\":\"YANSIMA \(key)\"}}\n\n" }
        let m = await mesaj { _ = try await client().streamTurn(system: "s", messages: [["role": "user", "content": "x"]], tools: [], onText: { _ in }) }
        #expect(m.contains("YANSIMA") && !m.contains(Self.anahtar))
    }

    /// Kanıt (G5): rapor özeti markanın izin vermediği sağlayıcıya çekirdekte reddedilir; istek hiç çıkmaz.
    @Test func raporOzetiIzinsizSaglayiciyaGitmez() async throws {
        let store = try makeStore()
        let brand = try store.createBrand(name: Self.gizliIcerik)
        let now = Date()
        let content = try ReportBuilder(store: store).build(brandId: brand.id, period: DateInterval(start: now.addingTimeInterval(-86_400), end: now))
        KayitliYanit.requestCount = 0
        KayitliYanit.status = 200
        KayitliYanit.body = { _, _ in
            String(decoding: try! JSONValue.object(["type": "message", "model": "claude-haiku-4-5-20251001", "stop_reason": "end_turn",
                "content": [["type": "text", "text": "{\"cumleler\":[]}"]], "usage": ["input_tokens": 3, "output_tokens": 2]]).data(), as: UTF8.self)
        }
        let beklenen = MarkaError.providerNotAllowed(brand: brand.name, provider: AIProviderKind.anthropic.displayName)
        await #expect(throws: beklenen) {
            _ = try await ReportSummarizer().summarize(content: content, brand: try store.brand(brand.id), provider: .anthropic(client()))
        }
        try store.setAIProviders(brand.id, providers: [.codex])
        await #expect(throws: MarkaError.self) {
            _ = try await ReportSummarizer().summarize(content: content, brand: try store.brand(brand.id), provider: .anthropic(client()))
        }
        #expect(KayitliYanit.requestCount == 0, "izinsiz markanın içeriği sağlayıcıya gitti")

        // İzin verilince aynı çağrı sağlayıcıya ulaşır.
        try store.setAIProviders(brand.id, providers: [.anthropic])
        let r = try await ReportSummarizer().summarize(content: content, brand: try store.brand(brand.id), provider: .anthropic(client()))
        #expect(KayitliYanit.requestCount == 1)
        #expect(r.kept.isEmpty && r.usage.inputTokens == 3)
    }
}
