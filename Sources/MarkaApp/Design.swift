import AppKit
import MarkaCore
import SwiftUI

/// Görsel dil (0.2.1, Rams: "daha az, ama daha iyi"). Belirteçler `docs/surum-0.2.1.md` §7'den; başka değer kullanılmaz.
/// - Renk: sistem nötrleri + tek vurgu (birincil düğme, onay bekleyen sayısı, seçim) + yalnız gecikme için tehlike rengi.
/// - Yazı: 4 stil (`Design.Font`). Boşluk: 4 değer (`Design.Space`). Köşe: tek değer (`Design.radius`), yalnız giriş alanı ve bant.
/// - Kutu yok: kart, gölge, rozet kapsülü yok; ayrım boşluk ve ince çizgiyle. Tek istisna onay bandı.
/// Renk değerleri `MarkaCore.Palette`'te; kontrastları `KontrastTests` denetler (WCAG AA).
enum Design {
    // MARK: Renk
    /// Metin olarak vurgu: onay bekleyen sayısı, seçili sekmenin alt çizgisi, kayıt bağlantısı.
    static let accent = AdaptiveColor(Palette.accentText)
    /// Dolgulu denetimler için `.tint`: birincil düğmede beyaz yazıyla ≥ 4.5:1.
    static let accentFill = AdaptiveColor(Palette.accentFill)
    /// Yalnızca gecikme.
    static let danger = AdaptiveColor(Palette.danger)
    /// İnce ayraç çizgisi.
    static let line = AdaptiveColor(system: .separatorColor, light: Palette.RGB(0xD9D9D9), dark: Palette.RGB(0x3D3D3D))
    /// Seçili satır zemini (kenar çubuğu). Opaklık `Palette.selectionAlpha` ile testle bağlı.
    static let selection = Color.primary.opacity(Palette.selectionAlpha)
    /// İçerik zemini; tek kutu istisnası olan onay bandı ve giriş alanları.
    static let bandBackground = AdaptiveColor(system: .controlBackgroundColor, light: Palette.lightSurfaces[0], dark: Palette.darkSurfaces[0])
    /// Pencere zemini.
    static let windowBackground = AdaptiveColor(system: .windowBackgroundColor, light: Palette.lightSurfaces[1], dark: Palette.darkSurfaces[1])

    // MARK: Yazı (4 stil)
    enum Font {
        /// Ekran başlığı.
        static let title = SwiftUI.Font.title2.weight(.semibold)
        /// Bölüm başlığı.
        static let section = SwiftUI.Font.headline
        /// Gövde.
        static let body = SwiftUI.Font.body
        /// Ek bilgi; `.captionStyle()` ile ikincil renkte.
        static let caption = SwiftUI.Font.caption
    }

    // MARK: Boşluk (4 değer) ve köşe
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
    }
    static let radius: CGFloat = 6
}

/// Açık/koyu görünüme göre çözülen renk. `NSColor` dinamik sağlayıcısı `ImageRenderer` çiziminde görünüme uymadığı için
/// renk SwiftUI ortamındaki `colorScheme`'den çözülür. Sistem rengi verilmişse uygulamada o kullanılır; ekran çiziminde
/// (`\.isSnapshot`) yerine `Palette`'teki yaklaşık yüzey değerleri.
struct AdaptiveColor: ShapeStyle {
    var system: NSColor?
    let light: Palette.RGB
    let dark: Palette.RGB

    init(_ pair: Palette.Pair) { system = nil; light = pair.light; dark = pair.dark }
    init(system: NSColor, light: Palette.RGB, dark: Palette.RGB) { self.system = system; self.light = light; self.dark = dark }

    func resolve(in environment: EnvironmentValues) -> Color {
        if let system, !environment.isSnapshot { return Color(nsColor: system) }
        let c = environment.colorScheme == .dark ? dark : light
        return Color(.sRGB, red: c.red, green: c.green, blue: c.blue)
    }
}

extension View {
    /// Ek stil: küçük yazı, ikincil renk.
    func captionStyle() -> some View { font(Design.Font.caption).foregroundStyle(.secondary) }
}

/// Ekran çizimi (`MARKA_SNAPSHOT`) `ImageRenderer` ile yapılır; `ScrollView` gibi AppKit destekli kapsayıcılar orada boş çıkar.
/// Kaydırma alanları bu değer `true` iken içeriği doğrudan verir.
private struct SnapshotKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var isSnapshot: Bool {
        get { self[SnapshotKey.self] }
        set { self[SnapshotKey.self] = newValue }
    }
}

/// AppKit görünümü ekleyen değiştiriciler (sürükle-bırak gibi) `ImageRenderer`'da tüm alanı boş çizdirir; ekran çiziminde atlanır.
struct LiveOnly<M: ViewModifier>: ViewModifier {
    @Environment(\.isSnapshot) private var isSnapshot
    let modifier: M
    func body(content: Content) -> some View {
        if isSnapshot { content } else { content.modifier(modifier) }
    }
}

extension View {
    func liveOnly<M: ViewModifier>(_ modifier: M) -> some View { self.modifier(LiveOnly(modifier: modifier)) }
}

/// Uygulamanın tek ikincil düğme biçimi (U9): gövde renginde metin; üzerine gelince hafif zemin. Gri "pasif" görünüm ve
/// vurgu renginde bağlantı biçimi yok — vurgu yalnız birincil düğme, onay sayısı ve seçili sekme/satırda.
struct TextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { TextButtonLabel(configuration: configuration) }
}

private struct TextButtonLabel: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false
    var body: some View {
        configuration.label
            .foregroundStyle(.primary)
            .padding(.horizontal, Design.Space.xs)
            .background(RoundedRectangle(cornerRadius: Design.radius)
                .fill((hovering || configuration.isPressed) && isEnabled ? AnyShapeStyle(Design.selection) : AnyShapeStyle(.clear)))
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

extension ButtonStyle where Self == TextButtonStyle {
    /// Metin düğmesi (tek ikincil biçim).
    static var text: TextButtonStyle { TextButtonStyle() }
}

/// Satır içi düzenlenebilir satırın ve metin menüsünün üzerine gelince aldığı hafif zemin.
struct HoverHighlight: ViewModifier {
    var enabled = true
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: Design.radius)
                .fill(hovering && enabled ? AnyShapeStyle(Design.selection) : AnyShapeStyle(.clear)))
            .onHover { hovering = $0 }
    }
}

/// Metin menüsü (ör. "···", durum): göstergesiz, kenarlıksız, gövde renginde (metin düğmesiyle aynı görünüm). Açılır menü
/// AppKit denetimi olduğundan ekran çiziminde yalnız etiketi çizilir.
struct TextMenu<Items: View>: View {
    @Environment(\.isSnapshot) private var isSnapshot
    let title: String
    var help: String? = nil
    @ViewBuilder var items: Items
    var body: some View {
        if isSnapshot {
            Text(title).padding(.horizontal, Design.Space.xs)
        } else {
            Menu { items } label: { Text(title).foregroundStyle(.primary) }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .tint(.primary)
                .fixedSize()
                .padding(.horizontal, Design.Space.xs)
                .modifier(HoverHighlight())
                .help(help ?? "")
                .accessibilityLabel(help ?? title)
        }
    }
}

/// Ayrıntı panelini kapatma eylemi (panel başlığındaki "Kapat"). `ListWithPanel` verir.
private struct PanelCloseKey: EnvironmentKey { nonisolated(unsafe) static let defaultValue: (() -> Void)? = nil }
extension EnvironmentValues {
    var panelClose: (() -> Void)? {
        get { self[PanelCloseKey.self] }
        set { self[PanelCloseKey.self] = newValue }
    }
}

/// "Durum" + metin menüsü (görev, söz/karar/talep, proje): tek biçim. Seçilince `select(sıra)`.
struct StatusMenu: View {
    let current: String
    let options: [String]
    let select: (Int) -> Void
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Design.Space.s) {
            Text(L("Durum")).captionStyle()
            TextMenu(title: current, help: L("Durumu değiştir")) {
                ForEach(options.indices, id: \.self) { i in Button(options[i]) { select(i) } }
            }
        }
    }
}

/// Tek satır giriş alanı. Ekran çiziminde (`TextField` AppKit denetimi) aynı ölçüde çerçeveli metin çizilir.
struct InputField: View {
    @Environment(\.isSnapshot) private var isSnapshot
    let title: String
    @Binding var text: String
    /// Dışarıdan odak isteği (ör. ⌘F).
    var focus: FocusState<Bool>.Binding? = nil
    var body: some View {
        if isSnapshot {
            Text(text.isEmpty ? title : text)
                .foregroundStyle(text.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .padding(.horizontal, Design.Space.s).padding(.vertical, Design.Space.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Design.radius).fill(Design.bandBackground))
                .overlay(RoundedRectangle(cornerRadius: Design.radius).strokeBorder(Design.line))
        } else if let focus {
            TextField(title, text: $text).textFieldStyle(.roundedBorder).focused(focus)
        } else {
            TextField(title, text: $text).textFieldStyle(.roundedBorder)
        }
    }
}

/// Kaydırılabilir sayfa: normalde `ScrollView`, ekran çiziminde düz içerik. `backgroundTap` verilirse içeriğin boş yerine
/// (satırların dışına) tıklamak onu çağırır; içerik en az görünür alan kadar uzatılır (ör. ayrıntı panelini kapatmak).
struct PageScroll<Content: View>: View {
    @Environment(\.isSnapshot) private var isSnapshot
    var backgroundTap: (() -> Void)? = nil
    @ViewBuilder var content: Content
    var body: some View {
        if isSnapshot {
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if let backgroundTap {
            GeometryReader { geo in
                ScrollView {
                    content
                        .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .topLeading)
                        .background { Color.clear.contentShape(Rectangle()).onTapGesture(perform: backgroundTap) }
                }
            }
        } else {
            ScrollView { content }
        }
    }
}

/// Boş ve hata durumlarının tek biçimi (U9: her listede aynı): sola hizalı, isteğe bağlı başlık (bölüm stili) + ikincil
/// renkte tek cümle + isteğe bağlı tek eylem (metin düğmesi). Simge ve kutu yok; konumu çağıran verir.
struct EmptyStateView: View {
    var title: String? = nil
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.xs) {
            if let title { Text(title).font(Design.Font.section) }
            Text(message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.text).padding(.horizontal, -Design.Space.xs)
            }
        }
        .padding(.vertical, Design.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Veri okunamadığında boş ekran yerine gösterilir (D9). Hata tanı kaydına içeriksiz, sabit bağlam anahtarıyla düşer.
struct ReadErrorView: View {
    @Environment(AppModel.self) private var app
    let error: Error
    let context: StaticString
    var retry: () -> Void
    var body: some View {
        EmptyStateView(title: L("Veriler okunamadı"),
                       message: L("Veri tabanından okuma başarısız oldu. Tekrar dene; sorun sürerse Ayarlar › Veri › “Tanı bilgisini kopyala” ile bize bildir."),
                       actionTitle: L("Tekrar dene"), action: retry)
            .onAppear { app.recordReadFailure(error, context: context) }
    }
}

/// Son tarih. Yalnızca gecikmiş olan tehlike renginde; bugün ve ileri tarih ikincil.
struct DueLabel: View {
    let day: String
    var body: some View {
        let today = DayString.from(Date())
        let overdue = day < today
        let date = DayString.date(day)
        Group {
            if let date { Text(date, format: .dateTime.day().month(.abbreviated)) } else { Text(day) }
        }
        .font(Design.Font.caption).monospacedDigit()
        .foregroundStyle(overdue ? AnyShapeStyle(Design.danger) : AnyShapeStyle(.secondary))
        .accessibilityLabel(overdue ? LF("Gecikmiş, son tarih %@", day) : LF("Son tarih %@", day))
    }
}

extension RecordRef.Kind {
    /// Arama sonucundaki tür adı (marka kaydında kaydın kendi türü kullanılır).
    var shortTitle: String {
        switch self {
        case .task: L("Görev")
        case .source: L("Dosya")
        case .workLog: L("İş kaydı")
        case .brandRecord: L("Söz, talep ya da karar")
        case .wikiPage: L("Hafıza sayfası")
        case .timeEntry: L("Görev")
        case .report: L("Rapor")
        }
    }
}

extension BrandRecordKind {
    /// Tek ad (plan §6): Akış, Yapılacaklar, öneriler ve panelde aynı.
    var title: String {
        switch self {
        case .goal: L("Hedef")
        case .request: L("Talep")
        case .promise: L("Söz")
        case .decision: L("Karar bekleniyor")
        case .proposal: L("Teklif")
        case .contract: L("Sözleşme")
        case .milestone: L("Önemli tarih")
        }
    }
    var statuses: [RecordStatus] {
        switch self {
        case .proposal: [.draft, .sent, .accepted, .rejected, .cancelled]
        case .contract: [.draft, .active, .expired, .cancelled]
        default: [.open, .done, .cancelled]
        }
    }
}

extension RecordStatus {
    var title: String {
        switch self {
        case .open: L("Açık")
        case .done: L("Bitti")
        case .cancelled: L("İptal")
        case .draft: L("Taslak")
        case .sent: L("Gönderildi")
        case .accepted: L("Kabul edildi")
        case .rejected: L("Reddedildi")
        case .active: L("Yürürlükte")
        case .expired: L("Süresi doldu")
        }
    }
}

extension TaskStatus {
    var title: String {
        switch self {
        case .todo: L("Yapılacak")
        case .inProgress: L("Sürüyor")
        case .waiting: L("Bekliyor")
        case .done: L("Bitti")
        case .cancelled: L("İptal")
        }
    }
}

extension WorkLogStatus {
    var title: String {
        switch self {
        case .draft: L("Doğrulanmadı")
        case .verified: L("Doğrulandı")
        case .retracted: L("Geri çekildi")
        }
    }
}

extension ProposalStatus {
    var title: String {
        switch self {
        case .pending: L("Onay bekliyor")
        case .applied: L("Onaylandı")
        case .rejected: L("Reddedildi")
        case .reverted: L("Geri alındı")
        }
    }
}

extension Actor {
    var title: String {
        switch self {
        case .user: L("Sen")
        case .ai: L("AI")
        case .import: L("İçe aktarım")
        case .system: L("Sistem")
        }
    }
}

extension AIProviderKind {
    /// Arayüzdeki tek ad (plan §6): Claude, Codex.
    var shortName: String {
        switch self {
        case .anthropic: "Claude"
        case .codex: "Codex"
        }
    }
}

extension ReportPeriod {
    var title: String { self == .weekly ? L("Haftalık") : L("Aylık") }
}

/// Onay kutusu — uygulamadaki tek kutu: satır başı seçim (öneriler, AI izinleri, yalıtım) ve tamamlama (Yapılacaklar).
/// Düz SwiftUI çizimi: ekran çiziminde de görünür; işaretliyken vurgu renginde.
struct CheckBox: View {
    @Binding var isOn: Bool
    /// Erişilebilirlik etiketi (satırın başlığı).
    let label: String
    /// Erişilebilirlik değeri (işaretli / işaretsiz), ör. tamamlamada "Bitti" / "Açık".
    var onValue = L("Seçili")
    var offValue = L("Seçili değil")
    var body: some View {
        Button { isOn.toggle() } label: {
            Image(systemName: isOn ? "checkmark.square.fill" : "square")
                .foregroundStyle(isOn ? AnyShapeStyle(Design.accent) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? onValue : offValue)
        .accessibilityAddTraits(.isToggle)
    }
}

/// `yyyy-MM-dd` ile DatePicker arasında köprü. Ekran çiziminde (AppKit denetimi) düz metin.
struct OptionalDayPicker: View {
    @Environment(\.isSnapshot) private var isSnapshot
    let title: String
    @Binding var day: String?
    var body: some View {
        if isSnapshot {
            Text(verbatim: title + " · " + (day.flatMap { DayString.date($0) }.map { $0.formatted(.dateTime.day().month(.wide).year()) } ?? "—"))
                .captionStyle()
        } else {
            picker
        }
    }

    /// Tarih var/yok: uygulamanın tek kutusu (`CheckBox`) + başlık; varsa sistem tarih seçicisi.
    private var picker: some View {
        let on = Binding(get: { day != nil }, set: { day = $0 ? (day ?? DayString.from(Date())) : nil })
        return HStack(alignment: .firstTextBaseline, spacing: Design.Space.s) {
            CheckBox(isOn: on, label: title)
            Text(title).onTapGesture { on.wrappedValue.toggle() }.accessibilityHidden(true)
            if day != nil {
                DatePicker("", selection: Binding(get: { DayString.date(day ?? "") ?? Date() }, set: { day = DayString.from($0) }),
                           displayedComponents: .date)
                    .labelsHidden()
                    .accessibilityLabel(title)
            }
        }
    }
}
