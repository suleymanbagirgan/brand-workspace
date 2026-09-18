import MarkaCore
import SwiftUI

/// Yapılacaklar — *ne bekliyor* (plan §4, U9): tek liste (`Store.todo`): açık görevler, söz, karar bekleniyor, açık talep.
/// Hedef/teklif/sözleşme/önemli tarih burada değil, Bilgiler'de. Gecikenler üstte, sonra son tarihe göre, tarihsizler sonda.
/// Satır başındaki kutu tamamlar (Bitti); satır kısa süre üstü çizili kalıp listeden çıkar.
/// Üstte tek satır: solda görünür tür seçimi "Görev | Söz", yanında alan (Enter ekler; not Akış'ta eklenir). Satıra
/// tıklayınca sağda ayrıntı paneli (satır içi düzenleme; altta İptal et, Sil… — tek yer).
struct TodoView: View {
    @Environment(AppModel.self) private var app
    let brand: Brand
    @State private var selection: PanelTarget?
    @State private var quickTitle = ""
    @State private var quickKind = QuickKind.task
    /// Az önce tamamlanan satırlar: kısa süre üstü çizili görünür, sonra listeden çıkar.
    @State private var lingering: [String: TodoItem] = [:]

    enum QuickKind: CaseIterable {
        case task, promise
        var title: String {
            switch self {
            case .task: L("Görev")
            case .promise: L("Söz")
            }
        }
    }

    init(brand: Brand, selection: PanelTarget? = nil) {
        self.brand = brand
        _selection = State(initialValue: selection)
    }

    var body: some View {
        let _ = app.revision
        let open = (try? app.store?.todo(brandId: brand.id)) ?? []
        let openIds = Set(open.map(\.id))
        let done = lingering.values.filter { !openIds.contains($0.id) }
        let items = (open + done).sorted(by: TodoItem.order)
        let doneIds = Set(done.map(\.id))
        ListWithPanel(selection: $selection) {
            VStack(alignment: .leading, spacing: 0) {
                addLine.padding(.horizontal, Design.Space.l).padding(.top, Design.Space.s)
                if items.isEmpty {
                    EmptyStateView(title: L("Bekleyen bir şey yok"),
                                   message: L("Yukarıdan görev ya da söz ekleyebilirsin; terminaldeki araç da görev önerebilir. Bitenler Akış'ta görünür."))
                        .padding(.horizontal, Design.Space.l)
                    Spacer()
                } else {
                    PageScroll(backgroundTap: { selection = nil }) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(items) { item in
                                row(item, done: doneIds.contains(item.id))
                            }
                        }
                        .padding(.horizontal, Design.Space.l).padding(.vertical, Design.Space.s)
                    }
                }
            }
        }
        .onChange(of: brand.id) { selection = nil; lingering = [:] }
    }

    // MARK: Ekleme

    /// Solda iki seçenekli tür seçimi (görünür, menü değil), sağda alan.
    private var addLine: some View {
        HStack(spacing: Design.Space.s) {
            HStack(spacing: 0) {
                ForEach(QuickKind.allCases, id: \.self) { k in
                    let on = quickKind == k
                    Button(k.title) { quickKind = k }
                        .buttonStyle(.text)
                        .background(RoundedRectangle(cornerRadius: Design.radius).fill(on ? AnyShapeStyle(Design.selection) : AnyShapeStyle(.clear)))
                        .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L("Eklenecek tür"))
            InputField(title: quickKind == .task ? L("Yeni görev — ↩") : L("Yeni söz — ↩"), text: $quickTitle)
                .onSubmit(add)
        }
    }

    private func add() {
        let t = quickTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let store = app.store else { return }
        let ok: Void? = app.perform(title: L("Eklenemedi"), context: "yapilacak.ekle") {
            switch quickKind {
            case .task: _ = try store.saveTask(WorkTask(brandId: brand.id, title: t))
            case .promise: _ = try store.saveRecord(BrandRecord(brandId: brand.id, kind: .promise, title: t))
            }
        }
        if ok != nil { quickTitle = "" }
    }

    // MARK: Satır

    private func row(_ item: TodoItem, done: Bool) -> some View {
        let target = PanelTarget(item)
        let selected = selection == target
        return HStack(alignment: .center, spacing: Design.Space.m) {
            CheckBox(isOn: Binding(get: { done }, set: { _ in toggle(item, done: done) }), label: item.title,
                     onValue: L("Bitti"), offValue: L("Açık"))
                .opacity(item.canComplete ? 1 : 0)
                .disabled(!item.canComplete)
            Text(item.title).lineLimit(1)
                .strikethrough(done)
                .foregroundStyle(done ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(item.kindTitle).captionStyle().lineLimit(1).frame(width: 150, alignment: .leading)
            // Boş sütun boş kalır ("—" yok).
            Text(item.assignee).captionStyle().lineLimit(1).frame(width: 80, alignment: .trailing)
            Group {
                if let d = item.dueDate { DueLabel(day: d) } else { Color.clear.frame(height: 1) }
            }
            .frame(width: 56, alignment: .trailing)
        }
        .padding(.vertical, Design.Space.s).padding(.horizontal, Design.Space.s)
        .background(RoundedRectangle(cornerRadius: Design.radius).fill(selected ? AnyShapeStyle(Design.selection) : AnyShapeStyle(.clear)))
        .overlay(alignment: .bottom) { Rectangle().fill(Design.line).frame(height: 1).padding(.horizontal, Design.Space.s).opacity(selected ? 0 : 1) }
        .padding(.horizontal, -Design.Space.s)
        .contentShape(Rectangle())
        .onTapGesture { selection = selected ? nil : target }
        // İptal et ve Sil… tek yerde: panelin altında (U9; sağ tık menüsü ikinci yoldu, kalktı).
        // VoiceOver: tek öğe; varsayılan eylem paneli açar, tamamlama adlı eylem.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.kindTitle + " · " + item.title)
        .accessibilityValue([done ? L("Bitti") : "", item.dueDate.map { LF("Son tarih %@", $0) } ?? ""].filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { selection = selected ? nil : target }
        .modifier(RowAction(name: done ? L("Yeniden aç") : L("Tamamla"), enabled: item.canComplete, perform: { toggle(item, done: done) }))
    }

    /// Kutu: açık satırı tamamlar; az önce tamamlananı geri açar.
    private func toggle(_ item: TodoItem, done: Bool) {
        guard let store = app.store else { return }
        if done {
            // Geri aç: önceki durumuna.
            let ok: Void? = app.perform(context: "yapilacak.geri-ac") {
                switch item.kind {
                case .task(let s): try store.setTaskStatus(item.entityId, s)
                case .record(_, let s): try setRecordStatus(item.entityId, s)
                }
            }
            if ok != nil { lingering[item.id] = nil }
            return
        }
        let ok: Void? = app.perform(title: L("Tamamlanamadı"), context: "yapilacak.tamamla") {
            switch item.kind {
            case .task: try store.setTaskStatus(item.entityId, .done)
            case .record: try setRecordStatus(item.entityId, .done)
            }
        }
        guard ok != nil else { return }
        lingering[item.id] = item
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            lingering[item.id] = nil
        }
    }

    private func setRecordStatus(_ id: String, _ status: RecordStatus) throws {
        guard let store = app.store, var r = try store.read({ db in try BrandRecord.fetchOne(db, key: id) }) else { return }
        r.status = status
        try store.saveRecord(r)
    }

}

extension TodoItem {
    /// Sağ sütundaki tür: "Görev", "Görev · Sürüyor", "Söz", "Karar bekleniyor", "Talep"…
    var kindTitle: String {
        switch kind {
        case .task(.todo): L("Görev")
        case .task(let s): L("Görev") + " · " + s.title
        case .record(let k, let s):
            k.statuses.first == s || s == .open ? k.title : k.title + " · " + s.title
        }
    }

    /// Kutuyla kapatılabilir mi? (Yapılacaklar'da yalnız görev ve söz/karar/talep var; hepsi Bitti ile kapanır.)
    var canComplete: Bool {
        if case .record(.proposal, _) = kind { return false }
        return true
    }
}
