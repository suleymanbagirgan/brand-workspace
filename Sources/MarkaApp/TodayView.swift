import MarkaCore
import SwiftUI

/// Bugün (plan §4): tüm etkin markalarda onay bekleyen, geciken, bu hafta yapılan ve müşteriden beklenen. Tek arama (⌘F)
/// burada; sonuçlar bölümlerin yerine aynı ekranda. Sayılar kayıtlardan sayılır (`Store.today`), AI tahmini yoktur.
/// Marka adına tıklayınca o marka açılır.
struct TodayView: View {
    @Environment(AppModel.self) private var app
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        let _ = app.revision
        Group {
            if app.brands.isEmpty {
                EmptyStateView(title: L("Henüz marka yok"),
                               message: L("İlk markanı ekle. Bugün ekranı markalarındaki işlerden oluşur."),
                               actionTitle: L("Marka ekle")) { app.showNewBrand = true }
                    .padding(Design.Space.l)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if let store = app.store {
                PageScroll {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                            TodaySearchResults(query: query)
                        } else {
                            switch Result(catching: { try store.today() }) {
                            case .failure(let error):
                                ReadErrorView(error: error, context: "okuma.bugun") { app.reloadViews() }
                            case .success(let t):
                                sections(t)
                            }
                        }
                    }
                    .padding(Design.Space.l)
                    .frame(maxWidth: 980, alignment: .leading)
                }
            }
        }
        .navigationTitle(L("Bugün"))
        .onChange(of: app.focusSearch) { _, requested in if requested { takeSearchFocus() } }
        .task { if app.focusSearch { try? await Task.sleep(for: .milliseconds(150)); takeSearchFocus() } }
    }

    private func takeSearchFocus() {
        searchFocused = true
        app.focusSearch = false
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Design.Space.xs) {
                Text(L("Bugün")).font(Design.Font.title).accessibilityAddTraits(.isHeader)
                Text(Date(), format: .dateTime.day().month(.wide).weekday(.wide)).captionStyle()
            }
            Spacer()
            InputField(title: L("Ara (⌘F)"), text: $query, focus: $searchFocused)
                .frame(width: 260)
                .accessibilityLabel(L("Tüm markalarda ara"))
        }
    }

    @ViewBuilder private func sections(_ t: TodaySummary) -> some View {
        TodaySectionTitle(text: L("Onay bekliyor"))
        // Sayı kenar çubuğu ve onay bandıyla aynı: bekleyen öneriler + klasördeki eklenmemiş dosyalar (taranmışsa).
        let pendingBrands = app.brands.map(\.id).filter { app.approvalCount($0) > 0 }
        if pendingBrands.isEmpty { EmptyStateView(message: L("Onay bekleyen bir şey yok.")) }
        ForEach(pendingBrands, id: \.self) { brandId in
            TodayRow(brandId: brandId, text: LF("%d onay bekliyor", app.approvalCount(brandId))) {
                app.select(brand: brandId)
                app.brandSheet = .approvals(brandId)
            } trailing: {
                Text(L("İncele"))
            }
        }

        TodaySectionTitle(text: L("Geciken"))
        if t.overdue.isEmpty { EmptyStateView(message: L("Geciken iş yok.")) }
        ForEach(t.overdue.prefix(12)) { line in
            TodayRow(brandId: line.brandId ?? "", text: line.text) {
                app.open(line.ref)
            } trailing: {
                if let due = line.dueDate { DueLabel(day: due) }
            }
        }
        if t.overdue.count > 12 { Text(LF("+%d daha", t.overdue.count - 12)).captionStyle().padding(.vertical, Design.Space.s) }

        TodaySectionTitle(text: L("Bu hafta yapılan"))
        if t.week.isEmpty { EmptyStateView(message: L("Bu hafta yapılan iş yok.")) }
        ForEach(t.week) { w in
            TodayRow(brandId: w.brandId, text: weekText(w)) {
                app.select(brand: w.brandId, tab: .flow)
            } trailing: {
                if w.unverified > 0 { Text(LF("%d doğrulanmadı", w.unverified)).captionStyle() }
            }
        }

        TodaySectionTitle(text: L("Karar bekleniyor"))
        if t.awaiting.isEmpty { EmptyStateView(message: L("Müşteriden karar beklenen bir şey yok.")) }
        ForEach(t.awaiting) { a in
            TodayRow(brandId: a.brandId, text: a.titles.joined(separator: " · ")) {
                app.select(brand: a.brandId, tab: .todo)
            } trailing: {
                EmptyView()
            }
        }
    }

    private func weekText(_ w: TodaySummary.Week) -> String {
        var parts: [String] = []
        if w.tasksDone > 0 { parts.append(LF("%d görev bitti", w.tasksDone)) }
        if w.workLogs > 0 { parts.append(LF("%d iş kaydı", w.workLogs)) }
        if w.files > 0 { parts.append(LF("%d dosya", w.files)) }
        if w.notes > 0 { parts.append(LF("%d not", w.notes)) }
        return parts.joined(separator: " · ")
    }
}

/// Bölüm başlığı (bölüm stili) — Bugün ve arama sonuçlarında aynı.
struct TodaySectionTitle: View {
    let text: String
    var body: some View {
        Text(text).font(Design.Font.section)
            .padding(.top, Design.Space.l).padding(.bottom, Design.Space.xs)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Tek satır, tek eylem: solda marka (ek stil), ortada metin, sağda ek bilgi. Tıklayınca kaydın yerine (markası, bölümü,
/// ayrıntı paneli) gidilir. Markayı açmak için kenar çubuğu.
struct TodayRow<Trailing: View>: View {
    @Environment(AppModel.self) private var app
    let brandId: String
    var kind: String? = nil
    let text: String
    var action: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        let brandName = app.brands.first { $0.id == brandId }?.name ?? ""
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: Design.Space.m) {
                Text(brandName).captionStyle().lineLimit(1).frame(width: 140, alignment: .leading)
                if let kind { Text(kind).captionStyle().lineLimit(1).frame(width: 100, alignment: .leading) }
                Text(text).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
            .padding(.vertical, Design.Space.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(Design.line).frame(height: 1) }
        .accessibilityLabel([brandName, kind ?? "", text].filter { !$0.isEmpty }.joined(separator: " · "))
    }
}

/// Arama sonuçları, bölümlerin yerine: marka · tür · başlık. Satır dayandığı kayda açılır.
struct TodaySearchResults: View {
    @Environment(AppModel.self) private var app
    let query: String

    var body: some View {
        let hits = (try? app.store?.searchToday(query)) ?? []
        VStack(alignment: .leading, spacing: 0) {
            TodaySectionTitle(text: LF("Arama sonuçları · %d", hits.count))
            if hits.isEmpty { EmptyStateView(message: L("Sonuç yok.")) }
            ForEach(hits) { hit in
                TodayRow(brandId: hit.brandId, kind: hit.recordKind?.title ?? hit.ref.kind.shortTitle, text: hit.title) {
                    app.open(hit.ref)
                } trailing: {
                    EmptyView()
                }
            }
        }
    }
}
