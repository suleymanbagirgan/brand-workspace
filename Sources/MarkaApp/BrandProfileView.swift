import AppKit
import MarkaCore
import SwiftUI

/// Marka Bilgileri (0.4.0): markanın ortak bağlamı. Asistan bu metinleri her konuşmada bağlam olarak okur. Boş bölüm bağlama girmez ve
/// kendiliğinden doldurulmaz; yapay zekâ bölüm yazamaz (öneri türü yoktur), yalnız sohbette taslak çıkarabilir, kaydı kullanıcı yapar.
/// Sayfa: bağlam durumu (halka, eksik çipleri, künye), süzgeç, okunaklı bölüm kartları. Altta ayrıntılar yerinde düzenlenir.
struct BrandProfileView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let brand: Brand
    @State private var editing: Target?
    @State private var draft = ""
    @State private var draftBase = ""
    @State private var pendingId = UUID()
    @State private var sectorPendingId = UUID()
    @State private var showContext: Bool
    @State private var selection: PanelTarget?
    @State private var filter: Filter
    @State private var hovered: String?
    @State private var saved: Target?
    @State private var editingSector = false
    @State private var sectorDraft = ""
    @FocusState private var editorFocused: Bool
    // Geliştirme: `MARKA_PARCA=goals|people|access` alt sekmeyi seçer (gerçek pencere doğrulaması için).
    @State private var part: Part = DevHook.value("MARKA_PARCA").flatMap { ["goals": Part.goals, "people": .people, "access": .access][$0] } ?? .profile

    init(brand: Brand, showContext: Bool = false, filter: Filter = .all) {
        self.brand = brand
        _showContext = State(initialValue: showContext)
        _filter = State(initialValue: filter)
    }

    /// Alt sekmeler: sayfa tek uzun sayfa olmasın diye konuya göre bölünür.
    enum Part: CaseIterable { case profile, goals, people, access
        var title: String { switch self { case .profile: L("Profil"); case .goals: L("Hedefler"); case .people: L("Kişiler ve projeler"); case .access: L("Ayrıntılar ve izinler") } }
    }

    enum Filter: CaseIterable { case all, filled, missing }

    enum Target: Hashable {
        case summary, section(ProfileSection)
        var key: String { switch self { case .summary: "ozet"; case .section(let s): s.rawValue } }
    }

    /// Bir bölüm kartının gösterdiği her şey (görünüm durumu değil, okunan veri).
    struct Card: Identifiable {
        let target: Target
        let title: String
        let symbol: String
        let prompt: String
        let text: String
        let updated: Date?
        var id: String { target.key }
        var isFilled: Bool { !text.isEmpty }
        var words: Int { text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count }
        /// Yaklaşık token (Türkçe için karakter/3,5). Ölçüm değil, tahmin; arayüzde "~" ile gösterilir.
        var tokens: Int { text.isEmpty ? 0 : max(1, Int((Double(text.count) / 3.5).rounded())) }
    }

    var body: some View {
        let _ = app.revision
        let current = app.read(or: brand) { try $0.brand(brand.id) }
        let cards = makeCards(current)
        let goalCount = (app.read(or: []) { try $0.records(brandId: brand.id, kinds: [.goal]) }).count
        let peopleCount = (app.read(or: []) { try $0.contacts(brandId: brand.id) }).count + (app.read(or: []) { try $0.projects(brandId: brand.id) }).count
        ListWithPanel(selection: $selection) {
            PageScroll(backgroundTap: { selection = nil }) {
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: Design.Space.l) {
                        SectionHeading(title: L("Marka Bilgileri"), subtitle: L("İş planının ve yapay zekânın ortak bağlamı."), symbol: "text.book.closed", tintKey: brand.id)
                        SegmentedChoice(options: partOptions(goals: goalCount, people: peopleCount), selection: $part)
                        switch part {
                        case .profile: profileTab(cards, current, proxy)
                        case .goals:
                            GoalsSection(brand: brand, selection: $selection)
                            decisions
                        case .people: BrandInfoView(brand: brand, embedded: true, show: .people)
                        case .access: BrandInfoView(brand: brand, embedded: true, show: .access)
                        }
                    }
                    .pagePadding().padding(.vertical, Design.Space.l)
                }
            }
        }
        .onChange(of: brand.id) { flushPendingEdits(); editing = nil; showContext = false; selection = nil; part = .profile; filter = .all; editingSector = false }
    }

    private func partOptions(goals: Int, people: Int) -> [(Part, String)] {
        Part.allCases.map { p in
            switch p {
            case .goals where goals > 0: (p, p.title + " " + String(goals))
            case .people where people > 0: (p, p.title + " " + String(people))
            default: (p, p.title)
            }
        }
    }

    private func makeCards(_ current: Brand) -> [Card] {
        let profile = app.read(or: [:]) { try $0.profile(brandId: brand.id) }
        let dates = app.read(or: [:]) { try $0.profileUpdatedAt(brandId: brand.id) }
        var out = [Card(target: .summary, title: L("Markayı tanı"), symbol: "text.book.closed",
                        prompt: L("Marka ne yapıyor, ne satıyor, kimin için? İki üç cümle."), text: current.summary, updated: nil)]
        for s in ProfileSection.allCases {
            out.append(Card(target: .section(s), title: s.title, symbol: s.symbol, prompt: s.prompt, text: profile[s] ?? "", updated: dates[s]))
        }
        return out
    }

    // MARK: Profil sekmesi

    @ViewBuilder private func profileTab(_ cards: [Card], _ current: Brand, _ proxy: ScrollViewProxy) -> some View {
        let missing = cards.filter { !$0.isFilled }
        statusCard(cards, missing: missing, current, proxy)
        if showContext { contextPreview }
        filterRow(cards)
        let shown = cards.filter { filter == .all || (filter == .filled) == $0.isFilled }
        if shown.isEmpty {
            Text(filter == .missing ? L("Eksik bölüm yok. Yapay zekâ bu markayı tanıyor.") : L("Henüz yazılmış bölüm yok."))
                .font(Design.Font.body).foregroundStyle(.secondary).padding(.vertical, Design.Space.l)
        }
        if let summary = shown.first(where: { $0.target == .summary }) { cardView(summary, proxy) }
        let rest = shown.filter { $0.target != .summary }
        // Aynı satırdaki kartlar eşit yükseklikte (Grid satır yüksekliğini eşitler).
        Grid(horizontalSpacing: 16, verticalSpacing: 16) {
            ForEach(Array(stride(from: 0, to: rest.count, by: 2)), id: \.self) { i in
                GridRow {
                    cardView(rest[i], proxy).frame(maxHeight: .infinity, alignment: .topLeading)
                    if i + 1 < rest.count { cardView(rest[i + 1], proxy).frame(maxHeight: .infinity, alignment: .topLeading) } else { Color.clear.frame(height: 0) }
                }
            }
        }
    }

    /// Bağlam durumu: halka, durum cümlesi, eksik çipleri, eylemler ve künye (tek kart).
    private func statusCard(_ cards: [Card], missing: [Card], _ current: Brand, _ proxy: ScrollViewProxy) -> some View {
        let total = cards.count
        let filled = total - missing.count
        let complete = missing.isEmpty
        let tint = BrandTintStyle(key: brand.id)
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 22) {
                ZStack {
                    Circle().stroke(Design.line, lineWidth: 8)
                    Circle().trim(from: 0, to: CGFloat(filled) / CGFloat(max(total, 1)))
                        .stroke(complete ? AnyShapeStyle(Color.green) : AnyShapeStyle(tint), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(verbatim: "\(filled)/\(total)").font(Design.Font.title.weight(.semibold)).monospacedDigit()
                }
                .frame(width: 84, height: 84).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 9) {
                    Text(complete ? L("Yapay zekâ bu markayı tanıyor") : L("Yapay zekâ bu markayı henüz tam tanımıyor"))
                        .font(Design.Font.heading.weight(.semibold)).accessibilityAddTraits(.isHeader)
                    Text(complete ? L("Bütün bölümler dolu. Doldurduğun bölümler asistanın bağlamına girer.")
                         : LF("Eksik bölüm: %d. Boş bölümler bağlama girmez, uydurulmaz.", missing.count))
                        .font(Design.Font.callout).foregroundStyle(.secondary)
                    if !complete {
                        FlowLayout(spacing: 8) {
                            ForEach(missing) { m in
                                Button { jump(m, proxy) } label: {
                                    Label(m.title, systemImage: "plus").labelStyle(.titleAndIcon).font(Design.Font.small.weight(.medium)).lineLimit(1)
                                        .padding(.horizontal, 9).padding(.vertical, 5)
                                        .background(Capsule().fill(Design.panel)).overlay(Capsule().strokeBorder(Design.line))
                                }
                                .buttonStyle(.plain).help(LF("“%@” bölümünü yaz", m.title))
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        Button { showContext.toggle() } label: {
                            Label(showContext ? L("Önizlemeyi gizle") : L("Yapay zekâ gözüyle bak"), systemImage: "eye").labelStyle(.titleAndIcon)
                        }.actionSecondary()
                        if let next = missing.first {
                            Button { jump(next, proxy) } label: { Label(LF("Sıradaki eksik: %@", next.title), systemImage: "arrow.down.to.line").labelStyle(.titleAndIcon).lineLimit(1) }
                                .actionSecondary().keyboardShortcut("e", modifiers: [.command, .shift])
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            Divider().opacity(0.6)
            facts(current)
        }
        .padding(20).card()
    }

    private func facts(_ current: Brand) -> some View {
        let contacts = app.read(or: []) { try $0.contacts(brandId: brand.id) }
        let projects = app.read(or: []) { try $0.projects(brandId: brand.id) }
        return HStack(alignment: .top, spacing: Design.Space.l) {
            sectorFact(current)
            factItem(L("İlgili kişi"), contacts.first.map { $0.role.isEmpty ? $0.name : $0.name + " · " + $0.role } ?? "—")
            factItem(L("Projeler"), projects.isEmpty ? "—" : String(projects.count))
            factItem(L("Eklendi"), current.createdAt.formatted(.dateTime.day().month(.abbreviated).year()))
        }
    }

    private func factItem(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(Design.Font.small).foregroundStyle(.secondary)
            Text(value).font(Design.Font.body.weight(.medium)).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Sektör satır içi düzenlenir: tıkla, yaz, ↩ kaydeder, Esc vazgeçer.
    private func sectorFact(_ current: Brand) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L("Sektör")).font(Design.Font.small).foregroundStyle(.secondary)
            if editingSector {
                TextField(L("Sektör"), text: $sectorDraft).textFieldStyle(.roundedBorder).font(Design.Font.callout)
                    .onSubmit { saveSector() }.onExitCommand { PendingEdits.shared.clear(sectorPendingId); editingSector = false }
                    .onChange(of: sectorDraft) { _, now in registerSectorPending(now, current: current.sector) }
                    .onDisappear { PendingEdits.shared.flush(sectorPendingId) }
            } else {
                Button { sectorDraft = current.sector; editingSector = true } label: {
                    HStack(spacing: 5) {
                        Text(current.sector.isEmpty ? L("Ekle") : current.sector).font(Design.Font.body.weight(.medium)).lineLimit(1)
                        Image(systemName: "pencil").font(Design.Icon.small).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain).help(L("Sektörü düzenle")).accessibilityLabel(LF("Sektör: %@", current.sector.isEmpty ? L("boş") : current.sector))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Yazarken uygulama kapanırsa sektör kaybolmasın (U-07); değişmediyse kayıt bırakılmaz.
    private func registerSectorPending(_ now: String, current: String) {
        guard editingSector else { return }
        let changed = now.trimmingCharacters(in: .whitespacesAndNewlines) != current
        if changed { PendingEdits.shared.register(sectorPendingId, save: { saveSector() }) }
        else { PendingEdits.shared.clear(sectorPendingId) }
    }

    /// Marka değişince ya da görünüm kapanınca bekleyen taslaklar (sektör, metin) kaybolmadan kaydedilir.
    private func flushPendingEdits() {
        PendingEdits.shared.flush(sectorPendingId)
        PendingEdits.shared.flush(pendingId)
    }

    private func saveSector() {
        PendingEdits.shared.clear(sectorPendingId)
        guard editingSector, let store = app.store else { return }
        let previous = app.read(or: nil) { try $0.brand(brand.id) }?.sector ?? ""
        let ok: Void? = app.perform(title: L("Kaydedilemedi"), context: "marka.sektor") {
            var b = try store.brand(brand.id)
            b.sector = sectorDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            try store.updateBrand(b)
        }
        editingSector = false
        guard ok != nil else { return }
        let brandId = brand.id
        undoManager?.registerUndo(withTarget: app) { _ in
            MainActor.assumeIsolated {
                app.perform(title: L("Geri alınamadı"), context: "marka.sektor.geri") {
                    var b = try store.brand(brandId); b.sector = previous; try store.updateBrand(b)
                }
            }
        }
        undoManager?.setActionName(L("Sektörü düzenle"))
    }

    private func filterRow(_ cards: [Card]) -> some View {
        let filled = cards.filter(\.isFilled).count
        let tokens = cards.reduce(0) { $0 + $1.tokens }
        return HStack(spacing: Design.Space.m) {
            SegmentedChoice(options: [(Filter.all, L("Tümü") + " " + String(cards.count)), (.filled, L("Dolu") + " " + String(filled)),
                                      (.missing, L("Eksik") + " " + String(cards.count - filled))], selection: $filter)
            Spacer()
            Text(LF("Bağlam boyutu (token): ~%d", tokens)).captionStyle().help(L("Tahmini; karakter sayısından hesaplanır"))
        }
    }

    // MARK: Bölüm kartı

    private func cardView(_ m: Card, _ proxy: ScrollViewProxy) -> some View {
        let isEditing = editing == m.target
        return VStack(alignment: .leading, spacing: 12) {
            cardHeader(m, isEditing: isEditing)
            if isEditing {
                editor(prompt: m.prompt, target: m.target)
            } else if m.isFilled {
                filledBody(m)
            } else {
                emptyBody(m)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .modifier(CardChrome(filled: m.isFilled))
        .onHover { hovered = $0 ? m.id : (hovered == m.id ? nil : hovered) }
        .id("kart-" + m.target.key)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(LF("%1$@, %2$@", m.title, m.isFilled ? L("dolu") : L("boş")))
    }

    private func cardHeader(_ m: Card, isEditing: Bool) -> some View {
        let hover = hovered == m.id
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: m.symbol).font(Design.Icon.medium.weight(.semibold))
                .foregroundStyle(m.isFilled ? AnyShapeStyle(BrandTintStyle(key: brand.id)) : AnyShapeStyle(.tertiary)).accessibilityHidden(true)
            Text(m.title).font(Design.Font.heading.weight(.semibold)).accessibilityAddTraits(.isHeader)
            if saved == m.target {
                Label(L("Kaydedildi"), systemImage: "checkmark.circle.fill").labelStyle(.titleAndIcon)
                    .font(Design.Font.small.weight(.medium)).foregroundStyle(.green).transition(.opacity)
            }
            Spacer()
            if !isEditing {
                HStack(spacing: 2) {
                    if m.isFilled { iconButton("square.on.square", L("Kopyala")) { copy(m.text) } }
                    iconButton(m.isFilled ? "pencil" : "plus", m.isFilled ? L("Düzenle") : L("Yaz")) { begin(m.target, m.text) }
                }
                .opacity(hover || !m.isFilled ? 1 : 0.4)
            }
        }
    }

    private func iconButton(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(Design.Icon.small.weight(.medium)).foregroundStyle(.secondary)
                .frame(width: 26, height: 26).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(label).accessibilityLabel(label)
    }

    /// Okuma tipografisi: 14 pt, geniş satır aralığı, okunur satır uzunluğu.
    private func filledBody(_ m: Card) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(m.text).font(Design.Font.body).lineSpacing(6).foregroundStyle(.primary.opacity(0.84))
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                .frame(maxWidth: 680, alignment: .leading)
            HStack(spacing: 10) {
                Text(LF("Sözcük: %d", m.words))
                Text(LF("Token: ~%d", m.tokens))
                if let u = m.updated { Text(u.formatted(.relative(presentation: .named))) }
            }
            .font(Design.Font.small).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private func emptyBody(_ m: Card) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(m.prompt).font(Design.Font.callout).foregroundStyle(.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button { begin(m.target, m.text) } label: { Label(L("Yaz"), systemImage: "square.and.pencil").labelStyle(.titleAndIcon) }.actionSecondary()
                Button { app.askAI(draftPrompt(m)) } label: { Label(L("Asistana sor"), systemImage: "sparkles").labelStyle(.titleAndIcon) }.actionSecondary()
                    .help(L("Asistan sohbette taslak çıkarır; kaydı sen yaparsın"))
            }
        }
    }

    /// Asistana giden istem: taslak yalnız sohbette görünür (profil bölümü yazma önerisi yoktur), uydurma yasak.
    private func draftPrompt(_ m: Card) -> String {
        "Bu markanın kayıtlarından “\(m.title)” bölümü için kısa bir taslak yaz. Kayıtlarda olmayan ya da bilmediğin bilgiyi uydurma; “bilinmiyor” de. Taslağı yalnızca sohbette göster; gözden geçirip kaydı ben yapacağım."
    }

    private func editor(prompt: String, target: Target) -> some View {
        let limit = ProfileSection.maxLength
        return VStack(alignment: .leading, spacing: 10) {
            Text(prompt).font(Design.Font.small).foregroundStyle(.secondary)
            TextEditor(text: $draft)
                .font(Design.Font.body).scrollContentBackground(.hidden).focused($editorFocused)
                .accessibilityLabel(prompt)
                .padding(8).frame(minHeight: 130)
                .background(RoundedRectangle(cornerRadius: Design.Radius.small, style: .continuous).fill(Design.panel))
                .overlay(RoundedRectangle(cornerRadius: Design.Radius.small, style: .continuous).strokeBorder(editorFocused ? AnyShapeStyle(Design.accent) : AnyShapeStyle(Design.line)))
            HStack {
                Text(verbatim: "\(draft.count)/\(limit)").font(Design.Font.small).monospacedDigit()
                    .foregroundStyle(draft.count > limit ? AnyShapeStyle(Design.danger) : (draft.count > limit * 9 / 10 ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary)))
                Spacer()
                Text(L("Esc vazgeçer · ⌘↩ kaydeder")).font(Design.Font.small).foregroundStyle(.tertiary)
                Button(L("Vazgeç")) { cancelEdit() }.actionSecondary()
                Button(L("Kaydet")) { save(target) }.actionPrimary().disabled(draft.count > limit)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .onExitCommand { cancelEdit() }
        .onChange(of: draft) { _, _ in registerDraftPending(target) }
        .onDisappear { PendingEdits.shared.flush(pendingId) }
    }

    /// Vazgeç / Esc: taslak atılır ve bekleyen kayıt silinir (kapanışta KAYDEDİLMEZ).
    private func cancelEdit() {
        PendingEdits.shared.clear(pendingId)
        editing = nil
    }

    /// Yazarken uygulama kapanırsa metin kaybolmasın (U-07). Her değişimde yeniden kaydedilir; kapanış güncel taslağı okur.
    private func registerDraftPending(_ target: Target) {
        guard editing == target else { return }
        if draft != draftBase && draft.count <= ProfileSection.maxLength {
            PendingEdits.shared.register(pendingId, save: { save(target) })
        } else {
            PendingEdits.shared.clear(pendingId)
        }
    }

    // MARK: Düzenleme

    private func begin(_ target: Target, _ text: String) {
        draft = text
        draftBase = text
        editing = target
        DispatchQueue.main.async { editorFocused = true }
    }

    /// Eksik bölüme kaydırır ve yazmaya açar (süzgeç "Tümü"ne döner ki kart görünsün).
    private func jump(_ m: Card, _ proxy: ScrollViewProxy) {
        filter = .all
        begin(m.target, m.text)
        DispatchQueue.main.async {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { proxy.scrollTo("kart-" + m.target.key, anchor: .center) }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func save(_ target: Target) {
        PendingEdits.shared.clear(pendingId)
        guard editing == target, let store = app.store else { return }
        // ⌘Z için önceki metin.
        let previous: String = {
            switch target {
            case .summary: return app.read(or: nil) { try $0.brand(brand.id) }?.summary ?? ""
            case .section(let section): return app.read(or: [:]) { try $0.profile(brandId: brand.id) }[section] ?? ""
            }
        }()
        let ok: Void? = app.perform(title: L("Kaydedilemedi"), context: "marka.profil") {
            switch target {
            case .summary:
                var b = try store.brand(brand.id)
                b.summary = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                try store.updateBrand(b)
            case .section(let section):
                try store.setProfileSection(brandId: brand.id, section, body: draft)
            }
        }
        guard ok != nil else { registerDraftPending(target); return }   // kaydedilemedi: kapanışta yeniden denensin
        let brandId = brand.id
        undoManager?.registerUndo(withTarget: app) { _ in
            MainActor.assumeIsolated {
                switch target {
                case .summary:
                    app.perform(title: L("Geri alınamadı"), context: "marka.profil.geri") {
                        var b = try store.brand(brandId); b.summary = previous; try store.updateBrand(b)
                    }
                case .section(let section):
                    app.perform(title: L("Geri alınamadı"), context: "marka.profil.geri") {
                        try store.setProfileSection(brandId: brandId, section, body: previous)
                    }
                }
                app.writeContext(brandId: brandId)
            }
        }
        undoManager?.setActionName(L("Metni düzenle"))
        editing = nil
        app.writeContext(brandId: brand.id)
        // "Kaydedildi" iki saniye görünür ("Hareketi Azalt" açıksa animasyonsuz).
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { saved = target }
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run { withAnimation(reduceMotion ? nil : .easeIn(duration: 0.3)) { if saved == target { saved = nil } } }
        }
    }

    // MARK: Kararlar ve notlar (yalnız okunur)

    @ViewBuilder private var decisions: some View {
        let records = (app.read(or: []) { try $0.records(brandId: brand.id, kinds: [.decision]) }).filter { $0.isOpen }
        let meetings = (app.read(or: []) { try $0.sources(brandId: brand.id) }).filter { $0.kind == .meeting }.prefix(5)
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Kararlar ve görüşme notları")).font(Design.Font.heading.weight(.semibold))
            if records.isEmpty && meetings.isEmpty {
                Text(L("Bekleyen karar ya da görüşme notu yok. Bunlar Görevler ve Dosyalar'dan gelir.")).font(Design.Font.callout).foregroundStyle(.tertiary)
            }
            ForEach(records) { r in
                line(r.title, meta: L("Karar bekleniyor") + (r.dueDate.map { " · " + $0 } ?? ""))
            }
            ForEach(Array(meetings)) { m in
                line(m.title, meta: L("Görüşme") + " · " + m.capturedAt.formatted(.dateTime.day().month(.abbreviated)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .card(padding: 18)
    }

    private func line(_ title: String, meta: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Design.Font.body)
            Text(meta).font(Design.Font.small).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Önizleme

    /// "Yapay zekâ gözüyle": asistanın bu marka için okuduğu bağlam; boyutu, kopyalama ve klasörde gösterme.
    private var contextPreview: some View {
        let text = ((try? app.store.map { try ContextBuilder(store: $0).brandContext(brandId: brand.id) }) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(L("Yapay zekânın okuduğu bağlam")).font(Design.Font.body.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Spacer()
                Text(LF("Karakter: %d", text.count)).captionStyle()
                iconButton("square.on.square", L("Kopyala")) { copy(text) }
                iconButton("folder", L("Klasörde göster")) {
                    if let folder = app.revealFolder(brandId: brand.id) { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                }
            }
            Text(L("Asistan bu marka için bu metni okur. Boş bölümler girmez. Şirket profili ve ekip yalnız Stüdyo aynı sağlayıcıya izin verdiyse eklenir; BAGLAM.md yalnız Codex izniyle ve şirket bilgisi olmadan yazılır."))
                .font(Design.Font.small).foregroundStyle(.secondary)
            Text(text).font(Design.Font.small.monospaced()).textSelection(.enabled).lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous).fill(Design.panel))
        .overlay(RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous).strokeBorder(Design.line))
    }
}

/// Dolu bölüm: normal kart. Boş bölüm: kesikli çerçeve, sönük zemin ("burada bir şey bekleniyor").
private struct CardChrome: ViewModifier {
    let filled: Bool
    func body(content: Content) -> some View {
        if filled {
            content.card(padding: 18)
        } else {
            content.padding(18)
                .background(RoundedRectangle(cornerRadius: Design.Radius.large, style: .continuous).fill(Design.panel.opacity(0.4)))
                .overlay(RoundedRectangle(cornerRadius: Design.Radius.large, style: .continuous).strokeBorder(Design.line, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        }
    }
}

extension ProfileSection {
    /// Kartın simgesi (SF Symbols).
    var symbol: String {
        switch self {
        case .audience: "person.2"
        case .positioning: "scope"
        case .voice: "text.bubble"
        case .scope: "list.bullet.rectangle"
        case .competitors: "chart.bar.xaxis"
        case .constraints: "exclamationmark.shield"
        case .success: "target"
        }
    }
}
