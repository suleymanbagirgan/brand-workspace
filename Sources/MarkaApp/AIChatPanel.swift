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
        .onChange(of: app.pendingChatPrompt) { _, _ in consumePending(chat, options) }
        .confirmationDialog(L("Bu marka için yapay zekâya izin verilsin mi?"), isPresented: Binding(get: { confirmProvider != nil }, set: { if !$0 { confirmProvider = nil } }), presenting: confirmProvider) { p in
            Button(LF("%@ ile paylaşmaya izin ver", p.displayName)) { allow(p) }
        } message: { p in
            Text(LF("“%1$@” markasının görev, not ve dosya içerikleri sohbet sırasında %2$@ sağlayıcısına gönderilir. İzni Marka Bilgileri › Ayrıntılar ve izinler'den geri alabilirsin.", brand.name, p.displayName))
        }
    }

    // MARK: Başlık

    private func header(_ chat: ChatModel, _ options: [AIProviderKind]) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles").font(.system(size: 14, weight: .semibold)).foregroundStyle(BrandTintStyle(key: brand.id))
            Text(L("Asistan")).font(.system(size: 14, weight: .semibold))
            Spacer()
            if options.count > 1 {
                Menu {
                    ForEach(options) { p in Button(p.displayName) { chat.provider = p } }
                } label: { Text((chat.provider ?? options[0]).displayName).font(.system(size: 11)).foregroundStyle(.secondary) }
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

    // MARK: Bağlı değil / izin yok

    @ViewBuilder private var unavailable: some View {
        let connected: [AIProviderKind] = [app.hasAnthropicKey ? .anthropic : nil, app.codexAccount != nil ? .codex : nil].compactMap { $0 }
        VStack(alignment: .leading, spacing: 16) {
            Spacer(minLength: 20)
            Image(systemName: "sparkles").font(.system(size: 30, weight: .light)).foregroundStyle(BrandTintStyle(key: brand.id))
            if connected.isEmpty {
                Text(L("Yapay zekâyı bağla")).font(.system(size: 18, weight: .bold)).tracking(-0.3)
                Text(L("Asistan, markanın görevlerini, notlarını ve dosyalarını okuyup sana ne yapacağını söyler, görev önerir. Başlamak için bir sağlayıcı bağla: Claude API anahtarı ya da Codex girişi."))
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                SettingsLink { Text(L("Ayarlar'ı aç")).frame(maxWidth: .infinity) }.actionPrimary()
            } else {
                Text(L("Bu marka için izin gerekli")).font(.system(size: 18, weight: .bold)).tracking(-0.3)
                Text(LF("Yapay zekâ “%@” markasının içeriklerini okuyacak. İçerik yalnızca izin verdiğin sağlayıcıya gider; izin her zaman geri alınabilir.", brand.name))
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
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
                        ForEach(chat.items) { item in MessageView(item: item, running: chat.running && item.id == chat.items.last?.id, brandId: brand.id).id(item.id) }
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
            Text(L("Ne yapmak istersin?")).font(.system(size: 20, weight: .bold)).tracking(-0.4)
            Text(LF("“%@” markasının görevlerini, hedeflerini, notlarını ve dosyalarını okuyabilirim. Önerilerim onayına gelir.", brand.name))
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(ChatPrompts.all, id: \.0) { prompt in
                    Button { chat.send(prompt.1, brand: brand, app: app) } label: {
                        HStack {
                            Text(prompt.0).font(.system(size: 12, weight: .medium))
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Design.panel))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Design.line))
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 8)
    }

    private func approvalCard(_ r: ApprovalRequest, _ chat: ChatModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(r.title, systemImage: "exclamationmark.shield").font(.system(size: 12, weight: .semibold))
            if !r.detail.isEmpty { Text(r.detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(6) }
            HStack {
                Button(L("Reddet")) { chat.respond(.decline, app: app) }.actionSecondary()
                Button(L("İzin ver")) { chat.respond(.accept, app: app) }.actionPrimary()
            }
        }
        .padding(12).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.orange.opacity(0.12)))
    }

    // MARK: Yazma alanı

    private func composer(_ chat: ChatModel, _ options: [AIProviderKind]) -> some View {
        @Bindable var chat = chat
        return VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField(L("Yapay zekâya sor…"), text: $chat.draft, axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 13)).lineLimit(1...6).focused($focused)
                    .onSubmit { chat.send(chat.draft, brand: brand, app: app) }
                    .padding(.vertical, 4)
                Button {
                    if chat.running { chat.stop(app: app) } else { chat.send(chat.draft, brand: brand, app: app) }
                } label: {
                    Image(systemName: chat.running ? "stop.circle.fill" : "arrow.up.circle.fill").font(.system(size: 24))
                        .foregroundStyle(chat.running || !chat.draft.trimmingCharacters(in: .whitespaces).isEmpty ? AnyShapeStyle(Design.accent) : AnyShapeStyle(.tertiary))
                }
                .buttonStyle(.plain).keyboardShortcut(.return, modifiers: .command).help(chat.running ? L("Durdur") : L("Gönder (↩)"))
                .accessibilityLabel(chat.running ? L("Durdur") : L("Gönder"))
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Design.windowBackground))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(focused ? AnyShapeStyle(Design.accent.opacity(0.6)) : AnyShapeStyle(Design.line), lineWidth: focused ? 1.5 : 1))
            HStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass").font(.system(size: 10))
                Text(LF("%@ · görev, hedef, not ve dosyaları okur", brand.name)).lineLimit(1)
                Spacer()
            }
            .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(12)
        .onAppear { focused = true }
    }

    private func consumePending(_ chat: ChatModel, _ options: [AIProviderKind]) {
        guard let prompt = app.pendingChatPrompt, !options.isEmpty else { return }
        app.pendingChatPrompt = nil
        chat.send(prompt, brand: brand, app: app)
    }
}

/// Tek mesaj: kullanıcı sağda yumuşak balon; asistan solda düz metin (markdown) ve altında araç/öneri olay kartları.
private struct MessageView: View {
    @Environment(AppModel.self) private var app
    let item: ChatModel.Item
    let running: Bool
    let brandId: String

    var body: some View {
        if item.role == .user {
            HStack {
                Spacer(minLength: 40)
                Text(item.text).font(.system(size: 13)).padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Design.accent.opacity(0.12)))
                    .textSelection(.enabled)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(item.events) { EventCard(event: $0, brandId: brandId) }
                if item.text.isEmpty && running {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text(L("Düşünüyor…")).font(.system(size: 12)).foregroundStyle(.secondary) }
                } else if !item.text.isEmpty {
                    Text(markdown(item.text)).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled)
                        .foregroundStyle(item.failed ? AnyShapeStyle(Design.danger) : AnyShapeStyle(.primary))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(allowsExtendedAttributes: true, interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

/// Araç olayı: "Görevleri okudu", "3 görev önerdi" gibi tek satır kart; öneri kartında "İncele" onay sayfasını açar.
private struct EventCard: View {
    @Environment(AppModel.self) private var app
    let event: ChatEventRecord
    let brandId: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                if !event.detail.isEmpty { Text(event.detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer(minLength: 4)
            if event.kind == .proposal {
                Button(L("İncele")) { app.brandSheet = .approvals(brandId) }.buttonStyle(.text).font(.system(size: 11, weight: .semibold))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.10)))
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
