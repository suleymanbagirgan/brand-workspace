import MarkaCore
import SwiftUI

/// Komut paleti (⌘K): marka değiştir, bölüme git, görev ekle, terminali göster/gizle. Odak hep arama alanında; ↑↓ seçer,
/// ↩ çalıştırır, Esc kapatır. Yalnız gezinme ve arayüz eylemleri vardır; veri değiştiren ya da geri alınamaz eylem yoktur.
struct CommandPalette: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
    @State private var query = ""
    @State private var index = 0
    @FocusState private var focused: Bool

    struct Entry: Identifiable {
        let id: String
        let title: String
        let detail: String
        let symbol: String
        let run: @MainActor () -> Void
    }

    private var entries: [Entry] {
        var list: [Entry] = []
        let brand = app.selectedBrand
        if let brand {
            for tab in BrandTab.allCases {
                list.append(Entry(id: "tab:" + tab.rawValue, title: tab.title, detail: LF("%@ · bölüm", brand.name), symbol: "rectangle.split.3x1") {
                    app.select(brand: brand.id, tab: tab)
                })
            }
            // H2-02 (U-11): sağlayıcı yokken giriş "Yapay zekâyı bağla…" olur ve Ayarlar'ı açar; istem bekletilmez.
            list.append(Entry(id: "ask-ai", title: app.aiReady(for: brand) ? L("Yapay zekâya sor: Ne yapmalıyım?") : L("Yapay zekâyı bağla…"), detail: brand.name, symbol: "sparkles") {
                app.select(brand: brand.id)
                app.askOrConnect(ChatPrompts.whatToDo, brand: brand, openSettings: openSettings)
            })
            list.append(Entry(id: "add-task", title: L("Görev ekle"), detail: brand.name, symbol: "plus.circle") {
                app.select(brand: brand.id, tab: .todo)
                app.addTaskRequested = true
            })
            list.append(Entry(id: "terminal", title: app.showAssistant ? L("Asistanı gizle") : L("Asistanı göster"), detail: L("⌘J"), symbol: "sparkles") {
                app.showAssistant.toggle()
            })
        }
        list.append(Entry(id: "today", title: L("Bugün"), detail: L("Tüm markalar"), symbol: "sun.max") { app.selection = .today })
        for b in app.brands {
            list.append(Entry(id: "brand:" + b.id, title: b.name, detail: L("Markaya git"), symbol: "square.stack") { app.select(brand: b.id) })
        }
        list.append(Entry(id: "new-brand", title: L("Yeni marka…"), detail: L("⇧⌘N"), symbol: "plus") { app.showNewBrand = true })
        return list
    }

    private var results: [Entry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return entries }
        return entries.filter { $0.title.localizedStandardContains(q) || $0.detail.localizedStandardContains(q) }
    }

    var body: some View {
        let shown = results
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("Marka, bölüm ya da komut ara…"), text: $query)
                    .textFieldStyle(.plain).font(Design.Font.heading).focused($focused)
                    .onSubmit { run(shown) }
                    .onChange(of: query) { index = 0 }
            }
            .padding(.horizontal, 16).frame(height: 48)
            Divider()
            if shown.isEmpty {
                Text(L("Eşleşen bir şey yok.")).font(Design.Font.callout).foregroundStyle(.secondary).padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        // a11y-tarama: yok-say — .isButton/.isSelected trait'i row(_:selected:) yardımcısında verilir; klavye ↑↓ + ↩
                        ForEach(Array(shown.enumerated()), id: \.element.id) { i, entry in row(entry, selected: i == min(index, shown.count - 1)).onTapGesture { index = i; run(shown) } }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 360)
            }
        }
        .frame(width: 520)
        .onAppear { focused = true }
        .onKeyPress(.downArrow) { index = min(index + 1, max(shown.count - 1, 0)); return .handled }
        .onKeyPress(.upArrow) { index = max(index - 1, 0); return .handled }
        .onExitCommand { dismiss() }
    }

    private func row(_ entry: Entry, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.symbol).font(Design.Icon.medium).foregroundStyle(.secondary).frame(width: 20)
            Text(entry.title).font(Design.Font.body.weight(.medium)).lineLimit(1)
            Spacer()
            Text(entry.detail).font(Design.Font.small).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 10).frame(height: 36)
        .background(RoundedRectangle(cornerRadius: Design.Radius.small, style: .continuous).fill(selected ? AnyShapeStyle(Design.rowSelected) : AnyShapeStyle(Color.clear)))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func run(_ shown: [Entry]) {
        guard !shown.isEmpty else { return }
        let entry = shown[min(index, shown.count - 1)]
        dismiss()
        entry.run()
    }
}
