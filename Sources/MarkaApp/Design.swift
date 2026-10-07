import AppKit
import MarkaCore
import SwiftUI

/// Görsel dil (0.2.1, Rams: "daha az, ama daha iyi"). Belirteçler `docs/surum-0.2.1.md` §7'den; başka değer kullanılmaz.
/// - Renk: sistem nötrleri + tek vurgu (birincil düğme, onay bekleyen sayısı, seçim) + yalnız gecikme için tehlike rengi.
/// - Yazı: 6 rol (`Design.Font`), simge: 4 boyut (`Design.Icon`). Boşluk: 4 değer (`Design.Space`). Köşe: 3 değer (`Design.Radius`).
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
    static let line = AdaptiveColor(system: .separatorColor, light: Palette.RGB(0xE8EAF0), dark: Palette.RGB(0x363B48),
                                    increased: (Palette.RGB(0x9AA1B2), Palette.RGB(0x7C8598)))
    /// Seçili satır zemini (kenar çubuğu). Opaklık `Palette.selectionAlpha` ile testle bağlı.
    static let selection = Color.primary.opacity(Palette.selectionAlpha)
    /// İçerik zemini; tek kutu istisnası olan onay bandı ve giriş alanları.
    static let bandBackground = AdaptiveColor(system: .controlBackgroundColor, light: Palette.lightSurfaces[0], dark: Palette.darkSurfaces[0])
    /// Pencere zemini.
    static let windowBackground = AdaptiveColor(system: .windowBackgroundColor, light: Palette.lightSurfaces[1], dark: Palette.darkSurfaces[1])

    /// Kenar çubuğu zemini (0.3.0): açıkta #F4F5F8, koyuda #191C24.
    static let sidebarBackground = AdaptiveColor(system: .windowBackgroundColor, light: Palette.lightSurfaces[1], dark: Palette.darkSurfaces[1])
    /// Hafif yüzey (grup başlığı sayacı, alan zemini): #F7F8FA / #272B35.
    static let panel = AdaptiveColor(system: .controlBackgroundColor, light: Palette.RGB(0xF7F8FA), dark: Palette.RGB(0x272B35))
    /// Seçili marka satırı zemini.
    static let rowSelected = AdaptiveColor(system: .selectedContentBackgroundColor.withAlphaComponent(0.18), light: Palette.RGB(0xE6E9F1), dark: Palette.RGB(0x303646))

    /// Rapor kâğıdı (her iki görünümde beyaza yakın: müşteriye giden belge) ve onu taşıyan tuval.
    static let reportPaper = Color(.sRGB, red: 0.99, green: 0.99, blue: 0.99)
    static let canvas = AdaptiveColor(Palette.Pair(light: Palette.RGB(0xE9ECF2), dark: Palette.RGB(0x15171D)))

    // MARK: Yazı (6 rol, H2-04). Ağırlık çağrı yerinde `.weight(…)` ile; en küçük rol 11 pt (okunabilirlik tabanı).
    /// `TasarimDiliTests` rol sayısını (≤ 6) ve sabit boyut tavanını denetler.
    enum Font {
        /// Sayfa başlığı ve büyük sayı göstergesi: 34 pt kalın.
        // sabit-boyut: macOS'ta 26 pt (largeTitle) üstünde anlamsal stil yok; tasarım teslimindeki sayfa başlığı 34 pt.
        static let display = SwiftUI.Font.system(size: 34, weight: .bold)
        /// Panel/karşılama başlığı: 22 pt (`.title`).
        static let title = SwiftUI.Font.title
        /// Bölüm ve kart başlığı: 15 pt (`.title3`).
        static let heading = SwiftUI.Font.title3
        /// Gövde: 13 pt (`.body`).
        static let body = SwiftUI.Font.body
        /// İkincil metin, düğme: 12 pt (`.callout`).
        static let callout = SwiftUI.Font.callout
        /// Küçük ek bilgi, hap, sayaç: 11 pt (`.subheadline`); `.captionStyle()` bunu ikincil renkte verir.
        static let small = SwiftUI.Font.subheadline
    }

    /// Simge ölçeği (yazı rolü değil; 4 değer). SF Symbol boyutu yazı boyutundan bağımsız seçilir.
    enum Icon {
        // sabit-boyut: simge ölçeği; anlamsal yazı stili simge boyutunu ifade etmez.
        static let small = SwiftUI.Font.system(size: 11)
        // sabit-boyut: simge ölçeği.
        static let medium = SwiftUI.Font.system(size: 14)
        // sabit-boyut: simge ölçeği.
        static let large = SwiftUI.Font.system(size: 20)
        // sabit-boyut: simge ölçeği (boş durum ve karşılama simgesi).
        static let hero = SwiftUI.Font.system(size: 30)
    }

    // MARK: Boşluk (4 değer) ve köşe
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
    }
    /// Köşe yarıçapı (3 değer, H2-04): küçük = düğme, giriş alanı, satır; orta = bildirim, kart içi kutu; büyük = kart, sütun.
    enum Radius {
        static let small: CGFloat = 7
        static let medium: CGFloat = 10
        static let large: CGFloat = 14
    }
    /// Sayfa kenar boşlukları. macOS 26'da kenar çubuğu içeriğin üstünde yüzen cam bir panel; sütun kenarından yaklaşık 24 pt
    /// taşar, bu yüzden sol boşluk daha geniş (gerçek pencerede ölçüldü: 34 pt'te içerik cama yapışık görünüyordu).
    static var pageLeading: CGFloat { if #available(macOS 26, *) { 54 } else { 34 } }
    static let pageTrailing: CGFloat = 34
}

/// Markanın kimlik rengi: marka kimliğinden kararlı biçimde seçilen, uyumlu sekiz renkten biri. Kimliği taşır (avatar, bölüm simgesi,
/// ince vurgular); eylemler (birincil düğme, seçim) uygulamanın indigo vurgusunda kalır.
enum BrandTint {
    /// (açık görünüm, koyu görünüm)
    static let palette: [(UInt32, UInt32)] = [
        (0x4E50D8, 0xA5A6FF), (0x0E8F89, 0x5FD3CC), (0xD2601A, 0xFFA066), (0xC23A82, 0xFF8EC4),
        (0x2F8A4F, 0x7BD99A), (0x2F6FE0, 0x8DB7FF), (0xB8860B, 0xF2C94C), (0x8A4FD8, 0xC7A2FF),
    ]
    static func index(_ key: String) -> Int {
        var h: UInt32 = 5381
        for u in key.unicodeScalars { h = (h &* 33) &+ u.value }
        return Int(h % UInt32(palette.count))
    }
}

struct BrandTintStyle: ShapeStyle {
    let key: String
    func resolve(in environment: EnvironmentValues) -> Color {
        let pair = BrandTint.palette[BrandTint.index(key)]
        let hex = environment.colorScheme == .dark ? pair.1 : pair.0
        return Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// Marka avatarı: harfli kare, markanın renginde (seçiliyken dolu, değilken açık zeminli).
struct BrandAvatar: View {
    @Environment(\.colorScheme) private var scheme
    let name: String
    var tintKey: String? = nil
    var selected = false
    var size: CGFloat = 30

    var body: some View {
        let initial = String(name.trimmingCharacters(in: .whitespaces).first.map { String($0) } ?? "?").lowercased()
        let tint: AnyShapeStyle = tintKey.map { AnyShapeStyle(BrandTintStyle(key: $0)) } ?? AnyShapeStyle(Design.accent)
        let ink: AnyShapeStyle = selected ? AnyShapeStyle(scheme == .dark ? Color(.sRGB, red: 0.1, green: 0.11, blue: 0.15) : Color.white) : tint
        let fill: AnyShapeStyle = selected ? tint : AnyShapeStyle(tint.opacity(scheme == .dark ? 0.22 : 0.14))
        Text(initial)
            // sabit-boyut: avatar harfi, kutu boyutuyla orantılı.
            .font(.system(size: size * 0.5, weight: .semibold, design: .serif))
            .foregroundStyle(ink)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).fill(fill))
            .accessibilityHidden(true)
    }
}

/// Açık/koyu görünüme göre çözülen renk. `NSColor` dinamik sağlayıcısı `ImageRenderer` çiziminde görünüme uymadığı için
/// renk SwiftUI ortamındaki `colorScheme`'den çözülür. Sistem rengi verilmişse uygulamada o kullanılır; ekran çiziminde
/// (`\.isSnapshot`) yerine `Palette`'teki yaklaşık yüzey değerleri.
struct AdaptiveColor: ShapeStyle {
    var system: NSColor?
    let light: Palette.RGB
    let dark: Palette.RGB
    /// "Artırılmış Kontrast" erişilebilirlik ayarı açıkken kullanılan değerler (yoksa normal değerler).
    var increased: (light: Palette.RGB, dark: Palette.RGB)? = nil

    init(_ pair: Palette.Pair) { system = nil; light = pair.light; dark = pair.dark }
    init(system: NSColor, light: Palette.RGB, dark: Palette.RGB, increased: (light: Palette.RGB, dark: Palette.RGB)? = nil) {
        self.system = system; self.light = light; self.dark = dark; self.increased = increased
    }

    func resolve(in environment: EnvironmentValues) -> Color {
        if let increased, environment.colorSchemeContrast == .increased {
            let c = environment.colorScheme == .dark ? increased.dark : increased.light
            return Color(.sRGB, red: c.red, green: c.green, blue: c.blue)
        }
        if let system, !environment.isSnapshot { return Color(nsColor: system) }
        let c = environment.colorScheme == .dark ? dark : light
        return Color(.sRGB, red: c.red, green: c.green, blue: c.blue)
    }
}

extension View {
    /// Ek stil: küçük yazı, ikincil renk.
    func captionStyle() -> some View { font(Design.Font.small).foregroundStyle(.secondary) }
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
            .background(RoundedRectangle(cornerRadius: Design.Radius.small)
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
            .background(RoundedRectangle(cornerRadius: Design.Radius.small)
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
                .background(RoundedRectangle(cornerRadius: Design.Radius.small).fill(Design.bandBackground))
                .overlay(RoundedRectangle(cornerRadius: Design.Radius.small).strokeBorder(Design.line))
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
                        // a11y-tarama: yok-say — boş zemine dokunma yalnız seçimi kaldırır; klavye/VoiceOver karşılığı Esc
                        .background { Color.clear.contentShape(Rectangle()).onTapGesture(perform: backgroundTap) }
                }
                .denseScrollEdge()
            }
        } else {
            ScrollView { content }.denseScrollEdge()
        }
    }
}

/// Boş durumun tek biçimi (0.3.0, Apple'ın `ContentUnavailableView` kalıbı): simge, başlık, açıklama ve isteğe bağlı tek eylem.
/// Ne yapılacağını söyler; konumu çağıran verir.
struct EmptyStateView: View {
    var title: String? = nil
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    /// SF Symbol (Apple'ın boş durum kalıbı: simge, başlık, açıklama, tek eylem).
    var symbol = "tray"
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(Design.Icon.hero.weight(.light)).foregroundStyle(.tertiary)
                .padding(.bottom, 4).accessibilityHidden(true)
            Text(title ?? message).font(Design.Font.heading.weight(.semibold)).multilineTextAlignment(.center)
            if title != nil {
                Text(message).font(Design.Font.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .lineSpacing(2).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 380)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action).actionSecondary().padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding(.vertical, Design.Space.l)
        .accessibilityElement(children: .combine)
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
    /// Kayıt hâlâ açık mı? Bitmiş/iptal kaydın geçmiş tarihi gecikme değildir; kırmızı yalnız açık ve geçmiş tarihli kayıtta.
    var isOpen: Bool = true
    var body: some View {
        let today = DayString.from(Date())
        let overdue = isOpen && day < today
        let date = DayString.date(day)
        Group {
            if let date { Text(date, format: .dateTime.day().month(.abbreviated)) } else { Text(day) }
        }
        .font(Design.Font.small).monospacedDigit()
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
        case .local: L("Bu Mac'teki model")
        case .apple: "Apple Intelligence"   // E-25
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


/// Birincil eylem düğmesi (tasarım teslimi): dolgulu vurgu, beyaz yazı, 33 pt yükseklik. Ekran başına en çok bir tane.
struct PrimaryActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Design.Font.callout.weight(.medium)).foregroundStyle(.white)
            .padding(.horizontal, 13).frame(height: 33)
            .background(RoundedRectangle(cornerRadius: Design.Radius.small, style: .continuous).fill(Design.accentFill).opacity(configuration.isPressed || !enabled ? 0.7 : 1))
    }
}

/// İkincil eylem düğmesi: çerçeveli.
struct SecondaryActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Design.Font.callout.weight(.medium))
            .padding(.horizontal, 12).frame(height: 33)
            .background(RoundedRectangle(cornerRadius: Design.Radius.small, style: .continuous).fill(configuration.isPressed ? AnyShapeStyle(Design.panel) : AnyShapeStyle(Design.windowBackground)))
            .overlay(RoundedRectangle(cornerRadius: Design.Radius.small, style: .continuous).strokeBorder(Design.line))
    }
}

extension ButtonStyle where Self == PrimaryActionStyle { static var primaryAction: PrimaryActionStyle { PrimaryActionStyle() } }
extension ButtonStyle where Self == SecondaryActionStyle { static var secondaryAction: SecondaryActionStyle { SecondaryActionStyle() } }


extension View {
    /// Sayfa yatay kenar boşluğu (sol ve sağ farklı; bkz. `Design.pageLeading`).
    func pagePadding() -> some View { padding(.leading, Design.pageLeading).padding(.trailing, Design.pageTrailing) }

    /// macOS 26: yoğun listelerde üst kenar efekti sert (okunaklı); eski sürümlerde etkisiz.
    @ViewBuilder func denseScrollEdge() -> some View {
        if #available(macOS 26, *) { scrollEdgeEffectStyle(.hard, for: .top) } else { self }
    }

    /// Birincil eylem: macOS 26'da sistemin cam düğmesi (`glassProminent`), eski sürümde ve ekran çiziminde kendi stilimiz.
    func actionPrimary() -> some View { modifier(ActionButtonModifier(prominent: true)) }
    /// İkincil eylem: macOS 26'da `glass`, aksi halde kendi çerçeveli stilimiz.
    func actionSecondary() -> some View { modifier(ActionButtonModifier(prominent: false)) }
}

private struct ActionButtonModifier: ViewModifier {
    @Environment(\.isSnapshot) private var isSnapshot
    let prominent: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26, *), !isSnapshot {
            // İkincil eylemde cam stili kök vurgu rengini devralıp birincil gibi görünüyordu (gerçek pencerede görüldü): kendi stilimiz.
            if prominent { content.buttonStyle(.glassProminent).tint(Design.accentFill) } else { content.buttonStyle(.secondaryAction) }
        } else if prominent {
            content.buttonStyle(.primaryAction)
        } else {
            content.buttonStyle(.secondaryAction)
        }
    }
}


extension View {
    /// Liste satırı zemini: seçiliyken seçim rengi, üzerine gelince hafif vurgu (fare: "uygulama yaşıyor" hissi). Hareketi Azalt'a
    /// saygılı, yalnız renk geçişi.
    func rowBackground(selected: Bool, radius: CGFloat = Design.Radius.small) -> some View {
        modifier(RowBackgroundModifier(selected: selected, radius: radius))
    }
}

private struct RowBackgroundModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let selected: Bool
    let radius: CGFloat
    @State private var hovering = false

    func body(content: Content) -> some View {
        let fill: AnyShapeStyle = selected ? AnyShapeStyle(Design.selection) : (hovering ? AnyShapeStyle(Design.panel) : AnyShapeStyle(Color.clear))
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
    }
}


extension View {
    /// Düz liste (v3, Things/Hatırlatıcılar sakinliği): çerçeve, dolgu, gölge yok; yalnız üstte ve altta ince çizgi. Satırlar arası çizgiyi satırlar koyar.
    func flatList() -> some View {
        overlay(alignment: .top) { Rectangle().fill(Design.line).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(Design.line).frame(height: 1) }
    }

    /// Gruplanmış yüzey (Ayarlar, Hatırlatıcılar gibi): hafif dolgu, ince çizgi, açık görünümde yumuşak gölge.
    func card(padding: CGFloat = 0, radius: CGFloat = Design.Radius.large) -> some View { modifier(CardModifier(padding: padding, radius: radius)) }
}

private struct CardModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let padding: CGFloat
    let radius: CGFloat
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Design.panel))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Design.line))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(scheme == .light ? 0.035 : 0), radius: 8, y: 2)
    }
}

/// Durum hapı: küçük, yumuşak zeminli etiket (Doğrulanmadı, Yüksek, Bekliyor…). Renk tek başına anlam taşımaz; metin her zaman var.
struct Pill: View {
    let text: String
    var tint: AnyShapeStyle = AnyShapeStyle(.secondary)
    var body: some View {
        Text(text).font(Design.Font.small.weight(.medium)).foregroundStyle(tint).lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.13)))
    }
}


/// Özet kutucuk satırı: sığdığı kadar (en çok dört) eşit sütun; dar alanda (örn. asistan paneli açıkken) alt satıra sarılır, geniş alanda
/// satırı doldurur. Sabit genişlik de, `.adaptive` de bunu yapmıyordu (sağda boşluk kalıyordu).
struct TileGrid<Content: View>: View {
    var minTile: CGFloat = 150
    /// Kutucuk sayısı (en çok sütun): üç kutucuk dört sütunda soldan yığılmasın.
    var columns = 4
    @ViewBuilder var content: Content
    @State private var width: CGFloat = 1000

    var body: some View {
        let fit = max(1, min(columns, Int((width + 12) / (minTile + 12))))
        // Dört kutucuk üç sütuna sığarsa 3+1 yetim kutu kalır; 2+2 dizilir.
        let n = (columns == 4 && fit == 3) ? 2 : fit
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .topLeading), count: n), alignment: .leading, spacing: 12) {
            content
        }
        .background(GeometryReader { g in
            Color.clear.onAppear { width = g.size.width }.onChange(of: g.size.width) { _, w in width = w }
        })
    }
}


/// Öğeleri soldan sağa dizer, sığmayınca alt satıra sarar (çipler için). Izgara sütunları eşit olmayan boşluk bırakıyordu.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { y += rowHeight + spacing; x = 0; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { y += rowHeight + spacing; x = bounds.minX; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Bölüm açılışında odak: ilk metin alanı (arama kutusu) odak almasın; odak kenar çubuğu listesine geçsin ki seçili satır
/// vurgulu (pasif gri değil) kalsın ve satırdaki onay sayısı okunsun. Liste bulunamazsa odak yalnız bırakılır.
/// AppKit pencere anahtar olunca ilk metin alanına kendiliğinden odak verebildiği için kısa bir gecikmeyle bir kez daha bakılır.
@MainActor enum OpeningFocus {
    static func settle() {
        DispatchQueue.main.async { apply() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            // Yalnız metin alanı odaktaysa (alan düzenleyicisi) yeniden düzelt; kullanıcı başka yere tıkladıysa dokunma.
            if NSApp.keyWindow?.firstResponder is NSTextView { apply() }
        }
    }

    /// Sayfa (sheet) açılışı: ilk metin alanı seçili/odaklı açılmasın (yanlışlıkla yazınca başlığın üstüne yazılıyordu).
    /// Sayfa penceresi bir süre sonra anahtar olduğundan iki kez bakılır; yalnız metin alanı odaktaysa odak bırakılır.
    static func clearTextFocus() {
        for delay in [0.05, 0.4] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if let window = NSApp.keyWindow, window.firstResponder is NSTextView { window.makeFirstResponder(nil) }
            }
        }
    }

    private static func apply() {
        guard let window = NSApp.keyWindow else { return }
        if let list = sidebarList(in: window.contentView) { window.makeFirstResponder(list) } else { window.makeFirstResponder(nil) }
    }

    /// Penceredeki en soldaki tablo/anahat görünümü kenar çubuğu listesidir.
    private static func sidebarList(in root: NSView?) -> NSTableView? {
        guard let root else { return nil }
        var found: [NSTableView] = []
        var stack: [NSView] = [root]
        while let view = stack.popLast() {
            if let table = view as? NSTableView, !table.isHiddenOrHasHiddenAncestor { found.append(table) }
            stack.append(contentsOf: view.subviews)
        }
        return found.min { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }
    }
}
