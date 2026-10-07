import AppKit
import MarkaCore
import SwiftUI

/// Geliştirme denetimi: `MARKA_SNAPSHOT=<klasör>` ile açılınca ana ekranları açık ve koyu görünümde PNG olarak çizer ve çıkar.
///
/// Pencere çizimi (`cacheDisplay`/katman) kenar çubuğunu, liste/kaydırma içeriğini ve koyu bölmeleri boş veriyordu (İ3 bulgu 2).
/// Bunun yerine her ekran `ImageRenderer` ile ayrı çizilir: aynı SwiftUI görünümleri, `\.isSnapshot` açıkken kaydırma
/// kapsayıcısız (`PageScroll`), `\.colorScheme` ve AppKit çizim görünümü (`NSAppearance`) birlikte ayarlanarak.
/// Pencere çerçevesi ve araç çubuğu çizilmez. Ekran kaydı izni gerekmez.
///
/// Yalnızca geçici veri alanıyla çalıştır (`MARKA_WORKSPACE` + `MARKA_FOLDERS`); bu kip tercih yazmaz, Keychain okumaz (D1).
@MainActor
enum SnapshotRunner {
    static func runIfRequested(app: AppModel) {
        guard let dir = DevHook.value("MARKA_SNAPSHOT") else { return }
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
                app.showAssistant = false
                screen.setup()
                for scheme in [ColorScheme.light, .dark] {
                    let file = out.appendingPathComponent("\(screen.name)-\(scheme == .light ? "acik" : "koyu").png")
                    if render(screen.view(), size: screen.size, scheme: scheme, app: app, to: file) { written.append(file.lastPathComponent) }
                }
            }
            print("SNAPSHOT: \(written.count) dosya → \(out.path)")
            for w in written { print("  \(w)") }
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
            for entry in [("16-dosyalar", BrandTab.files), ("17-marka-bilgileri", .info), ("18-finans", .finance)] {
                list.append(Screen(name: entry.0, setup: { app.select(brand: brand.id, tab: entry.1) }, view: { AnyView(shell { DetailView() }) }))
            }
            // Marka Bilgileri: bölümleri eksik ikinci marka ve "yapay zekâ gözüyle" önizlemesi açık hâl.
            if let other = app.customerBrands.first(where: { $0.id != brand.id }) {
                list.append(Screen(name: "17b-marka-bilgileri-eksik", setup: { app.select(brand: other.id, tab: .info) }, view: { AnyView(shell { DetailView() }) }))
                list.append(Screen(name: "17c-marka-bilgileri-onizleme", size: CGSize(width: 1500, height: 1300), setup: { app.select(brand: other.id, tab: .info) },
                                   view: { AnyView(shell { brandPage(other) { BrandProfileView(brand: other, showContext: true) } }) }))
            }
            list.append(Screen(name: "17d-marka-bilgileri-eksikler", size: CGSize(width: 1500, height: 1300), setup: { app.select(brand: brand.id, tab: .info) },
                               view: { AnyView(shell { brandPage(brand) { BrandProfileView(brand: brand, filter: .missing) } }) }))
            list.append(Screen(name: "14-gantt", setup: { app.select(brand: brand.id, tab: .todo) },
                               view: { AnyView(shell { brandPage(brand) { TodoView(brand: brand, mode: .gantt) } }) }))
            list.append(Screen(name: "14b-takvim", setup: { app.select(brand: brand.id, tab: .todo) },
                               view: { AnyView(shell { brandPage(brand) { TodoView(brand: brand, mode: .calendar) } }) }))
            list.append(Screen(name: "15-pano", setup: { app.select(brand: brand.id, tab: .todo) },
                               view: { AnyView(shell { brandPage(brand) { TodoView(brand: brand, mode: .board) } }) }))
            list.append(Screen(name: "19-terminal", size: CGSize(width: 1600, height: 1000),
                               setup: { app.select(brand: brand.id, tab: .todo); app.showAssistant = true },
                               view: { AnyView(shell { DetailView() }) }))
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
        // Örnek marka (varsa): bilgi şeridi olan Özet ve yapay zekâsız rapor.
        if let sampleId = try? app.store?.sampleBrandId(), let sample = app.brands.first(where: { $0.id == sampleId }) {
            list.append(Screen(name: "30-ornek-ozet", setup: { app.select(brand: sample.id, tab: .flow) }, view: { AnyView(shell { DetailView() }) }))
            list.append(Screen(name: "31-ornek-rapor", size: CGSize(width: 1280, height: 1100), setup: { app.select(brand: sample.id, tab: .report) },
                               view: { AnyView(shell { DetailView() }) }))
            list.append(Screen(name: "32-ornek-asistan", size: CGSize(width: 1600, height: 1000),
                               setup: { app.select(brand: sample.id, tab: .flow); app.showAssistant = true },
                               view: { AnyView(shell { DetailView() }) }))
        }
        // Ayarlar (iki sekme) ve ilk açılış: markadan bağımsız.
        // Stüdyo (kendi şirketimiz): Genel, Ekip, Yetenekler, Şema.
        if let own = app.ownBrand {
            for (i, entry) in [("genel", CompanyView.Tab.about), ("ekip", .team), ("yetenekler", .skills), ("sema", .chart)].enumerated() {
                list.append(Screen(name: "2\(i)-studyo-\(entry.0)", size: CGSize(width: 1500, height: 1100), setup: { app.select(brand: own.id, tab: .info) },
                                   view: { AnyView(shell { brandPage(own) { CompanyView(tab: entry.1) } }) }))
            }
        }
        list.append(Screen(name: "09-ayarlar-genel", size: CGSize(width: 620, height: 540), view: { AnyView(GeneralSettings()) }))
        list.append(Screen(name: "10-ayarlar-veri", size: CGSize(width: 620, height: 640), view: { AnyView(DataSettings()) }))
        list.append(Screen(name: "11-ilk-acilis", size: CGSize(width: 980, height: 640), view: { AnyView(OnboardingView()) }))
        return list
    }

    /// Marka ekranının çizim karşılığı (`BrandDetailView.page` ile aynı yerleşim), bölüm içeriği verilerek.
    static func brandPage<Content: View>(_ brand: Brand, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandHeader(brand: brand)
                .padding(.horizontal, 30).padding(.vertical, Design.Space.m)
                .overlay(alignment: .bottom) { Rectangle().fill(Design.line).frame(height: 1) }
            SectionTabs()
                .padding(.horizontal, 30)
            ApprovalBand(brand: brand)
                .padding(.horizontal, 30).padding(.top, Design.Space.m)
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
