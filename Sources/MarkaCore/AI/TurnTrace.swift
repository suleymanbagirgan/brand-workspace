import Foundation

// Yerel yapay zekâ tur izi (E-30): son asistan turlarının içeriksiz izi. Fikir langfuse/langfuse'un tur başına izinden ve
// getsentry/sentry'nin kara kutusundan alındı; kod özgündür, SDK ve ağ yoktur.
// İz yalnız bellekte tutulur: diske, tercihlere ya da ağa yazılmaz, hiçbir yere gönderilmez. Uygulama her açılışta boş
// tamponla başlar. Kullanıcı Tanı raporunu kendisi kopyalarsa "son_turlar" bölümünde görünür.
// İzde YOK: marka adı ya da kimliği, oturum kimliği, kullanıcı ya da model metni, araç girdisi ve çıktısı, hata mesajı.

/// Turun nasıl bittiği. Hata yalnız TÜRÜYLE (`AIErrorKind`) yazılır; mesaj yazılmaz.
public enum TurnOutcome: Sendable, Hashable {
    case tamam
    case durduruldu
    case hata(AIErrorKind)

    public var key: String {
        switch self {
        case .tamam: "tamam"
        case .durduruldu: "durduruldu"
        case .hata(let kind): "hata." + kind.rawValue
        }
    }
}

/// Tek asistan turunun içeriksiz izi.
public struct TurnTrace: Sendable, Hashable {
    /// Araç adı izinli kataloğun dışındaysa (model uydurduysa) bu ad yazılır: modelden gelen ad içerik taşıyabilir.
    public static let unknownTool = "bilinmeyen"
    /// Yazılabilen araç adları: yalnız koddaki sabit katalog.
    static let knownTools: Set<String> = Set((ToolCatalog.brandTools + ToolCatalog.allBrandTools).map(\.name))

    public var at: Date
    /// Oturum okunamadan biten turda nil.
    public var provider: AIProviderKind?
    public var durationMs: Int
    /// Araç ADI → çağrı sayısı. Girdi ve çıktı tutulmaz.
    public private(set) var toolCalls: [String: Int]
    /// Turda üretilen bekleyen öneri sayısı.
    public var proposalCount: Int
    /// Sağlayıcı kullanım bildirdiyse belirteç sayıları; bildirmediyse nil.
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var outcome: TurnOutcome

    public init(at: Date = Date(), provider: AIProviderKind?, durationMs: Int, toolNames: [String] = [], proposalCount: Int = 0,
                inputTokens: Int? = nil, outputTokens: Int? = nil, outcome: TurnOutcome) {
        self.at = at
        self.provider = provider
        self.durationMs = max(0, durationMs)
        var counts: [String: Int] = [:]
        for name in toolNames { counts[Self.knownTools.contains(name) ? name : Self.unknownTool, default: 0] += 1 }
        self.toolCalls = counts
        self.proposalCount = max(0, proposalCount)
        self.inputTokens = inputTokens.map { max(0, $0) }
        self.outputTokens = outputTokens.map { max(0, $0) }
        self.outcome = outcome
    }

    /// Tek satırlık gösterim:
    /// `2026-10-06T10:00:00Z  saglayici=anthropic sure_ms=820 sonuc=tamam araclar=gorev_oner:1,kaynak_ara:2 oneri=1 giris=1200 cikis=300`
    public var line: String {
        var parts = ["saglayici=\(provider?.rawValue ?? "—")", "sure_ms=\(durationMs)", "sonuc=\(outcome.key)"]
        let tools = toolCalls.keys.sorted().map { "\($0):\(toolCalls[$0]!)" }
        parts.append("araclar=\(tools.isEmpty ? "—" : tools.joined(separator: ","))")
        parts.append("oneri=\(proposalCount)")
        if let inputTokens { parts.append("giris=\(inputTokens)") }
        if let outputTokens { parts.append("cikis=\(outputTokens)") }
        return "\(ISO8601DateFormatter().string(from: at))  \(parts.joined(separator: " "))"
    }
}

/// Son `capacity` turu tutan bellek içi halka tampon. Kalıcı depo yoktur.
public final class TurnTraces: @unchecked Sendable {
    public static let capacity = 20
    /// Süreç boyunca tek tampon; uygulama kapanınca kaybolur.
    public static let shared = TurnTraces()

    private let lock = NSLock()
    private var buffer: [TurnTrace] = []

    public init() {}

    public func record(_ trace: TurnTrace) {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(trace)
        if buffer.count > Self.capacity { buffer.removeFirst(buffer.count - Self.capacity) }
    }

    /// Eskiden yeniye tüm izler.
    public func entries() -> [TurnTrace] {
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

/// Tur sürerken izin sayaçlarını toplar (ChatEngine içi). Araç girdisi/çıktısı ve olay metni burada da tutulmaz.
final class TurnTraceCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var tools: [String] = []
    private var input: Int?
    private var output: Int?

    func tool(_ name: String) { lock.withLock { tools.append(name) } }

    func observe(_ event: AIEvent) {
        guard case .usage(let u) = event else { return }
        lock.withLock {
            input = (input ?? 0) + u.inputTokens
            output = (output ?? 0) + u.outputTokens
        }
    }

    func trace(provider: AIProviderKind?, durationMs: Int, proposalCount: Int, outcome: TurnOutcome) -> TurnTrace {
        lock.withLock {
            TurnTrace(provider: provider, durationMs: durationMs, toolNames: tools, proposalCount: proposalCount,
                      inputTokens: input, outputTokens: output, outcome: outcome)
        }
    }
}
