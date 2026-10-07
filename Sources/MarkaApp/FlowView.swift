import AppKit
import MarkaCore
import SwiftUI

/// Akış — *ne yapıldı* (plan §4, U9): günlere göre, en yeni üstte, tek satırlık öğeler (`Store.flow`): iş kaydı, biten
/// görev (iş kaydı bağlı olan yalnız iş kaydı satırıyla), not, dosya, kapanan söz / karar / talep, onaylanan öneri.
/// Akış onay istemez: klasördeki yeni dosyalar ve öneriler onay sayfasında. Satıra tıklayınca sağda ayrıntı paneli; iş
/// kaydı yalnız orada, içeriği görülerek doğrulanır; onaylanan öneri orada geri alınır.
/// Üstte yalnız "Not ekle"; dosya sürüklenip bırakılır ya da marka klasörüne konur (bu ipucu yalnız boş durumda).
struct FlowView: View {
    @Environment(AppModel.self) private var app
    let brand: Brand
    @State private var selection: PanelTarget?
    @State private var composing = false
    @State private var dropTargeted = false
    /// Elle iş kaydı (H2-03, U-09): "+ İş kaydı" ile açılan düzenleyici.
    @State private var writingLog: WorkLogDetail?

    init(brand: Brand, selection: PanelTarget? = nil) {
        self.brand = brand
        _selection = State(initialValue: selection)
    }

    /// Akış'ta gösterilen en çok öğe.
    static let limit = 200

    var body: some View {
        let _ = app.revision
        let days = FlowItem.days(app.read(or: []) { try $0.flow(brandId: brand.id, limit: Self.limit) }, calendar: .current)
        let todo = app.read(or: []) { try $0.todo(brandId: brand.id) }
        let flowItems = days.flatMap(\.items)
        ListWithPanel(selection: $selection) {
            PageScroll(backgroundTap: { selection = nil }) {
                VStack(alignment: .leading, spacing: Design.Space.l) {
                    if app.store?.isSampleBrand(brand.id) == true { SampleBrandBanner(brand: brand) }
                    BrandSummaryLine(brand: brand)
                    overview(todo: todo, flow: flowItems)
                    upcoming(todo)
                    HStack(alignment: .center) {
                        Text(L("Akış")).font(Design.Font.heading.weight(.semibold)).accessibilityAddTraits(.isHeader)
                        Text(L("Ne yapıldı: iş kayıtları, biten görevler, notlar ve dosyalar.")).font(Design.Font.callout).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: Design.Space.m)
                        Button { writingLog = .newDraft(brandId: brand.id) } label: {
                            Label(L("İş kaydı"), systemImage: "plus").labelStyle(.titleAndIcon)
                        }
                        .actionSecondary()
                        .help(L("Yaptığın işi yaz; kaydettiğinde doğrulanmış sayılır ve rapora girer."))
                        .accessibilityLabel(L("İş kaydı ekle"))
                        Button { composing.toggle() } label: {
                            Label(composing ? L("Vazgeç") : L("Not ekle"), systemImage: composing ? "xmark" : "square.and.pencil").labelStyle(.titleAndIcon)
                        }
                        .actionSecondary()
                        .keyboardShortcut(composing ? KeyboardShortcut.cancelAction : nil)
                    }
                    .padding(.top, Design.Space.s)
                    if composing { NoteComposer(brand: brand) { composing = false } }
                    if days.isEmpty {
                        EmptyStateView(title: L("Henüz bir şey yok"),
                                       message: L("Dosya sürükle ya da not ekle. Asistanın önerileri onay bandında görünür."),
                                       symbol: "clock.arrow.circlepath")
                    } else {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(days) { day in
                                Text(Self.dayTitle(day.day)).font(Design.Font.callout.weight(.semibold))
                                    .padding(.top, Design.Space.m).padding(.bottom, Design.Space.xs)
                                    .accessibilityAddTraits(.isHeader)
                                VStack(spacing: 0) {
                                    ForEach(Array(day.items.enumerated()), id: \.element.id) { index, item in
                                        if index > 0 { Rectangle().fill(Design.line).frame(height: 1) }
                                        FlowRow(item: item, selection: $selection)
                                    }
                                }
                                .flatList()
                            }
                        }
                    }
                }
                .pagePadding().padding(.vertical, Design.Space.l)
            }
        }
        .overlay { if dropTargeted { RoundedRectangle(cornerRadius: Design.Radius.small).strokeBorder(Design.accent, lineWidth: 2) } }
        .liveOnly(FileDrop(targeted: $dropTargeted) { addFiles($0) })
        .sheet(item: $writingLog) { d in WorkLogEditor(detail: d, isNew: true).environment(app) }
        .onChange(of: brand.id) { selection = nil; composing = false; writingLog = nil }
    }

    /// Dört özet kutucuğu: açık iş (Görevler'deki liste), bu hafta biten, müşteriden beklenen karar, doğrulanmamış iş kaydı.
    private func overview(todo: [TodoItem], flow: [FlowItem]) -> some View {
        // H3-10: "Bu hafta" aralığı ve "biten görev" tanımı Bugün'deki kutucukla aynı (`CountDefinitions`).
        let week = CountDefinitions.week(containing: Date(), calendar: StatusService.turkishCalendar)
        // Görevler bölümünün başlığındaki "N açık" ile aynı tanım: `store.todo` öğelerinin tümü (görev, söz, karar, talep).
        let openTasks = todo.count
        let decisions = todo.filter { if case .record(.decision, _) = $0.kind { true } else { false } }.count
        // Görevler doğrudan sayılır: iş kaydı bağlı biten görev Akış'ta ayrı bir kayıt olarak görünür ve `flow` üzerinden sayılmazdı.
        let doneThisWeek = app.read(or: 0) { try $0.completedTaskCount(brandId: brand.id, week: week) }
        let drafts = flow.filter { if case .workLog(.draft) = $0.kind { true } else { false } }.count
        return TileGrid {
            TodayTile(symbol: "checklist", title: L("Açık iş"), count: openTasks) { app.brandTab = .todo }
            TodayTile(symbol: "checkmark.circle", title: L("Bu hafta biten görev"), count: doneThisWeek) {}
            TodayTile(symbol: "hourglass", title: L("Karar bekleniyor"), count: decisions, emphasize: decisions > 0) { app.brandTab = .todo }
            TodayTile(symbol: "checkmark.seal", title: L("Doğrulanmadı"), count: drafts, emphasize: drafts > 0) {}
        }
    }

    /// Sıradaki teslimler: tarihli ilk üç açık iş (gecikenler önce); satıra tıklayınca Görevler'de ayrıntısı açılır.
    @ViewBuilder private func upcoming(_ todo: [TodoItem]) -> some View {
        let dated = todo.filter { $0.dueDate != nil }.sorted { ($0.dueDate ?? "") < ($1.dueDate ?? "") }.prefix(3)
        if !dated.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "calendar").font(Design.Icon.small.weight(.semibold)).foregroundStyle(.secondary)
                    Text(L("Sıradaki teslimler")).font(Design.Font.heading.weight(.semibold))
                }
                .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    ForEach(Array(dated.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Rectangle().fill(Design.line).frame(height: 1) }
                        Button { app.brandTab = .todo; app.panelTarget = PanelTarget(item) } label: {
                            HStack(spacing: 12) {
                                StatusCircle(state: item.circleState, size: 15)
                                Text(item.title).font(Design.Font.body.weight(.medium)).lineLimit(1)
                                Spacer()
                                Text(item.kindTitle).font(Design.Font.small).foregroundStyle(.secondary)
                                if let d = item.dueDate { DueLabel(day: d) }
                            }
                            .padding(.vertical, 12).padding(.horizontal, 14).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).rowBackground(selected: false, radius: 0)
                        .accessibilityValue(item.circleState.title)
                    }
                }
                .flatList()
            }
        }
    }

    /// Sürükle-bırak: dosya olduğu gibi saklanır.
    private func addFiles(_ urls: [URL]) {
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            app.perform(title: L("Dosya eklenemedi"), context: "kaynak.dosya") { try app.store?.addFileSource(brandId: brand.id, fileURL: url) }
        }
    }

    static func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        let date = day.formatted(.dateTime.day().month(.wide))
        if cal.isDateInToday(day) { return LF("Bugün · %@", date) }
        if cal.isDateInYesterday(day) { return LF("Dün · %@", date) }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

/// Akış satırı: solda tür (ek stil), ortada başlık, sağda (doğrulanmamış iş kaydında) durum ve saat. Tıklayınca ayrıntı
/// paneli açılır/kapanır. Satırda eylem yok (U9): doğrulama ve geri alma panelde. VoiceOver'da tek öğe; "Geri al" adlı eylem.
struct FlowRow: View {
    @Environment(AppModel.self) private var app
    let item: FlowItem
    @Binding var selection: PanelTarget?

    static let kindWidth: CGFloat = 120
    static let timeWidth: CGFloat = 40

    var body: some View {
        let target = PanelTarget(item)
        let selected = selection == target
        HStack(alignment: .center, spacing: 12) {
            let tint: AnyShapeStyle = Self.isWorkLog(item.kind) ? AnyShapeStyle(Design.accent) : AnyShapeStyle(.secondary)
            Image(systemName: Self.symbol(item.kind)).font(Design.Icon.medium.weight(.semibold)).foregroundStyle(tint)
                .frame(width: 32, height: 32).background(Circle().fill(tint.opacity(0.13)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(Design.Font.body.weight(.medium)).lineLimit(1)
                Text(item.kind.title).font(Design.Font.small).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if case .workLog(.draft) = item.kind { Pill(text: WorkLogStatus.draft.title, tint: AnyShapeStyle(Design.accent)) }
            Text(item.date, format: .dateTime.hour().minute()).font(Design.Font.small).foregroundStyle(.secondary).monospacedDigit()
                .frame(width: Self.timeWidth, alignment: .trailing)
        }
        .padding(.vertical, 10).padding(.horizontal, 14)
        .rowBackground(selected: selected, radius: 0)
        .contentShape(Rectangle())
        .onTapGesture { selection = selected ? nil : target }
        .contextMenu {
            Button(L("Ayrıntıyı aç")) { selection = target }
            if undoable { Button(L("Geri al"), action: undoProposal) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.kind.title + " · " + item.title)
        .accessibilityValue(item.date.formatted(.dateTime.hour().minute()))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { selection = selected ? nil : target }
        .modifier(RowAction(name: L("Geri al"), enabled: undoable, perform: undoProposal))
    }

    static func isWorkLog(_ kind: FlowItem.Kind) -> Bool { if case .workLog = kind { true } else { false } }

    /// Satırın türüne göre simge.
    static func symbol(_ kind: FlowItem.Kind) -> String {
        switch kind {
        case .workLog(.verified): "checkmark.seal.fill"
        case .workLog(.draft): "seal"
        case .workLog(.retracted): "arrow.uturn.backward.circle"
        case .taskDone: "checkmark.circle.fill"
        case .note: "note.text"
        case .file: "doc.fill"
        case .recordClosed: "flag.checkered"
        case .proposalApplied: "sparkles"
        }
    }

    /// Onaylanan öneri geri alınabilir mi (VoiceOver eylemi için; görünür yol ayrıntı panelindeki "Geri al").
    private var undoable: Bool {
        guard case .proposalApplied = item.kind,
              let p = try? app.store?.read({ db in try AIProposal.fetchOne(db, key: item.entityId) }) else { return false }
        return canUndo(p, app: app)
    }

    private func undoProposal() {
        if let p = try? app.store?.read({ db in try AIProposal.fetchOne(db, key: item.entityId) }) { undo(p, app: app) }
    }
}

/// Koşullu adlı erişilebilirlik eylemi (VoiceOver "Eylemler" menüsü). Düğme değildir; görünür yolun klavye/VoiceOver karşılığı.
struct RowAction: ViewModifier {
    let name: String
    let enabled: Bool
    let perform: () -> Void
    func body(content: Content) -> some View {
        if enabled { content.accessibilityAction(named: name, perform) } else { content }
    }
}

extension FlowItem.Kind {
    /// Satırın sol sütunundaki tür adı (plan §6 sözlüğü; tamamlanma tek ad: Bitti).
    var title: String {
        switch self {
        case .workLog: L("İş kaydı")
        case .taskDone: L("Görev") + " · " + TaskStatus.done.title
        case .note: L("Not")
        case .file: L("Dosya")
        case .recordClosed(let k, let s): k.title + " · " + s.title
        case .proposalApplied: L("Öneri onaylandı")
        }
    }
}

/// Akış'ın üstünde açılan satır içi not alanı: başlık + metin. Metin boşsa başlık metin olarak saklanır. Vazgeçmek için
/// üstteki "Vazgeç" ya da Esc.
struct NoteComposer: View {
    @Environment(AppModel.self) private var app
    let brand: Brand
    let done: () -> Void
    @State private var title = ""
    @State private var text = ""
    @State private var finished = false
    @State private var pendingId = UUID()
    @FocusState private var titleFocused: Bool
    @FocusState private var noteFocused: Bool

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canAdd: Bool { !trimmedTitle.isEmpty || !trimmedText.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.s) {
            InputField(title: L("Başlık"), text: $title, focus: $titleFocused)
                .onSubmit { noteFocused = true }
            // Enter yeni satır açar (çok satırlı not); kayıt: Ekle, ⌘↩ ya da odak iki alandan da çıkınca.
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .focused($noteFocused)
                .frame(minHeight: 72, maxHeight: 200)
                .padding(Design.Space.xs)
                .background(RoundedRectangle(cornerRadius: Design.Radius.small).fill(Design.bandBackground))
                .overlay(RoundedRectangle(cornerRadius: Design.Radius.small).strokeBorder(Design.line))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(L("Not")).foregroundStyle(.secondary)
                            .padding(.horizontal, Design.Space.xs + 5).padding(.vertical, Design.Space.xs + 1)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityLabel(L("Not"))
            HStack(spacing: Design.Space.m) {
                Spacer()
                Button(L("Ekle")) { add() }
                    .buttonStyle(.text)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canAdd)
            }
        }
        .padding(.vertical, Design.Space.s)
        .overlay(alignment: .bottom) { Rectangle().fill(Design.line).frame(height: 1) }
        .onChange(of: titleFocused) { _, _ in focusMaybeLeft() }
        .onChange(of: noteFocused) { _, _ in focusMaybeLeft() }
        .onChange(of: title) { _, _ in registerPending() }
        .onChange(of: text) { _, _ in registerPending() }
        .onDisappear { finished = true; PendingEdits.shared.clear(pendingId) }
    }

    /// Odak iki alandan da çıktıysa ve yazılmış bir şey varsa kaydeder (alanlar arası geçiş kayıt sayılmaz).
    private func focusMaybeLeft() {
        if !titleFocused && !noteFocused && canAdd && !finished { add() }
    }

    /// Yazarken uygulama kapanırsa yazılan kaybolmasın (U-07); kayıt `add` ile tek sefer olur.
    private func registerPending() {
        if canAdd && !finished { PendingEdits.shared.register(pendingId, save: { add() }) }
    }

    private func add() {
        guard !finished, canAdd else { return }
        finished = true
        PendingEdits.shared.clear(pendingId)
        // Başlık boşsa notun ilk satırı başlık olur; metin boşsa başlık metin olarak saklanır.
        let firstLine = trimmedText.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let t = trimmedTitle.isEmpty ? String(firstLine.prefix(60)) : trimmedTitle
        let body = trimmedText
        let ok: Void? = app.perform(title: L("Not eklenemedi"), context: "kaynak.not") {
            _ = try app.store?.addTextSource(brandId: brand.id, kind: .note, title: t, body: body.isEmpty ? t : body)
        }
        if ok != nil { done() } else { finished = false }
    }
}

/// Dosya bırakma alanı (AppKit sürükle-bırak görünümü; ekran çiziminde uygulanmaz).
struct FileDrop: ViewModifier {
    @Binding var targeted: Bool
    let add: ([URL]) -> Void
    func body(content: Content) -> some View {
        content.dropDestination(for: URL.self) { urls, _ in
            add(urls.filter(\.isFileURL))
            return true
        } isTargeted: { targeted = $0 }
    }
}


/// Marka tanımı (Özet'in üstü, onay bandından sonra): düz, ikincil metin; en çok 2 satır, tam metin ipucunda.
/// Ad araç çubuğunda, sektör pencere alt başlığında olduğundan burada tekrarlanmaz. Tanım yoksa "Ekle" bağlantısı.
/// Yalnız örnek markada, Özet'in üstünde sakin bir bilgi şeridi: bunun örnek olduğunu ve AI'sız raporu söyler; "Arşivle…"
/// mevcut arşiv onayını açar (normal arşiv yolu).
struct SampleBrandBanner: View {
    @Environment(AppModel.self) private var app
    let brand: Brand
    @State private var archiving = false

    var body: some View {
        HStack(alignment: .center, spacing: Design.Space.s) {
            Image(systemName: "info.circle").foregroundStyle(.secondary).accessibilityHidden(true)
            Text(L("Bu bir örnek markadır. Rapor sekmesinde yapay zekâsız PDF raporu görebilirsin."))
                .font(Design.Font.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Design.Space.m)
            Button(L("Rapora git")) { app.brandTab = .report }.buttonStyle(.text)
            Button(L("Arşivle…")) { archiving = true }.buttonStyle(.text)
        }
        .padding(.horizontal, Design.Space.m).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: Design.Radius.small, style: .continuous).fill(Design.panel))
        .overlay(RoundedRectangle(cornerRadius: Design.Radius.small, style: .continuous).strokeBorder(Design.line))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("Örnek marka"))
        .brandArchiveConfirmation(brand: archiving ? brand : nil, isPresented: $archiving)
    }
}

struct BrandSummaryLine: View {
    @Environment(AppModel.self) private var app
    let brand: Brand

    var body: some View {
        let summary = (app.read(or: brand) { try $0.brand(brand.id) }).summary
        if summary.isEmpty {
            HStack(spacing: Design.Space.s) {
                Text(L("Marka tanımı yok.")).font(Design.Font.body).foregroundStyle(.secondary)
                Button(L("Ekle")) { app.brandTab = .info }
                    .buttonStyle(.plain).font(Design.Font.body.weight(.medium)).foregroundStyle(.primary)
                    .accessibilityHint(L("Marka Bilgileri'ni açar"))
            }
        } else {
            Text(summary).font(Design.Font.body).foregroundStyle(.secondary).lineLimit(2).lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(summary)
        }
    }
}
