import AppKit
import MarkaCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // SwiftPM ile derlenen uygulama paketi dışından çalıştırılırsa ön plana gelsin.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Çalışan terminal oturumu varsa tek soru (U9); yoksa sorusuz kapanır.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppModel.shared.confirmQuit() ? .terminateNow : .terminateCancel
    }
}

@main
struct MarkaCalismaAlaniApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var app = AppModel.shared

    var body: some Scene {
        WindowGroup(L("Marka Çalışma Alanı"), id: "main") {
            RootView()
                .environment(app)
                .defaultAppStorage(app.preferences.defaults)
                .tint(Design.accentFill)
                .frame(minWidth: 980, minHeight: 640)
                .onAppear { SnapshotRunner.runIfRequested(app: app) }
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands { AppCommands(app: app) }

        Settings {
            SettingsView()
                .environment(app)
                .defaultAppStorage(app.preferences.defaults)
                .tint(Design.accentFill)
        }
    }
}

/// Menü ve kısayollar (plan §4): ⌘0 Bugün · ⌘1 Akış · ⌘2 Yapılacaklar · ⌘3 Rapor · ⌘J Terminal · ⌘F Ara · ⇧⌘N Marka.
struct AppCommands: Commands {
    let app: AppModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button(L("Yeni marka…")) { app.showNewBrand = true }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        CommandMenu(L("Git")) {
            Button(L("Bugün")) { app.selection = .today }
                .keyboardShortcut("0", modifiers: .command)
            Divider()
            ForEach(BrandTab.allCases) { tab in
                Button(tab.title) {
                    if app.selectedBrand == nil, let first = app.brands.first { app.select(brand: first.id) }
                    app.brandTab = tab
                }
                .keyboardShortcut(KeyEquivalent(Character("\(tab.shortcutDigit)")), modifiers: .command)
                .disabled(app.brands.isEmpty)
            }
            Divider()
            Button(app.showTerminal ? L("Terminali gizle") : L("Terminali göster")) { app.showTerminal.toggle() }
                .keyboardShortcut("j", modifiers: .command)
                .disabled(app.selectedBrand == nil)
            Button(L("Ara")) {
                app.selection = .today
                app.focusSearch = true
            }
            .keyboardShortcut("f", modifiers: .command)
        }
        // Yardım belgesi yok; veri klasörü Ayarlar › Veri › Konum'da (tek yer).
        CommandGroup(replacing: .help) {}
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Group {
            if let error = app.startupError {
                EmptyStateView(title: L("Veri tabanı açılamadı"),
                               message: error + "\n\n" + L("Yedekten geri yüklemek için Ayarlar › Veri bölümünü kullanabilirsin."),
                               actionTitle: L("Tekrar dene")) { app.openWorkspace() }
                    .padding(Design.Space.l)
                    .frame(maxWidth: 520, maxHeight: .infinity, alignment: .topLeading)
            } else if app.showOnboarding {
                // İlk açılış tek ekran: pencerenin tamamı (sayfa değil).
                OnboardingView()
            } else {
                NavigationSplitView {
                    SidebarView()
                        .navigationSplitViewColumnWidth(min: 200, ideal: 224, max: 300)
                } detail: {
                    DetailView()
                }
            }
        }
        // Eylemsiz uyarı: sistem tek "Tamam" düğmesini kendisi koyar (Enter/Esc kapatır).
        .alert(app.alert?.title ?? "", isPresented: Binding(get: { app.alert != nil }, set: { if !$0 { app.alert = nil } })) {
        } message: {
            Text(app.alert?.message ?? "")
        }
    }
}

/// Seçime göre sağ bölme: Bugün ya da marka ekranı.
struct DetailView: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        switch app.selection {
        case .brand(let id):
            if let brand = app.brands.first(where: { $0.id == id }) {
                BrandDetailView(brand: brand).id(id)
            }
        case .today, .none:
            TodayView()
        }
    }
}

/// Kenar çubuğu: "Bugün" + markalar (onay bekleyen sayısı vurgu renginde) + en altta "+ Marka". Başka hiçbir şey.
/// Düz satırlar (liste denetimi değil): açık/koyu ekran çiziminde de aynı görünür. Arşivleme marka ··· menüsünde (tek yer).
struct SidebarView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        // Arşivlenmiş markaların bekleyenleri sayılmaz.
        let total = app.brands.reduce(0) { $0 + app.approvalCount($1.id) }
        VStack(alignment: .leading, spacing: 0) {
            PageScroll {
                VStack(alignment: .leading, spacing: Design.Space.xs) {
                    row(L("Bugün"), count: total, item: .today)
                    Text(L("Markalar")).captionStyle()
                        .padding(.horizontal, Design.Space.s).padding(.top, Design.Space.m)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(app.brands) { brand in
                        row(brand.name, count: app.approvalCount(brand.id), item: .brand(brand.id))
                    }
                }
                .padding(Design.Space.s)
            }
            if app.showNewBrand {
                NewBrandField()
                    .padding(.horizontal, Design.Space.s).padding(.vertical, Design.Space.s)
            } else {
                HStack {
                    Button(L("+ Marka")) { app.showNewBrand = true }
                        .buttonStyle(.text)
                        .help(L("Yeni marka (⇧⌘N)"))
                    Spacer()
                }
                .padding(.horizontal, Design.Space.s).padding(.vertical, Design.Space.s)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onChange(of: app.selection) { _, new in
            if case .brand(let id) = new { app.preferences.set(id, forKey: "lastBrand") }
        }
    }

    private func row(_ title: String, count: Int, item: SidebarItem) -> some View {
        let selected = app.selection == item
        return Button { app.selection = item } label: {
            HStack(spacing: Design.Space.s) {
                Text(title).lineLimit(1).fontWeight(selected ? .semibold : .regular)
                Spacer(minLength: Design.Space.s)
                if count > 0 {
                    Text(verbatim: "\(count)").font(Design.Font.caption).monospacedDigit().foregroundStyle(Design.accent)
                }
            }
            .padding(.horizontal, Design.Space.s).padding(.vertical, Design.Space.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Design.radius).fill(selected ? Design.selection : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count > 0 ? LF("%1$@, %2$d öneri onay bekliyor", title, count) : title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension View {
    /// Marka arşivleme onayı: ne olacağını ve nereden geri alınacağını söyler.
    func brandArchiveConfirmation(brand: Brand?, isPresented: Binding<Bool>, onArchived: @escaping () -> Void = {}) -> some View {
        modifier(BrandArchiveConfirmation(brand: brand, isPresented: isPresented, onArchived: onArchived))
    }
}

struct BrandArchiveConfirmation: ViewModifier {
    @Environment(AppModel.self) private var app
    let brand: Brand?
    @Binding var isPresented: Bool
    let onArchived: () -> Void
    func body(content: Content) -> some View {
        content.confirmationDialog(LF("“%@” arşivlensin mi?", brand?.name ?? ""), isPresented: $isPresented, presenting: brand) { b in
            Button(L("Arşivle")) {
                if app.perform({ try app.store?.setBrandArchived(b.id, archived: true) }) != nil { onArchived() }
            }
        } message: { _ in
            Text(L("Marka listeden kalkar; verisi silinmez. Ayarlar › Veri › “Arşivlenmiş markalar” bölümünden geri alabilirsin."))
        }
    }
}

/// Yeni marka: kenar çubuğunun altında tek alan (ad), ayrı sayfa yok. Yer tutucu Enter'ı söyler; sağda görünür "Ekle".
/// Esc ya da boşken alandan çıkmak vazgeçer. Sektör ve tanım ··· › Bilgiler'de.
struct NewBrandField: View {
    @Environment(AppModel.self) private var app
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Design.Space.xs) {
            InputField(title: L("Marka adı — ↩"), text: $name, focus: $focused)
                .onSubmit(add)
                .onExitCommand(perform: cancel)
                .onChange(of: focused) { _, now in
                    if !now && name.trimmingCharacters(in: .whitespaces).isEmpty { cancel() }
                }
                .help(L("Enter ekler, Esc vazgeçer"))
                .accessibilityLabel(L("Yeni marka adı"))
                .accessibilityHint(L("Enter ekler, Esc vazgeçer"))
                .accessibilityAction(named: L("Vazgeç"), cancel)
            Button(L("Ekle"), action: add)
                .buttonStyle(.text)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    private func cancel() {
        name = ""
        app.showNewBrand = false
    }

    private func add() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { cancel(); return }
        guard let created = app.perform({ try app.store?.createBrand(name: name) }), let brand = created else { return }
        app.reloadBasics()
        app.select(brand: brand.id, tab: .flow)
        cancel()
    }
}
