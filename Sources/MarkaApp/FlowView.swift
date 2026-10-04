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

    init(brand: Brand, selection: PanelTarget? = nil) {
        self.brand = brand
        _selection = State(initialValue: selection)
    }

    /// Akış'ta gösterilen en çok öğe.
    static let limit = 200

    var body: some View {
        let _ = app.revision
        let days = FlowItem.days((try? app.store?.flow(brandId: brand.id, limit: Self.limit)) ?? [], calendar: .current)
        let todo = (try? app.store?.todo(brandId: brand.id)) ?? []
        let flowItems = days.flatMap(\.items)
        ListWithPanel(selection: $selection) {
            PageScroll(backgroundTap: { selection = nil }) {
                VStack(alignment: .leading, spacing: Design.Space.l) {
                    BrandHero(brand: brand)
                    overview(todo: todo, flow: flowItems)
                    upcoming(todo)
                    HStack(alignment: .center) {
                        Text(L("Akış")).font(.system(size: 20, weight: .bold)).tracking(-0.3).accessibilityAddTraits(.isHeader)
                        Text(L("Ne yapıldı: iş kayıtları, biten görevler, notlar ve dosyalar.")).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: Design.Space.m)
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
                                       message: L("Terminalde çalışırken Claude'dan yaptıklarını oneriler/ klasörüne yazmasını isteyebilirsin; gelenler onay için burada görünür. Dosya eklemek için buraya sürükle ya da marka klasörüne koy."),
                                       symbol: "clock.arrow.circlepath")
                    } else {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(days) { day in
                                Text(Self.dayTitle(day.day)).font(.system(size: 12, weight: .semibold))
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
        .overlay { if dropTargeted { RoundedRectangle(cornerRadius: Design.radius).strokeBorder(Design.accent, lineWidth: 2) } }
        .liveOnly(FileDrop(targeted: $dropTargeted) { addFiles($0) })
        .onChange(of: brand.id) { selection = nil; composing = false }
    }

    /// Dört özet kutucuğu: açık görev, bu hafta biten, müşteriden beklenen karar, doğrulanmamış iş kaydı.
    private func overview(todo: [TodoItem], flow: [FlowItem]) -> some View {
        let calendar = StatusService.turkishCalendar
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let openTasks = todo.filter { if case .task = $0.kind { true } else { false } }.count
        let decisions = todo.filter { if case .record(.decision, _) = $0.kind { true } else { false } }.count
        let doneThisWeek = flow.filter { if case .taskDone = $0.kind { $0.date >= weekStart } else { false } }.count
        let drafts = flow.filter { if case .workLog(.draft) = $0.kind { true } else { false } }.count
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 12, alignment: .topLeading)], alignment: .leading, spacing: 12) {
            TodayTile(symbol: "checklist", title: L("Açık görev"), count: openTasks) { app.brandTab = .todo }
            TodayTile(symbol: "checkmark.circle", title: L("Bu hafta biten"), count: doneThisWeek) {}
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
                    Image(systemName: "calendar").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    Text(L("Sıradaki teslimler")).font(.system(size: 12, weight: .semibold))
                }
                .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    ForEach(Array(dated.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Rectangle().fill(Design.line).frame(height: 1) }
                        Button { app.brandTab = .todo; app.panelTarget = PanelTarget(item) } label: {
                            HStack(spacing: 12) {
                                StatusCircle(state: item.circleState, size: 15)
                                Text(item.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                Spacer()
                                Text(item.kindTitle).font(.system(size: 11)).foregroundStyle(.secondary)
                                if let d = item.dueDate { DueLabel(day: d) }
                            }
                            .padding(.vertical, 12).padding(.horizontal, 14).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).rowBackground(selected: false, radius: 0)
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
            Image(systemName: Self.symbol(item.kind)).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 32, height: 32).background(Circle().fill(tint.opacity(0.13)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(item.kind.title).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if case .workLog(.draft) = item.kind { Pill(text: WorkLogStatus.draft.title, tint: AnyShapeStyle(Design.accent)) }
            Text(item.date, format: .dateTime.hour().minute()).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
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

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.s) {
            InputField(title: L("Başlık"), text: $title)
                .onSubmit { if !title.trimmingCharacters(in: .whitespaces).isEmpty { add() } }
            TextField(L("Not"), text: $text, axis: .vertical)
                .lineLimit(3...10)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: Design.Space.m) {
                Spacer()
                Button(L("Ekle")) { add() }
                    .buttonStyle(.text)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.vertical, Design.Space.s)
        .overlay(alignment: .bottom) { Rectangle().fill(Design.line).frame(height: 1) }
    }

    private func add() {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let ok: Void? = app.perform(title: L("Not eklenemedi"), context: "kaynak.not") {
            _ = try app.store?.addTextSource(brandId: brand.id, kind: .note, title: t, body: body.isEmpty ? t : body)
        }
        if ok != nil { done() }
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


/// Marka künyesi (Özet'in üstü): marka renginde yumuşak zeminli geniş kart: büyük avatar, ad, sektör ve tanım.
struct BrandHero: View {
    @Environment(AppModel.self) private var app
    let brand: Brand

    var body: some View {
        let current = (try? app.store?.brand(brand.id)) ?? brand
        let tint = BrandTintStyle(key: brand.id)
        HStack(alignment: .center, spacing: 18) {
            BrandAvatar(name: current.name, tintKey: brand.id, selected: true, size: 64)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(current.name).font(.system(size: 28, weight: .bold)).tracking(-0.6).lineLimit(1).accessibilityAddTraits(.isHeader)
                    if !current.sector.isEmpty { Pill(text: current.sector, tint: AnyShapeStyle(tint)) }
                }
                Text(current.summary.isEmpty ? L("Marka tanımı henüz yok. Marka Bilgileri'nden ekleyebilirsin.") : current.summary)
                    .font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(2).lineSpacing(2)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(tint.opacity(0.10))
        )
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(tint.opacity(0.22)))
        .accessibilityElement(children: .combine)
    }
}
