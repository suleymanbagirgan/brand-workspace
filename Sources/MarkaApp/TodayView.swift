import AppKit
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
                    .pagePadding().padding(.vertical, Design.Space.l)
                    .frame(maxWidth: 980, alignment: .leading)
                }
            }
        }
        .navigationTitle(app.preferences.scope.kind == .trial ? L("Bugün · Demo") : L("Bugün"))
        // Açılışta ilk metin alanı odak halkası almasın (⌘F ile odaklanır).
        .onAppear { DispatchQueue.main.async { if !app.focusSearch { OpeningFocus.settle() } } }
        .onChange(of: app.focusSearch) { _, requested in if requested { takeSearchFocus() } }
        .task { if app.focusSearch { try? await Task.sleep(for: .milliseconds(150)); takeSearchFocus() } }
    }

    private func takeSearchFocus() {
        searchFocused = true
        app.focusSearch = false
    }

    /// Saate göre selamlama (Apple'ın ana ekran kalıbı: kişisel, kısa).
    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: L("Günaydın")
        case 12..<18: L("İyi günler")
        case 18..<23: L("İyi akşamlar")
        default: L("İyi geceler")
        }
    }

    /// Başlık + arama: geniş pencerede arama başlığın ilk satırıyla aynı tabanda sağda; dar pencerede (ör. asistan paneli
    /// açıkken) başlığın altına iner ve tam genişlik alır.
    private var header: some View {
        let subtitle = Date().formatted(.dateTime.day().month(.wide).weekday(.wide))
        return ViewThatFits(in: .horizontal) {
            SectionHeading(title: greeting, subtitle: subtitle, actionsAlignment: .firstTextBaseline) {
                TodaySearchField(text: $query, focus: $searchFocused).frame(width: 260)
            }
            VStack(alignment: .leading, spacing: Design.Space.m) {
                SectionHeading(title: greeting, subtitle: subtitle)
                TodaySearchField(text: $query, focus: $searchFocused)
            }
        }
        .padding(.bottom, Design.Space.l)
    }

    @ViewBuilder private func sections(_ t: TodaySummary) -> some View {
        // Onay bekleyenler en üstte (tek vurgu): sayı kenar çubuğu ve onay bandıyla aynı — bekleyen öneriler + klasördeki
        // eklenmemiş dosyalar (taranmışsa). Her satır o markanın incelemesine geçer.
        let pendingBrands = app.brands.map(\.id).filter { app.approvalCount($0) > 0 }
        let pendingTotal = pendingBrands.reduce(0) { $0 + app.approvalCount($1) }
        Text(LF("Onay bekliyor · %d", pendingTotal)).font(Design.Font.body.weight(.bold))
            .padding(.bottom, Design.Space.xs)
            .accessibilityAddTraits(.isHeader)
        if pendingBrands.isEmpty { Text(L("Onay bekleyen bir şey yok.")).captionStyle().padding(.vertical, Design.Space.s) }
        if !pendingBrands.isEmpty {
            VStack(spacing: 0) {
                ForEach(pendingBrands, id: \.self) { brandId in
                    TodayRow(brandId: brandId, text: LF("%d onay bekliyor", app.approvalCount(brandId))) {
                        app.select(brand: brandId)
                        app.brandSheet = .approvals(brandId)
                    } trailing: {
                        Text(L("İncele")).foregroundStyle(Design.accent).fontWeight(.medium)
                    }
                    .accessibilityHint(L("İncelemeyi açar"))
                }
            }
            .flatList()
        }
        tiles(t).padding(.top, Design.Space.l)

        TodaySectionTitle(text: L("Geciken"))
        if t.overdue.isEmpty { Text(L("Geciken iş yok.")).captionStyle().padding(.vertical, Design.Space.s) }
        if !t.overdue.isEmpty {
            VStack(spacing: 0) {
                ForEach(t.overdue.prefix(12)) { line in
            TodayRow(brandId: line.brandId ?? "", text: line.text) {
                app.open(line.ref)
            } trailing: {
                if let due = line.dueDate { DueLabel(day: due) }
            }
        }
            }
            .flatList()
        }
        if t.overdue.count > 12 { Text(LF("+%d daha", t.overdue.count - 12)).captionStyle().padding(.vertical, Design.Space.s) }

        TodaySectionTitle(text: L("Bu hafta yapılan"))
        if t.week.isEmpty { Text(L("Bu hafta yapılan iş yok.")).captionStyle().padding(.vertical, Design.Space.s) }
        if !t.week.isEmpty {
            VStack(spacing: 0) {
                ForEach(t.week) { w in
            TodayRow(brandId: w.brandId, text: weekText(w)) {
                app.select(brand: w.brandId, tab: .flow)
            } trailing: {
                if w.unverified > 0 { Text(LF("%d doğrulanmadı", w.unverified)).captionStyle() }
            }
        }
            }
            .flatList()
        }

        TodaySectionTitle(text: L("Karar bekleniyor"))
        if t.awaiting.isEmpty { Text(L("Müşteriden karar beklenen bir şey yok.")).captionStyle().padding(.vertical, Design.Space.s) }
        if !t.awaiting.isEmpty {
            VStack(spacing: 0) {
                ForEach(t.awaiting) { a in
            TodayRow(brandId: a.brandId, text: a.titles.joined(separator: " · ")) {
                app.select(brand: a.brandId, tab: .todo)
            } trailing: {
                EmptyView()
            }
        }
            }
            .flatList()
        }
    }

    /// Üç özet kutucuğu (Hatırlatıcılar'ın ana ekranı gibi): büyük sayı, simge, dokununca ilgili yere git. Onay bekleyenler
    /// kutucuk değil, üstteki listedir.
    private func tiles(_ t: TodaySummary) -> some View {
        // Sayı ile etiket aynı şeyi söyler: yalnız biten görevler (iş kaydı/dosya/not aşağıdaki satır içi dökümde).
        let doneTotal = CountDefinitions.weekDoneTaskTotal(t.week)
        let awaitingTotal = t.awaiting.reduce(0) { $0 + $1.titles.count }
        return TileGrid(columns: 3) {
            TodayTile(symbol: "exclamationmark.circle", title: L("Geciken"), count: t.overdue.count, danger: !t.overdue.isEmpty) {
                if let first = t.overdue.first { app.open(first.ref) }
            }
            TodayTile(symbol: "clock.arrow.circlepath", title: L("Bu hafta biten görev"), count: doneTotal) {
                if let w = t.week.first(where: { $0.tasksDone > 0 }) ?? t.week.first { app.select(brand: w.brandId, tab: .flow) }
            }
            TodayTile(symbol: "hourglass", title: L("Karar bekleniyor"), count: awaitingTotal) {
                if let a = t.awaiting.first { app.select(brand: a.brandId, tab: .todo) }
            }
        }
        .padding(.bottom, Design.Space.s)
    }

    private func weekText(_ w: TodaySummary.Week) -> String {
        // H3-10: her parça kendi birimiyle; birimler toplanmaz (`CountDefinitions.weekParts`).
        CountDefinitions.weekParts(w).map { part in
            switch part.unit {
            case .task: LF("%d görev bitti", part.count)
            case .workLog: LF("%d iş kaydı", part.count)
            case .file: LF("%d dosya", part.count)
            case .note: LF("%d not", part.count)
            }
        }.joined(separator: " · ")
    }
}

/// Bugün'ün arama kutusu: solda büyüteç, yer tutucu, sağda "⌘F" kısayol ipucu. Ekran çiziminde düz metin.
struct TodaySearchField: View {
    @Environment(\.isSnapshot) private var isSnapshot
    @Binding var text: String
    var focus: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: Design.Space.xs) {
            Image(systemName: "magnifyingglass").font(Design.Icon.small).foregroundStyle(.secondary).accessibilityHidden(true)
            field.frame(maxWidth: .infinity, alignment: .leading)
            if text.isEmpty {
                Text("⌘F").font(Design.Font.small).foregroundStyle(.tertiary).accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Design.Space.s).padding(.vertical, Design.Space.xs)
        .background(RoundedRectangle(cornerRadius: Design.Radius.small).fill(Design.bandBackground))
        .overlay(RoundedRectangle(cornerRadius: Design.Radius.small).strokeBorder(Design.line))
    }

    @ViewBuilder private var field: some View {
        if isSnapshot {
            Text(text.isEmpty ? L("Kayıtlarda ara") : text).foregroundStyle(text.isEmpty ? .secondary : .primary).lineLimit(1)
        } else {
            TextField(L("Kayıtlarda ara"), text: $text).textFieldStyle(.plain).focused(focus)
                .accessibilityLabel(L("Tüm markalarda ara"))
                .accessibilityHint("⌘F")
        }
    }
}

/// Bölüm başlığı (bölüm stili) — Bugün ve arama sonuçlarında aynı.
struct TodaySectionTitle: View {
    let text: String
    var body: some View {
        Text(text).font(Design.Font.body.weight(.bold))
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
                HStack(spacing: 8) {
                    BrandAvatar(name: brandName, tintKey: brandId, size: 20).accessibilityHidden(true)
                    Text(brandName).font(Design.Font.callout.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(width: 160, alignment: .leading)
                if let kind { Text(kind).captionStyle().lineLimit(1).frame(width: 100, alignment: .leading) }
                Text(text).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
            .padding(.vertical, 12).padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .rowBackground(selected: false, radius: 0)
        .overlay(alignment: .bottom) { Rectangle().fill(Design.line).frame(height: 1) }
        .accessibilityLabel([brandName, kind ?? "", text].filter { !$0.isEmpty }.joined(separator: " · "))
    }
}

/// Arama sonuçları, bölümlerin yerine: marka · tür · başlık. Satır dayandığı kayda açılır.
struct TodaySearchResults: View {
    @Environment(AppModel.self) private var app
    let query: String

    var body: some View {
        let hits = app.read(or: []) { try $0.searchToday(query) }
        VStack(alignment: .leading, spacing: 0) {
            TodaySectionTitle(text: LF("Arama sonuçları · %d", hits.count))
            if hits.isEmpty { Text(L("Sonuç yok.")).captionStyle().padding(.vertical, Design.Space.s) }
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


/// Özet kutucuğu: simge rozeti, büyük sayı, ad. Sıfırken sönük; geciken kırmızı, onay bekleyen vurgulu.
struct TodayTile: View {
    let symbol: String
    let title: String
    let count: Int
    var emphasize = false
    var danger = false
    /// Dar kutucuk dizisinde (Şirket özeti) etiket iki satıra sarar ve iki satırlık yer ayırır: kesilmez, kutular eş boyda kalır.
    var titleLines = 1
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let tint: AnyShapeStyle = danger ? AnyShapeStyle(Design.danger) : (emphasize ? AnyShapeStyle(Design.accent) : AnyShapeStyle(.secondary))
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: symbol).font(Design.Icon.medium.weight(.semibold)).foregroundStyle(tint)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Design.windowBackground))
                        .overlay(Circle().strokeBorder(Design.line))
                    Spacer()
                    // Sayı hiçbir genişlikte satıra bölünmez (dar kutuda "1"/"3" diye kırılıyordu); gerekirse küçülür.
                    Text(verbatim: "\(count)").font(Design.Font.display.weight(.semibold)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.6).layoutPriority(1)
                        .foregroundStyle(count == 0 ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                        .contentTransition(.numericText())
                }
                Text(title).font(Design.Font.callout.weight(.medium)).foregroundStyle(.secondary)
                    .lineLimit(titleLines, reservesSpace: titleLines > 1).fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Design.Radius.large, style: .continuous).fill(hovering ? AnyShapeStyle(Design.rowSelected) : AnyShapeStyle(Design.panel)))
            .overlay(RoundedRectangle(cornerRadius: Design.Radius.large, style: .continuous).strokeBorder(Design.line))
            .contentShape(RoundedRectangle(cornerRadius: Design.Radius.large, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LF("%1$@: %2$d", title, count))
        .accessibilityAddTraits(.isButton)
    }
}
