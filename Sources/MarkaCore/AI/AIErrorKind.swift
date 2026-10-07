import Foundation

// MARK: - Yapay zekâ hata sınıflandırması (H3-04 · A-13, A-14, U-27)
//
// Sağlayıcı hataları (HTTP durumu, Anthropic hata gövdesi, URLError, Codex hata metni) tek bir türe eşlenir. Kullanıcıya
// gösterilen mesaj YALNIZ türden üretilir: sunucunun ham gövdesi, anahtar ya da istek içeriği mesaja girmez. Tanı günlüğüne
// de yalnız tür yazılır (kural 6). Eşleme saf işlevlerdir; ağ ya da anahtar gerektirmez, sahte girdilerle test edilir.

/// Yapay zekâ hatasının türü. Ham değer tanı günlüğüne ve sohbet olayına (`ChatEventRecord.refId`) yazılan kararlı addır.
public enum AIErrorKind: String, Sendable, CaseIterable, Codable, Error {
    /// Anahtar eklenmemiş / sağlayıcıya giriş yapılmamış.
    case missingKey
    /// Anahtar ya da giriş geçersiz (401, kimlik doğrulama hatası).
    case invalidKey
    /// Hesabın bu isteğe izni yok (403, faturalandırma).
    case permission
    /// Hız sınırı (429).
    case rateLimited
    /// Sağlayıcı aşırı yüklü ya da geçici olarak yanıt veremiyor (529, 5xx).
    case overloaded
    /// Ağ yok / sunucuya ulaşılamadı.
    case offline
    /// İstek zaman aşımına uğradı.
    case timeout
    /// Bağlam (istem) modelin sınırını aştı.
    case contextTooLong
    /// Model isteği güvenlik nedeniyle reddetti.
    case refusal
    /// Sınıflandırılamayan hata.
    case unknown

    /// Aynı istek değiştirilmeden yeniden gönderilirse başarılı olabilir mi? ("Tekrar dene" düğmesi bu bilgiye bağlı.)
    public var isRetryable: Bool {
        switch self {
        case .rateLimited, .overloaded, .offline, .timeout, .unknown: true
        case .missingKey, .invalidKey, .permission, .contextTooLong, .refusal: false
        }
    }

    /// Hız sınırı ve aşırı yükte kullanıcıya beklemesi önerilir. Otomatik yeniden deneme YOK; yalnız mesajda söylenir.
    public var suggestsBackoff: Bool { self == .rateLimited || self == .overloaded }

    /// Hata satırının tek eylemi.
    public var action: AIErrorAction {
        switch self {
        case .missingKey, .invalidKey: .openSettings
        default: isRetryable ? .retry : .none
        }
    }

    /// Kullanıcıya gösterilecek mesaj (Türkçe anahtar, `L` ile yerelleştirilir). Ham gövde ya da anahtar içermez.
    public func userMessage(provider: AIProviderKind?) -> String {
        switch self {
        case .missingKey:
            provider == .codex ? AIErrorKind.codexLoginMissingMessage : AIErrorKind.anthropicKeyMissingMessage
        case .invalidKey:
            provider == .codex ? L("Codex girişi geçersiz ya da süresi dolmuş. Ayarlar › AI bölümünden yeniden giriş yap.")
                               : L("Claude API anahtarı geçersiz. Ayarlar › Genel'den anahtarı kontrol et.")
        case .permission:
            L("Sağlayıcı bu isteğe izin vermedi. Hesabının bu modele erişimi ya da bakiyesi olmayabilir.")
        case .rateLimited:
            L("Hız sınırına takıldı. Bir dakika kadar bekleyip tekrar dene.")
        case .overloaded:
            L("Sağlayıcı şu an yoğun ya da geçici olarak yanıt veremiyor. Birkaç dakika bekleyip tekrar dene.")
        case .offline:
            L("Sağlayıcıya ulaşılamadı. İnternet bağlantını kontrol edip tekrar dene.")
        case .timeout:
            L("İstek zaman aşımına uğradı. Tekrar deneyebilirsin.")
        case .contextTooLong:
            L("Sohbet modelin bağlam sınırını aştı. Yeni bir sohbet başlat ya da daha kısa bir soru sor.")
        case .refusal:
            L("Model bu isteği güvenlik nedeniyle yanıtlamadı. Soruyu farklı biçimde sorabilirsin.")
        case .unknown:
            L("Yapay zekâ yanıtı alınamadı. Tekrar deneyebilirsin; sorun sürerse daha sonra dene.")
        }
    }

    /// Sağlayıcıların anahtar/giriş yokken fırlattığı mesajlar (sınıflandırma bu metinle eşleşir; tek kaynak burası).
    static var anthropicKeyMissingMessage: String { L("Claude API anahtarı eklenmemiş. Ayarlar › Genel bölümünden ekleyebilirsin.") }
    static var codexLoginMissingMessage: String { L("Codex'e giriş yapılmamış. Ayarlar › AI bölümünden ChatGPT ile giriş yap.") }
}

/// Hata satırındaki eylem.
public enum AIErrorAction: String, Sendable, Equatable {
    case retry, openSettings, none
}

/// Sağlayıcı katmanının sınıflandırılmış hatası. `technicalMessage` eski davranışın (karartılmış, kısaltılmış) metnidir;
/// anahtar doğrulama gibi teknik yüzeylerde kullanılır. Sohbet paneli onu GÖSTERMEZ, `kind.userMessage` gösterir.
public struct AIServiceError: LocalizedError, Sendable, Equatable {
    public let kind: AIErrorKind
    public let status: Int?
    public let technicalMessage: String

    public init(kind: AIErrorKind, status: Int? = nil, technicalMessage: String) {
        self.kind = kind; self.status = status; self.technicalMessage = technicalMessage
    }

    public var errorDescription: String? { technicalMessage }
}

/// Sohbet paneline giden, kullanıcıya güvenli hata özeti.
public struct AIFailure: Sendable, Equatable {
    public let kind: AIErrorKind
    public let message: String

    public var isRetryable: Bool { kind.isRetryable }
    public var action: AIErrorAction { kind.action }

    public init(kind: AIErrorKind, message: String) { self.kind = kind; self.message = message }

    /// Herhangi bir hatayı türe ve güvenli mesaja çevirir. Uygulamanın kendi doğrulama hataları (`MarkaError`, `.ai` dışı:
    /// izin yok, kayıt bulunamadı…) ham gövde taşımadığından kendi metniyle gösterilir. `.ai` metni yalnız uygulamanın kendi
    /// yazdığı bilinen bir metinse (`AIErrorClassifier.trustedMessages`) gösterilir; sağlayıcıdan gelen ham metin (Codex
    /// JSON-RPC hatası gibi) gösterilmez, türün mesajı gösterilir. Geri kalan her şey türün mesajını alır.
    public init(error: Error, provider: AIProviderKind?) {
        let kind = AIErrorClassifier.classify(error)
        if let m = error as? MarkaError {
            switch m {
            case .ai(let text):
                if kind == .unknown, AIErrorClassifier.trustedMessages.contains(text) {
                    self.init(kind: kind, message: text)
                    return
                }
            default:
                self.init(kind: kind, message: m.errorDescription ?? kind.userMessage(provider: provider))
                return
            }
        }
        self.init(kind: kind, message: kind.userMessage(provider: provider))
    }
}

/// Saf eşleme işlevleri.
public enum AIErrorClassifier {
    /// Herhangi bir hatanın türü.
    public static func classify(_ error: Error) -> AIErrorKind {
        if let k = error as? AIErrorKind { return k }
        if let e = error as? AIServiceError { return e.kind }
        if let u = error as? URLError { return classify(urlError: u.code) }
        if let m = error as? MarkaError {
            switch m {
            case .ai(let text):
                if text == AIErrorKind.anthropicKeyMissingMessage || text == AIErrorKind.codexLoginMissingMessage { return .missingKey }
                return classify(codexMessage: text)
            case .providerNotAllowed: return .permission
            default: return .unknown
            }
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain { return classify(urlError: URLError.Code(rawValue: ns.code)) }
        return .unknown
    }

    /// HTTP durumu ve (varsa) Anthropic hata gövdesi → tür. Gövdedeki `error.type` durum kodundan önceliklidir;
    /// 400'de `prompt is too long` benzeri ileti bağlam aşımıdır.
    /// Kaynak: Anthropic API "Errors" belgesi (400 invalid_request_error, 401 authentication_error, 402 billing_error,
    /// 403 permission_error, 404 not_found_error, 413 request_too_large, 429 rate_limit_error, 500 api_error,
    /// 504 timeout_error, 529 overloaded_error).
    public static func classify(httpStatus: Int, body: Data?) -> AIErrorKind {
        let parsed = body.flatMap { try? JSONValue.parse($0) }
        let type = parsed?["error"]?["type"]?.string
        let message = parsed?["error"]?["message"]?.string ?? ""
        if let type, let k = classify(anthropicErrorType: type, message: message) { return k }
        switch httpStatus {
        case 400: return mentionsContextLimit(message.lowercased()) ? .contextTooLong : .unknown
        case 401: return .invalidKey
        case 402, 403: return .permission
        case 408, 504: return .timeout
        case 413: return .contextTooLong
        case 429: return .rateLimited
        case 500...503, 529: return .overloaded
        default: return .unknown
        }
    }

    /// Anthropic `error.type` → tür (tanınmayan tür için `nil`: durum koduna bakılır).
    public static func classify(anthropicErrorType type: String, message: String = "") -> AIErrorKind? {
        switch type {
        case "authentication_error": .invalidKey
        case "permission_error", "billing_error": .permission
        case "rate_limit_error": .rateLimited
        case "overloaded_error", "api_error": .overloaded
        case "timeout_error": .timeout
        case "request_too_large": .contextTooLong
        case "invalid_request_error": mentionsContextLimit(message.lowercased()) ? .contextTooLong : .unknown
        default: nil
        }
    }

    /// URLError kodu → tür.
    public static func classify(urlError code: URLError.Code) -> AIErrorKind {
        switch code {
        case .timedOut: .timeout
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
             .internationalRoamingOff, .dataNotAllowed, .callIsActive, .secureConnectionFailed:
            .offline
        case .userAuthenticationRequired: .invalidKey
        default: .unknown
        }
    }

    /// Codex (ya da akış sırasında gelen) hata metni → tür. Metin yalnız sınıflandırılır, kullanıcıya gösterilmez.
    public static func classify(codexMessage text: String) -> AIErrorKind {
        let t = text.lowercased()
        func has(_ words: String...) -> Bool { words.contains { t.contains($0) } }
        if mentionsContextLimit(t) { return .contextTooLong }
        if has("rate limit", "rate_limit", "too many requests", "usage limit", "429") { return .rateLimited }
        if has("overloaded", "529", "503", "server is busy", "capacity", "temporarily unavailable", "internal server error") { return .overloaded }
        if has("timed out", "timeout", "time out") { return .timeout }
        if has("not connected to the internet", "network", "connection refused", "connection reset", "could not resolve",
               "stream disconnected", "offline", "unreachable") { return .offline }
        if has("unauthorized", "401", "invalid api key", "invalid_api_key", "authentication", "not logged in", "token expired",
               "refresh token", "log in again", "login again") { return .invalidKey }
        if has("forbidden", "403", "permission", "billing", "insufficient_quota", "quota") { return .permission }
        if has("refus", "safety", "content policy", "flagged", "violat") { return .refusal }
        return .unknown
    }

    /// Sohbet yolunda uygulamanın kendi yazdığı (ham sağlayıcı metni olmayan) `MarkaError.ai` metinleri. Bunlar olduğu gibi
    /// gösterilir; listede olmayan `.ai` metni sağlayıcıdan gelmiş sayılır ve gösterilmez.
    static var trustedMessages: Set<String> {
        var set: Set<String> = [L("Bu sağlayıcı bu sürümde kullanılamaz.")]
        #if !MAS
        set.formUnion(codexTrustedMessages)
        #endif
        return set
    }

    #if !MAS
    private static var codexTrustedMessages: Set<String> {
        [L("Codex model listesi alınamadı."),
         L("Codex CLI bulunamadı. Codex'i kurduktan sonra tekrar dene (Ayarlar › AI)."),
         L("Marka yalıtımı bu Mac'te uygulanamadı (sandbox-exec). Markalar arası okuma açık kalmasın diye Codex başlatılmadı."),
         L("Codex çalışmıyor."),
         L("Codex süreci beklenmedik şekilde kapandı."),
         L("Codex oturumu başlatılamadı."),
         L("Codex turu yalnızca marka yalıtımıyla başlatılmış süreçte çalışır.")]
    }
    #endif

    static func mentionsContextLimit(_ lower: String) -> Bool {
        ["prompt is too long", "context length", "context window", "context_length", "maximum context", "too many tokens",
         "input is too long", "request too large", "request_too_large"].contains { lower.contains($0) }
    }

    /// "Tekrar dene" kuralı: tür yeniden denenebilir olmalı, yanıt sürmüyor olmalı ve istek şu an açık olan markada sorulmuş
    /// olmalı (marka değiştiyse istek başka markaya gönderilmez).
    public static func canRetry(kind: AIErrorKind?, requestBrandId: String?, currentBrandId: String, running: Bool) -> Bool {
        guard let kind, kind.isRetryable, !running, let requestBrandId else { return false }
        return requestBrandId == currentBrandId
    }
}
