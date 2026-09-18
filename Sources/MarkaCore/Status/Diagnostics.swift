import Foundation
import GRDB

// İçeriksiz tanı raporu (İ5). Beta katılımcısı bir hata yaşadığında bize yalnızca "ne tür hata, nerede, ne zaman"
// bilgisini verir. Hata MESAJI hiçbir zaman saklanmaz: mesajlar marka adı, kaynak metni ya da dosya yolu taşıyabilir.

/// Yakalanan bir hatanın içeriksiz kaydı.
public struct DiagnosticEntry: Codable, Sendable, Hashable {
    public var at: Date
    /// Sabit bağlam anahtarı (ör. "rapor.pdf", "ai.anthropic.akis", "WorkView:53").
    public var context: String
    /// Swift tipi (ör. "MarkaCore.MarkaError", "Foundation.CocoaError").
    public var type: String
    /// Enum vaka adı (ör. "validation"); vaka adı çıkarılamayan hatalarda nil.
    public var caseName: String?
    /// NSError alanı ve kodu (ör. "NSCocoaErrorDomain 260 ← NSPOSIXErrorDomain 2").
    public var code: String

    public init(at: Date, context: String, type: String, caseName: String?, code: String) {
        self.at = at; self.context = context; self.type = type; self.caseName = caseName; self.code = code
    }

    /// Hatayı içeriksiz kayda çevirir. Yalnızca tip adı, vaka adı ve sayısal kod okunur; mesaj, userInfo metinleri,
    /// ilişkili değerler ve yollar okunmaz.
    public init(error: Error, context: String, at: Date = Date()) {
        self.at = at
        self.context = Self.validKey(context) ? context : "gecersiz-baglam"
        let typeName = Self.typeName(String(reflecting: Swift.type(of: error)))
        self.type = typeName
        self.caseName = Self.caseName(of: error)
        let ns = error as NSError
        var code = "\(Self.domain(ns.domain, typeName: typeName)) \(ns.code)"
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            code += " ← \(Self.domain(underlying.domain, typeName: nil)) \(underlying.code)"
        }
        self.code = code
    }

    /// Diskten okunan kaydı yeniden süzer: dosya elle ya da eski bir sürümle yazılmış olabilir, olduğu gibi güvenilmez.
    /// Her alan `init(error:context:)` ile aynı kurala tabidir.
    public var sanitized: DiagnosticEntry {
        let typeName = Self.typeName(type, strict: true)
        return DiagnosticEntry(at: at, context: Self.validKey(context) ? context : "gecersiz-baglam", type: typeName,
                               caseName: caseName.flatMap(Self.validIdentifier), code: Self.sanitizedCode(code, typeName: typeName))
    }

    /// Tip adı: yerel tip bağlamı ve genel tip argümanları (`<` sonrası) atılır; argüman olarak içerik taşıyan bir tip adı gelebilir.
    /// `strict` (diskten okunan kayıt): kalan ad tanımlayıcı karakterleri dışında bir şey taşıyorsa süzülmez, tümden atılır.
    static func typeName(_ reflected: String, strict: Bool = false) -> String {
        var name = reflected.replacingOccurrences(of: #"\(unknown context at [^)]*\)\."#, with: "", options: .regularExpression)
        if let open = name.firstIndex(of: "<") { name = String(name[..<open]) }
        if strict, !name.unicodeScalars.allSatisfy({ $0.isASCII && keyChars.contains($0) }) { return "?" }
        return clean(name, allowed: keyChars, limit: 120, fallback: "?")
    }

    /// Enum hatalarında vaka adı: ilişkili değerli vakalarda derleyicinin ürettiği Mirror etiketi (değer okunmaz),
    /// değersiz vakalarda derleyicinin ürettiği `String(describing:)` adı. Tip bu yolları kendi koduyla değiştirebiliyorsa
    /// (`CustomReflectable` Mirror'ı; `TextOutputStreamable`, `CustomStringConvertible`, `CustomDebugStringConvertible`
    /// açıklamayı) çıkan metin içerik taşıyabileceği için vaka adı yazılmaz.
    static func caseName(of error: Error) -> String? {
        let errorType = Swift.type(of: error)
        if errorType is CustomReflectable.Type { return nil }
        let mirror = Mirror(reflecting: error)
        guard mirror.displayStyle == .enum else { return nil }
        if let first = mirror.children.first { return first.label.flatMap(validIdentifier) }
        if errorType is TextOutputStreamable.Type || errorType is CustomStringConvertible.Type
            || errorType is CustomDebugStringConvertible.Type { return nil }
        return validIdentifier(String(describing: error))
    }

    /// Yalnızca tanımlayıcı biçimindeki ad geçer; boşluk, nokta, yol, @ … taşıyan her şey atılır.
    static func validIdentifier(_ raw: String) -> String? {
        guard raw.count <= 60, let first = raw.unicodeScalars.first,
              CharacterSet.letters.contains(first) || first == "_",
              raw.unicodeScalars.allSatisfy({ identifierChars.contains($0) && $0.isASCII }) else { return nil }
        return raw
    }

    /// Yazılabilen NSError alanları: sistemin ve bağımlılıkların sabit alan adları. Önekle serbest eşleşme yapılmaz;
    /// `NS…` ya da `com.apple.` ile başlayıp içerik taşıyan bir alan da "özel" olur.
    static let knownDomains: Set<String> = [
        NSCocoaErrorDomain, NSPOSIXErrorDomain, NSURLErrorDomain, NSOSStatusErrorDomain, NSMachErrorDomain,
        "kCFErrorDomainCFNetwork", "GRDB.DatabaseError", "MarkaCore.MarkaError",
    ]

    /// NSError alanı yalnızca izin listesindeyse ya da hatanın (zaten yazılan, süzülmüş) tip adıyla aynıysa yazılır
    /// (Swift hatalarının varsayılan alanı tip adıdır); başka her alan "özel" olarak gizlenir.
    static func domain(_ domain: String, typeName: String?) -> String {
        if knownDomains.contains(domain) || (domain == typeName && typeName != "?") { return domain }
        return "özel"
    }

    /// `"<alan> <kod>[ ← <alan> <kod>]"` biçimini parça parça yeniden kurar; biçim dışı parça atılır.
    static func sanitizedCode(_ code: String, typeName: String) -> String {
        var out: [String] = []
        for (i, part) in code.components(separatedBy: " ← ").prefix(2).enumerated() {
            guard let space = part.lastIndex(of: " "), let n = Int(part[part.index(after: space)...]) else { break }
            out.append("\(domain(String(part[..<space]), typeName: i == 0 ? typeName : nil)) \(n)")
        }
        return out.isEmpty ? "özel 0" : out.joined(separator: " ← ")
    }

    static let identifierChars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
    static let keyChars = identifierChars.union(CharacterSet(charactersIn: ".-:"))

    /// Bağlam anahtarı ya olduğu gibi geçerlidir ya da hiç yazılmaz: süzmek (ör. bir yoldan harfleri bırakmak) içerik sızdırır.
    static func validKey(_ s: String) -> Bool {
        !s.isEmpty && s.count <= 64 && s.unicodeScalars.allSatisfy { $0.isASCII && keyChars.contains($0) }
    }

    static func clean(_ s: String, allowed: CharacterSet, limit: Int, fallback: String) -> String {
        let kept = String(String.UnicodeScalarView(s.unicodeScalars.filter { $0.isASCII && allowed.contains($0) }).prefix(limit))
        return kept.isEmpty ? fallback : kept
    }

    /// Tek satırlık gösterim: `2026-09-18T10:00:00Z  rapor.pdf  MarkaCore.MarkaError.validation [MarkaCore.MarkaError 0]`
    public var line: String {
        let iso = ISO8601DateFormatter()
        return "\(iso.string(from: at))  \(context)  \(type)\(caseName.map { "." + $0 } ?? "") [\(code)]"
    }
}

/// Son `capacity` hatayı küçük bir JSON dosyasında tutar. Veri tabanında değil: çalışma alanı açılamadığında ve
/// yedekten geri yüklemede de kayıt sürer, denetim olayı ve veri tabanı gözlemcisi tetiklenmez.
public final class DiagnosticsLog: @unchecked Sendable {
    public static let capacity = 200
    public static let fileName = "tani-kayitlari.json"

    /// nil ise yalnızca bellekte tutulur (testler).
    public let url: URL?
    private let lock = NSLock()
    private var cache: [DiagnosticEntry]

    public init(url: URL?) {
        self.url = url
        if let url, let data = try? Data(contentsOf: url),
           let list = try? Self.decoder.decode([DiagnosticEntry].self, from: data) {
            // Dosya uygulama dışında değiştirilmiş olabilir: yüklenen her kayıt yeniden süzülür.
            cache = list.suffix(Self.capacity).map(\.sanitized)
        } else {
            cache = []
        }
    }

    /// Çalışma alanı klasöründeki kayıt dosyası.
    public convenience init(workspace: URL) {
        self.init(url: workspace.appendingPathComponent(Self.fileName))
    }

    /// Hatayı içeriksiz kaydeder. Kullanıcının durdurduğu işler (iptal) hata sayılmaz.
    public func record(_ error: Error, context: String, at: Date = Date()) {
        if error is CancellationError { return }
        if let c = error as? CocoaError, c.code == .userCancelled { return }
        record(DiagnosticEntry(error: error, context: context, at: at))
    }

    public func record(_ entry: DiagnosticEntry) {
        lock.lock()
        defer { lock.unlock() }
        cache.append(entry)
        if cache.count > Self.capacity { cache.removeFirst(cache.count - Self.capacity) }
        guard let url else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? Self.encoder.encode(cache) { try? data.write(to: url, options: .atomic) }
    }

    /// Eskiden yeniye tüm kayıtlar.
    public func entries() -> [DiagnosticEntry] {
        lock.lock()
        defer { lock.unlock() }
        return cache
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

/// Tanı metninin tüm girdisi. Yalnızca sayı, bayrak ve sabit anahtar taşır.
public struct DiagnosticSnapshot: Sendable, Hashable {
    public enum CodexState: String, Sendable, Hashable { case girisli, girissiz, bilinmiyor }

    public var appVersion: String
    public var build: String
    public var macOS: String
    public var architecture: String
    public var language: String
    public var interfaceLanguage: String
    public var brandCount: Int
    public var archivedBrandCount: Int
    public var sourceCount: Int
    public var taskCount: Int
    public var reportCount: Int
    public var anthropicKeyPresent: Bool
    public var anthropicAllowedBrands: Int
    public var codex: CodexState
    public var codexAllowedBrands: Int
    /// Eskiden yeniye; metne son 20'si yazılır.
    public var errors: [DiagnosticEntry]
    public var metrics: BetaMetrics?

    public init(appVersion: String, build: String, macOS: String, architecture: String, language: String, interfaceLanguage: String,
                brandCount: Int, archivedBrandCount: Int, sourceCount: Int, taskCount: Int, reportCount: Int,
                anthropicKeyPresent: Bool, anthropicAllowedBrands: Int, codex: CodexState, codexAllowedBrands: Int,
                errors: [DiagnosticEntry], metrics: BetaMetrics?) {
        self.appVersion = appVersion; self.build = build; self.macOS = macOS; self.architecture = architecture
        self.language = language; self.interfaceLanguage = interfaceLanguage
        self.brandCount = brandCount; self.archivedBrandCount = archivedBrandCount; self.sourceCount = sourceCount
        self.taskCount = taskCount; self.reportCount = reportCount
        self.anthropicKeyPresent = anthropicKeyPresent; self.anthropicAllowedBrands = anthropicAllowedBrands
        self.codex = codex; self.codexAllowedBrands = codexAllowedBrands
        self.errors = errors; self.metrics = metrics
    }

    /// Veri tabanından yalnızca sayıları, günlükten kayıtları, sistemden sürüm/mimari/dil bilgisini toplar.
    public static func collect(store: Store?, log: DiagnosticsLog, anthropicKeyPresent: Bool, codex: CodexState,
                               bundle: Bundle = .main, now: Date = Date()) -> DiagnosticSnapshot {
        struct Counts { var brands = 0, archived = 0, sources = 0, tasks = 0, reports = 0, anthropic = 0, codex = 0 }
        var c = Counts()
        if let store, let read = try? store.read({ db -> Counts in
            var c = Counts()
            let brands = try Brand.fetchAll(db)
            c.brands = brands.count
            c.archived = brands.filter { $0.status == .archived }.count
            c.anthropic = brands.filter { $0.allows(.anthropic) }.count
            c.codex = brands.filter { $0.allows(.codex) }.count
            c.sources = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM source") ?? 0
            c.tasks = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM workTask") ?? 0
            c.reports = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM report") ?? 0
            return c
        }) { c = read }
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return DiagnosticSnapshot(
            appVersion: MarkaCoreVersion.string,
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "geliştirme",
            macOS: "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)",
            architecture: Self.architecture(),
            language: Locale.preferredLanguages.first ?? "?",
            interfaceLanguage: bundle.preferredLocalizations.first ?? "?",
            brandCount: c.brands, archivedBrandCount: c.archived, sourceCount: c.sources, taskCount: c.tasks, reportCount: c.reports,
            anthropicKeyPresent: anthropicKeyPresent, anthropicAllowedBrands: c.anthropic,
            codex: codex, codexAllowedBrands: c.codex,
            errors: log.entries(),
            metrics: store.flatMap { try? BetaMetrics.compute(store: $0, now: now) })
    }

    /// Mac mimarisi; Intel ikilisi Apple Silicon'da Rosetta ile çalışıyorsa belirtilir.
    static func architecture() -> String {
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        var translated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let rosetta = sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0) == 0 && translated == 1
        return machine + (rosetta ? " (Rosetta)" : "")
    }
}

public enum DiagnosticReport {
    public static let recentErrorLimit = 20

    /// Panoya kopyalanacak düz metin. Saf fonksiyon: yalnızca girdiyi biçimler, hiçbir şey okumaz.
    public static func render(_ s: DiagnosticSnapshot, now: Date) -> String {
        let iso = ISO8601DateFormatter()
        let recent = s.errors.suffix(recentErrorLimit).reversed()
        var lines = [
            "Marka Çalışma Alanı tanı bilgisi (içerik içermez)",
            "olusturma: \(iso.string(from: now))",
            "surum: \(s.appVersion) (build \(s.build))",
            "macos: \(s.macOS)",
            "mimari: \(s.architecture)",
            "dil: \(s.language) (arayuz: \(s.interfaceLanguage))",
            "marka: \(s.brandCount) (arsivli: \(s.archivedBrandCount))",
            "kaynak: \(s.sourceCount) · gorev: \(s.taskCount) · rapor: \(s.reportCount)",
            "ai_anthropic: anahtar \(s.anthropicKeyPresent ? "var" : "yok") · izinli marka: \(s.anthropicAllowedBrands)",
            "ai_codex: \(s.codex.rawValue) · izinli marka: \(s.codexAllowedBrands)",
            "son_hatalar (\(recent.count)/\(s.errors.count), yeniden eskiye):",
        ]
        if recent.isEmpty { lines.append("  —") }
        lines += recent.map { "  " + $0.line }
        lines.append("")
        lines.append(s.metrics?.shareableSummary ?? "beta ölçümleri: çalışma alanı açık değil")
        return lines.joined(separator: "\n")
    }
}
