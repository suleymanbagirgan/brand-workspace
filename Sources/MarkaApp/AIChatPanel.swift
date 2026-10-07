import MarkaCore
import SwiftUI

/// Asistan paneli (Cursor tarzı, sağ kenarda): yapay zekâya marka hakkında sor; marka kayıtlarını (görev, hedef, karar, not, dosya) kendisi okur,
/// görev ve kayıt ÖNERİR; öneriler onay sayfasına düşer, sen onaylamadan hiçbir şey eklenmez. İçerik yalnız markanın izin verdiği sağlayıcıya gider.
struct AIChatPanel: View {
    @Environment(AppModel.self) private var app
    let brand: Brand
    @State private var confirmProvider: AIProviderKind?
    @FocusState private var focused: Bool

    var body: some View {
        let chat = app.chat(for: brand.id)
        let options = ChatModel.available(brand: brand, app: app)
        VStack(spacing: 0) {
            header(chat, options)
            Divider().opacity(0.5)
            if options.isEmpty { unavailable } else { conversation(chat, options) }
        }
        .background(.regularMaterial)
        .task(id: brand.id) { await chat.load(app: app); consumePending(chat, options) }
        .onChange(of: app.pendingChat) { _, _ in consumePending(chat, options) }
        .confirmationDialog(L("Bu marka için yapay zekâya izin verilsin mi?"), isPresented: Binding(get: { confirmProvider != nil }, set: { if !$0 { confirmProvider = nil } }), presenting: confirmProvider) { p in
            Button(LF("%@ ile paylaşmaya izin ver", p.displayName)) { allow(p) }
        } message: { p in
            // Codex: onaysız komut, açık ağ ve ev dizini okuma yetkisi izin verilen yerde açıkça söylenir (güvence denetimi Y2).
            if p == .codex {
                Text(LF("“%1$@” markasının görev, not ve dosya içerikleri sohbet sırasında %2$@ sağlayıcısına gönderilir. Codex bu markanın klasöründe sana sormadan komut çalıştırabilir; komutlar internete çıkabilir ve diğer markalar dışında Mac'indeki dosyaları okuyabilir. İzni Marka Bilgileri › Ayrıntılar ve izinler'den geri alabilirsin.", brand.name, p.displayName))
            } else {
                Text(LF("“%1$@” markasının görev, not ve dosya içerikleri sohbet sırasında %2$@ sağlayıcısına gönderilir. İzni Marka Bilgileri › Ayrıntılar ve izinler'den geri alabilirsin.", brand.name, p.displayName))
            }
        }
    }

    // MARK: Başlık

    private func header(_ chat: ChatModel, _ options: [AIProviderKind]) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles").font(Design.Icon.medium.weight(.semibold)).foregroundStyle(BrandTintStyle(key: brand.id))
                .accessibilityHidden(true)   // süs; başlığın adı yanındaki "Asistan"
            roleMenu(chat, provider: chat.provider ?? options.first)
            Spacer()
            providerBadge(chat, options)
            if options.count > 1 {
                Menu {
                    ForEach(options) { p in Button(p.displayName) { chat.provider = p } }
                } label: { Text((chat.provider ?? options[0]).displayName).font(Design.Font.small).foregroundStyle(.secondary) }
                    .menuStyle(.borderlessButton).fixedSize()
            }
            Button { chat.newChat(app: app) } label: { Image(systemName: "square.and.pencil").frame(width: 26, height: 26) }
                .buttonStyle(.plain).foregroundStyle(.secondary).help(L("Yeni sohbet")).accessibilityLabel(L("Yeni sohbet"))
                .disabled(chat.items.isEmpty)
            Button { app.showAssistant = false } label: { Image(systemName: "sidebar.right").frame(width: 26, height: 26) }
                .buttonStyle(.plain).foregroundStyle(.secondary).help(L("Asistanı gizle (⌘J)")).accessibilityLabel(L("Asistanı gizle"))
        }
        .padding(.horizontal, 16).frame(height: 48)
    }

    /// E-24: o an seçili sağlayıcının rozeti. Metin sağlayıcının `onDevice` yeteneğinden gelir; yalnız hangi modelle konuşulduğunu söyler.
    @ViewBuilder private func providerBadge(_ chat: ChatModel, _ options: [AIProviderKind]) -> some View {
        let current = chat.provider.flatMap { options.contains($0) ? $0 : nil } ?? options.first
        if let current, let badge = app.engine?.badge(for: current) {
            Label(badge.text, systemImage: badge.onDevice ? "desktopcomputer" : "cloud")
                .labelStyle(.titleAndIcon).font(Design.Font.small).foregroundStyle(.secondary).lineLimit(1)
                .padding(.horizontal, Design.Space.s).padding(.vertical, Design.Space.xs)
                .background(Capsule().fill(Design.panel))
                .help(badge.detail).accessibilityElement(children: .ignore).accessibilityLabel(badge.detail)
        }
    }

    /// "Kim olarak?": genel asistan ya da markaya atanmış yapay zekâ çalışanlardan biri. Rol, görev tarifi ve yeteneklerle çalışır;
    /// yetki değişmez (yalnızca öneri).
    /// Rol şirket verisidir: Stüdyo bu sağlayıcıya izin vermiyorsa rol listesi boş kalır (çekirdek de reddeder).
    @ViewBuilder private func roleMenu(_ chat: ChatModel, provider: AIProviderKind?) -> some View {
        let allowed = app.store.map { ContextBuilder(store: $0).companyDataAllowed(brandId: brand.id, provider: provider) } ?? false
        let team = allowed ? (app.read(or: []) { try $0.brandTeam(brandId: brand.id) }).filter { $0.member.kind == .ai && $0.member.status == .active } : []
        let current = team.first { $0.member.id == chat.memberId }?.member
        if team.isEmpty {
            Text(L("Asistan")).font(Design.Font.heading.weight(.semibold))
        } else {
            Menu {
                Button(L("Asistan")) { chat.select(member: nil, app: app) }
                Divider()
                ForEach(team, id: \.member.id) { t in
                    Button("\(t.member.name) — \(t.member.title)") { chat.select(member: t.member.id, app: app) }
                }
            } label: {
                Text(current?.name ?? L("Asistan")).font(Design.Font.heading.weight(.semibold))
            }
            .menuStyle(.borderlessButton).fixedSize()
            .help(L("Kim olarak çalışsın?"))
            .accessibilityLabel(L("Çalışan rolü"))
        }
    }

    // MARK: Bağlı değil / izin yok

    /// MAS derlemesinde Codex girişi yok; yalnız Claude API anahtarı önerilir.
    private var connectHint: String {
        #if !MAS
        L("Asistan, markanın görevlerini, notlarını ve dosyalarını okuyup sana ne yapacağını söyler, görev önerir. Başlamak için bir sağlayıcı bağla: Claude API anahtarı ya da Codex girişi.")
        #else
        L("Asistan, markanın görevlerini, notlarını ve dosyalarını okuyup sana ne yapacağını söyler, görev önerir. Başlamak için Claude API anahtarını bağla.")
        #endif
    }

    @ViewBuilder private var unavailable: some View {
        let connected: [AIProviderKind] = [app.hasAnthropicKey ? .anthropic : nil, app.codexConnected ? .codex : nil].compactMap { $0 }
        VStack(alignment: .leading, spacing: 16) {
            Spacer(minLength: 20)
            Image(systemName: "sparkles").font(Design.Icon.hero.weight(.light)).foregroundStyle(BrandTintStyle(key: brand.id))
                .accessibilityHidden(true)
            if connected.isEmpty {
                Text(L("Yapay zekâyı bağla")).font(Design.Font.heading.weight(.bold)).tracking(-0.3)
                Text(connectHint)
                    .font(Design.Font.callout).foregroundStyle(.secondary).lineSpacing(3)
                SettingsLink { Text(L("Ayarlar'ı aç")).frame(maxWidth: .infinity) }.actionPrimary()
                // Doğru: görevler, dosyalar, finans ve rapor PDF'i (`ReportBuilder` + `ReportPDFRenderer`) sağlayıcısız çalışır;
                // AI yalnız rapordaki isteğe bağlı özette ve bu panelde kullanılır.
                Label(L("Bağlamadan da kullanabilirsin: görevler, dosyalar, finans ve rapor yapay zekâsız çalışır."), systemImage: "checkmark.circle")
                    .font(Design.Font.callout).foregroundStyle(.secondary).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(L("Bu marka için izin gerekli")).font(Design.Font.heading.weight(.bold)).tracking(-0.3)
                Text(LF("Yapay zekâ “%@” markasının içeriklerini okuyacak. İçerik yalnızca izin verdiğin sağlayıcıya gider; izin her zaman geri alınabilir.", brand.name))
                    .font(Design.Font.callout).foregroundStyle(.secondary).lineSpacing(3)
                ForEach(connected) { p in
                    Button { confirmProvider = p } label: { Text(LF("%@ ile kullan…", p.displayName)).frame(maxWidth: .infinity) }.actionPrimary()
                }
            }
            Spacer()
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func allow(_ provider: AIProviderKind) {
        var set = brand.allowedProviders
        set.insert(provider)
        app.perform(title: L("İzin verilemedi"), context: "marka.ai-izin") { try app.store?.setAIProviders(brand.id, providers: set) }
        app.reloadBasics()
    }

    // MARK: Sohbet

    private func conversation(_ chat: ChatModel, _ options: [AIProviderKind]) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if chat.items.isEmpty { welcome(chat, options) }
                        ForEach(chat.items) { item in
                            let isLast = item.id == chat.items.last?.id
                            MessageView(item: item, running: chat.running && isLast, brandId: brand.id,
                                        onRetry: isLast && chat.canRetry(currentBrandId: brand.id) ? { chat.retry(brand: brand, app: app) } : nil)
                                .id(item.id)
                        }
                        if let approval = chat.pendingApproval { approvalCard(approval, chat) }
                        Color.clear.frame(height: 1).id("alt")
                    }
                    .padding(16)
                }
                .onChange(of: chat.items.last?.text) { _, _ in proxy.scrollTo("alt") }
                .onChange(of: chat.items.count) { _, _ in withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("alt") } }
            }
            composer(chat, options)
        }
    }

    private func welcome(_ chat: ChatModel, _ options: [AIProviderKind]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Ne yapmak istersin?")).font(Design.Font.title.weight(.bold)).tracking(-0.4)
            Text(LF("“%@” markasının görevlerini, hedeflerini, notlarını ve dosyalarını okuyabilirim. Önerilerim onayına gelir.", brand.name))
                .font(Design.Font.callout).foregroundStyle(.secondary).lineSpacing(3)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(ChatPrompts.all(for: brand), id: \.0) { prompt in
                    Button { chat.send(prompt.1, brand: brand, app: app) } label: {
                        HStack {
                            Text(prompt.0).font(Design.Font.callout.weight(.medium))
                            Spacer()
                            Image(systemName: "arrow.up.right").font(Design.Icon.small).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous).fill(Design.panel))
                        .overlay(RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous).strokeBorder(Design.line))
                        .contentShape(RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 8)
    }

    private func approvalCard(_ r: ApprovalRequest, _ chat: ChatModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(r.title, systemImage: "exclamationmark.shield").font(Design.Font.callout.weight(.semibold))
            if !r.detail.isEmpty { Text(r.detail).font(Design.Font.small).foregroundStyle(.secondary).lineLimit(6) }
            HStack {
                Button(L("Reddet")) { chat.respond(.decline, app: app) }.actionSecondary()
                Button(L("İzin ver")) { chat.respond(.accept, app: app) }.actionPrimary()
            }
        }
        .padding(12).background(RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous).fill(Color.orange.opacity(0.12)))
    }

    // MARK: Yazma alanı

    private func composer(_ chat: ChatModel, _ options: [AIProviderKind]) -> some View {
        @Bindable var chat = chat
        return VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField(L("Yapay zekâya sor…"), text: $chat.draft, axis: .vertical)
                    .textFieldStyle(.plain).font(Design.Font.body).lineLimit(1...6).focused($focused)
                    .onSubmit { chat.send(chat.draft, brand: brand, app: app) }
                    .padding(.vertical, 4)
                Button {
                    if chat.running { chat.stop(app: app) } else { chat.send(chat.draft, brand: brand, app: app) }
                } label: {
                    Image(systemName: chat.running ? "stop.circle.fill" : "arrow.up.circle.fill").font(Design.Icon.large)
                        .foregroundStyle(chat.running || !chat.draft.trimmingCharacters(in: .whitespaces).isEmpty ? AnyShapeStyle(Design.accent) : AnyShapeStyle(.tertiary))
                }
                .buttonStyle(.plain).keyboardShortcut(.return, modifiers: .command).help(chat.running ? L("Durdur") : L("Gönder (↩)"))
                .accessibilityLabel(chat.running ? L("Durdur") : L("Gönder"))
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: Design.Radius.large, style: .continuous).fill(Design.windowBackground))
            .overlay(RoundedRectangle(cornerRadius: Design.Radius.large, style: .continuous).strokeBorder(focused ? AnyShapeStyle(Design.accent.opacity(0.6)) : AnyShapeStyle(Design.line), lineWidth: focused ? 1.5 : 1))
            HStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass").font(Design.Icon.small)
                Text(LF("%@ · görev, hedef, not ve dosyaları okur", brand.name)).lineLimit(1)
                Spacer()
            }
            .font(Design.Font.small).foregroundStyle(.secondary)
        }
        .padding(12)
        .onAppear { focused = true }
    }

    private func consumePending(_ chat: ChatModel, _ options: [AIProviderKind]) {
        // H2-02 (U-11): yuva her denemede boşalır; istem yalnız bu markaya aitse ve sağlayıcı hazırsa gönderilir.
        guard app.pendingChat.pending != nil,
              let prompt = app.pendingChat.take(brandId: brand.id, providerReady: !options.isEmpty) else { return }
        chat.send(prompt.text, brand: brand, app: app)
    }
}

/// Tek mesaj: kullanıcı sağda yumuşak balon; asistan solda düz metin (markdown) ve altında araç/öneri olay kartları.
private struct MessageView: View {
    @Environment(AppModel.self) private var app
    let item: ChatModel.Item
    let running: Bool
    let brandId: String
    /// H3-04: yalnız son hatalı yanıtta ve kural izin veriyorsa dolu ("Tekrar dene").
    var onRetry: (() -> Void)?

    var body: some View {
        if item.role == .user {
            HStack {
                Spacer(minLength: 40)
                Text(item.text).font(Design.Font.body).padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: Design.Radius.large, style: .continuous).fill(Design.accent.opacity(0.12)))
                    .textSelection(.enabled)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                // Hatalı yanıtta hata olayı kart olarak değil, aşağıdaki hata satırında gösterilir.
                ForEach(item.failed ? item.events.filter { $0.kind != .error } : item.events) { EventCard(event: $0, brandId: brandId) }
                if item.text.isEmpty && running {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text(L("Düşünüyor…")).font(Design.Font.callout).foregroundStyle(.secondary) }
                } else if item.failed {
                    // Yarım kalan yanıt metni (varsa) korunur; hata mesajı ayrı satırdadır.
                    if !item.text.isEmpty, item.text != item.failureMessage {
                        Text(markdown(item.text)).font(Design.Font.body).lineSpacing(4).textSelection(.enabled)
                    }
                    ErrorRow(message: item.failureMessage ?? AIErrorKind.unknown.userMessage(provider: nil),
                             kind: item.failureKind, onRetry: onRetry)
                } else if !item.text.isEmpty {
                    Text(markdown(item.text)).font(Design.Font.body).lineSpacing(4).textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(allowsExtendedAttributes: true, interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

/// H3-04: asistan hata satırı. Türün güvenli mesajı + tek eylem: anahtar/giriş hatasında "Ayarlar'ı aç", yeniden
/// denenebilir hatada "Tekrar dene" (yalnız son yanıtta ve aynı markada). Hız/aşırı yükte bekleme önerisi mesajın içindedir;
/// otomatik tekrar yok.
private struct ErrorRow: View {
    let message: String
    let kind: AIErrorKind?
    let onRetry: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle").font(Design.Icon.small.weight(.semibold)).foregroundStyle(Design.danger)
                .accessibilityHidden(true)
            Text(message).font(Design.Font.callout).foregroundStyle(.primary).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Spacer(minLength: 4)
            if kind?.action == .openSettings {
                SettingsLink { Text(L("Ayarlar'ı aç")) }.buttonStyle(.text).font(Design.Font.small.weight(.semibold))
            } else if let onRetry {
                Button(L("Tekrar dene"), action: onRetry).buttonStyle(.text).font(Design.Font.small.weight(.semibold))
                    .accessibilityHint(L("Son soruyu aynı markada yeniden gönderir"))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous).fill(Design.danger.opacity(0.10)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(LF("Hata: %@", message))
    }
}

/// Araç olayı: "Görevleri okudu", "3 görev önerdi" gibi tek satır kart; öneri kartında "İncele" onay sayfasını açar.
private struct EventCard: View {
    @Environment(AppModel.self) private var app
    let event: ChatEventRecord
    let brandId: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(Design.Icon.small.weight(.semibold)).foregroundStyle(tint).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(Design.Font.callout.weight(.medium)).lineLimit(2)
                if !event.detail.isEmpty { Text(event.detail).font(Design.Font.small).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer(minLength: 4)
            if event.kind == .proposal {
                Button(L("İncele")) { app.brandSheet = .approvals(brandId) }.buttonStyle(.text).font(Design.Font.small.weight(.semibold))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous).fill(tint.opacity(0.10)))
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch event.kind {
        case .toolRead: "doc.text.magnifyingglass"
        case .proposal: "checkmark.seal"
        case .fileChange: "doc.badge.plus"
        case .command: "terminal"
        case .approval: "exclamationmark.shield"
        case .notice: "info.circle"
        case .error: "exclamationmark.triangle"
        case .usage: "gauge"
        }
    }

    private var tint: AnyShapeStyle {
        switch event.kind {
        case .proposal: AnyShapeStyle(Design.accent)
        case .error: AnyShapeStyle(Design.danger)
        default: AnyShapeStyle(.secondary)
        }
    }
}
