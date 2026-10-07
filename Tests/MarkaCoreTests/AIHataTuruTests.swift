import Foundation
import Testing
@testable import MarkaCore

/// H3-04 (A-13, A-14, U-27): yapay zekâ hatalarının türe eşlenmesi, güvenli mesaj ve "Tekrar dene" kuralı.
/// Canlı çağrı yok: tüm girdiler sahte (HTTP durumu, hata gövdesi, URLError, Codex metni).
struct AIHataTuruTests {
    static let anahtar = "sk-ant-SAHTE-DENEME-1234"

    static func govde(_ type: String, _ message: String) -> Data {
        try! JSONValue.object(["type": "error", "error": ["type": .string(type), "message": .string(message)]]).data()
    }

    @Test func httpDurumKodlariTureEslenir() {
        let beklenen: [(Int, AIErrorKind)] = [
            (400, .unknown), (401, .invalidKey), (402, .permission), (403, .permission), (404, .unknown), (408, .timeout),
            (413, .contextTooLong), (429, .rateLimited), (500, .overloaded), (502, .overloaded), (503, .overloaded),
            (504, .timeout), (529, .overloaded), (418, .unknown),
        ]
        for (durum, tur) in beklenen {
            #expect(AIErrorClassifier.classify(httpStatus: durum, body: nil) == tur, "durum \(durum)")
        }
    }

    @Test func anthropicHataGovdesiDurumKodundanOnceliklidir() {
        #expect(AIErrorClassifier.classify(httpStatus: 500, body: Self.govde("overloaded_error", "Overloaded")) == .overloaded)
        #expect(AIErrorClassifier.classify(httpStatus: 400, body: Self.govde("authentication_error", "x")) == .invalidKey)
        #expect(AIErrorClassifier.classify(httpStatus: 400, body: Self.govde("billing_error", "x")) == .permission)
        #expect(AIErrorClassifier.classify(httpStatus: 400, body: Self.govde("rate_limit_error", "x")) == .rateLimited)
        #expect(AIErrorClassifier.classify(httpStatus: 400, body: Self.govde("timeout_error", "x")) == .timeout)
        #expect(AIErrorClassifier.classify(httpStatus: 400, body: Self.govde("request_too_large", "x")) == .contextTooLong)
        // Tanınmayan tür: durum koduna düşer.
        #expect(AIErrorClassifier.classify(httpStatus: 429, body: Self.govde("yeni_bir_tur", "x")) == .rateLimited)
        // JSON olmayan gövde: durum koduna düşer.
        #expect(AIErrorClassifier.classify(httpStatus: 401, body: Data("<html>vekil</html>".utf8)) == .invalidKey)
    }

    @Test func istemCokUzunHatasiBaglamAsimidir() {
        let g = Self.govde("invalid_request_error", "prompt is too long: 210000 tokens > 200000 maximum")
        #expect(AIErrorClassifier.classify(httpStatus: 400, body: g) == .contextTooLong)
        #expect(AIErrorClassifier.classify(httpStatus: 400, body: Self.govde("invalid_request_error", "messages: field required")) == .unknown)
    }

    @Test func urlErrorKodlariAgVeZamanAsiminaEslenir() {
        #expect(AIErrorClassifier.classify(URLError(.notConnectedToInternet)) == .offline)
        #expect(AIErrorClassifier.classify(URLError(.networkConnectionLost)) == .offline)
        #expect(AIErrorClassifier.classify(URLError(.cannotFindHost)) == .offline)
        #expect(AIErrorClassifier.classify(URLError(.timedOut)) == .timeout)
        #expect(AIErrorClassifier.classify(URLError(.badServerResponse)) == .unknown)
        // NSError olarak gelen URL hatası da tanınır.
        #expect(AIErrorClassifier.classify(NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)) == .offline)
    }

    @Test func codexHataMetniTureEslenir() {
        let beklenen: [(String, AIErrorKind)] = [
            ("You've hit your usage limit. Try again later.", .rateLimited),
            ("stream error: 429 Too Many Requests", .rateLimited),
            ("Server overloaded, please retry", .overloaded),
            ("stream disconnected before completion: network error", .offline),
            ("request timed out", .timeout),
            ("Your input exceeds the context window of this model", .contextTooLong),
            ("401 Unauthorized: token expired", .invalidKey),
            ("403 Forbidden", .permission),
            ("The request was flagged by the safety system", .refusal),
            ("beklenmedik bir şey oldu", .unknown),
        ]
        for (metin, tur) in beklenen {
            #expect(AIErrorClassifier.classify(codexMessage: metin) == tur, "\(metin)")
        }
    }

    @Test func anahtarYokVeGirisYokMetinleriAnahtarYokTurudur() {
        #expect(AIErrorClassifier.classify(MarkaError.ai(AIErrorKind.anthropicKeyMissingMessage)) == .missingKey)
        #expect(AIErrorClassifier.classify(MarkaError.ai(AIErrorKind.codexLoginMissingMessage)) == .missingKey)
        #expect(AIErrorClassifier.classify(MarkaError.providerNotAllowed(brand: "Deneme Yangın", provider: "x")) == .permission)
    }

    @Test func herTurunTurkceMesajiVarVeAyriDir() {
        var gorulen: Set<String> = []
        for tur in AIErrorKind.allCases {
            let m = tur.userMessage(provider: .anthropic)
            #expect(!m.isEmpty, "\(tur)")
            #expect(m.hasSuffix("."), "\(tur)")
            gorulen.insert(m)
        }
        #expect(gorulen.count == AIErrorKind.allCases.count)
        #expect(AIErrorKind.missingKey.userMessage(provider: .codex) != AIErrorKind.missingKey.userMessage(provider: .anthropic))
    }

    @Test func yenidenDenenebilirlikVeEylemKurali() {
        let denenebilir: Set<AIErrorKind> = [.rateLimited, .overloaded, .offline, .timeout, .unknown]
        for tur in AIErrorKind.allCases {
            #expect(tur.isRetryable == denenebilir.contains(tur), "\(tur)")
        }
        #expect(AIErrorKind.missingKey.action == .openSettings)
        #expect(AIErrorKind.invalidKey.action == .openSettings)
        #expect(AIErrorKind.rateLimited.action == .retry)
        #expect(AIErrorKind.contextTooLong.action == AIErrorAction.none)
        #expect(AIErrorKind.refusal.action == AIErrorAction.none)
        // Geri çekilme önerisi yalnız hız ve aşırı yükte; mesajda bekleme söylenir.
        #expect(AIErrorKind.allCases.filter(\.suggestsBackoff) == [.rateLimited, .overloaded])
        #expect(AIErrorKind.rateLimited.userMessage(provider: nil).contains("bekle"))
        #expect(AIErrorKind.overloaded.userMessage(provider: nil).contains("bekle"))
    }

    @Test func tekrarDeneYalnizAyniMarkadaVeDenenebilirTurde() {
        #expect(AIErrorClassifier.canRetry(kind: .offline, requestBrandId: "m1", currentBrandId: "m1", running: false))
        #expect(!AIErrorClassifier.canRetry(kind: .offline, requestBrandId: "m1", currentBrandId: "m2", running: false))
        #expect(!AIErrorClassifier.canRetry(kind: .offline, requestBrandId: "m1", currentBrandId: "m1", running: true))
        #expect(!AIErrorClassifier.canRetry(kind: .offline, requestBrandId: nil, currentBrandId: "m1", running: false))
        #expect(!AIErrorClassifier.canRetry(kind: .missingKey, requestBrandId: "m1", currentBrandId: "m1", running: false))
        #expect(!AIErrorClassifier.canRetry(kind: .contextTooLong, requestBrandId: "m1", currentBrandId: "m1", running: false))
        #expect(!AIErrorClassifier.canRetry(kind: nil, requestBrandId: "m1", currentBrandId: "m1", running: false))
    }

    @Test func kullaniciMesajiHamGovdeyiVeAnahtariIcermez() {
        let client = AnthropicClient(apiKey: Self.anahtar, model: "claude-haiku-4-5-20251001")
        let gizli = "GizliMarkaXYZ"
        for durum in [400, 401, 403, 404, 429, 500, 529] {
            let g = Self.govde("invalid_request_error", "YANSIMA key=\(Self.anahtar) body=\(gizli)")
            let hata = client.apiError(status: durum, data: g)
            let f = AIFailure(error: hata, provider: .anthropic)
            #expect(!f.message.contains(Self.anahtar) && !f.message.contains("sk-ant-"), "durum \(durum)")
            #expect(!f.message.contains(gizli) && !f.message.contains("YANSIMA"), "durum \(durum)")
            #expect(f.message == f.kind.userMessage(provider: .anthropic))
            // Teknik metin eski davranışla karartılmış kalır (anahtar yok).
            #expect(!hata.technicalMessage.contains(Self.anahtar))
        }
        // Ham Codex metni de gösterilmez.
        let ham = AIServiceError(kind: .unknown, technicalMessage: "codex internal: \(gizli) \(Self.anahtar)")
        let f = AIFailure(error: ham, provider: .codex)
        #expect(!f.message.contains(gizli) && !f.message.contains(Self.anahtar))
    }

    @Test func bilinmeyenHataGuvenliGenelMesajAlir() {
        let gizli = "GizliMarkaXYZ ozel-belge.txt"
        let hatalar: [Error] = [
            NSError(domain: "Ozel", code: 9, userInfo: [NSLocalizedDescriptionKey: gizli]),
            MarkaError.ai("sağlayıcı ham metni: \(gizli)"),
            DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: gizli)),
        ]
        for hata in hatalar {
            let f = AIFailure(error: hata, provider: .anthropic)
            #expect(f.kind == .unknown)
            #expect(f.message == AIErrorKind.unknown.userMessage(provider: .anthropic))
            #expect(!f.message.contains("GizliMarka"))
            #expect(f.isRetryable)
        }
        // Uygulamanın kendi bilinen metni olduğu gibi gösterilir.
        let kendi = AIFailure(error: MarkaError.ai(L("Bu sağlayıcı bu sürümde kullanılamaz.")), provider: .codex)
        #expect(kendi.message == L("Bu sağlayıcı bu sürümde kullanılamaz."))
    }

    @Test func sohbetMotoruHataTurunuOlayaYazarVeTaniGunlugeYalnizTur() async throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Kuzey Lojistik")
        try store.setAIProviders(b.id, providers: [.anthropic])
        let log = DiagnosticsLog(url: nil)
        let engine = ChatEngine(store: store, codex: CodexAppServer(), folders: BrandFolders(root: try tempDir("f"), store: store),
                                workspace: try tempDir("ws"), settings: AISettings(), anthropicKey: { nil }, diagnostics: log)
        let s = try await engine.createSession(scope: .brand(b.id), provider: .anthropic, title: "x")
        var hataOlayi: ChatEventRecord?
        var basarisiz: String?
        for await ev in await engine.send(sessionId: s.id, text: "merhaba") {
            if case .event(let e) = ev, e.kind == .error { hataOlayi = e }
            if case .failed(let m) = ev { basarisiz = m }
        }
        #expect(hataOlayi?.refId == AIErrorKind.missingKey.rawValue)
        #expect(basarisiz == AIErrorKind.missingKey.userMessage(provider: .anthropic))
        // Kalıcı olaylarda tür korunur (yeniden yüklemede "Ayarlar'ı aç" kararı verilebilir).
        let son = try await engine.messages(sessionId: s.id).last
        #expect(son?.state == .failed)
        #expect(try Store.decodeEvents(son?.eventsJSON ?? "[]").last?.refId == AIErrorKind.missingKey.rawValue)
        #expect(log.entries().last.map { !$0.type.contains("Kuzey") } == true)
    }

    @Test func siniflandirilmisSaglayiciHatasindaTaniGunlugeYalnizTurYazilir() {
        let log = DiagnosticsLog(url: nil)
        let hata = AIServiceError(kind: .rateLimited, status: 429, technicalMessage: "GizliMarkaXYZ")
        log.record(hata.kind, context: "ai.anthropic.akis")
        let e = log.entries().last
        #expect(e?.type == "MarkaCore.AIErrorKind")
        #expect(e?.caseName == "rateLimited")
        #expect(e.map { !"\($0)".contains("GizliMarkaXYZ") } == true)
    }
}
