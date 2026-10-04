import AppKit
import MarkaCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // SwiftPM ile derlenen uygulama paketi dışından çalıştırılırsa ön plana gelsin.
        // Geliştirme: `MARKA_GORUNUM=light|dark` uygulamanın görünümünü sistemden bağımsız seçer (ekran doğrulaması için).
        switch ProcessInfo.processInfo.environment["MARKA_GORUNUM"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        if ProcessInfo.processInfo.environment["MARKA_GORUNUM"] == nil { AppModel.applyAppearance(AppModel.shared.appearance) }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Menü çubuğu simgesi açıksa pencere kapanınca uygulama yaşamaya devam eder.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !AppModel.shared.showMenuBarExtra }

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
        WindowGroup("Workspace AI", id: "main") {
            RootView()
                .environment(app)
                .defaultAppStorage(app.preferences.defaults)
                .tint(Design.accentFill)
                .frame(minWidth: 1100, minHeight: 700)
                .onAppear { SnapshotRunner.runIfRequested(app: app) }
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .windowResizability(.contentMinSize)
        .commands {
            AppCommands(app: app)
            SidebarCommands()   // Görünüm › Kenar Çubuğunu Gizle/Göster (⌃⌘S)
        }

        MenuBarExtra(isInserted: Binding(get: { app.showMenuBarExtra || app.runningTimer != nil }, set: { app.showMenuBarExtra = $0 })) {
            MenuBarPopover().environment(app)
        } label: {
            MenuBarLabel().environment(app)
        }
        .menuBarExtraStyle(.window)

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
            Button(L("Yeni görev")) {
                if let brand = app.selectedBrand ?? app.brands.first { app.select(brand: brand.id, tab: .todo); app.addTaskRequested = true }
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(app.brands.isEmpty)
            Button(L("Yeni marka…")) { app.showNewBrand = true }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        // HIG: aç/kapa komutları Görünüm menüsünde, değişen etiketle.
        CommandGroup(after: .toolbar) {
            Menu(L("Görünüm modu")) {
                ForEach([("light", L("Açık")), ("dark", L("Koyu")), ("system", L("Sistem"))], id: \.0) { item in
                    Button { app.appearance = item.0 } label: {
                        if app.appearance == item.0 { Label(item.1, systemImage: "checkmark") } else { Text(item.1) }
                    }
                }
            }
        }
        CommandGroup(after: .sidebar) {
            Button(app.showCompletedTasks ? L("Tamamlananları gizle") : L("Tamamlananları göster")) { app.showCompletedTasks.toggle() }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(app.selectedBrand == nil)
            Button(app.showAssistant ? L("Asistanı gizle") : L("Asistanı göster")) { app.showAssistant.toggle() }
                .keyboardShortcut("j", modifiers: .command)
                .disabled(app.selectedBrand == nil)
        }
        CommandGroup(after: .textEditing) {
            Button(L("Komut paleti…")) { app.showPalette = true }
                .keyboardShortcut("k", modifiers: .command)
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
        @Bindable var app = app
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
        .sheet(isPresented: $app.showPalette) { CommandPalette().environment(app) }
        // Çentik zamanlayıcısı: sayaç başlayıp bitince ya da ayar değişince pencereyi güncelle.
        .onAppear { NotchTimerController.shared.update(app: app) }
        .onChange(of: app.runningTimer?.id) { NotchTimerController.shared.update(app: app) }
        .onChange(of: app.showNotchTimer) { NotchTimerController.shared.update(app: app) }
        .onChange(of: app.notchDismissed) { NotchTimerController.shared.update(app: app) }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isSnapshot) private var isSnapshot
    var body: some View {
        // Markalar arası geçişte kısa çapraz solma (Hareketi Azalt açıksa anında).
        content
            .transition(.opacity)
            .animation(reduceMotion || isSnapshot ? nil : .easeInOut(duration: 0.18), value: app.selection)
    }

    @ViewBuilder private var content: some View {
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
    @Environment(\.isSnapshot) private var isSnapshot

    /// Arama kutusu görünümlü düğme: komut paletini açar (⌘K).
    private var searchField: some View {
        Button { app.showPalette = true } label: {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
                Text(L("Ara")).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Text(verbatim: "⌘K").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Design.windowBackground.opacity(0.7)))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Design.line))
        }
        .buttonStyle(.plain)
        .help(L("Komut paleti (⌘K)"))
        .accessibilityLabel(L("Komut paleti"))
    }

    var body: some View {
        if isSnapshot { snapshotBody } else { nativeBody }
    }

    /// Gerçek pencere: sistemin kenar çubuğu listesi. Okla gezinme, yazarak seçme, odak halkası, VoiceOver ve seçim rengi
    /// (sistem vurgusu) sistemden gelir. Arama kutusu üstte, "+ Marka" altta sabit durur.
    private var nativeBody: some View {
        // Arşivlenmiş markaların bekleyenleri sayılmaz.
        let total = app.brands.reduce(0) { $0 + app.approvalCount($1.id) }
        return List(selection: Binding(get: { app.selection }, set: { app.selection = $0 })) {
            rowLabel(L("Bugün"), count: total, item: .today).tag(SidebarItem.today)
            Section(L("Markalar")) {
                ForEach(app.brands) { brand in
                    rowLabel(brand.name, subtitle: brand.sector, count: app.approvalCount(brand.id), item: .brand(brand.id), brandName: brand.name, tintKey: brand.id)
                        .tag(SidebarItem.brand(brand.id))
                        .contextMenu {
                            Button(L("Klasörü Finder'da göster")) {
                                if let folder = app.writeContext(brandId: brand.id) { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                            }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) { searchField.padding(.horizontal, Design.Space.s).padding(.top, Design.Space.s).padding(.bottom, 4) }
        .safeAreaInset(edge: .bottom, spacing: 0) { newBrandFooter }
        .onChange(of: app.selection) { _, new in
            if case .brand(let id) = new { app.preferences.set(id, forKey: "lastBrand") }
        }
    }

    @ViewBuilder private var newBrandFooter: some View {
        if app.showNewBrand {
            NewBrandField().padding(.horizontal, Design.Space.s).padding(.vertical, Design.Space.s)
        } else {
            HStack {
                Button(L("+ Marka")) { app.showNewBrand = true }.buttonStyle(.text).help(L("Yeni marka (⇧⌘N)"))
                Spacer()
            }
            .padding(.horizontal, Design.Space.s).padding(.vertical, Design.Space.s)
        }
    }

    /// Ekran çizimi (ImageRenderer liste çizemez): özel satırlar.
    private var snapshotBody: some View {
        // Arşivlenmiş markaların bekleyenleri sayılmaz.
        let total = app.brands.reduce(0) { $0 + app.approvalCount($1.id) }
        return VStack(alignment: .leading, spacing: 0) {
            searchField.padding(.horizontal, Design.Space.s).padding(.top, Design.Space.s).padding(.bottom, 2)
            PageScroll {
                VStack(alignment: .leading, spacing: 4) {
                    row(L("Bugün"), count: total, item: .today)
                    Text(L("Markalar")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 9).padding(.top, Design.Space.l).padding(.bottom, 2)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(app.brands) { brand in
                        row(brand.name, subtitle: brand.sector, count: app.approvalCount(brand.id), item: .brand(brand.id), brandName: brand.name, tintKey: brand.id)
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
        // Gerçek pencerede arka plan verilmez: kenar çubuğu sistem malzemesini (macOS 26'da cam) kendisi alır.
        // Düz renk yalnız ekran çiziminde (ImageRenderer malzemeyi çizemez).
        .background { if isSnapshot { Rectangle().fill(Design.sidebarBackground) } }
        .onChange(of: app.selection) { _, new in
            if case .brand(let id) = new { app.preferences.set(id, forKey: "lastBrand") }
        }
    }

    /// Satırın içeriği: marka avatarı, ad, sektör alt satırı ve onay sayısı.
    private func rowLabel(_ title: String, subtitle: String? = nil, count: Int, item: SidebarItem, brandName: String? = nil, tintKey: String? = nil) -> some View {
        let selected = app.selection == item
        return HStack(spacing: 11) {
            if let brandName { BrandAvatar(name: brandName, tintKey: tintKey, selected: selected) }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: selected ? .semibold : .medium)).lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: Design.Space.s)
            if count > 0 {
                Text(verbatim: "\(count)").font(.system(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(Design.accent)
            }
        }
        .padding(.vertical, brandName == nil ? 2 : 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(count > 0 ? LF("%1$@, %2$d öneri onay bekliyor", title, count) : title)
    }

    private func row(_ title: String, subtitle: String? = nil, count: Int, item: SidebarItem, brandName: String? = nil, tintKey: String? = nil) -> some View {
        let selected = app.selection == item
        return Button { app.selection = item } label: {
            rowLabel(title, subtitle: subtitle, count: count, item: item, brandName: brandName, tintKey: tintKey)
                .padding(.horizontal, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? AnyShapeStyle(Design.rowSelected) : AnyShapeStyle(.clear)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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


/// Menü çubuğu simgesi: yığın simgesi ve bekleyen onay sayısı (sıfırken yalnız simge).
struct MenuBarLabel: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        let total = app.brands.reduce(0) { $0 + app.approvalCount($1.id) }
        HStack(spacing: 4) {
            if app.runningTimer != nil {
                // Zamanlayıcı çalışırken menü çubuğunda canlı süre (çentiğin yanında).
                Image(systemName: "timer")
                Text(Timecode.string(app.elapsed)).monospacedDigit()
            } else {
                Image(systemName: "square.stack.3d.up")
                if total > 0 { Text(verbatim: "\(total)").monospacedDigit() }
            }
        }
        .accessibilityLabel(total > 0 ? LF("Workspace AI, %d onay bekliyor", total) : "Workspace AI")
        // Menü çubuğu simgesi açıkken SwiftUI ana pencereyi kendiliğinden açmıyordu (uygulama açılıyor ama pencere yoktu): açılışta pencere yoksa aç.
        .task {
            try? await Task.sleep(for: .milliseconds(700))
            if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}

/// Menü çubuğu menüsü: markalara göre bekleyen onaylar, uygulamayı aç, Bugün, simgeyi gizle. Yalnız gezinme; veri değiştirmez.
struct MenuBarSummary: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let pending = app.brands.filter { app.approvalCount($0.id) > 0 }
        if let task = app.runningTask {
            Text(LF("%1$@ · %2$@", task.title, Timecode.string(app.elapsed)))
            Button(L("Zamanlayıcıyı durdur")) { app.stopTimer() }
            Divider()
        }
        if pending.isEmpty {
            Text(L("Onay bekleyen bir şey yok"))
        } else {
            ForEach(pending) { brand in
                Button(LF("%1$@ · %2$d onay bekliyor", brand.name, app.approvalCount(brand.id))) {
                    show()
                    app.select(brand: brand.id)
                    app.brandSheet = .approvals(brand.id)
                }
            }
        }
        Divider()
        Button(L("Bugün")) { show(); app.selection = .today }
        Button(L("Workspace AI'ı aç")) { show() }
        Divider()
        Button(L("Menü çubuğu simgesini gizle")) { app.showMenuBarExtra = false }
    }

    /// Uygulamayı öne getirir; pencere kapalıysa yeniden açar.
    private func show() {
        NSApp.activate(ignoringOtherApps: true)
        if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) { openWindow(id: "main") }
    }
}


/// Menü çubuğu simgesine tıklayınca açılan hızlı aksiyon paneli: çalışan zamanlayıcı, hızlı görev ekleme, sıradaki görevleri
/// tek tıkla başlatma, bekleyen onaylar ve kısayollar. Yalnız gezinme ve kendi görev/sayaç eylemleri; veri silmez.
struct MenuBarPopover: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    @State private var title = ""
    @State private var brandId = ""
    @State private var added = false
    @FocusState private var focused: Bool

    private var selectedBrandId: String { brandId.isEmpty ? (app.selectedBrand?.id ?? app.brands.first?.id ?? "") : brandId }

    var body: some View {
        let _ = app.revision
        let tasks = ((try? app.store?.tasks(brandId: nil, statuses: [.todo, .inProgress, .waiting])) ?? []).sorted(by: WorkTask.displayOrder).prefix(5)
        let pending = app.brands.filter { app.approvalCount($0.id) > 0 }
        VStack(alignment: .leading, spacing: 14) {
            if let task = app.runningTask {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Circle().fill(Color.red).frame(width: 8, height: 8)
                        Text(task.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    }
                    HStack {
                        Text(Timecode.string(app.elapsed)).font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
                        Spacer()
                        Button { app.stopTimer() } label: { Label(L("Durdur"), systemImage: "stop.fill").labelStyle(.titleAndIcon) }
                            .buttonStyle(.borderedProminent).tint(.red)
                    }
                    if app.notchDismissed {
                        Button(L("Çentikte tekrar göster")) { app.notchDismissed = false }.buttonStyle(.link).font(.system(size: 11))
                    }
                }
                .padding(12).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.red.opacity(0.10)))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Hızlı görev")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    TextField(L("Yeni görev…"), text: $title).textFieldStyle(.roundedBorder).focused($focused).onSubmit(add)
                    Picker("", selection: Binding(get: { selectedBrandId }, set: { brandId = $0 })) {
                        ForEach(app.brands) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden().frame(width: 110)
                }
                if added { Label(L("Eklendi"), systemImage: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(.green) }
            }
            if !tasks.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Sıradaki görevler")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.bottom, 4)
                    ForEach(Array(tasks), id: \.id) { task in
                        let running = app.runningTimer?.taskId == task.id
                        HStack(spacing: 10) {
                            Button { running ? app.stopTimer() : app.startTimer(task.id) } label: {
                                Image(systemName: running ? "stop.circle.fill" : "play.circle").font(.system(size: 18))
                                    .foregroundStyle(running ? Color.red : Color.secondary)
                            }
                            .buttonStyle(.plain).help(running ? L("Zamanlayıcıyı durdur") : L("Zamanlayıcıyı başlat"))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(task.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                Text(app.brands.first { $0.id == task.brandId }?.name ?? "").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if let d = task.dueDate { DueLabel(day: d) }
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
            if !pending.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(pending) { brand in
                        Button { show(); app.select(brand: brand.id); app.brandSheet = .approvals(brand.id) } label: {
                            HStack {
                                Image(systemName: "checkmark.seal.fill").foregroundStyle(Design.accent)
                                Text(LF("%1$@ · %2$d onay bekliyor", brand.name, app.approvalCount(brand.id))).font(.system(size: 12))
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Divider()
            HStack {
                Button(L("Bugün")) { show(); app.selection = .today }.buttonStyle(.link)
                Button(L("Uygulamayı aç")) { show() }.buttonStyle(.link)
                Spacer()
                Button(L("Simgeyi gizle")) { app.showMenuBarExtra = false }.buttonStyle(.link).foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
        }
        .padding(16).frame(width: 340)
        .onAppear { focused = true }
    }

    private func add() {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !selectedBrandId.isEmpty else { return }
        let ok: WorkTask?? = app.perform(title: L("Eklenemedi"), context: "menucubugu.gorev") { try app.store?.saveTask(WorkTask(brandId: selectedBrandId, title: t)) }
        guard ok != nil else { return }
        title = ""; added = true
        Task { try? await Task.sleep(for: .seconds(2)); added = false }
    }

    /// Uygulamayı öne getirir; pencere kapalıysa yeniden açar.
    private func show() {
        NSApp.activate(ignoringOtherApps: true)
        if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) { openWindow(id: "main") }
    }
}
