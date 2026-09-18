import AppKit
import MarkaCore
import SwiftUI

/// Marka ekranı kabuğu (plan §4): başlıkta marka adı, sağda "Terminal" ve "···"; altında (yalnız varsa) onay bandı ve
/// metin sekmeleri Akış · Yapılacaklar · Rapor. Terminal paneli altta ya da yanda açılır; oturumu `AppModel.terminals`'da
/// yaşar (gizlemek, marka değiştirmek ya da yer değiştirmek kabuğu öldürmez).
/// Marka açılınca BAGLAM.md kendiliğinden yazılır, öneri kutusu (`oneriler/`) birkaç saniyede bir, marka klasöründeki
/// eklenmemiş dosyalar her veri değişikliğinde arka planda taranır (ikisi de onay bandına düşer).
struct BrandDetailView: View {
    @Environment(AppModel.self) private var app
    let brand: Brand

    var body: some View {
        Group {
            if app.showTerminal && app.terminalOnSide {
                HSplitView {
                    page.frame(minWidth: 460)
                    TerminalPanel(brand: brand).frame(minWidth: 400, idealWidth: 480)
                }
            } else if app.showTerminal {
                VSplitView {
                    page.frame(minHeight: 300)
                    TerminalPanel(brand: brand).frame(minHeight: 160, idealHeight: 260)
                }
            } else {
                page
            }
        }
        .navigationTitle(brand.name)
        .brandSheets(brand: brand)
        .task(id: brand.id) {
            app.writeContext(brandId: brand.id)
            app.scanSuggestions(brandId: brand.id)
            // Öneri kutusu hafifçe taranır: tek klasör listesi; yeni dosya yoksa okuma yapılmaz. Son 1,5 saniyede değişen
            // dosya atlanır (yazılması sürüyor olabilir).
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                app.scanSuggestions(brandId: brand.id, settle: 1.5)
            }
        }
        .task(id: "\(brand.id)#\(app.revision)") { await app.scanNewFiles(brandId: brand.id) }
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandHeader(brand: brand)
                .padding(.horizontal, Design.Space.l).padding(.top, Design.Space.l).padding(.bottom, Design.Space.m)
            ApprovalBand(brand: brand)
                .padding(.horizontal, Design.Space.l).padding(.bottom, Design.Space.m)
            SectionTabs()
                .padding(.horizontal, Design.Space.l)
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder private var content: some View {
        switch app.brandTab {
        case .flow: FlowView(brand: brand)
        case .todo: TodoView(brand: brand)
        case .report: ReportsView(brand: brand)
        }
    }
}

/// Başlık: marka adı; sağda "Terminal" metin düğmesi ve "···" menüsü.
struct BrandHeader: View {
    @Environment(AppModel.self) private var app
    let brand: Brand
    @State private var archiving = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Design.Space.m) {
            Text(brand.name).font(Design.Font.title).lineLimit(1).accessibilityAddTraits(.isHeader)
            Spacer()
            // Açıkken seçili zemin (seçim dili); gizlemek oturumu bitirmez.
            Button(L("Terminal")) { app.showTerminal.toggle() }
                .buttonStyle(.text)
                .background(RoundedRectangle(cornerRadius: Design.radius).fill(app.showTerminal ? AnyShapeStyle(Design.selection) : AnyShapeStyle(.clear)))
                .help(app.showTerminal ? L("Terminali gizle (⌘J); oturum sürer") : L("Marka klasöründe terminal (⌘J)"))
                .accessibilityValue(app.showTerminal ? L("Açık") : L("Kapalı"))
            // Öneriler ve klasördeki yeni dosyalar onay bandından açılır (tek yer); menüde yinelenmez.
            TextMenu(title: "···", help: L("Diğer")) {
                Button(L("Bilgiler ve AI izinleri…")) { app.brandSheet = .info(brand.id) }
                Button(L("Klasörü Finder'da göster")) {
                    if let folder = app.writeContext(brandId: brand.id) { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                }
                Divider()
                Button(L("Dışa aktar…")) { exportBrand(app: app, brand: brand) }
                Button(L("Arşivle…")) { archiving = true }
            }
        }
        .brandArchiveConfirmation(brand: archiving ? brand : nil, isPresented: $archiving)
    }
}

/// Markayı klasöre dışa aktarır ve sonucu Finder'da gösterir.
@MainActor
func exportBrand(app: AppModel, brand: Brand) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.prompt = L("Buraya aktar")
    guard panel.runModal() == .OK, let dir = panel.url, let store = app.store else { return }
    if let out = app.perform(context: "marka.disa-aktar", { try BackupService(workspace: app.workspaceURL).exportBrand(brand.id, store: store, to: dir) }) {
        NSWorkspace.shared.activateFileViewerSelecting([out])
    }
}

/// Metin sekmeleri: seçili olan kalın ve vurgu renginde alt çizgili; altında ince ayraç.
struct SectionTabs: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: Design.Space.l) {
            ForEach(BrandTab.allCases) { tab in
                let selected = app.brandTab == tab
                Button { app.brandTab = tab } label: {
                    Text(tab.title)
                        .fontWeight(selected ? .semibold : .regular)
                        .foregroundStyle(selected ? .primary : .secondary)
                        .padding(.vertical, Design.Space.s)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Design.accent).frame(height: 2).opacity(selected ? 1 : 0)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(LF("%1$@ (⌘%2$d)", tab.title, tab.shortcutDigit))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer()
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Design.line).frame(height: 1) }
    }
}

extension View {
    /// Marka ekranının sayfaları (onay, Bilgiler ve AI izinleri).
    func brandSheets(brand: Brand) -> some View { modifier(BrandSheets(brand: brand)) }
}

struct BrandSheets: ViewModifier {
    @Environment(AppModel.self) private var app
    let brand: Brand
    func body(content: Content) -> some View {
        @Bindable var app = app
        content.sheet(item: $app.brandSheet) { sheet in
            Group {
                switch sheet {
                case .approvals: ApprovalSheet(brand: brand, pending: (try? app.store?.pendingApprovals(brandId: brand.id)) ?? PendingApprovals(),
                                               files: app.newFiles[brand.id] ?? [])
                case .info: BrandInfoView(brand: brand)
                }
            }
            .environment(app)
        }
    }
}
