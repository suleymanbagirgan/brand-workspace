import AppKit
import MarkaCore
import SwiftUI

/// Geliştirme denetimi: `MARKA_SNAPSHOT=<klasör>` ile açılınca ana ekranları açık ve koyu görünümde PNG olarak çizer ve çıkar.
///
/// Pencere çizimi (`cacheDisplay`/katman) kenar çubuğunu, liste/kaydırma içeriğini ve koyu bölmeleri boş veriyordu (İ3 bulgu 2).
/// Bunun yerine her ekran `ImageRenderer` ile ayrı çizilir: aynı SwiftUI görünümleri, `\.isSnapshot` açıkken kaydırma
/// kapsayıcısız (`PageScroll`), `\.colorScheme` ve AppKit çizim görünümü (`NSAppearance`) birlikte ayarlanarak.
/// Pencere çerçevesi, araç çubuğu ve terminal (AppKit görünümü) çizilmez. Ekran kaydı izni gerekmez.
///
/// Yalnızca geçici veri alanıyla çalıştır (`MARKA_WORKSPACE` + `MARKA_FOLDERS`); bu kip tercih yazmaz, Keychain okumaz (D1).
@MainActor
enum SnapshotRunner {
    static func runIfRequested(app: AppModel) {
        guard let dir = ProcessInfo.processInfo.environment["MARKA_SNAPSHOT"] else { return }
        let out = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        Task { @MainActor in
            // Çalışma alanı açılsın, öneri kutusu taransın.
            try? await Task.sleep(for: .seconds(1))
            for brand in app.brands {
                app.scanSuggestions(brandId: brand.id)
                // `.task` ekran çiziminde çalışmaz: klasördeki yeni dosyalar (onay sayfasının "Dosyalar" grubu) doğrudan okunur.
                app.newFiles[brand.id] = (try? app.folders?.importableFiles(brandId: brand.id)) ?? []
            }
            var written: [String] = []
            for screen in screens(app: app) {
                app.showNewBrand = false
                app.showTerminal = false
                screen.setup()
                for scheme in [ColorScheme.light, .dark] {
                    let file = out.appendingPathComponent("\(screen.name)-\(scheme == .light ? "acik" : "koyu").png")
                    if render(screen.view(), size: screen.size, scheme: scheme, app: app, to: file) { written.append(file.lastPathComponent) }
                }
            }
            print("SNAPSHOT: \(written.count) dosya → \(out.path)")
            for w in written { print("  \(w)") }
            if ProcessInfo.processInfo.environment["MARKA_TERMINAL_PROVA"] != nil {
                for line in await terminalProva(app: app) { print(line) }
            }
            NSApp.terminate(nil)
        }
    }

    struct Screen {
        let name: String
        var size = CGSize(width: 1280, height: 800)
        /// Model durumunu ekran için ayarlar (seçim, sekme).
        var setup: () -> Void = {}
        let view: () -> AnyView
    }

    /// Çizilecek ekranlar. Kabuk (kenar çubuğu + ayrıntı) pencerenin içeriğiyle aynı bileşenlerden kurulur.
    static func screens(app: AppModel) -> [Screen] {
        var list = [Screen(name: "01-bugun", setup: { app.selection = .today }, view: { AnyView(shell { DetailView() }) })]
        // Onay bekleyeni olan marka varsa o (onay bandı görünsün), yoksa ilk marka.
        if let brand = app.brands.first(where: { (app.pendingCounts[$0.id] ?? 0) > 0 }) ?? app.brands.first {
            // Akış ve Yapılacaklar, sağ ayrıntı paneli kapalı ve açık (U3/U4). Panel seçimi görünüm durumudur; ilk değerle verilir.
            let flow = (try? app.store?.flow(brandId: brand.id)) ?? []
            let flowTarget = (flow.first { $0.kind == .workLog(.draft) } ?? flow.first).map(PanelTarget.init)
            let proposalTarget = flow.first { if case .proposalApplied = $0.kind { true } else { false } }.map(PanelTarget.init)
            let todoTarget = ((try? app.store?.todo(brandId: brand.id)) ?? []).first.map(PanelTarget.init)
            list.append(Screen(name: "02-akis", setup: { app.select(brand: brand.id, tab: .flow) },
                               view: { AnyView(shell { DetailView() }) }))
            list.append(Screen(name: "03-akis-panel", setup: { app.select(brand: brand.id, tab: .flow) },
                               view: { AnyView(shell { brandPage(brand) { FlowView(brand: brand, selection: flowTarget) } }) }))
            if let proposalTarget {
                list.append(Screen(name: "03b-akis-oneri-paneli", setup: { app.select(brand: brand.id, tab: .flow) },
                                   view: { AnyView(shell { brandPage(brand) { FlowView(brand: brand, selection: proposalTarget) } }) }))
            }
            list.append(Screen(name: "04-yapilacaklar", setup: { app.select(brand: brand.id, tab: .todo) },
                               view: { AnyView(shell { DetailView() }) }))
            list.append(Screen(name: "05-yapilacaklar-panel", setup: { app.select(brand: brand.id, tab: .todo) },
                               view: { AnyView(shell { brandPage(brand) { TodoView(brand: brand, selection: todoTarget) } }) }))
            list.append(Screen(name: "06-rapor", size: CGSize(width: 1280, height: 1100), setup: { app.select(brand: brand.id, tab: .report) },
                               view: { AnyView(shell { DetailView() }) }))
            list.append(Screen(name: "07-onay", size: CGSize(width: 680, height: 1000),
                               view: { AnyView(ApprovalSheet(brand: brand, pending: (try? app.store?.pendingApprovals(brandId: brand.id)) ?? PendingApprovals(),
                                                             files: app.newFiles[brand.id] ?? [])) }))
            // İş kaydı düzenleyicisi (U9: düz satırlar; sistem formu değil, çizilebilir).
            let draftLog = flow.first { $0.kind == .workLog(.draft) }.flatMap { try? app.store?.workLogDetail($0.entityId) }
            if let draftLog {
                list.append(Screen(name: "13-is-kaydi-duzenleyici", size: CGSize(width: 680, height: 900),
                                   view: { AnyView(WorkLogEditor(detail: draftLog)) }))
            }
            list.append(Screen(name: "08-bilgiler", size: CGSize(width: 680, height: 820),
                               view: { AnyView(BrandInfoView(brand: brand)) }))
            // Yeni marka: kenar çubuğunun altındaki tek alan.
            list.append(Screen(name: "12-yeni-marka", setup: { app.select(brand: brand.id, tab: .flow); app.showNewBrand = true },
                               view: { AnyView(shell { DetailView() }) }))
        }
        // Ayarlar (iki sekme) ve ilk açılış: markadan bağımsız.
        list.append(Screen(name: "09-ayarlar-genel", size: CGSize(width: 620, height: 540), view: { AnyView(GeneralSettings()) }))
        list.append(Screen(name: "10-ayarlar-veri", size: CGSize(width: 620, height: 640), view: { AnyView(DataSettings()) }))
        list.append(Screen(name: "11-ilk-acilis", size: CGSize(width: 980, height: 640), view: { AnyView(OnboardingView()) }))
        return list
    }

    /// Marka ekranının çizim karşılığı (`BrandDetailView.page` ile aynı yerleşim), bölüm içeriği verilerek.
    static func brandPage<Content: View>(_ brand: Brand, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandHeader(brand: brand)
                .padding(.horizontal, Design.Space.l).padding(.top, Design.Space.l).padding(.bottom, Design.Space.m)
            ApprovalBand(brand: brand)
                .padding(.horizontal, Design.Space.l).padding(.bottom, Design.Space.m)
            SectionTabs()
                .padding(.horizontal, Design.Space.l)
            content().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// Pencere içeriğinin çizim karşılığı: solda kenar çubuğu, sağda ayrıntı.
    static func shell<Detail: View>(@ViewBuilder detail: () -> Detail) -> some View {
        // Üstten hizalı: ayrıntı pencereden uzunsa (ör. rapor sayfası) kenar çubuğu ortaya kaymasın.
        HStack(alignment: .top, spacing: 0) {
            SidebarView().frame(width: 230)
            Divider()
            detail().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: Terminal oturumu provası (U9)

    /// `MARKA_TERMINAL_PROVA=1` ile: gerçek `DetailView` ekran dışı bir pencerede sürülür ve marka terminali oturumunun
    /// gizleme, yana alma, başka markaya ve Bugün'e geçişte **yaşadığı** gerçek kabukla ölçülür: süreç kimliği canlı mı,
    /// aynı görünüm mü, kabuktaki değişken korunuyor mu (kabuk marka klasörüne dosya yazar). Sonra arşivlemenin ve kapanışın
    /// süreci bitirdiği ölçülür. Yalnız geçici veri alanında çalıştır (`SHELL=/bin/sh` önerilir: kullanıcının zsh
    /// başlangıç dosyaları çalışmasın). Tıklama/klavye yerine model durumu değiştirilir; pencere ekranda görünmez.
    static func terminalProva(app: AppModel) async -> [String] {
        var out: [String] = []
        func check(_ ok: Bool, _ text: String) { out.append("TERMINAL PROVA: " + (ok ? "✓ " : "✗ ") + text) }
        guard app.brands.count >= 3, let folders = app.folders else { return ["TERMINAL PROVA: ✗ en az üç marka gerekir"] }
        let (a, b, c) = (app.brands[0], app.brands[1], app.brands[2])
        let host = NSHostingView(rootView: DetailView().environment(app).frame(width: 1000, height: 700))
        let window = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: 1000, height: 700), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        func step(_ change: () -> Void) async {
            change()
            host.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(700))
            host.layoutSubtreeIfNeeded()
        }
        func alive(_ pid: pid_t) -> Bool { pid > 0 && kill(pid, 0) == 0 }

        app.terminalOnSide = false
        await step { app.select(brand: a.id, tab: .flow); app.showTerminal = true }
        guard let sessionA = app.terminals.existing(a.id) else {
            window.close()
            return ["TERMINAL PROVA: ✗ A markasının oturumu başlamadı"]
        }
        let pidA = sessionA.pid
        func where_(_ s: TerminalSession) -> String {
            "pencere: \(s.view.window === window ? "bu" : (s.view.window == nil ? "yok" : "başka")), kap: \(s.view.superview.map { String(describing: type(of: $0)) } ?? "yok")"
        }
        check(alive(pidA) && sessionA.view.window != nil, "A oturumu başladı ve pencerede (pid \(pidA), \(where_(sessionA)))")
        sessionA.view.send(txt: "PROVA=ayni-kabuk\n")
        try? await Task.sleep(for: .milliseconds(500))

        await step { app.terminalOnSide = true }
        check(app.terminals.existing(a.id) === sessionA && alive(pidA) && sessionA.view.window != nil, "yana alınca aynı oturum, süreç canlı (\(where_(sessionA)))")
        await step { app.showTerminal = false }
        check(alive(pidA) && sessionA.view.window == nil, "gizleyince süreç canlı, görünüm pencereden çıktı")
        await step { app.showTerminal = true; app.select(brand: b.id, tab: .flow) }
        let sessionB = app.terminals.existing(b.id)
        check(sessionB != nil && sessionB !== sessionA && alive(pidA), "B'ye geçince B'nin kendi oturumu, A canlı")
        await step { app.selection = .today }
        check(alive(pidA) && (sessionB.map { alive($0.pid) } ?? false), "Bugün'e geçince iki oturum da canlı")
        await step { app.select(brand: a.id, tab: .todo); app.terminalOnSide = false }
        check(app.terminals.existing(a.id) === sessionA && sessionA.pid == pidA && sessionA.view.window != nil,
              "A'ya dönünce aynı görünüm ve aynı süreç yeniden bağlandı (\(where_(sessionA)))")
        // Kabuktaki değişken korunmuş mu: kabuk marka klasörüne yazar (yalıtım bu klasöre yazmaya izin verir).
        let dirA = try? folders.folder(for: .brand(a.id))
        let result = dirA?.appendingPathComponent("prova-sonuc.txt")
        if let result { try? FileManager.default.removeItem(at: result) }
        sessionA.view.send(txt: "echo \"$PROVA\" > prova-sonuc.txt\n")
        try? await Task.sleep(for: .seconds(1))
        let written = result.flatMap { try? String(contentsOf: $0, encoding: .utf8) }?.trimmingCharacters(in: .whitespacesAndNewlines)
        check(written == "ayni-kabuk", "kabuk değişkeni korundu (yazılan: \(written ?? "yok"))")
        if let result { try? FileManager.default.removeItem(at: result) }

        // Yalıtım ayarı değişince açık oturum sürer; başlık tek satırla söyler.
        let isolationBefore = app.terminalIsolation
        app.terminalIsolation.toggle()
        await step {}
        check(alive(pidA) && app.terminals.isolationDiffers(a.id, current: app.terminalIsolation), "yalıtım değişince oturum sürer, fark işaretli")
        app.terminalIsolation = isolationBefore

        // Arşivleme: yalnız o markanın süreci biter.
        await step { app.select(brand: c.id, tab: .flow) }
        let pidC = app.terminals.existing(c.id)?.pid ?? 0
        check(alive(pidC), "C oturumu başladı")
        await step {
            _ = app.perform { try app.store?.setBrandArchived(c.id, archived: true) }
            app.reloadBasics()
        }
        try? await Task.sleep(for: .seconds(3))
        check(!alive(pidC) && app.terminals.existing(c.id) == nil && alive(pidA), "C arşivlenince yalnız C'nin süreci bitti")
        _ = app.perform { try app.store?.setBrandArchived(c.id, archived: false) }
        app.reloadBasics()

        // Kapanış: tek soru sayısı ve sonlandırma (soru penceresi burada açılmaz; `confirmQuit` aynı sayıyı kullanır).
        check(app.terminals.quitQuestionCount == 2, "kapanışta sorulacak çalışan oturum sayısı 2")
        let pids = [pidA, sessionB?.pid ?? 0]
        app.terminals.handle(.appQuit).forEach { $0.terminate() }
        try? await Task.sleep(for: .seconds(3))
        check(pids.allSatisfy { !alive($0) } && app.terminals.quitQuestionCount == nil, "kapanışta tüm kabuklar sonlandı")
        app.showTerminal = false
        window.orderOut(nil)
        return out
    }

    @discardableResult
    static func render(_ view: AnyView, size: CGSize, scheme: ColorScheme, app: AppModel, to url: URL) -> Bool {
        // Ortam değerleri en dışta: zemin de ekran çizimi kipini ve görünümü görsün.
        let content = view
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(Design.windowBackground)
            .tint(Design.accentFill)
            .environment(app)
            .environment(\.isSnapshot, true)
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)!
        NSApp.appearance = appearance
        var image: CGImage?
        appearance.performAsCurrentDrawingAppearance { image = renderer.cgImage }
        guard let image, let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: url)) != nil
    }
}
