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
        ListWithPanel(selection: $selection) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: Design.Space.m) {
                    Spacer()
                    Button(composing ? L("Vazgeç") : L("Not ekle")) { composing.toggle() }
                        .buttonStyle(.text)
                        .keyboardShortcut(composing ? KeyboardShortcut.cancelAction : nil)
                }
                .padding(.horizontal, Design.Space.l).padding(.top, Design.Space.s)
                if composing {
                    NoteComposer(brand: brand) { composing = false }
                        .padding(.horizontal, Design.Space.l).padding(.top, Design.Space.s)
                }
                if days.isEmpty {
                    EmptyStateView(title: L("Henüz bir şey yok"),
                                   message: L("Terminalde çalışırken Claude'dan yaptıklarını oneriler/ klasörüne yazmasını isteyebilirsin; gelenler onay için burada görünür. Dosya eklemek için buraya sürükle ya da marka klasörüne koy."))
                        .padding(.horizontal, Design.Space.l)
                    Spacer()
                } else {
                    PageScroll(backgroundTap: { selection = nil }) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(days) { day in
                                Text(Self.dayTitle(day.day)).captionStyle()
                                    .padding(.top, Design.Space.m).padding(.bottom, Design.Space.xs)
                                    .accessibilityAddTraits(.isHeader)
                                ForEach(day.items) { FlowRow(item: $0, selection: $selection) }
                            }
                        }
                        .padding(.horizontal, Design.Space.l).padding(.bottom, Design.Space.l)
                    }
                }
            }
        }
        .overlay { if dropTargeted { RoundedRectangle(cornerRadius: Design.radius).strokeBorder(Design.accent, lineWidth: 2) } }
        .liveOnly(FileDrop(targeted: $dropTargeted) { addFiles($0) })
        .onChange(of: brand.id) { selection = nil; composing = false }
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
        HStack(alignment: .firstTextBaseline, spacing: Design.Space.m) {
            Text(item.kind.title).captionStyle().lineLimit(1).frame(width: Self.kindWidth, alignment: .leading)
            Text(item.title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            if case .workLog(.draft) = item.kind {
                Text(WorkLogStatus.draft.title).captionStyle()
            }
            Text(item.date, format: .dateTime.hour().minute()).captionStyle().monospacedDigit()
                .frame(width: Self.timeWidth, alignment: .trailing)
        }
        .padding(.vertical, Design.Space.s).padding(.horizontal, Design.Space.s)
        .background(RoundedRectangle(cornerRadius: Design.radius).fill(selected ? AnyShapeStyle(Design.selection) : AnyShapeStyle(.clear)))
        .overlay(alignment: .bottom) { Rectangle().fill(Design.line).frame(height: 1).padding(.horizontal, Design.Space.s).opacity(selected ? 0 : 1) }
        .padding(.horizontal, -Design.Space.s)
        .contentShape(Rectangle())
        .onTapGesture { selection = selected ? nil : target }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.kind.title + " · " + item.title)
        .accessibilityValue(item.date.formatted(.dateTime.hour().minute()))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { selection = selected ? nil : target }
        .modifier(RowAction(name: L("Geri al"), enabled: undoable, perform: undoProposal))
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
