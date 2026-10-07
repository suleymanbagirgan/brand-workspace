import Foundation

// Yerel kara kutu (E-05): hatadan önceki son adımların içeriksiz iz kırıntısı. Fikir getsentry/sentry'nin
// "breadcrumb" kavramından alındı; kod özgündür, SDK ve ağ yoktur.
// Kırıntı yalnız bellekte tutulur: diske, tercihlere ya da ağa yazılmaz, hiçbir yere gönderilmez. Uygulama her
// açılışta boş tamponla başlar. Kullanıcı Tanı raporunu kendisi kopyalarsa "son_adimlar" bölümünde görünür.

/// Kırıntıda yazılabilen tek alan kümesi. Bu küme dışındaki her alan kayıtta atılır.
public enum BreadcrumbField: String, Sendable, Hashable, CaseIterable, Comparable {
    /// Sabit ekran anahtarı (ör. "sohbet", "ayarlar.tani").
    case ekran
    /// Sabit eylem türü (ör. "gonder", "onayla").
    case eylem
    /// Sağlayıcı türü; yalnız `AIProviderKind` ham değerleri geçer.
    case saglayici
    /// Süre, milisaniye; yalnız negatif olmayan tam sayı geçer.
    case sureMs = "sure_ms"

    public static func < (a: Self, b: Self) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }

    /// Değer ya olduğu gibi geçerlidir ya da hiç yazılmaz: süzmek (ör. bir metinden harfleri bırakmak) içerik sızdırır.
    func accepts(_ value: String) -> Bool {
        switch self {
        case .ekran, .eylem:
            // Yalnız küçük ASCII harf, rakam ve `._-`: marka adı, kullanıcı metni, yol (`/`), e-posta (`@`), boşluk ve
            // Türkçe karakter taşıyan değer geçmez. Değerler koddaki sabitlerdir, kullanıcı girdisi değildir.
            guard (1...40).contains(value.count), let first = value.unicodeScalars.first,
                  Breadcrumb.lowerLetters.contains(first) else { return false }
            return value.unicodeScalars.allSatisfy { Breadcrumb.keyValueChars.contains($0) }
        case .saglayici:
            return AIProviderKind(rawValue: value) != nil
        case .sureMs:
            guard value.count <= 9, let n = Int(value), n >= 0 else { return false }
            return String(n) == value
        }
    }
}

/// Tek adımın içeriksiz kaydı.
public struct Breadcrumb: Sendable, Hashable {
    public var at: Date
    /// Yalnız izinli alanlar ve doğrulanmış değerler.
    public private(set) var fields: [BreadcrumbField: String]

    /// Ham alanlardan kırıntı kurar. İzinli küme dışındaki anahtar ve doğrulamadan geçmeyen değer atılır.
    public init(at: Date = Date(), raw: [String: String]) {
        self.at = at
        var kept: [BreadcrumbField: String] = [:]
        for (key, value) in raw {
            guard let field = BreadcrumbField(rawValue: key), field.accepts(value) else { continue }
            kept[field] = value
        }
        self.fields = kept
    }

    /// Tipli kurucu: çağrı noktaları için önerilen yol.
    public init(at: Date = Date(), screen: String, action: String, provider: AIProviderKind? = nil, durationMs: Int? = nil) {
        var raw = ["ekran": screen, "eylem": action]
        if let provider { raw["saglayici"] = provider.rawValue }
        if let durationMs { raw["sure_ms"] = String(durationMs) }
        self.init(at: at, raw: raw)
    }

    /// Tek satırlık gösterim: `2026-09-18T10:00:00Z  ekran=sohbet eylem=gonder saglayici=anthropic sure_ms=820`
    public var line: String {
        let parts = fields.keys.sorted().map { "\($0.rawValue)=\(fields[$0]!)" }
        return "\(ISO8601DateFormatter().string(from: at))  \(parts.isEmpty ? "—" : parts.joined(separator: " "))"
    }

    static let lowerLetters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz")
    static let keyValueChars = lowerLetters.union(CharacterSet(charactersIn: "0123456789._-"))
}

/// Son `capacity` adımı tutan bellek içi halka tampon. Kalıcı depo yoktur.
public final class Breadcrumbs: @unchecked Sendable {
    public static let capacity = 50
    /// Süreç boyunca tek tampon; uygulama kapanınca kaybolur.
    public static let shared = Breadcrumbs()

    private let lock = NSLock()
    private var buffer: [Breadcrumb] = []

    public init() {}

    /// Hiç geçerli alanı kalmamış kırıntı kaydedilmez.
    public func record(_ crumb: Breadcrumb) {
        if crumb.fields.isEmpty { return }
        lock.lock()
        defer { lock.unlock() }
        buffer.append(crumb)
        if buffer.count > Self.capacity { buffer.removeFirst(buffer.count - Self.capacity) }
    }

    /// Ham alanlarla kayıt; izinli küme dışı alanlar atılır.
    public func record(_ raw: [String: String], at: Date = Date()) {
        record(Breadcrumb(at: at, raw: raw))
    }

    public func record(screen: String, action: String, provider: AIProviderKind? = nil, durationMs: Int? = nil, at: Date = Date()) {
        record(Breadcrumb(at: at, screen: screen, action: action, provider: provider, durationMs: durationMs))
    }

    /// Eskiden yeniye tüm kırıntılar.
    public func entries() -> [Breadcrumb] {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    public func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        buffer.removeAll()
    }
}
