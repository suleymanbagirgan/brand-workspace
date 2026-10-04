import MarkaCore
import SwiftUI

/// Marka başına sohbet durumu (Cursor tarzı asistan paneli). Motor (`ChatEngine`) sağlayıcı iznini, bağlamı, araçları ve kalıcı geçmişi yönetir;
/// buradaki model yalnızca akışı ekrana taşır. Yapay zekâ veriyi değiştirmez: önerilen görev/kayıtlar onay sayfasına düşer.
@Observable @MainActor
final class ChatModel {
    struct Item: Identifiable {
        let id: String
        var role: AIMessageRole
        var text: String
        var events: [ChatEventRecord] = []
        var failed = false
    }

    let brandId: String
    var items: [Item] = []
    var draft = ""
    var running = false
    var pendingApproval: ApprovalRequest?
    var provider: AIProviderKind?
    private(set) var loaded = false
    private var sessionId: String?
    private var task: Task<Void, Never>?

    init(brandId: String) { self.brandId = brandId }

    /// Son oturumu ve mesajlarını yükler (varsa).
    func load(app: AppModel) async {
        if ProcessInfo.processInfo.environment["MARKA_SOHBET_ORNEK"] == "1", !loaded {
            loaded = true
            items = [
                Item(id: "u1", role: .user, text: "Ne yapmalıyım?"),
                Item(id: "a1", role: .assistant, text: "Önce **gecikmiş** işe bak: *Teknik föyleri topla* dünden beri bekliyor. Ardından cuma günü verdiğin söz için teklifi bitir.\n\n1. Teknik föyleri topla (gecikti)\n2. Teklifi kontrol et ve gönder (cuma)\n3. Müşteriden bütçe onayını hatırlat\n\nİlk ikisi için görev önerdim; onay sayfasından ekleyebilirsin.",
                     events: [ChatEventRecord(kind: .toolRead, title: "Görevleri okudu", detail: "11 açık görev"),
                              ChatEventRecord(kind: .toolRead, title: "Notları ve dosyaları okudu", detail: "4 not · 2 dosya"),
                              ChatEventRecord(kind: .proposal, title: "2 görev önerdi", detail: "Onayına bekliyor")]),
            ]
            return
        }
        guard !loaded, let engine = app.engine else { return }
        loaded = true
        guard let session = (try? await engine.sessions(scope: .brand(brandId)))?.first else { return }
        sessionId = session.id
        provider = session.provider
        let messages = (try? await engine.messages(sessionId: session.id)) ?? []
        items = messages.map { m in
            Item(id: m.id, role: m.role, text: m.text, events: (try? Store.decodeEvents(m.eventsJSON)) ?? [], failed: m.state == .failed)
        }
    }

    func newChat(app: AppModel) {
        if running { stop(app: app) }
        sessionId = nil
        items = []
        running = false
    }

    /// Kullanılabilir sağlayıcılar: markanın izin verdiği ve bağlı olanlar.
    static func available(brand: Brand, app: AppModel) -> [AIProviderKind] {
        // Geliştirme: `MARKA_SOHBET_ORNEK=1` ekran doğrulaması için sağlayıcıyı bağlıymış gibi gösterir ve örnek bir konuşma yükler (API çağrısı yapmaz).
        if ProcessInfo.processInfo.environment["MARKA_SOHBET_ORNEK"] == "1" { return [.anthropic] }
        var out: [AIProviderKind] = []
        if brand.allows(.anthropic) && app.hasAnthropicKey { out.append(.anthropic) }
        if brand.allows(.codex) && app.codexAccount != nil { out.append(.codex) }
        return out
    }

    func send(_ text: String, brand: Brand, app: AppModel) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !running, let engine = app.engine else { return }
        let options = Self.available(brand: brand, app: app)
        guard let chosen = provider.flatMap({ options.contains($0) ? $0 : nil }) ?? options.first else { return }
        draft = ""
        running = true
        items.append(Item(id: UUID().uuidString, role: .user, text: clean))
        let assistantId = UUID().uuidString
        items.append(Item(id: assistantId, role: .assistant, text: ""))
        task = Task {
            do {
                if sessionId == nil || provider != chosen {
                    let s = try await engine.createSession(scope: .brand(brandId), provider: chosen, title: "")
                    sessionId = s.id
                    provider = chosen
                }
                guard let sid = sessionId else { return }
                for await event in await engine.send(sessionId: sid, text: clean) { apply(event, to: assistantId) }
            } catch {
                update(assistantId) { $0.failed = true; $0.text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
            }
            running = false
            app.revision += 1   // yeni öneriler/kayıtlar ekranlara yansısın
        }
    }

    private func apply(_ event: AIEvent, to id: String) {
        switch event {
        case .textDelta(let t): update(id) { $0.text += t }
        case .event(let e): update(id) { $0.events.append(e) }
        case .eventUpdated(let e): update(id) { if let i = $0.events.firstIndex(where: { $0.id == e.id }) { $0.events[i] = e } }
        case .approvalNeeded(let r): pendingApproval = r
        case .failed(let m): update(id) { $0.failed = true; if $0.text.isEmpty { $0.text = m } }
        case .usage, .finished: break
        }
    }

    private func update(_ id: String, _ change: (inout Item) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[i])
    }

    func respond(_ decision: ApprovalDecision, app: AppModel) {
        guard let r = pendingApproval, let engine = app.engine else { return }
        pendingApproval = nil
        Task { await engine.respond(approvalId: r.id, decision: decision) }
    }

    /// Çalışan yanıtı durdurur; kısmi metin ve olaylar kalıcı kaydedilir, öneriler uygulanmaz.
    func stop(app: AppModel) {
        guard let sid = sessionId, let engine = app.engine else { return }
        Task { await engine.cancel(sessionId: sid) }
    }
}

extension AppModel {
    /// Marka için sohbet modeli (marka başına tek; geçmiş kalıcıdır).
    func chat(for brandId: String) -> ChatModel {
        if let c = chats[brandId] { return c }
        let c = ChatModel(brandId: brandId)
        chats[brandId] = c
        return c
    }

    /// Asistanı açıp bir soruyu sorar ("Ne yapmalıyım?").
    func askAI(_ prompt: String) {
        showAssistant = true
        pendingChatPrompt = prompt
    }
}

/// Hazır sorular (boş sohbette görünür).
enum ChatPrompts {
    static let whatToDo = "Bu markanın tüm görevlerini, hedeflerini, bekleyen kararlarını, notlarını ve dosyalarını oku. Şu an ne yapmam gerektiğini öncelik sırasıyla söyle ve uygun olanları görev önerisi olarak ekle."
    static var all: [(String, String)] {
        [(L("Ne yapmalıyım?"), whatToDo),
         (L("Bu haftayı özetle"), "Bu hafta yapılan işleri ve bekleyenleri özetle; müşteriye gidecek rapor için eksik kalan bir şey var mı?"),
         (L("Gecikenleri toparla"), "Geciken ve yaklaşan işleri bul; her biri için bir sonraki adımı öner."),
         (L("Müşteriye e-posta taslağı"), "Bu haftanın doğrulanmış işlerinden müşteriye gönderilecek kısa bir e-posta taslağı yaz."),
         (L("Eksik bilgileri bul"), "Marka bilgilerinde ve kayıtlarda eksik ya da çelişkili olanları bul ve neyi tamamlamam gerektiğini söyle.")]
    }
}
