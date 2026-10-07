import Foundation

// MARK: - Sağlayıcı katmanı (H2-01)
//
// ChatEngine sağlayıcıdan bağımsız işi yapar: oturum, izin denetimi (marka × sağlayıcı), kullanıcı mesajı, araç yürütücü
// (marka kimliği + kapsam denetimi), iptal ve kalıcı geçmiş. Sağlayıcı yalnız modelle konuşur: akış, araç çağrısını
// `AITurn.callTool` ile geri verir, kullanım bilgisini yazar. Sağlayıcı seçimi tek yerde: `AIProviderRegistry`.

/// Sağlayıcının yetenekleri. ChatEngine bunlara göre turu kurar (ör. araç desteği yoksa araçsız tur).
struct AIProviderCapabilities: Sendable, Equatable {
    /// Araç (fonksiyon) çağrısı destekleniyor mu? `false` ise sağlayıcıya araç verilmez ve araç çağrısı reddedilir.
    var supportsTools: Bool
    /// Toplam bağlam penceresi (belirteç); `nil` = büyük ya da modele göre değişir (bağlam bütçesi uygulanmaz).
    var contextTokens: Int?
    /// Model cihaz üstünde mi çalışıyor (içerik Mac'ten çıkmaz)?
    var onDevice: Bool
    /// Kullanıcının API anahtarı gerekiyor mu?
    var needsAPIKey: Bool
}

/// Bir sohbet sağlayıcısı. Uygulamalar: `AnthropicProvider`, `CodexProvider` (`#if !MAS`), testlerde `FakeProvider`.
protocol AIProvider: Sendable {
    var kind: AIProviderKind { get }
    var capabilities: AIProviderCapabilities { get }
    /// Yeni oturumun model adı.
    func sessionModel(settings: AISettings) -> String
    /// Bir sohbet turunu çalıştırır. Metin `turn.emit(.textDelta)` ile akar; araç çağrıları `turn.callTool` üzerinden
    /// ChatEngine'in yürütücüsüne gider (sağlayıcı aracı kendisi çalıştırmaz); her model isteğinden önce
    /// `turn.checkCancellation()` çağrılır. `assistant` metni, belirteç ve maliyet toplamlarını taşır.
    func runTurn(_ turn: AITurn, assistant: inout AIMessage) async throws
    /// Süren turu sağlayıcı tarafında durdurur (görev iptaline ek olarak; ör. Codex `turn/interrupt`).
    func cancel(sessionId: String) async
}

/// Sağlayıcıya verilen tur girdisi.
struct AITurn: Sendable {
    var session: AISession
    var scope: SessionScope
    var allowedBrandIds: Set<String>
    /// Kullanıcının (kırpılmış) mesajı; ayrıca geçmişe yazılmıştır.
    var text: String
    var settings: AISettings
    /// Sağlayıcıya sunulan araçlar (yetenek `supportsTools == false` ise boş).
    var tools: [ToolSpec]
    var store: Store
    var folders: BrandFolders
    var approvals: ApprovalBroker
    var cancellation: TurnCancellation
    var emit: @Sendable (AIEvent) -> Void
    /// Araç yürütme: marka kimliği, kapsam ve iptal denetimi ChatEngine'de yapılır.
    var callTool: @Sendable (_ name: String, _ input: JSONValue) async -> ToolResult

    /// Kullanıcı durdurduysa (`ChatEngine.cancel`) ya da görev iptal edildiyse `CancellationError` fırlatır.
    func checkCancellation() throws {
        if cancellation.isCancelled { throw CancellationError() }
        try Task.checkCancellation()
    }

    /// Oturumun kalıcı mesajları (eskiden yeniye).
    func storedMessages() throws -> [AIMessage] { try ChatEngine.messages(store: store, sessionId: session.id) }
}

/// Sağlayıcı kaydı: sağlayıcı seçiminin tek yeri. Kayıtlı olmayan sağlayıcı reddedilir (ör. MAS derlemesinde Codex).
struct AIProviderRegistry: Sendable {
    private let providers: [AIProviderKind: any AIProvider]
    let all: [any AIProvider]

    init(_ list: [any AIProvider]) {
        all = list
        providers = Dictionary(list.map { ($0.kind, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func provider(for kind: AIProviderKind) throws -> any AIProvider {
        guard let p = providers[kind] else { throw MarkaError.ai(L("Bu sağlayıcı bu sürümde kullanılamaz.")) }
        return p
    }
}

/// Komut/dosya onayı bekleyen sağlayıcı istekleri (Codex). `ChatEngine.respond` buradan yanıtlar.
final class ApprovalBroker: @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [String: CheckedContinuation<ApprovalDecision, Never>] = [:]

    /// İsteği kaydeder, `registered` çağrılır (kartı göstermek için), kullanıcının kararını bekler.
    func wait(id: String, registered: () -> Void) async -> ApprovalDecision {
        await withCheckedContinuation { c in
            lock.lock(); waiters[id] = c; lock.unlock()
            registered()
        }
    }

    func resolve(id: String, decision: ApprovalDecision) {
        lock.lock(); let c = waiters.removeValue(forKey: id); lock.unlock()
        c?.resume(returning: decision)
    }
}

/// Bir turun durdurma işareti. `ChatEngine.cancel` işaretler; sağlayıcı bir sonraki model isteğinden önce, ChatEngine her
/// araç çağrısından önce bakar: durdurulmuş turda yeni istek ve yeni öneri olmaz.
final class TurnCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

extension AIProviderKind {
    public var displayName: String {
        switch self {
        case .anthropic: "Anthropic (Claude API)"
        case .codex: "OpenAI Codex"
        case .local: L("Bu Mac'teki model")
        case .apple: L("Apple Intelligence (cihaz üstü)")   // E-25
        }
    }
}

final class TextBox: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""
    func append(_ s: String) { lock.lock(); buffer += s; lock.unlock() }
    func drain() -> String { lock.lock(); defer { buffer = ""; lock.unlock() }; return buffer }
}

/// Olayları gönderim sırasıyla, eşzamanlı kaydeder.
final class EventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [ChatEventRecord] = []
    func record(_ event: AIEvent) {
        lock.lock(); defer { lock.unlock() }
        switch event {
        case .event(let e): list.append(e)
        case .eventUpdated(let e):
            if let i = list.firstIndex(where: { $0.id == e.id }) { list[i] = e } else { list.append(e) }
        default: break
        }
    }
    func events() -> [ChatEventRecord] { lock.lock(); defer { lock.unlock() }; return list }
}
