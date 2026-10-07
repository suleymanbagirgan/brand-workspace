import AppKit
import MarkaCore
import QuickLookThumbnailing
import SwiftUI

// 0.3.0 — tasarım teslimindeki marka bölümleri: Planlama, Hedefler, Dosyalar, Finans (+ ortak başlık ve durum halkası).
// Hepsi mevcut veriden okunur; yeni veri alanı yok. Finans'ta tutar tutulmadığı için tutar gösterilmez (yalnız teklif ve
// sözleşme durumu ile harcanan süre). Satıra tıklayınca Akış/Görevler'deki aynı ayrıntı paneli açılır.

/// Bölüm başlığı: marka renginde simge rozeti, büyük başlık, ikincil alt satır, sağda eylemler.
struct SectionHeading<Actions: View>: View {
    let title: String
    var subtitle: String?
    var symbol: String?
    var tintKey: String?
    /// Eylemlerin başlıkla dikey hizası; varsayılan son satırın tabanı (alt satır varsa ona). Bugün ilk satırı kullanır.
    var actionsAlignment: VerticalAlignment = .lastTextBaseline
    @ViewBuilder var actions: Actions

    var body: some View {
        // v3: simge rozeti yok; büyük, sade başlık. Marka rengi yalnız başlığın önündeki ince çizgide.
        HStack(alignment: actionsAlignment, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(Design.Font.display).tracking(-0.9).lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle, !subtitle.isEmpty { Text(subtitle).font(Design.Font.body).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: Design.Space.m)
            actions.fixedSize(horizontal: true, vertical: false).layoutPriority(1)
        }
    }
}

extension SectionHeading where Actions == EmptyView {
    init(title: String, subtitle: String? = nil, symbol: String? = nil, tintKey: String? = nil) {
        self.init(title: title, subtitle: subtitle, symbol: symbol, tintKey: tintKey) { EmptyView() }
    }
}

/// Görev durumu halkası: boş (yapılacak), yarım dolu (sürüyor), kesikli (bekliyor), dolu + onay işareti (bitti).
struct StatusCircle: View {
    enum State { case todo, doing, waiting, done }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let state: State
    var size: CGFloat = 17

    var body: some View {
        ZStack {
            switch state {
            case .todo:
                Circle().strokeBorder(Color.secondary.opacity(0.75), lineWidth: 1.5)
            case .doing:
                Circle().strokeBorder(Design.accent, lineWidth: 1.5)
                Circle().trim(from: 0, to: 0.4).stroke(Design.accent, style: StrokeStyle(lineWidth: size * 0.36))
                    .rotationEffect(.degrees(-90)).frame(width: size * 0.5, height: size * 0.5)
            case .waiting:
                Circle().strokeBorder(Color.secondary.opacity(0.75), style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2.5]))
            case .done:
                Circle().fill(Design.accentFill)
                // sabit-boyut: simge, işaret dairesinin boyutuyla orantılı.
                Image(systemName: "checkmark").font(.system(size: size * 0.5, weight: .bold)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        // Tamamlanınca kısa yay hareketi ve dokunsal onay; "Hareketi Azalt" açıksa yalnız anında değişir.
        .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.4), value: state)
        .sensoryFeedback(.success, trigger: state == .done)
        .accessibilityHidden(true)
    }
}

extension StatusCircle.State {
    /// Durumun metni: halka `accessibilityHidden` olduğundan VoiceOver'a durum bu metinle verilir (renk/biçim tek başına
    /// durum taşımasın).
    var title: String {
        switch self {
        case .todo: L("Yapılacak")
        case .doing: L("Sürüyor")
        case .waiting: L("Bekliyor")
        case .done: L("Bitti")
        }
    }
}

extension TodoItem {
    /// Daire durumu çekirdekteki aşamadan gelir (H3-10: süzgeç ve bant aynı tanımı kullanır).
    var circleState: StatusCircle.State {
        switch stage {
        case .todo: .todo
        case .doing: .doing
        case .waiting: .waiting
        case .done: .done
        }
    }
}

/// Yerel arama alanı (HIG: kapsamı gösteren yer tutucu; Esc temizler). Yalnız bulunduğu listeyi süzer.
struct LocalSearchField: View {
    @Environment(\.isSnapshot) private var isSnapshot
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(Design.Icon.small).foregroundStyle(.secondary)
            // Ekran çizimi: `ImageRenderer` TextField'ı sarı "çizilemez" yer tutucuyla çizer ve boyutu koşudan koşuya 1 px oynar (H2-07).
            if isSnapshot { Text(prompt).font(Design.Font.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
            else { TextField(prompt, text: $text).textFieldStyle(.plain).font(Design.Font.callout) }
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").font(Design.Icon.small).foregroundStyle(.secondary) }
                    .buttonStyle(.plain).help(L("Aramayı temizle")).accessibilityLabel(L("Aramayı temizle"))
            }
        }
        .padding(.horizontal, 9).frame(minWidth: 130, idealWidth: 220, maxWidth: 220).frame(height: 28)
        .background(RoundedRectangle(cornerRadius: Design.Radius.small, style: .continuous).fill(Design.panel))
        .overlay(RoundedRectangle(cornerRadius: Design.Radius.small, style: .continuous).strokeBorder(Design.line))
        .onExitCommand { text = "" }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(prompt)
    }
}

/// Satır üstünde ince ayraçlı, tasarım teslimindeki gibi iki seçenekli kapsül seçici.
struct SegmentedChoice<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let on = options[i].0 == selection
                Button(options[i].1) { selection = options[i].0 }
                    .buttonStyle(.plain)
                    .lineLimit(1).fixedSize()
                    .font(Design.Font.small.weight(on ? .semibold : .regular))
                    .foregroundStyle(on ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: Design.Radius.small, style: .continuous).fill(on ? AnyShapeStyle(Design.windowBackground) : AnyShapeStyle(.clear)))
                    .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(1)
        .background(RoundedRectangle(cornerRadius: Design.Radius.small, style: .continuous).fill(Design.panel))
        .overlay(RoundedRectangle(cornerRadius: Design.Radius.small, style: .continuous).strokeBorder(Design.line))
    }
}

// MARK: - Planlama

/// Planlama — aynı görevlerin iki zaman görünümü: ay Gantt'ı ve takvim. Başlangıç tarihi tutulmadığı için teslimler elmas
/// işaretiyle gösterilir (süre çubuğu yok); tarihsiz işler ayrı listelenir (tasarım teslimi kararı).
struct PlanningView: View {
    @Environment(AppModel.self) private var app
    let brand: Brand
    /// Görevler bölümünün Gantt ve Takvim görünümü; başlık, görünüm seçici ve "Görev ekle" ebeveynde (`TodoView`).
    let mode: Mode
    @State private var selection: PanelTarget?
    @State private var monthOffset = 0

    init(brand: Brand, mode: Mode = .timeline) {
        self.brand = brand
        self.mode = mode
    }

    enum Mode { case timeline, calendar }

    struct Item: Identifiable, Hashable {
        let id: String
        let title: String
        let day: String?
        let done: Bool
        let target: PanelTarget
        let isMilestone: Bool
    }

    private var calendar: Calendar { StatusService.turkishCalendar }

    private func items() -> [Item] {
        guard let store = app.store else { return [] }
        let tasks = ((try? store.tasks(brandId: brand.id)) ?? []).filter { $0.status != .cancelled }.map {
            Item(id: "t:" + $0.id, title: $0.title, day: $0.dueDate, done: $0.status == .done, target: .task($0.id), isMilestone: false)
        }
        let marks = ((try? store.records(brandId: brand.id, kinds: [.milestone])) ?? []).filter { $0.status != .cancelled }.map {
            Item(id: "r:" + $0.id, title: $0.title, day: $0.dueDate, done: $0.status == .done, target: .record($0.id), isMilestone: true)
        }
        return (tasks + marks).sorted { ($0.day ?? "9999") < ($1.day ?? "9999") }
    }

    private var monthBase: Date { calendar.date(byAdding: .month, value: monthOffset, to: Date()) ?? Date() }
    private var monthInterval: DateInterval { calendar.dateInterval(of: .month, for: monthBase) ?? DateInterval(start: monthBase, duration: 86400 * 30) }

    private var monthTitle: String {
        let f = DateFormatter(); f.locale = Locale.current; f.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return f.string(from: monthBase).capitalized
    }

    var body: some View {
        let _ = app.revision
        let all = items()
        let dated = all.filter { $0.day != nil }
        let undated = all.filter { $0.day == nil && !$0.done }
        ListWithPanel(selection: $selection) {
            PageScroll(backgroundTap: { selection = nil }) {
                VStack(alignment: .leading, spacing: Design.Space.l) {
                    controls
                    if all.isEmpty {
                        EmptyStateView(title: L("Planlanacak bir şey yok"),
                                       message: L("Teslim tarihli görevler ve önemli tarihler burada zaman çizelgesi ve takvim olarak görünür."))
                    } else if mode == .timeline {
                        timeline(dated)
                    } else {
                        month(dated)
                    }
                    if !undated.isEmpty { undatedList(undated) }
                    if mode == .timeline && !all.isEmpty {
                        Text(L("Elmas işaretleri teslim gününü gösterir. Başlangıç tarihi tutulmadığı için süre çubuğu kullanılmaz."))
                            .captionStyle().padding(.top, Design.Space.s)
                    }
                }
                .pagePadding().padding(.vertical, Design.Space.l)
            }
        }
        .onChange(of: brand.id) { selection = nil; monthOffset = 0 }
    }

    private var controls: some View {
        HStack(spacing: Design.Space.s) {
            Text(monthTitle).font(Design.Font.heading.weight(.semibold))
            Button { monthOffset -= 1 } label: { Image(systemName: "chevron.left").frame(width: 24, height: 24) }
                .buttonStyle(.plain).foregroundStyle(.secondary).help(L("Önceki ay")).accessibilityLabel(L("Önceki ay"))
            Button { monthOffset += 1 } label: { Image(systemName: "chevron.right").frame(width: 24, height: 24) }
                .buttonStyle(.plain).foregroundStyle(.secondary).help(L("Sonraki ay")).accessibilityLabel(L("Sonraki ay"))
            Spacer()
            Button(L("Bugün")) { monthOffset = 0 }.actionSecondary().frame(height: 30)
        }
    }

    // Zaman çizelgesi: ayın dört sütunu (1–8, 9–16, 17–24, 25–son); her iş bir satır, teslim günü elmas.
    private func timeline(_ dated: [Item]) -> some View {
        let interval = monthInterval
        let first = DayString.from(interval.start, calendar: calendar)
        let lastDay = calendar.range(of: .day, in: .month, for: interval.start)?.count ?? 30
        let prefix = String(first.prefix(7))
        let visible = dated.filter { ($0.day ?? "").hasPrefix(prefix) }
        let labelWidth: CGFloat = 250
        let ranges = [(1, 8), (9, 16), (17, 24), (25, lastDay)]
        let monthShort: String = { let f = DateFormatter(); f.locale = Locale.current; f.setLocalizedDateFormatFromTemplate("MMM"); return f.string(from: interval.start) }()
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(L("Görev")).padding(.leading, 20).frame(width: labelWidth, alignment: .leading)
                ForEach(ranges.indices, id: \.self) { i in
                    Text("\(ranges[i].0)–\(ranges[i].1) \(monthShort)").frame(maxWidth: .infinity)
                }
            }
            .font(Design.Font.small.weight(.medium)).foregroundStyle(.secondary)
            .padding(.vertical, 15).background(Design.panel)
            Rectangle().fill(Design.line).frame(height: 1)
            ForEach(visible) { item in
                TimelineRow(item: item, lastDay: lastDay, labelWidth: labelWidth, selection: $selection)
            }
            if visible.isEmpty {
                Text(L("Bu ayda teslim tarihi olan iş yok.")).captionStyle().padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .card()
    }

    // Takvim: ay ızgarası; her gün en çok üç iş.
    private func month(_ dated: [Item]) -> some View {
        let interval = monthInterval
        let first = calendar.dateInterval(of: .weekOfYear, for: interval.start)?.start ?? interval.start
        let days = (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
        let weeks = stride(from: 0, to: 42, by: 7).map { Array(days[$0..<$0 + 7]) }.filter { w in w.contains { interval.contains($0) } }
        let byDay = Dictionary(grouping: dated, by: { $0.day ?? "" })
        let today = DayString.from(Date(), calendar: calendar)
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(days.prefix(7)), id: \.self) { d in
                    Text(d, format: .dateTime.weekday(.abbreviated)).frame(maxWidth: .infinity).padding(.vertical, 12)
                }
            }
            .font(Design.Font.small).foregroundStyle(.secondary).background(Design.panel)
            ForEach(weeks.indices, id: \.self) { wi in
                HStack(spacing: 0) {
                    ForEach(weeks[wi], id: \.self) { d in
                        CalendarDayCell(date: d, inMonth: interval.contains(d), isToday: DayString.from(d, calendar: calendar) == today,
                                        items: byDay[DayString.from(d, calendar: calendar)] ?? [], day: calendar.component(.day, from: d),
                                        selection: $selection)
                    }
                }
                .overlay(alignment: .top) { Rectangle().fill(Design.line).frame(height: 1) }
            }
        }
        .card()
    }

    private func undatedList(_ items: [Item]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("Tarihsiz işler")).font(Design.Font.callout.weight(.semibold)).padding(.bottom, Design.Space.s)
            ForEach(items) { listRow($0) }
        }
    }

    private func listRow(_ item: Item) -> some View {
        HStack(spacing: 12) {
            StatusCircle(state: item.done ? .done : .todo, size: 15)
            Text(item.title).font(Design.Font.callout).lineLimit(1)
            Spacer()
            if let d = item.day { DueLabel(day: d, isOpen: !item.done) }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Design.line).frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture { selection = selection == item.target ? nil : item.target }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityValue((item.done ? StatusCircle.State.done : .todo).title + (item.day.map { ", " + $0 } ?? ""))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { selection = item.target }
    }
}

// MARK: - Hedefler

/// Hedefler — `goal` türündeki marka kayıtları; Marka Bilgileri'nin bir bölümü ("neden"). İlerleme: kayda bağlı projedeki
/// görevlerin biten oranı (proje yoksa gösterilmez). Çubuk yalnızca görev tamamlanmasını gösterir; ticari sonuç iddiası taşımaz.
/// Kaydırma ve ayrıntı paneli ebeveynde (`BrandProfileView`).
struct GoalsSection: View {
    @Environment(AppModel.self) private var app
    let brand: Brand
    @Binding var selection: PanelTarget?
    @State private var adding = false
    @State private var newTitle = ""
    @FocusState private var titleFocused: Bool

    var body: some View {
        let _ = app.revision
        let goals = (app.read(or: []) { try $0.records(brandId: brand.id, kinds: [.goal]) }).filter { $0.status != .cancelled }
        let tasks = app.read(or: []) { try $0.tasks(brandId: brand.id) }
        VStack(alignment: .leading, spacing: Design.Space.l) {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("Hedefler")).font(Design.Font.heading.weight(.semibold))
                Spacer()
                Button(adding ? L("Vazgeç") : L("Hedef ekle")) {
                    adding.toggle()
                    if adding { DispatchQueue.main.async { titleFocused = true } } else { newTitle = "" }
                }
                .buttonStyle(.text)
            }
            if adding {
                InputField(title: L("Hedef — ↩"), text: $newTitle, focus: $titleFocused).onSubmit(add).onExitCommand { adding = false; newTitle = "" }
            }
            if goals.isEmpty {
                Text(L("Hedef ekle; görevlerin nedenini ve beklenen çıktıyı netleştirir.")).font(Design.Font.callout).foregroundStyle(.tertiary)
            } else {
                VStack(spacing: 0) { ForEach(goals) { goalRow($0, tasks: tasks) } }
                Text(L("Çubuklar bağlı görevlerin tamamlanmasını gösterir; ticari sonuç veya hedefe ulaşıldığı iddiası taşımaz."))
                    .captionStyle().padding(.top, Design.Space.s)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .card(padding: 18)
        ObservationsView(brand: brand, selection: $selection) // E-12: Marka belleği (onaylı gözlemler)
        RadarView(brand: brand) // E-21: Marka radarı (elle beslenen; rapora girmez)
        }
        .onChange(of: brand.id) { adding = false }
    }

    private func add() {
        let t = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let store = app.store else { return }
        let ok: Void? = app.perform(title: L("Eklenemedi"), context: "hedef.ekle") { _ = try store.saveRecord(BrandRecord(brandId: brand.id, kind: .goal, title: t)) }
        if ok != nil { newTitle = ""; adding = false }
    }

    private func goalRow(_ goal: BrandRecord, tasks: [WorkTask]) -> some View {
        let linked = goal.projectId.map { pid in tasks.filter { $0.projectId == pid && $0.status != .cancelled } } ?? []
        let done = linked.filter { $0.status == .done }.count
        return HStack(alignment: .top, spacing: 22) {
            Image(systemName: goal.status == .done ? "checkmark.circle" : "scope")
                .font(Design.Icon.large).foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .overlay(RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous).strokeBorder(Design.line))
            VStack(alignment: .leading, spacing: 10) {
                Text(goal.title).font(Design.Font.heading.weight(.semibold)).tracking(-0.3)
                if !goal.detail.isEmpty {
                    Text(goal.detail).font(Design.Font.body).foregroundStyle(.secondary).lineSpacing(4).lineLimit(3).frame(maxWidth: 560, alignment: .leading)
                }
                Text(Self.meta(goal, linkedCount: linked.count)).font(Design.Font.small).foregroundStyle(.secondary)
                if !linked.isEmpty { progressBar(done: done, total: linked.count) }
            }
            Spacer(minLength: Design.Space.m)
            if !linked.isEmpty {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(LF("Görev %1$d/%2$d", done, linked.count)).font(Design.Font.heading.weight(.semibold)).monospacedDigit()
                    Text(L("tamamlandı")).font(Design.Font.small).foregroundStyle(.secondary)
                    Button { app.brandTab = .todo } label: { Label(L("Görevleri gör"), systemImage: "arrow.right").labelStyle(.titleAndIcon) }
                        .buttonStyle(.plain).font(Design.Font.callout).foregroundStyle(Design.accent).padding(.top, 12)
                }
            }
        }
        .padding(.vertical, 20)
        .contentShape(Rectangle())
        .onTapGesture { selection = selection == .record(goal.id) ? nil : .record(goal.id) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { selection = .record(goal.id) }
    }

    private func progressBar(done: Int, total: Int) -> some View {
        let fraction = CGFloat(done) / CGFloat(max(total, 1))
        return Capsule().fill(Design.line).frame(width: 290, height: 4)
            .overlay(alignment: .leading) { Capsule().fill(Design.accentFill).frame(width: 290 * fraction, height: 4) }
            .padding(.top, 4)
            .accessibilityHidden(true)
    }

    private static func meta(_ goal: BrandRecord, linkedCount: Int) -> String {
        var parts: [String] = []
        if let d = goal.dueDate, let date = DayString.date(d) {
            let f = DateFormatter(); f.locale = Locale.current; f.setLocalizedDateFormatFromTemplate("LLLL yyyy")
            parts.append(f.string(from: date).capitalized)
        }
        if linkedCount > 0 { parts.append(LF("Bağlı görev: %d", linkedCount)) }
        parts.append(goal.status.title)
        return parts.joined(separator: "  ·  ")
    }
}

// MARK: - Dosyalar

/// Dosyalar — markanın değişmez kaynakları: dosyalar ve bağlantılar. Üstte *Dosya ekle* ve *Bağlantı ekle*; satırdaki simge
/// dosyayı (ya da bağlantıyı) açar, satıra tıklayınca önizleme paneli. Kaynaklar silinmez, yalnız arşivlenir.
/// "Arşivlenenler" sekmesi arşivlenmiş dosya ve bağlantıları listeler; oradan "Arşivden çıkar". Arşivlemeden sonra
/// "Geri al" bildirimi çıkar ve ⌘Z arşivlemeyi geri alır.
struct FilesView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.undoManager) private var undoManager
    let brand: Brand
    @State private var selection: PanelTarget?
    @State private var tab = Tab.files
    @State private var addingLink = false
    @State private var linkTitle = ""
    @State private var linkURL = ""
    @State private var query = ""
    @State private var layout = Layout.gallery
    @FocusState private var linkFocused: Bool
    /// Son arşivlenen kaynak: "Geri al" bildirimi için (kimlik ve başlık).
    @State private var archivedNotice: ArchivedNotice?

    enum Tab { case files, links, archived }
    enum Layout { case gallery, list }
    struct ArchivedNotice: Equatable { let id: String; let title: String }

    var body: some View {
        let _ = app.revision
        // Tek okuma: etkin ve arşivlenmiş kaynaklar birlikte gelir, burada ayrılır.
        let everything = app.read(or: []) { try $0.sources(brandId: brand.id, includeArchived: true) }
        let all = everything.filter { $0.archivedAt == nil }.sorted { $0.capturedAt > $1.capturedAt }
        let archived = everything.filter { $0.archivedAt != nil }.sorted { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) }
        let links = all.filter { $0.kind == .link }
        let files = all.filter { $0.kind != .link }
        let shown = (tab == .files ? files : tab == .links ? links : archived).filter {
            query.isEmpty || $0.title.localizedStandardContains(query) || ($0.fileName ?? "").localizedStandardContains(query)
        }
        ListWithPanel(selection: $selection) {
            PageScroll(backgroundTap: { selection = nil }) {
                VStack(alignment: .leading, spacing: Design.Space.l) {
                    SectionHeading(title: L("Dosyalar"), subtitle: L("Markanın malzemeleri, belgeleri ve bağlantıları."), symbol: "folder", tintKey: brand.id) {
                        Button { addingLink.toggle(); tab = .links; if addingLink { DispatchQueue.main.async { linkFocused = true } } } label: {
                            Label(L("Bağlantı ekle"), systemImage: "link").labelStyle(.titleAndIcon)
                        }
                        .actionSecondary()
                        Button(action: pickFiles) { Label(L("Dosya ekle"), systemImage: "square.and.arrow.up").labelStyle(.titleAndIcon) }
                            .actionPrimary()
                    }
                    HStack {
                        SegmentedChoice(options: [(Tab.files, LF("Dosyalar %d", files.count)), (Tab.links, LF("Bağlantılar %d", links.count)),
                                                  (Tab.archived, LF("Arşivlenenler %d", archived.count))], selection: $tab)
                        if tab == .files {
                            SegmentedChoice(options: [(Layout.gallery, L("Galeri")), (Layout.list, L("Liste"))], selection: $layout)
                        }
                        Spacer()
                        LocalSearchField(text: $query, prompt: L("Dosyalarda ara"))
                    }
                    if let archivedNotice { undoBanner(archivedNotice) }
                    if addingLink { linkComposer }
                    if shown.isEmpty {
                        EmptyStateView(title: !query.isEmpty ? L("Eşleşen bir şey yok.") : emptyTitle, message: emptyMessage)
                    } else if tab == .files && layout == .gallery {
                        gallery(shown)
                    } else {
                        table(shown)
                    }
                    Text(L("Eklenenler markanın değişmez kaynaklarıdır; silinmez, yalnızca arşivlenir. Marka değiştiğinde bu alan da seçilen markaya geçer."))
                        .captionStyle()
                }
                .pagePadding().padding(.vertical, Design.Space.l)
            }
        }
        // Açılışta arama alanı odak almasın (Bugün/Stüdyo ile aynı kalıp).
        .onAppear { OpeningFocus.settle() }
        .onChange(of: brand.id) { selection = nil; addingLink = false; archivedNotice = nil }
        // Bildirim bir süre sonra kendiliğinden kalkar; ⌘Z yine çalışır.
        .task(id: archivedNotice) {
            guard archivedNotice != nil else { return }
            try? await Task.sleep(for: .seconds(10))
            if !Task.isCancelled { archivedNotice = nil }
        }
    }

    private var emptyTitle: String {
        switch tab {
        case .files: L("Henüz dosya yok")
        case .links: L("Henüz bağlantı yok")
        case .archived: L("Arşivlenmiş dosya yok")
        }
    }

    private var emptyMessage: String {
        switch tab {
        case .files: L("“Dosya ekle”yi kullanabilir, dosyaları Akış'a sürükleyebilir ya da marka klasörüne koyabilirsin.")
        case .links: L("Bu markayla ilgili adresleri “Bağlantı ekle” ile kaydedebilirsin.")
        case .archived: L("Arşivlediğin dosya ve bağlantılar burada durur; buradan arşivden çıkarabilirsin.")
        }
    }

    /// Arşivlemeden sonra: ne olduğunu ve nasıl geri alınacağını söyler.
    private func undoBanner(_ n: ArchivedNotice) -> some View {
        HStack(spacing: Design.Space.s) {
            Image(systemName: "archivebox").foregroundStyle(.secondary).accessibilityHidden(true)
            Text(LF("“%@” arşivlendi. Arşivlenenler sekmesinde durur.", n.title)).font(Design.Font.callout).lineLimit(2)
            Spacer(minLength: 8)
            Button(L("Geri al")) { setArchived(n.id, title: n.title, archived: false) }
                .actionSecondary()
                .help(L("Arşivlemeyi geri alır (⌘Z)"))
            Button { archivedNotice = nil } label: { Image(systemName: "xmark").font(Design.Icon.small) }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help(L("Kapat")).accessibilityLabel(L("Bildirimi kapat"))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: Design.Radius.small, style: .continuous).fill(Design.panel))
        .accessibilityElement(children: .contain)
    }

    /// Arşivler ya da arşivden çıkarır (görünen markayla kapsanır) ve tersini ⌘Z'ye bağlar.
    private func setArchived(_ id: String, title: String, archived: Bool) {
        guard let store = app.store else { return }
        let brandId = brand.id
        let ok: Void? = app.perform(title: archived ? L("Arşivlenemedi") : L("Arşivden çıkarılamadı"), context: "kaynak.arsiv") {
            try store.setSourceArchived(id, brandId: brandId, archived: archived)
        }
        guard ok != nil else { return }
        undoManager?.registerUndo(withTarget: app) { app in
            MainActor.assumeIsolated { _ = app.perform(context: "kaynak.arsiv.geri-al") { try app.store?.setSourceArchived(id, brandId: brandId, archived: !archived) } }
        }
        undoManager?.setActionName(archived ? L("Arşivle") : L("Arşivden çıkar"))
        if archived {
            if selection == .source(id) { selection = nil }
            archivedNotice = ArchivedNotice(id: id, title: title)
        } else if archivedNotice?.id == id {
            archivedNotice = nil
        }
    }

    @ViewBuilder private func archiveMenuItem(_ s: Source) -> some View {
        if s.archivedAt == nil {
            Button(L("Arşivle")) { setArchived(s.id, title: s.title, archived: true) }
        } else {
            Button(L("Arşivden çıkar")) { setArchived(s.id, title: s.title, archived: false) }
        }
    }

    private func table(_ rows: [Source]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(L("Ad")).frame(maxWidth: .infinity, alignment: .leading)
                Text(tab == .links ? L("Adres") : L("Tür")).frame(width: tab == .links ? 220 : 130, alignment: .leading)
                Text(tab == .archived ? L("Arşivlendi") : L("Güncellendi")).frame(width: 100, alignment: .leading)
                Color.clear.frame(width: tab == .archived ? 120 : 30, height: 1)
            }
            .font(Design.Font.small.weight(.medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Design.windowBackground.opacity(0.5))
            .overlay(alignment: .bottom) { Rectangle().fill(Design.line).frame(height: 1) }
            ForEach(rows) { r in
                row(r)
                if r.id != rows.last?.id { Rectangle().fill(Design.line).frame(height: 1) }
            }
        }
        .flatList()
    }

    /// Galeri (Finder'ın galeri görünümü gibi): gerçek önizleme küçük resmi, ad, tür ve tarih.
    private func gallery(_ rows: [Source]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 250), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
            ForEach(rows) { fileCard($0) }
        }
    }

    private func fileCard(_ s: Source) -> some View {
        let selected = selection == .source(s.id)
        return VStack(alignment: .leading, spacing: 0) {
            FileThumbnail(url: app.store?.fileURL(for: s), symbol: Self.icon(s.kind), tintKey: brand.id)
                .frame(maxWidth: .infinity).frame(height: 116).clipped()
            Rectangle().fill(Design.line).frame(height: 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(s.title).font(Design.Font.callout.weight(.semibold)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    Text(Self.kindTitle(s.kind))
                    Text(verbatim: "·")
                    Text(s.capturedAt, format: .dateTime.day().month(.abbreviated))
                }
                .font(Design.Font.small).foregroundStyle(.secondary)
            }
            .padding(12)
        }
        .card()
        .overlay(RoundedRectangle(cornerRadius: Design.Radius.large, style: .continuous).strokeBorder(selected ? AnyShapeStyle(Design.accent) : AnyShapeStyle(Color.clear), lineWidth: 2))
        .contentShape(RoundedRectangle(cornerRadius: Design.Radius.large, style: .continuous))
        .onTapGesture { selection = selected ? nil : .source(s.id) }
        .onTapGesture(count: 2) { open(s) }
        .contextMenu {
            Button(L("Aç")) { open(s) }
            Button(L("Önizle")) { selection = .source(s.id) }
            Divider()
            archiveMenuItem(s)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { selection = .source(s.id) }
        .accessibilityAction(named: s.archivedAt == nil ? L("Arşivle") : L("Arşivden çıkar")) {
            setArchived(s.id, title: s.title, archived: s.archivedAt == nil)
        }
    }

    private func row(_ s: Source) -> some View {
        let selected = selection == .source(s.id)
        let sub: String = (s.fileName.flatMap { $0 != s.title ? $0 : nil }) ?? ""
        return HStack(spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: Self.icon(s.kind)).font(Design.Icon.medium).foregroundStyle(.secondary)
                    .frame(width: 36, height: 40)
                    .overlay(RoundedRectangle(cornerRadius: Design.Radius.small, style: .continuous).strokeBorder(Design.line))
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.title).font(Design.Font.body.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                    if !sub.isEmpty { Text(sub).font(Design.Font.small).foregroundStyle(.secondary).lineLimit(1) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(tab == .links ? (s.url ?? "") : Self.kindTitle(s.kind)).lineLimit(1)
                .frame(width: tab == .links ? 220 : 130, alignment: .leading)
            Text(s.archivedAt ?? s.capturedAt, format: .dateTime.day().month(.abbreviated)).frame(width: 100, alignment: .leading)
            if s.archivedAt != nil {
                Button(L("Arşivden çıkar")) { setArchived(s.id, title: s.title, archived: false) }
                    .buttonStyle(.text).frame(width: 120, alignment: .trailing)
                    .help(L("Dosya Dosyalar'a ve Akış'a geri döner."))
            } else {
                Button { open(s) } label: { Image(systemName: "arrow.up.right.square").font(Design.Icon.medium).foregroundStyle(.secondary).frame(width: 30, height: 30) }
                    .buttonStyle(.plain).help(L("Aç")).accessibilityLabel(L("Aç"))
            }
        }
        .font(Design.Font.small).foregroundStyle(.secondary)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .rowBackground(selected: selected, radius: 0)
        .contentShape(Rectangle())
        .onTapGesture { selection = selected ? nil : .source(s.id) }
        .contextMenu {
            Button(L("Aç")) { open(s) }
            Button(L("Önizle")) { selection = .source(s.id) }
            Divider()
            archiveMenuItem(s)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { selection = .source(s.id) }
        .accessibilityAction(named: s.archivedAt == nil ? L("Arşivle") : L("Arşivden çıkar")) {
            setArchived(s.id, title: s.title, archived: s.archivedAt == nil)
        }
    }

    private var linkComposer: some View {
        VStack(alignment: .leading, spacing: Design.Space.s) {
            InputField(title: L("Bağlantı adı"), text: $linkTitle, focus: $linkFocused)
            InputField(title: L("Adres (https://…)"), text: $linkURL).onSubmit(addLink)
            HStack {
                Button(L("Vazgeç")) { addingLink = false; linkTitle = ""; linkURL = "" }.actionSecondary()
                Button(L("Ekle"), action: addLink).actionPrimary()
                    .disabled(linkURL.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14).frame(maxWidth: 520, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Design.Radius.small, style: .continuous).fill(Design.panel))
    }

    private func addLink() {
        let t = linkTitle.trimmingCharacters(in: .whitespacesAndNewlines), u = linkURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty, let store = app.store else { return }
        let ok: Void? = app.perform(title: L("Bağlantı eklenemedi"), context: "kaynak.baglanti") {
            // U-42: şemasız adrese https:// eklenir, ad boşsa alan adı kullanılır, geçersiz adres reddedilir.
            _ = try store.addLink(brandId: brand.id, title: t, address: u)
        }
        if ok != nil { addingLink = false; linkTitle = ""; linkURL = "" }
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = L("Ekle")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            app.perform(title: L("Dosya eklenemedi"), context: "kaynak.dosya") { try app.store?.addFileSource(brandId: brand.id, fileURL: url) }
        }
        tab = .files
    }

    private func open(_ s: Source) {
        if let file = app.store?.fileURL(for: s) { NSWorkspace.shared.open(file) }
        else if let u = s.url, let url = URL(string: u) { NSWorkspace.shared.open(url) }
        else { selection = .source(s.id) }
    }

    static func kindTitle(_ k: SourceKind) -> String {
        switch k {
        case .file: L("Belge")
        case .note: L("Not")
        case .meeting: L("Görüşme")
        case .clientRequest: L("Müşteri talebi")
        case .workOutput: L("Çıktı")
        case .link: L("Bağlantı")
        case .imported: L("İçe aktarılan")
        }
    }

    static func icon(_ k: SourceKind) -> String {
        switch k {
        case .file, .workOutput, .imported: "doc.text"
        case .note: "note.text"
        case .meeting: "person.2"
        case .clientRequest: "tray"
        case .link: "link"
        }
    }
}

// MARK: - Finans

/// Finans — danışmanlık ilişkisi: özet, ödeme planı, çalışma bütçeleri, teklifler ve sözleşmeler. Kayıtlar elle tutulur;
/// uygulama muhasebe, banka bağlantısı ya da otomatik tahsilat yapmaz. Tutar kuruş cinsinden saklanır (₺).
struct FinanceView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.undoManager) private var undoManager
    let brand: Brand
    @State private var selection: PanelTarget?
    @State private var composer: Composer?
    @State private var deleting: FinanceEntry?

    struct Composer {
        var id: String?
        var kind: FinanceKind = .payment
        var title = ""
        var amountText = ""
        var date: String?
        var status: PaymentStatus = .planned
        var note = ""

        init(kind: FinanceKind = .payment) { self.kind = kind }
        init(_ e: FinanceEntry) {
            id = e.id; kind = e.kind; title = e.title
            amountText = e.amountMinor.map { Money.format(minor: $0).replacingOccurrences(of: "₺", with: "") } ?? ""
            date = e.date; status = e.status ?? .planned; note = e.note
        }
        var amountIsValid: Bool { amountText.trimmingCharacters(in: .whitespaces).isEmpty || Money.parseMinor(amountText) != nil }
        var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty && amountIsValid }
    }

    var body: some View {
        let _ = app.revision
        let entries = app.read(or: []) { try $0.financeEntries(brandId: brand.id) }
        let payments = entries.filter { $0.kind == .payment }
        let budgets = entries.filter { $0.kind == .budget }
        let records = (app.read(or: []) { try $0.records(brandId: brand.id, kinds: [.proposal, .contract]) }).sorted { $0.updatedAt > $1.updatedAt }
        ListWithPanel(selection: $selection) {
            PageScroll(backgroundTap: { selection = nil }) {
                VStack(alignment: .leading, spacing: Design.Space.l) {
                    SectionHeading(title: L("Finans"), subtitle: L("Danışmanlık ücreti, ödeme planı ve çalışma bütçesi."), symbol: "turkishlirasign.circle", tintKey: brand.id) {
                        Button { composer = Composer() } label: { Label(L("Kayıt ekle"), systemImage: "plus").labelStyle(.titleAndIcon) }
                            .actionPrimary()
                    }
                    summary(payments)
                    if let c = composer { composerView(c) }
                    paymentPlan(payments)
                    budgetTable(budgets)
                    if !records.isEmpty { proposals(records) }
                    Text(L("Danışmanlık ilişkisini takip eder. Muhasebe, banka bağlantısı veya otomatik tahsilat işlemi yapmaz."))
                        .captionStyle()
                }
                .pagePadding().padding(.vertical, Design.Space.l)
            }
        }
        .onChange(of: brand.id) { selection = nil; composer = nil }
        .confirmationDialog(LF("“%@” silinsin mi?", deleting?.title ?? ""), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { e in
            Button(L("Sil"), role: .destructive) {
                let ok: Void? = app.perform(title: L("Silinemedi"), context: "finans.sil") { try app.store?.deleteFinanceEntry(e.id) }
                if ok != nil {
                    // ⌘Z: silinen kaydı geri getirir.
                    undoManager?.registerUndo(withTarget: app) { _ in
                        MainActor.assumeIsolated { _ = app.perform(title: L("Geri alınamadı"), context: "finans.sil.geri") { try app.store?.saveFinanceEntry(e) } }
                    }
                    undoManager?.setActionName(L("Sil"))
                }
            }
        } message: { _ in
            Text(L("Kayıt kalıcı olarak silinir. Bu işlem geri alınamaz."))
        }
    }

    // MARK: Özet

    private func summary(_ payments: [FinanceEntry]) -> some View {
        let month = String(DayString.from(Date()).prefix(7))
        func sum(_ list: [FinanceEntry]) -> Int64 { list.reduce(0) { $0 + ($1.amountMinor ?? 0) } }
        let collected = sum(payments.filter { $0.status == .collected && ($0.date ?? "").hasPrefix(month) })
        let expected = sum(payments.filter { $0.status != .collected && ($0.date ?? "").hasPrefix(month) })
        let openTotal = sum(payments.filter { $0.status != .collected })
        let monthStart = StatusService.turkishCalendar.dateInterval(of: .month, for: Date())?.start ?? Date()
        let seconds = (app.read(or: []) { try $0.timeEntries(brandId: brand.id, from: monthStart, to: Date()) }).reduce(0) { $0 + $1.seconds }
        // Kartlar dar pencerede alt satıra sarılır (sabit genişlikli satır sayfanın dışına taşıyordu).
        return TileGrid {
            stat(L("Bu ay tahsil edilen"), Money.format(minor: collected), symbol: "checkmark.circle")
            stat(L("Bu ay beklenen"), Money.format(minor: expected), symbol: "clock")
            stat(L("Toplam bekleyen"), Money.format(minor: openTotal), symbol: "hourglass")
            stat(L("Bu ay çalışma süresi"), seconds > 0 ? Self.hours(seconds) : "—", symbol: "stopwatch")
        }
    }

    private func stat(_ title: String, _ value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol).font(Design.Icon.medium.weight(.semibold)).foregroundStyle(BrandTintStyle(key: brand.id))
                .frame(width: 30, height: 30).background(Circle().fill(BrandTintStyle(key: brand.id).opacity(0.14)))
            VStack(alignment: .leading, spacing: 4) {
                Text(value).font(Design.Font.title.weight(.semibold)).tracking(-0.5).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                Text(title).font(Design.Font.small).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16)
    }

    // MARK: Ödeme planı

    private func paymentPlan(_ payments: [FinanceEntry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("Ödeme planı")).font(Design.Font.heading.weight(.semibold))
                Spacer()
                if let range = Self.rangeText(payments) { Text(range).font(Design.Font.callout).foregroundStyle(.secondary) }
            }
            .padding(.bottom, Design.Space.m)
            if payments.isEmpty {
                EmptyStateView(title: L("Henüz ödeme satırı yok"), message: L("“Kayıt ekle” ile danışmanlık ücretinin vadelerini ekleyebilirsin."))
            } else {
                VStack(spacing: 0) {
                    header([(L("Açıklama"), nil), (L("Tarih"), 100), (L("Tutar"), 84), (L("Durum"), 124)])
                    ForEach(payments) { e in
                        paymentRow(e)
                        if e.id != payments.last?.id { Rectangle().fill(Design.line).frame(height: 1) }
                    }
                }
                .flatList()
            }
        }
    }

    private func paymentRow(_ e: FinanceEntry) -> some View {
        HStack(spacing: 12) {
            Text(e.title).font(Design.Font.body).frame(maxWidth: .infinity, alignment: .leading).lineLimit(2)
            Text(e.date.flatMap(Self.longDate) ?? "—").frame(width: 100, alignment: .leading)
            Text(e.amountMinor.map { Money.format(minor: $0) } ?? L("Henüz belirlenmedi")).frame(width: 84, alignment: .leading).monospacedDigit().lineLimit(1)
            statusLabel(e.status ?? .planned).frame(width: 124, alignment: .leading)
            rowMenu(e)
        }
        .font(Design.Font.callout).foregroundStyle(.secondary)
        .padding(.horizontal, 14).padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    private func statusLabel(_ s: PaymentStatus) -> some View {
        let (symbol, title): (String, String) = switch s {
        case .collected: ("checkmark", L("Tahsil edildi"))
        case .pending: ("clock", L("Bekleniyor"))
        case .planned: ("calendar", L("Planlandı"))
        }
        return Label(title, systemImage: symbol).labelStyle(.titleAndIcon).font(Design.Font.callout)
            .foregroundStyle(s == .collected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
    }

    private func rowMenu(_ e: FinanceEntry) -> some View {
        Menu {
            if e.kind == .payment {
                ForEach(PaymentStatus.allCases, id: \.self) { s in
                    Button(Self.statusTitle(s)) { setStatus(e, s) }.disabled(e.status == s)
                }
                Divider()
            }
            Button(L("Düzenle")) { composer = Composer(e) }
            Button(L("Sil…"), role: .destructive) { deleting = e }
        } label: {
            Image(systemName: "ellipsis").font(Design.Icon.small).foregroundStyle(.secondary).frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .frame(width: 28, height: 28)
        .help(L("Diğer")).accessibilityLabel(L("Diğer"))
    }

    private func setStatus(_ e: FinanceEntry, _ s: PaymentStatus) {
        var copy = e
        copy.status = s
        let ok: FinanceEntry?? = app.perform(title: L("Kaydedilemedi"), context: "finans.durum") { try app.store?.saveFinanceEntry(copy) }
        if ok != nil {
            undoManager?.registerUndo(withTarget: app) { _ in
                MainActor.assumeIsolated { _ = app.perform(title: L("Geri alınamadı"), context: "finans.durum.geri") { try app.store?.saveFinanceEntry(e) } }
            }
            undoManager?.setActionName(L("Durumu değiştir"))
        }
    }

    // MARK: Bütçeler

    private func budgetTable(_ budgets: [FinanceEntry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("Çalışma bütçeleri")).font(Design.Font.heading.weight(.semibold)).padding(.bottom, Design.Space.m).padding(.top, Design.Space.m)
            if budgets.isEmpty {
                EmptyStateView(title: L("Henüz bütçe kalemi yok"), message: L("Çekim, üretim gibi kalemlerin planlanan tutarını “Kayıt ekle” ile ekleyebilirsin."))
            } else {
                VStack(spacing: 0) {
                    header([(L("Kalem"), nil), (L("Planlanan"), 110), (L("Not"), 170)])
                    ForEach(budgets) { e in
                    if e.id != budgets.first?.id { Rectangle().fill(Design.line).frame(height: 1) }
                    HStack(spacing: 12) {
                        Text(e.title).font(Design.Font.body).frame(maxWidth: .infinity, alignment: .leading).lineLimit(2)
                        Text(e.amountMinor.map { Money.format(minor: $0) } ?? L("Henüz belirlenmedi")).frame(width: 110, alignment: .leading).monospacedDigit().lineLimit(1)
                        Text(e.note).lineLimit(2).frame(width: 170, alignment: .leading)
                        rowMenu(e)
                    }
                    .font(Design.Font.callout).foregroundStyle(.secondary)
                    .padding(.horizontal, 14).padding(.vertical, 14)
                    .accessibilityElement(children: .combine)
                    }
                }
                .flatList()
            }
        }
    }

    // MARK: Teklifler ve sözleşmeler

    private func proposals(_ records: [BrandRecord]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("Teklifler ve sözleşmeler")).font(Design.Font.heading.weight(.semibold)).padding(.bottom, Design.Space.m).padding(.top, Design.Space.m)
            VStack(spacing: 0) {
            ForEach(records) { r in
                let selected = selection == .record(r.id)
                if r.id != records.first?.id { Rectangle().fill(Design.line).frame(height: 1) }
                HStack(spacing: 12) {
                    Image(systemName: r.kind == .contract ? "doc.text" : "doc.plaintext").font(Design.Icon.medium).foregroundStyle(.secondary).frame(width: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(r.title).font(Design.Font.body.weight(.medium)).lineLimit(1)
                        Text(r.kind.title).font(Design.Font.small).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(r.status.title).font(Design.Font.callout).foregroundStyle(.secondary)
                    if let d = r.dueDate { DueLabel(day: d, isOpen: r.isOpen).frame(width: 56, alignment: .trailing) }
                }
                .padding(.vertical, 14).padding(.horizontal, 14)
                .rowBackground(selected: selected, radius: 0)
                .contentShape(Rectangle())
                .onTapGesture { selection = selected ? nil : .record(r.id) }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { selection = .record(r.id) }
            }
            }
            .flatList()
        }
    }

    // MARK: Ekleme / düzenleme

    private func composerView(_ c: Composer) -> some View {
        let binding = Binding<Composer>(get: { composer ?? c }, set: { composer = $0 })
        return VStack(alignment: .leading, spacing: Design.Space.m) {
            HStack {
                Text(c.id == nil ? L("Yeni finans kaydı") : L("Kaydı düzenle")).font(Design.Font.body.weight(.semibold))
                Spacer()
                if c.id == nil {
                    SegmentedChoice(options: [(FinanceKind.payment, L("Ödeme")), (FinanceKind.budget, L("Bütçe"))], selection: binding.kind)
                }
            }
            InputField(title: c.kind == .payment ? L("Açıklama (ör. Ekim danışmanlık hizmeti)") : L("Kalem (ör. Fotoğraf çekimi)"), text: binding.title)
            HStack(spacing: Design.Space.s) {
                InputField(title: L("Tutar (₺) — boş: henüz belirlenmedi"), text: binding.amountText)
                if c.kind == .payment { OptionalDayPicker(title: L("Tarih"), day: binding.date) }
            }
            if !c.amountIsValid { Text(L("Tutarı 45.000 ya da 45.000,50 biçiminde yaz.")).font(Design.Font.small).foregroundStyle(Design.danger) }
            if c.kind == .payment {
                SegmentedChoice(options: PaymentStatus.allCases.map { ($0, Self.statusTitle($0)) }, selection: binding.status)
            } else {
                InputField(title: L("Not (isteğe bağlı)"), text: binding.note)
            }
            HStack {
                Spacer()
                Button(L("Vazgeç")) { composer = nil }.actionSecondary()
                Button(L("Kaydet")) { save(c) }.actionPrimary().disabled(!c.canSave)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Design.Radius.small, style: .continuous).fill(Design.panel))
        .overlay(RoundedRectangle(cornerRadius: Design.Radius.small, style: .continuous).strokeBorder(Design.line))
    }

    private func save(_ c: Composer) {
        guard let store = app.store, c.canSave else { return }
        let trimmedAmount = c.amountText.trimmingCharacters(in: .whitespaces)
        let existing = c.id.flatMap { id in (try? store.financeEntries(brandId: brand.id))?.first { $0.id == id } }
        var entry = existing ?? FinanceEntry(brandId: brand.id, kind: c.kind, title: c.title)
        entry.title = c.title
        entry.amountMinor = trimmedAmount.isEmpty ? nil : Money.parseMinor(trimmedAmount)
        entry.date = c.kind == .payment ? c.date : nil
        entry.status = c.kind == .payment ? c.status : nil
        entry.note = c.kind == .budget ? c.note : ""
        let ok: FinanceEntry?? = app.perform(title: L("Kaydedilemedi"), context: "finans.kaydet") { try store.saveFinanceEntry(entry) }
        if ok != nil { composer = nil }
    }

    // MARK: Yardımcılar

    private func header(_ columns: [(String, CGFloat?)]) -> some View {
        HStack(spacing: 12) {
            ForEach(columns.indices, id: \.self) { i in
                if let w = columns[i].1 { Text(columns[i].0).frame(width: w, alignment: .leading) }
                else { Text(columns[i].0).frame(maxWidth: .infinity, alignment: .leading) }
            }
            Color.clear.frame(width: 28, height: 1)
        }
        .font(Design.Font.small.weight(.medium)).foregroundStyle(.secondary)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Design.windowBackground.opacity(0.5))
        .overlay(alignment: .bottom) { Rectangle().fill(Design.line).frame(height: 1) }
    }

    static func statusTitle(_ s: PaymentStatus) -> String {
        switch s {
        case .collected: L("Tahsil edildi")
        case .pending: L("Bekleniyor")
        case .planned: L("Planlandı")
        }
    }

    private static func longDate(_ day: String) -> String? {
        guard let d = DayString.date(day) else { return nil }
        return d.formatted(.dateTime.day().month(.abbreviated).year())
    }

    /// İlk ve son tarihli ödemeden: "Eylül – Kasım 2026"; yıllar farklıysa ikisi de yıllı ("Kasım 2025 – Aralık 2026"),
    /// aynı aydaysa tek ay. (Önceden ilk tarihin yılı düşüyordu: 2025'te başlayan plan "Kasım – Aralık 2026" görünüyordu.)
    static func rangeText(_ payments: [FinanceEntry], calendar: Calendar = .current) -> String? {
        let dates = payments.compactMap { $0.date.flatMap { DayString.date($0) } }.sorted()
        guard let first = dates.first, let last = dates.last else { return nil }
        let month = Date.FormatStyle().month(.wide), full = Date.FormatStyle().month(.wide).year()
        let sameYear = calendar.component(.year, from: first) == calendar.component(.year, from: last)
        if sameYear && calendar.component(.month, from: first) == calendar.component(.month, from: last) { return last.formatted(full) }
        return (sameYear ? first.formatted(month) : first.formatted(full)) + " – " + last.formatted(full)
    }

    private static func hours(_ s: Int) -> String {
        let h = s / 3600, m = (s % 3600) / 60
        return h > 0 ? LF("%1$d sa %2$d dk", h, m) : LF("%d dk", m)
    }
}

/// Zaman çizelgesinde tek satır: solda iş, sağda dört haftalık izde elmas işareti.
private struct TimelineRow: View {
    let item: PlanningView.Item
    let lastDay: Int
    let labelWidth: CGFloat
    @Binding var selection: PanelTarget?

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                StatusCircle(state: item.done ? .done : .todo, size: 14)
                Text(item.title).font(Design.Font.callout).lineLimit(2).strikethrough(item.done)
            }
            .padding(.leading, 20).padding(.trailing, 8).frame(width: labelWidth, alignment: .leading)
            track
        }
        .contentShape(Rectangle())
        .onTapGesture { selection = selection == item.target ? nil : item.target }
        .overlay(alignment: .bottom) { Rectangle().fill(Design.line).frame(height: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title + (item.day.map { ", " + $0 } ?? ""))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { selection = item.target }
    }

    private var track: some View {
        GeometryReader { geo in
            let calendar = StatusService.turkishCalendar
            let today: String = DayString.from(Date(), calendar: calendar)
            let overdue: Bool = (item.day ?? "") < today && !item.done
            let x: CGFloat = max(4, min(geo.size.width - 84, geo.size.width * markerFraction - 5))
            ZStack(alignment: .leading) {
                grid
                marker(overdue: overdue).offset(x: x)
            }
        }
        .frame(height: 52)
    }

    /// Elmasın izdeki yeri: dört eşit sütun; sütun içinde günün oranı (1–8, 9–16, 17–24, 25–son).
    private var markerFraction: CGFloat {
        guard let day = item.day, let n = Int(day.suffix(2)) else { return 0 }
        let col = min(3, (n - 1) / 8)
        let colDays = col < 3 ? 8 : max(1, lastDay - 24)
        let within = (CGFloat(n - 1 - col * 8) + 0.5) / CGFloat(colDays)
        return (CGFloat(col) + within) / 4
    }

    private var grid: some View {
        HStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { _ in
                Color.clear.frame(maxWidth: .infinity).overlay(alignment: .trailing) { Rectangle().fill(Design.line).frame(width: 1) }
            }
        }
    }

    private func marker(overdue: Bool) -> some View {
        let tint: AnyShapeStyle = overdue ? AnyShapeStyle(Design.danger) : (item.done ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(Design.accent))
        return HStack(spacing: 7) {
            Rectangle().fill(tint).frame(width: 9, height: 9).rotationEffect(.degrees(45))
            if let d = item.day { DueLabel(day: d, isOpen: !item.done) }
        }
    }
}

/// Takvimde tek gün hücresi: gün numarası ve en çok üç iş.
private struct CalendarDayCell: View {
    let date: Date
    let inMonth: Bool
    let isToday: Bool
    let items: [PlanningView.Item]
    let day: Int
    @Binding var selection: PanelTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            number
            ForEach(items.prefix(3)) { item in chip(item) }
            if items.count > 3 { Text(LF("+%d daha", items.count - 3)).captionStyle() }
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background(inMonth ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Design.panel))
        .overlay(alignment: .trailing) { Rectangle().fill(Design.line).frame(width: 1) }
    }

    private var number: some View {
        let ink: AnyShapeStyle = isToday ? AnyShapeStyle(Color.white) : (inMonth ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
        let fill: AnyShapeStyle = isToday ? AnyShapeStyle(Design.accentFill) : AnyShapeStyle(Color.clear)
        return Text(verbatim: "\(day)")
            .font(Design.Font.small.weight(isToday ? .bold : .regular)).monospacedDigit()
            .foregroundStyle(ink)
            .frame(width: 22, height: 22)
            .background(Circle().fill(fill))
    }

    private func chip(_ item: PlanningView.Item) -> some View {
        let ink: AnyShapeStyle = item.done ? AnyShapeStyle(.secondary) : AnyShapeStyle(Design.accent)
        return Text(item.title).font(Design.Font.small).lineLimit(1)
            .foregroundStyle(ink)
            .padding(.horizontal, 5).padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Design.Radius.small).fill(Design.accent.opacity(0.12)))
            .onTapGesture { selection = selection == item.target ? nil : item.target }
            .accessibilityValue(item.done ? StatusCircle.State.done.title : StatusCircle.State.todo.title)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { selection = item.target }
    }
}


/// Dosya önizlemesi: sistemin Quick Look küçük resmi (yerelde üretilir); yoksa türün simgesi marka renginde.
struct FileThumbnail: View {
    let url: URL?
    let symbol: String
    let tintKey: String
    @State private var image: NSImage?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Küçük resim kendi doğal boyutuyla düzeni büyütmesin: zemin kabın boyutunu alır, resim üstüne bindirilip kırpılır.
        // (Önceden `scaledToFill` kabı taşırıyor, koyu temada kartın başlık şeridini örtüyordu.)
        Rectangle().fill(BrandTintStyle(key: tintKey).opacity(0.08))
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                        .opacity(colorScheme == .dark ? 0.82 : 1)   // koyu temada parlak beyaz sayfayı kıs
                } else {
                    Image(systemName: symbol).font(Design.Icon.hero.weight(.light)).foregroundStyle(BrandTintStyle(key: tintKey))
                }
            }
            .clipped()
        .task(id: url) {
            guard let url else { return }
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 340, height: 232),
                                                       scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
            if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { image = rep.nsImage }
        }
        .accessibilityHidden(true)
    }
}
