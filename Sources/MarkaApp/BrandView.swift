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
    @State private var archiving = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isSnapshot) private var isSnapshot

    /// Kilit simgesinin ipucu: mutlak "veri burada durur" değil; AI açıksa içeriğin hangi sağlayıcıya gittiğini söyler.
    private var localDataHelp: String {
        let allowed = AIProviderKind.selectable.filter { brand.allows($0) }
        if allowed.isEmpty { return L("Veriler bu Mac'te yerel saklanır; bu markada yapay zekâ kapalı.") }
        return LF("Veriler bu Mac'te yerel saklanır; bu markanın içeriği yalnız izin verdiğin sağlayıcıya gönderilir: %@",
                  allowed.map(\.shortName).joined(separator: ", "))
    }

    var body: some View {
        @Bindable var app = app
        GeometryReader { geo in
            HStack(spacing: 0) {
                page.frame(minWidth: 460)
                if app.showAssistant {
                    TerminalResizeHandle(width: Binding(get: { app.terminalWidth }, set: { app.terminalWidth = $0 }),
                                         limit: max(AppModel.terminalWidthRange.lowerBound, min(AppModel.terminalWidthRange.upperBound, geo.size.width - 460)))
                    // v3: terminal pencereye gömülü şerit değil, yüzen yuvarlak bir panel (çevresinde boşluk).
                    AIChatPanel(brand: brand)
                        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.large, style: .continuous))
                        .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
                        .padding(.trailing, 12).padding(.vertical, 10)
                        .frame(width: min(app.terminalWidth, max(AppModel.terminalWidthRange.lowerBound, geo.size.width - 460)) + 12)
                }
            }
        }
        .navigationTitle(brand.name)
        .navigationSubtitle(brand.isOwn ? L("Kendi şirketimiz") : brand.sector)
        .toolbar {
            // Bölüm seçici pencerenin araç çubuğunda (Finder, Hatırlatıcılar gibi): yalnız metin, altı segment.
            ToolbarItem(placement: .principal) {
                Picker(L("Bölüm"), selection: $app.brandTab) {
                    ForEach(BrandTab.allCases) { tab in Text(tab.title(for: brand)).tag(tab) }
                }
                .pickerStyle(.segmented).labelsHidden()
                .frame(minWidth: 440)
                .help(L("Bölüm (⌘1–⌘6)"))
            }
            ToolbarItemGroup(placement: .primaryAction) {
                // Deneme veri alanı (demo): gerçek veriyle karışmasın diye turuncu etiket.
                if app.preferences.scope.kind == .trial {
                    Text(L("Demo veri")).font(Design.Font.small.weight(.semibold)).foregroundStyle(.orange)
                        .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(Color.orange.opacity(0.15)))
                        .help(L("Bu pencere örnek veriyle çalışıyor; gerçek verin değişmez"))
                }
                Label(L("Yerel"), systemImage: "lock").labelStyle(.iconOnly).font(.callout).foregroundStyle(.secondary)
                    .help(localDataHelp)
                Toggle(isOn: $app.showAssistant) { Label(L("Asistan"), systemImage: "sparkles") }
                    .toggleStyle(.button)
                    .help(app.showAssistant ? L("Asistanı gizle (⌘J)") : L("Yapay zekâ asistanını göster (⌘J)"))
                Menu {
                    Button(L("Bilgiler ve AI izinleri…")) { app.brandSheet = .info(brand.id) }
                    Button(L("Klasörü Finder'da göster")) {
                        if let folder = app.revealFolder(brandId: brand.id) { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                    }
                    Divider()
                    Button(L("Dışa aktar…")) { exportBrand(app: app, brand: brand) }
                    if !brand.isOwn { Button(L("Arşivle…")) { archiving = true } }
                } label: {
                    Label(L("Diğer"), systemImage: "ellipsis.circle")
                }
                .help(L("Diğer"))
            }
        }
        .brandArchiveConfirmation(brand: archiving ? brand : nil, isPresented: $archiving)
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
            // Gerçek pencerede marka adı ve bölüm seçici araç çubuğundadır; ekran çizimi araç çubuğunu çizemediği için
            // yalnız orada eski başlık ve sekmeler gösterilir.
            if isSnapshot {
                BrandHeader(brand: brand)
                    .padding(.horizontal, 30).padding(.vertical, Design.Space.m)
                    .overlay(alignment: .bottom) { Rectangle().fill(Design.line).frame(height: 1) }
                SectionTabs()
                    .padding(.horizontal, 30)
            }
            ApprovalBand(brand: brand)
                .pagePadding().padding(.top, Design.Space.m)
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        // Markanın rengiyle sayfa üstüne yumuşak ton geçişi: her marka kendi alanında olduğunu hisseder.
        .background(alignment: .top) {
            Rectangle().fill(BrandTintStyle(key: brand.id).opacity(0.04)).frame(height: 220)
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                .allowsHitTesting(false)
        }
    }

    /// Bölüm içeriği: geçişte kısa bir çapraz solma ("Hareketi Azalt" açıksa anında).
    private var content: some View {
        sectionContent
            .id(app.brandTab)
            .transition(.opacity)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: app.brandTab)
    }

    @ViewBuilder private var sectionContent: some View {
        switch app.brandTab {
        case .flow: FlowView(brand: brand)
        case .todo: TodoView(brand: brand)
        case .files: FilesView(brand: brand)
        case .info:
            if brand.isOwn { CompanyView() } else { BrandProfileView(brand: brand) }
        case .finance: FinanceView(brand: brand)
        case .report: ReportsView(brand: brand)
        }
    }
}

/// Başlık: marka kimliği (avatar, ad, sektör). Terminal, yerel etiketi ve ··· menüsü pencerenin araç çubuğundadır
/// (`BrandDetailView.toolbar`): Mac uygulamalarında pencere düzeyi eylemlerin yeri orasıdır.
struct BrandHeader: View {
    let brand: Brand

    var body: some View {
        HStack(alignment: .center, spacing: Design.Space.m) {
            BrandAvatar(name: brand.name, tintKey: brand.id, selected: true, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(brand.name).font(Design.Font.heading.weight(.semibold)).lineLimit(1).accessibilityAddTraits(.isHeader)
                Text(brand.sector.isEmpty ? L("Marka çalışma alanı") : brand.sector).captionStyle().lineLimit(1)
            }
            Spacer()
        }
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
        NSWorkspace.shared.activateFileViewerSelecting([out.folder])
        // Depoda bulunamayan dosya sessizce atlanmaz: kullanıcıya sayısı söylenir, listesi veri.json'da.
        if !out.missingFiles.isEmpty {
            app.alert = AppAlert(title: L("Dışa aktarım eksik"),
                                 message: LF("%d dosya depoda bulunamadığı için dışa aktarılamadı. Listesi veri.json içinde \"missingFiles\" altında.", out.missingFiles.count))
        }
    }
}

/// Metin sekmeleri: seçili olan kalın ve vurgu renginde alt çizgili; altında ince ayraç.
struct SectionTabs: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let brand = app.selectedBrand
        HStack(spacing: 20) {
            ForEach(BrandTab.allCases) { tab in
                let selected = app.brandTab == tab
                Button { app.brandTab = tab } label: {
                    Text(brand.map { tab.title(for: $0) } ?? tab.title)
                        .font(Design.Font.body.weight(selected ? .semibold : .regular))
                        .foregroundStyle(selected ? AnyShapeStyle(Design.accent) : AnyShapeStyle(.secondary))
                        .padding(.top, 14).padding(.bottom, 12)
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
                case .approvals: ApprovalSheet(brand: brand, pending: app.read(or: PendingApprovals()) { try $0.pendingApprovals(brandId: brand.id) },
                                               files: app.newFiles[brand.id] ?? [])
                case .info: BrandInfoView(brand: brand)
                }
            }
            .environment(app)
        }
    }
}


/// Terminal sütununun sol kenarındaki tutamaç: sola/sağa sürüklenir (315–600, pencereye sığacak kadar); genişlik hatırlanır.
struct TerminalResizeHandle: View {
    @Binding var width: CGFloat
    let limit: CGFloat
    @State private var startWidth: CGFloat?

    var body: some View {
        Rectangle().fill(Color.clear).frame(width: 1)
            .overlay {
                Color.clear.frame(width: 9).contentShape(Rectangle())
                    .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { drag in
                            let start = startWidth ?? width
                            startWidth = start
                            width = min(max(start - drag.translation.width, AppModel.terminalWidthRange.lowerBound), limit)
                        }
                        .onEnded { _ in startWidth = nil })
            }
            .accessibilityElement()
            .accessibilityLabel(L("Asistan genişliği"))
            .accessibilityValue("\(Int(width))")
            .accessibilityAdjustableAction { direction in
                let step: CGFloat = 40
                width = min(max(width + (direction == .increment ? -step : step), AppModel.terminalWidthRange.lowerBound), limit)
            }
    }
}
