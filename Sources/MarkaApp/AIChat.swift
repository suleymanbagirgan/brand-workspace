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
        /// H3-04: hatanın türü (çekirdekteki `ChatEventRecord.refId`'den); "Tekrar dene"/"Ayarlar'ı aç" buna göre.
        var failureKind: AIErrorKind?

        /// Hata satırında gösterilecek güvenli mesaj (türün mesajı; ham gövde yok).
        var failureMessage: String? {
            guard failed else { return nil }
            return events.last(where: { $0.kind == .error })?.detail ?? (text.isEmpty ? nil : text)
        }

        static func failureKind(in events: [ChatEventRecord]) -> AIErrorKind? {
            events.last(where: { $0.kind == .error })?.refId.flatMap(AIErrorKind.init(rawValue:))
        }
    }

    let brandId: String
    var items: [Item] = []
    var draft = ""
    var running = false
    var pendingApproval: ApprovalRequest?
    var provider: AIProviderKind?
    /// Sohbetin hangi yapay zekâ çalışanın rolüyle yürüdüğü (`nil` = genel asistan).
    private(set) var memberId: String?
    private var sessionMemberId: String?
    private(set) var loaded = false
    private var sessionId: String?
    private var task: Task<Void, Never>?
    /// H3-04: son gönderilen istek ve sorulduğu marka ("Tekrar dene" yalnız aynı markada yeniden gönderir).
    private(set) var lastRequest: (text: String, brandId: String)?

    init(brandId: String) { self.brandId = brandId }

    /// Son oturumu ve mesajlarını yükler (varsa).
    func load(app: AppModel) async {
        if DevHook.value("MARKA_SOHBET_ORNEK") == "1", !loaded {
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
        memberId = session.memberId; sessionMemberId = session.memberId
        let messages = (try? await engine.messages(sessionId: session.id)) ?? []
        items = messages.map { m in
            let events = (try? Store.decodeEvents(m.eventsJSON)) ?? []
            return Item(id: m.id, role: m.role, text: m.text, events: events, failed: m.state == .failed,
                        failureKind: m.state == .failed ? Item.failureKind(in: events) : nil)
        }
        // Yeniden yüklenen geçmişte son istek, son kullanıcı mesajıdır (bu markada sorulmuş).
        if let last = items.last(where: { $0.role == .user }) { lastRequest = (last.text, brandId) }
    }

    /// Rolü değiştirir: yeni bir sohbet başlar (bir sohbet tek rolde yürür).
    func select(member id: String?, app: AppModel) {
        guard id != memberId else { return }
        newChat(app: app)
        memberId = id
    }

    func newChat(app: AppModel) {
        if running { stop(app: app) }
        sessionId = nil; sessionMemberId = nil
        items = []
        running = false
    }

    /// Kullanılabilir sağlayıcılar: markanın izin verdiği ve bağlı olanlar.
    static func available(brand: Brand, app: AppModel) -> [AIProviderKind] {
        // Geliştirme: `MARKA_SOHBET_ORNEK=1` ekran doğrulaması için sağlayıcıyı bağlıymış gibi gösterir ve örnek bir konuşma yükler (API çağrısı yapmaz).
        if DevHook.value("MARKA_SOHBET_ORNEK") == "1" { return [.anthropic] }
        var out: [AIProviderKind] = []
        if brand.allows(.anthropic) && app.hasAnthropicKey { out.append(.anthropic) }
        if brand.allows(.codex) && app.codexConnected { out.append(.codex) }  // MAS: hep false
        #if !MAS
        if brand.allows(.local) && app.localModel != nil && AIProviderKind.local.isSelectable { out.append(.local) }  // E-24: MAS'ta seçilemez
        #endif
        return out
    }

    func send(_ text: String, brand: Brand, app: AppModel) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !running, let engine = app.engine else { return }
        let options = Self.available(brand: brand, app: app)
        guard let chosen = provider.flatMap({ options.contains($0) ? $0 : nil }) ?? options.first else { return }
        draft = ""
        running = true
        lastRequest = (clean, brandId)
        items.append(Item(id: UUID().uuidString, role: .user, text: clean))
        let assistantId = UUID().uuidString
        items.append(Item(id: assistantId, role: .assistant, text: ""))
        task = Task {
            do {
                if sessionId == nil || provider != chosen || sessionMemberId != memberId {
                    let s = try await engine.createSession(scope: .brand(brandId), provider: chosen, title: "", memberId: memberId)
                    sessionId = s.id
                    provider = chosen
                    sessionMemberId = memberId
                }
                guard let sid = sessionId else { return }
                for await event in await engine.send(sessionId: sid, text: clean) { apply(event, to: assistantId) }
            } catch {
                let failure = AIFailure(error: error, provider: chosen)
                update(assistantId) { $0.failed = true; $0.failureKind = failure.kind; $0.text = failure.message }
            }
            running = false
            // U-27: hata olursa soru kaybolmasın; yazma alanı boşsa taslak geri gelir.
            if items.first(where: { $0.id == assistantId })?.failed == true, draft.isEmpty { draft = clean }
            app.revision += 1   // yeni öneriler/kayıtlar ekranlara yansısın
        }
    }

    private func apply(_ event: AIEvent, to id: String) {
        switch event {
        case .textDelta(let t): update(id) { $0.text += t }
        case .event(let e): update(id) {
            $0.events.append(e)
            if e.kind == .error { $0.failureKind = AIErrorKind(rawValue: e.refId ?? "") ?? .unknown }
        }
        case .eventUpdated(let e): update(id) { if let i = $0.events.firstIndex(where: { $0.id == e.id }) { $0.events[i] = e } }
        case .approvalNeeded(let r): pendingApproval = r
        case .failed(let m): update(id) { $0.failed = true; if $0.text.isEmpty { $0.text = m } }
        case .usage, .finished: break
        }
    }

    /// "Tekrar dene" görünür mü: son yanıt hatalı, tür yeniden denenebilir ve istek bu markada sorulmuş (çekirdek kuralı).
    func canRetry(currentBrandId: String) -> Bool {
        guard let last = items.last, last.role == .assistant, last.failed else { return false }
        return AIErrorClassifier.canRetry(kind: last.failureKind, requestBrandId: lastRequest?.brandId,
                                          currentBrandId: currentBrandId, running: running)
    }

    /// Son isteği aynı markada yeniden gönderir; marka değiştiyse ya da tür yeniden denenemezse göndermez. Otomatik tekrar yok.
    func retry(brand: Brand, app: AppModel) {
        guard canRetry(currentBrandId: brand.id), let request = lastRequest else { return }
        let keptDraft = draft
        // Hatalı çift ekrandan kalkar (kalıcı geçmişte durur); istek yeniden gönderilir.
        if items.last?.failed == true { items.removeLast() }
        if items.last?.role == .user, items.last?.text == request.text { items.removeLast() }
        send(request.text, brand: brand, app: app)
        if keptDraft != request.text { draft = keptDraft }
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

    /// En az bir sağlayıcı bağlı mı (Anthropic anahtarı ya da girişli Codex). Markanın izni ayrıca `aiReady(for:)` ile sorulur.
    var aiConnected: Bool {
        DevHook.value("MARKA_SOHBET_ORNEK") == "1" || hasAnthropicKey || codexConnected
    }

    /// Bu markada istem gönderilebilir mi (bağlı ve markanın izin verdiği bir sağlayıcı var).
    func aiReady(for brand: Brand) -> Bool { !ChatModel.available(brand: brand, app: self).isEmpty }

    /// Asistanı açıp bir soruyu sorar ("Ne yapmalıyım?"). H2-02 (U-11): istem yalnız sağlayıcı hazırsa bekletilir ve
    /// yalnız sorulduğu markada gönderilir; hazır değilse bekletilmez (sonra kendiliğinden gönderilmez), panel bağlama/izin ekranını gösterir.
    func askAI(_ prompt: String, brandId: String? = nil) {
        guard let brand = brandId.flatMap({ id in brands.first { $0.id == id } }) ?? selectedBrand else {
            pendingChat.providerLost()
            return
        }
        pendingChat.request(prompt, brandId: brand.id, providerReady: aiReady(for: brand))
        showAssistant = true
    }

    /// "Yapay zekâya sor" düğmelerinin ortak eylemi: hazırsa sorar; hiç sağlayıcı bağlı değilse Ayarlar'ı açar;
    /// bağlı ama markada izin yoksa paneli (izin ekranı) açar. Hazır değilken istem bekletilmez.
    func askOrConnect(_ prompt: String, brand: Brand, openSettings: OpenSettingsAction) {
        if aiReady(for: brand) {
            askAI(prompt, brandId: brand.id)
        } else if aiConnected {
            pendingChat.providerLost()
            showAssistant = true
        } else {
            pendingChat.providerLost()
            openSettings()
        }
    }

    /// Düğme metni: hazırsa "Yapay zekâya sor", değilse "Yapay zekâyı bağla…".
    func askAITitle(for brand: Brand) -> String { aiReady(for: brand) ? L("Yapay zekâya sor") : L("Yapay zekâyı bağla…") }
}

/// Hazır sorular (boş sohbette görünür).
enum ChatPrompts {
    static let whatToDo = "Bu markanın tüm görevlerini, hedeflerini, bekleyen kararlarını, notlarını ve dosyalarını oku. Şu an ne yapmam gerektiğini öncelik sırasıyla söyle ve uygun olanları görev önerisi olarak ekle."
    /// Kendi şirketimizde (Stüdyo) örnek istemler: kendi işlerimiz, ekip ve yeni müşteriler.
    static let studio: [(String, String)] = [
        (L("Bu hafta ne yapmalıyız?"), "Şirketin tüm görevlerini, hedeflerini ve ekibini oku. Bu hafta ne yapmamız gerektiğini öncelik sırasıyla söyle ve uygun olanları görev önerisi olarak ekle."),
        (L("Ekibe çalışan öner"), "Ekibi, hizmetleri ve açık görevleri oku. Ekipte eksik ya da yoğun bir rol varsa, o rol için bir yapay zekâ çalışan öner (calisan_oner): ad, unvan, kıdem, kime bağlı olacağı, görev tarifi ve yetenekleri. Neden gerektiğini bir cümleyle açıkla."),
        (L("Web sitesini planla"), "Web sitesi ve portfolyo işlerine bak. Biten işlerden siteye eklenecekleri ve siteyi geliştirmek için sıradaki küçük adımları görev önerisi olarak çıkar."),
        (L("Reklam planı çıkar"), "Reklam ve büyüme işlerine, bütçeye ve hedeflere bak. Bu ay için kısa bir reklam planı ve görev önerileri çıkar; harcama kararını bana bırak."),
        (L("Yeni müşteri görüşmesine hazırla"), "Satış hattındaki görevlere ve hizmetlerimize bak. Yaklaşan bir potansiyel müşteri görüşmesi için gündem, sorular ve görev önerileri hazırla."),
    ]

    static func all(for brand: Brand) -> [(String, String)] { brand.isOwn ? studio : all }

    static var all: [(String, String)] {
        [(L("Ne yapmalıyım?"), whatToDo),
         (L("Bu haftayı özetle"), "Bu hafta yapılan işleri ve bekleyenleri özetle; müşteriye gidecek rapor için eksik kalan bir şey var mı?"),
         (L("Gecikenleri toparla"), "Geciken ve yaklaşan işleri bul; her biri için bir sonraki adımı öner."),
         (L("Müşteriye e-posta taslağı"), "Bu haftanın doğrulanmış işlerinden müşteriye gönderilecek kısa bir e-posta taslağı yaz."),
         (L("Eksik bilgileri bul"), "Marka bilgilerinde ve kayıtlarda eksik ya da çelişkili olanları bul ve neyi tamamlamam gerektiğini söyle.")]
    }
}
