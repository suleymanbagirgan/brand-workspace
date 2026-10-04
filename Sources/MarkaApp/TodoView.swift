import MarkaCore
import SwiftUI

/// Yapılacaklar — *ne bekliyor* (plan §4, U9): tek liste (`Store.todo`): açık görevler, söz, karar bekleniyor, açık talep.
/// Hedef/teklif/sözleşme/önemli tarih burada değil, Bilgiler'de. Gecikenler üstte, sonra son tarihe göre, tarihsizler sonda.
/// Satır başındaki kutu tamamlar (Bitti); satır kısa süre üstü çizili kalıp listeden çıkar.
/// Üstte tek satır: solda görünür tür seçimi "Görev | Söz", yanında alan (Enter ekler; not Akış'ta eklenir). Satıra
/// tıklayınca sağda ayrıntı paneli (satır içi düzenleme; altta İptal et, Sil… — tek yer).
struct TodoView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let brand: Brand
    @State private var selection: PanelTarget?
    @State private var quickTitle = ""
    @State private var quickKind = QuickKind.task
    @State private var adding = false
    @State private var query = ""
    @State private var dropTarget: String?
    @State private var sort = SortKey.recommended
    @State private var mode = ViewMode.list
    @State private var filter = StatusFilter.all
    @State private var collapsed: Set<String> = []
    /// Az önce tamamlanan satırlar: kısa süre üstü çizili görünür, sonra listeden çıkar.
    @State private var lingering: [String: TodoItem] = [:]

    enum ViewMode { case list, board, gantt, calendar }

    enum StatusFilter: CaseIterable {
        case all, todo, doing, waiting
        var title: String {
            switch self {
            case .all: L("Tüm durumlar")
            case .todo: L("Yapılacak")
            case .doing: L("Sürüyor")
            case .waiting: L("Bekliyor")
            }
        }
        func matches(_ item: TodoItem, done: Bool) -> Bool {
            switch self {
            case .all: return true
            case .todo: return !done && item.circleState == .todo
            case .doing: return !done && item.circleState == .doing
            case .waiting: return !done && item.circleState == .waiting
            }
        }
    }

    /// Sıralama (Hatırlatıcılar: teslim tarihi, öncelik, başlık, oluşturulma).
    enum SortKey: CaseIterable {
        case recommended, due, priority, title, created
        var title: String {
            switch self {
            case .recommended: L("Önerilen")
            case .due: L("Teslim tarihi")
            case .priority: L("Öncelik")
            case .title: L("Başlık")
            case .created: L("Oluşturulma")
            }
        }
        func apply(_ items: [TodoItem]) -> [TodoItem] {
            switch self {
            case .recommended: return items
            case .due: return items.sorted { ($0.dueDate ?? "9999") == ($1.dueDate ?? "9999") ? $0.title.localizedStandardCompare($1.title) == .orderedAscending : ($0.dueDate ?? "9999") < ($1.dueDate ?? "9999") }
            case .priority: return items.sorted { $0.priority == $1.priority ? $0.title.localizedStandardCompare($1.title) == .orderedAscending : $0.priority > $1.priority }
            case .title: return items.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            case .created: return items.sorted { $0.createdAt > $1.createdAt }
            }
        }
    }

    enum QuickKind: CaseIterable {
        case task, promise
        var title: String {
            switch self {
            case .task: L("Görev")
            case .promise: L("Söz")
            }
        }
    }

    init(brand: Brand, selection: PanelTarget? = nil, mode: ViewMode = .list) {
        self.brand = brand
        _selection = State(initialValue: selection)
        // Geliştirme: `MARKA_MOD=board|gantt|calendar` görünümü seçer (gerçek pencere doğrulaması için).
        let override = ProcessInfo.processInfo.environment["MARKA_MOD"].flatMap { ["board": ViewMode.board, "gantt": .gantt, "calendar": .calendar][$0] }
        _mode = State(initialValue: override ?? mode)
    }

    var body: some View {
        let _ = app.revision
        let open = (try? app.store?.todo(brandId: brand.id)) ?? []
        let openIds = Set(open.map(\.id))
        let done = lingering.values.filter { !openIds.contains($0.id) }
        let all = (open + done).sorted(by: TodoItem.order)
        let items = sort.apply(all.filter { filter.matches($0, done: done.contains($0)) && (query.isEmpty || $0.title.localizedStandardContains(query)) })
        // Tamamlananlar (yalnız açıksa): en son biten üstte, en çok 100; aramaya uyar.
        let shownIds = Set(items.map(\.id))
        let completed: [TodoItem] = app.showCompletedTasks
            ? Array(((try? app.store?.tasks(brandId: brand.id, statuses: [.done])) ?? [])
                .sorted { ($0.completedAt ?? $0.updatedAt) > ($1.completedAt ?? $1.updatedAt) }
                .map(TodoItem.init)
                .filter { !shownIds.contains($0.id) && (query.isEmpty || $0.title.localizedStandardContains(query)) }
                .prefix(100))
            : []
        let doneIds = Set(done.map(\.id)).union(completed.map(\.id))
        let waitingCount = open.filter { $0.circleState == .waiting && { if case .record(.decision, _) = $0.kind { true } else { false } }($0) }.count
        let groups = grouped(items)
        VStack(alignment: .leading, spacing: 0) {
            // Başlık ve görünüm çubuğu sabit; altı kayar. Gantt ve Takvim aynı görevlerin zaman görünümüdür.
            VStack(alignment: .leading, spacing: Design.Space.l) {
                SectionHeading(title: L("Görevler"), subtitle: LF("%d açık", open.count), symbol: "checklist", tintKey: brand.id) {
                    Button {
                        app.askAI(ChatPrompts.whatToDo)
                    } label: { Label(L("Yapay zekâya sor"), systemImage: "sparkles").labelStyle(.titleAndIcon) }
                        .actionSecondary()
                        .help(L("Asistan tüm kayıtları okuyup ne yapman gerektiğini söyler ve görev önerir"))
                    Button {
                        if mode == .gantt || mode == .calendar { mode = .list }
                        adding.toggle()
                    } label: { Label(L("Görev ekle"), systemImage: "plus").labelStyle(.titleAndIcon) }
                        .actionPrimary()
                        .popover(isPresented: $adding, arrowEdge: .bottom) { NewTaskCard(brand: brand, isPresented: $adding) }
                }
                toolbar(count: items.count)
            }
            .pagePadding().padding(.top, Design.Space.l)
            switch mode {
            case .gantt: PlanningView(brand: brand, mode: .timeline)
            case .calendar: PlanningView(brand: brand, mode: .calendar)
            case .list, .board:
                ListWithPanel(selection: $selection) {
                    PageScroll(backgroundTap: { selection = nil }) {
                        VStack(alignment: .leading, spacing: 0) {
                            if waitingCount > 0 { callout(waitingCount).padding(.bottom, Design.Space.m) }
                            if items.isEmpty && completed.isEmpty {
                                EmptyStateView(title: all.isEmpty ? L("Bekleyen bir şey yok") : L("Bu filtreyle eşleşen iş yok"),
                                               message: all.isEmpty ? L("Yukarıdan görev ya da söz ekleyebilirsin; terminaldeki araç da görev önerebilir. Bitenler Akış'ta görünür.") : L("Filtreyi “Tüm durumlar” yapabilirsin."),
                                               symbol: all.isEmpty ? "checklist" : "magnifyingglass")
                                    .padding(.top, Design.Space.m)
                            } else if mode == .board {
                                board(items, doneIds: doneIds).padding(.top, Design.Space.s)
                            } else {
                                ForEach(groups, id: \.name) { group in groupView(group, doneIds: doneIds) }
                                if !completed.isEmpty { groupView(Group(name: L("Tamamlananlar"), items: completed), doneIds: doneIds) }
                            }
                        }
                        .pagePadding().padding(.top, Design.Space.m).padding(.bottom, Design.Space.l)
                        // Klavye: ↑↓ satır seçer (ayrıntı paneli açılır), Boşluk seçili satırı tamamlar/yeniden açar.
                        .focusable().focusEffectDisabled()
                        .onKeyPress(.downArrow) { moveSelection(1, in: flatItems(groups: groups, items: items)); return .handled }
                        .onKeyPress(.upArrow) { moveSelection(-1, in: flatItems(groups: groups, items: items)); return .handled }
                        .onKeyPress(.space) { toggleSelected(in: items, doneIds: doneIds) ? .handled : .ignored }
                    }
                }
            }
        }
        .onChange(of: brand.id) { selection = nil; lingering = [:]; filter = .all; query = "" }
        .onChange(of: app.addTaskRequested) { _, now in if now { mode = .list; adding = true; app.addTaskRequested = false } }
        .onAppear { if app.addTaskRequested { mode = .list; adding = true; app.addTaskRequested = false } }
    }

    // MARK: Klavye

    /// Ekrandaki sırayla (grupların sırası, kapalı gruplar hariç) satırlar.
    private func flatItems(groups: [Group], items: [TodoItem]) -> [TodoItem] {
        mode == .board ? items : groups.filter { !collapsed.contains($0.name) }.flatMap(\.items)
    }

    private func moveSelection(_ delta: Int, in list: [TodoItem]) {
        guard !list.isEmpty else { return }
        let current = list.firstIndex { PanelTarget($0) == selection }
        let next = current.map { min(max($0 + delta, 0), list.count - 1) } ?? (delta > 0 ? 0 : list.count - 1)
        selection = PanelTarget(list[next])
    }

    private func toggleSelected(in items: [TodoItem], doneIds: Set<String>) -> Bool {
        guard let item = items.first(where: { PanelTarget($0) == selection }), item.canComplete else { return false }
        toggle(item, done: doneIds.contains(item.id))
        return true
    }

    // MARK: Üst bölüm

    private func callout(_ count: Int) -> some View {
        // v3: kutu yok; tek satır, sakin.
        HStack(spacing: 10) {
            Image(systemName: "hourglass").font(.system(size: 13)).foregroundStyle(.secondary)
            Text(LF("Müşteri yanıtı bekleyen iş: %d", count)).font(.system(size: 13, weight: .medium))
            Spacer()
            Button(L("Bekleyenleri gör")) { filter = .waiting }.buttonStyle(.text)
        }
        .padding(.vertical, 6)
    }

    private func toolbar(count: Int) -> some View {
        let listLike = mode == .list || mode == .board
        return HStack(spacing: 8) {
            SegmentedChoice(options: [(ViewMode.list, L("Liste")), (ViewMode.board, L("Pano")),
                                      (ViewMode.gantt, L("Gantt")), (ViewMode.calendar, L("Takvim"))], selection: $mode)
            if listLike {
                Menu {
                    ForEach(StatusFilter.allCases, id: \.self) { f in
                        Button { filter = f } label: { if filter == f { Label(f.title, systemImage: "checkmark") } else { Text(f.title) } }
                    }
                } label: {
                    Text(filter.title).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton).fixedSize()
                Menu {
                    ForEach(SortKey.allCases, id: \.self) { k in
                        Button { sort = k } label: { if sort == k { Label(k.title, systemImage: "checkmark") } else { Text(k.title) } }
                    }
                    Divider()
                    Toggle(L("Tamamlananları göster"), isOn: Binding(get: { app.showCompletedTasks }, set: { app.showCompletedTasks = $0 }))
                } label: {
                    Label(L("Sırala"), systemImage: "arrow.up.arrow.down").labelStyle(.titleAndIcon).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton).fixedSize()
                .help(L("Sıralama ve tamamlananlar"))
            }
            Spacer()
            if listLike {
                LocalSearchField(text: $query, prompt: L("Görevlerde ara"))
            }
        }
        .padding(.bottom, Design.Space.m)
        .overlay(alignment: .bottom) { Rectangle().fill(Design.line).frame(height: 1) }
    }

    // MARK: Gruplar

    struct Group { let name: String; let items: [TodoItem] }

    /// Proje adına göre gruplar (görevin projesi); projesi olmayan görev ve söz/karar/talepler "Diğer"de.
    private func grouped(_ items: [TodoItem]) -> [Group] {
        guard let store = app.store else { return [Group(name: L("Diğer"), items: items)] }
        let projects = (try? store.projects(brandId: brand.id)) ?? []
        let names = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.name) })
        let taskProject = Dictionary(uniqueKeysWithValues: ((try? store.tasks(brandId: brand.id)) ?? []).compactMap { t in t.projectId.map { (t.id, $0) } })
        var buckets: [String: [TodoItem]] = [:]
        for item in items {
            var key = L("Diğer")
            if case .task = item.kind, let pid = taskProject[item.entityId], let name = names[pid] { key = name }
            buckets[key, default: []].append(item)
        }
        let ordered = projects.map(\.name).filter { buckets[$0] != nil }
        let rest = buckets.keys.filter { !ordered.contains($0) && $0 != L("Diğer") }.sorted()
        let tail = buckets[L("Diğer")] != nil ? [L("Diğer")] : []
        return (ordered + rest + tail).map { Group(name: $0, items: buckets[$0] ?? []) }
    }

    private func groupView(_ group: Group, doneIds: Set<String>) -> some View {
        let isCollapsed = collapsed.contains(group.name)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                    if isCollapsed { collapsed.remove(group.name) } else { collapsed.insert(group.name) }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).frame(width: 14)
                    Text(group.name).font(.system(size: 12, weight: .semibold))
                    Text(verbatim: "\(group.items.count)").font(.system(size: 11)).foregroundStyle(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Design.panel))
                    Spacer()
                }
                .frame(height: 32).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isCollapsed ? L("Kapalı") : L("Açık"))
            if !isCollapsed {
                VStack(spacing: 0) {
                    ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Rectangle().fill(Design.line).frame(height: 1) }
                        row(item, done: doneIds.contains(item.id))
                    }
                }
                .flatList()
            }
        }
        .padding(.top, 22)
    }

    private func board(_ items: [TodoItem], doneIds: Set<String>) -> some View {
        let columns: [(String, StatusCircle.State)] = [(L("Yapılacak"), .todo), (L("Sürüyor"), .doing), (L("Bekliyor"), .waiting)]
        return HStack(alignment: .top, spacing: 14) {
            ForEach(columns, id: \.0) { col in
                let list = items.filter { doneIds.contains($0.id) ? col.1 == .todo : $0.circleState == col.1 }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        StatusCircle(state: col.1, size: 14)
                        Text(col.0).font(.system(size: 12, weight: .semibold))
                        Text(verbatim: "\(list.count)").font(.system(size: 11)).foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(Design.line.opacity(0.6)))
                        Spacer()
                    }
                    .padding(.horizontal, 4).padding(.bottom, 2)
                    if list.isEmpty {
                        Text(L("Boş")).font(.system(size: 11)).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, minHeight: 64)
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Design.line, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
                    }
                    ForEach(list) { item in boardCard(item, done: doneIds.contains(item.id)) }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Design.sidebarBackground.opacity(dropTarget == col.0 ? 1 : 0.7)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(dropTarget == col.0 ? AnyShapeStyle(Design.accent) : AnyShapeStyle(Color.clear), lineWidth: 2))
                // Kartı başka sütuna bırakmak görevin durumunu değiştirir (yalnız görevler; söz/karar/talep durumları sütunla eşleşmez).
                .dropDestination(for: String.self, action: { ids, _ in dropTasks(ids, to: col.1) },
                                 isTargeted: { dropTarget = $0 ? col.0 : (dropTarget == col.0 ? nil : dropTarget) })
            }
        }
    }

    /// Pano sütununa bırakılan görevlerin durumunu değiştirir; ⌘Z önceki durumlara döndürür.
    private func dropTasks(_ ids: [String], to state: StatusCircle.State) -> Bool {
        guard let store = app.store else { return false }
        let status: TaskStatus = switch state { case .todo: .todo; case .doing: .inProgress; case .waiting: .waiting; case .done: .done }
        let tasks = ids.compactMap { id in (try? store.tasks(brandId: brand.id))?.first { $0.id == id } }.filter { $0.status != status && $0.status.isOpen }
        guard !tasks.isEmpty else { return false }
        let ok: Void? = app.perform(title: L("Durum değiştirilemedi"), context: "yapilacak.surukle") {
            for t in tasks { try store.setTaskStatus(t.id, status) }
        }
        guard ok != nil else { return false }
        let before = tasks.map { ($0.id, $0.status) }
        undoManager?.registerUndo(withTarget: app) { _ in
            MainActor.assumeIsolated { for (id, old) in before { try? app.store?.setTaskStatus(id, old) } }
        }
        undoManager?.setActionName(L("Durumu değiştir"))
        return true
    }

    private func boardCard(_ item: TodoItem, done: Bool) -> some View {
        let target = PanelTarget(item)
        let selected = selection == target
        return VStack(alignment: .leading, spacing: 10) {
            Text(item.title).font(.system(size: 12, weight: .medium)).strikethrough(done).lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                Text(item.kindTitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                if item.priority >= 3 { Pill(text: L("Yüksek"), tint: AnyShapeStyle(Design.accent)) }
                Spacer(minLength: 4)
                if let d = item.dueDate { DueLabel(day: d) }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Design.windowBackground))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(selected ? AnyShapeStyle(Design.accent) : AnyShapeStyle(Design.line), lineWidth: selected ? 2 : 1))
        .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { selection = selected ? nil : target }
        .modifier(DragIfTask(item: item))
        .contextMenu {
            if item.canComplete { Button(done ? L("Yeniden aç") : L("Tamamla")) { toggle(item, done: done) } }
            Button(L("Ayrıntıyı aç")) { selection = target }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { selection = target }
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
        return HStack(alignment: .center, spacing: 12) {
            statusButton(item, done: done)
            titleBlock(item, done: done)
            priorityColumn(item)
            dueColumn(item)
            timerButton(item)
            assigneeBadge(item.assignee)
        }
        .padding(.vertical, 12).padding(.horizontal, 14)
        .rowBackground(selected: selected, radius: 0)
        .contentShape(Rectangle())
        .onTapGesture { selection = selected ? nil : target }
        .contextMenu {
            if item.canComplete {
                Button(done ? L("Yeniden aç") : L("Tamamla")) { toggle(item, done: done) }
            }
            if case .task(let st) = item.kind, st.isOpen {
                Button(app.runningTimer?.taskId == item.entityId ? L("Zamanlayıcıyı durdur") : L("Zamanlayıcıyı başlat")) {
                    app.runningTimer?.taskId == item.entityId ? app.stopTimer() : app.startTimer(item.entityId)
                }
            }
            Button(L("Ayrıntıyı aç")) { selection = target }
        }
        // İptal et ve Sil… tek yerde: panelin altında (U9; sağ tık menüsü ikinci yoldu, kalktı).
        // VoiceOver: tek öğe; varsayılan eylem paneli açar, tamamlama adlı eylem.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.kindTitle + " · " + item.title)
        .accessibilityValue(Self.accessibilityValue(item, done: done))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { selection = selected ? nil : target }
        .modifier(RowAction(name: done ? L("Yeniden aç") : L("Tamamla"), enabled: item.canComplete, perform: { toggle(item, done: done) }))
    }

    /// Zamanlayıcı: açık görevde oynat/durdur; çalışırken süre görünür.
    @ViewBuilder private func timerButton(_ item: TodoItem) -> some View {
        if case .task(let status) = item.kind, status.isOpen {
            let running = app.runningTimer?.taskId == item.entityId
            Button { running ? app.stopTimer() : app.startTimer(item.entityId) } label: {
                HStack(spacing: 4) {
                    Image(systemName: running ? "stop.circle.fill" : "play.circle").font(.system(size: 16))
                    if running { Text(Timecode.string(app.elapsed)).font(.system(size: 11, weight: .medium)).monospacedDigit() }
                }
                .foregroundStyle(running ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
                .frame(minWidth: 28, minHeight: 28)
            }
            .buttonStyle(.plain)
            .help(running ? L("Zamanlayıcıyı durdur") : L("Zamanlayıcıyı başlat"))
            .accessibilityLabel(running ? L("Zamanlayıcıyı durdur") : L("Zamanlayıcıyı başlat"))
        } else {
            Color.clear.frame(width: 28, height: 28)
        }
    }

    private func statusButton(_ item: TodoItem, done: Bool) -> some View {
        let state: StatusCircle.State = done ? .done : item.circleState
        return Button { toggle(item, done: done) } label: { StatusCircle(state: state) }
            .buttonStyle(.plain)
            .opacity(item.canComplete ? 1 : 0)
            .disabled(!item.canComplete)
            .help(done ? L("Yeniden aç") : L("Tamamla"))
    }

    private func titleBlock(_ item: TodoItem, done: Bool) -> some View {
        let ink: AnyShapeStyle = done ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)
        return VStack(alignment: .leading, spacing: 3) {
            Text(item.title).font(.system(size: 13, weight: .medium)).lineLimit(1).strikethrough(done).foregroundStyle(ink)
            Text(item.kindTitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func dueColumn(_ item: TodoItem) -> some View {
        if let d = item.dueDate { DueLabel(day: d).frame(width: 64, alignment: .trailing) } else { Color.clear.frame(width: 64, height: 1) }
    }

    private static func accessibilityValue(_ item: TodoItem, done: Bool) -> String {
        var parts: [String] = []
        if done { parts.append(L("Bitti")) }
        if let d = item.dueDate { parts.append(LF("Son tarih %@", d)) }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder private func priorityColumn(_ item: TodoItem) -> some View {
        if item.priority >= 3 {
            Label(L("Yüksek"), systemImage: "flag").labelStyle(.titleAndIcon).font(.system(size: 10)).foregroundStyle(.secondary)
                .frame(width: 74, alignment: .leading)
        } else {
            Color.clear.frame(width: 74, height: 1)
        }
    }

    private func assigneeBadge(_ name: String) -> some View {
        let empty = name.isEmpty
        let fill: AnyShapeStyle = empty ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Design.panel)
        let stroke: AnyShapeStyle = empty ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Design.line)
        return Text(Self.initials(name)).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .background(Circle().fill(fill))
            .overlay(Circle().strokeBorder(stroke))
    }

    static func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map { String($0).uppercased() } }.joined()
    }

    /// Kutu: açık satırı tamamlar; az önce tamamlananı geri açar.
    private func toggle(_ item: TodoItem, done: Bool) {
        guard let store = app.store else { return }
        if done {
            let wasDone: Bool = { if case .task(.done) = item.kind { true } else { false } }()
            restore(item)
            if wasDone {
                // ⌘Z: yeniden açılan görevi tekrar tamamlar.
                undoManager?.registerUndo(withTarget: app) { _ in MainActor.assumeIsolated { try? app.store?.setTaskStatus(item.entityId, .done) } }
                undoManager?.setActionName(L("Yeniden aç"))
            }
            return
        }
        let ok: Void? = app.perform(title: L("Tamamlanamadı"), context: "yapilacak.tamamla") {
            switch item.kind {
            case .task: try store.setTaskStatus(item.entityId, .done)
            case .record: try setRecordStatus(item.entityId, .done)
            }
        }
        guard ok != nil else { return }
        // ⌘Z (Düzen › Geri Al): tamamlanan işi önceki durumuna döndürür.
        undoManager?.registerUndo(withTarget: app) { _ in MainActor.assumeIsolated { restore(item) } }
        undoManager?.setActionName(L("Tamamla"))
        lingering[item.id] = item
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            lingering[item.id] = nil
        }
    }

    /// Geri aç: önceki durumuna (kutu ve ⌘Z aynı yolu kullanır).
    private func restore(_ item: TodoItem) {
        guard let store = app.store else { return }
        let ok: Void? = app.perform(context: "yapilacak.geri-ac") {
            switch item.kind {
            case .task(let s): try store.setTaskStatus(item.entityId, s == .done ? .todo : s)   // biten görev "yapılacak"a döner
            case .record(_, let s): try setRecordStatus(item.entityId, s)
            }
        }
        if ok != nil { lingering[item.id] = nil }
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


/// Görev kartı sürüklenebilir (kimliği metin olarak taşır); söz/karar/talep sürüklenmez.
private struct DragIfTask: ViewModifier {
    let item: TodoItem
    @ViewBuilder func body(content: Content) -> some View {
        if case .task = item.kind { content.draggable(item.entityId) } else { content }
    }
}

/// Yeni görev kartı ("Görev ekle" açılır penceresi): başlık, tür, tarih çipleri, öncelik ve en üstte yapay zekâya sorma.
struct NewTaskCard: View {
    @Environment(AppModel.self) private var app
    let brand: Brand
    @Binding var isPresented: Bool
    @State private var title = ""
    @State private var kind = Kind.task
    @State private var due = Due.none
    @State private var pickedDay = Date()
    @State private var priority = 0
    @FocusState private var focused: Bool

    enum Kind { case task, promise }
    enum Due: Hashable { case none, today, tomorrow, week, pick }

    private var day: String? {
        let cal = StatusService.turkishCalendar
        switch due {
        case .none: return nil
        case .today: return DayString.from(Date())
        case .tomorrow: return DayString.from(cal.date(byAdding: .day, value: 1, to: Date())!)
        case .week: return DayString.from(cal.date(byAdding: .day, value: 7, to: Date())!)
        case .pick: return DayString.from(pickedDay)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button { isPresented = false; app.askAI(ChatPrompts.whatToDo) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles").font(.system(size: 14, weight: .semibold)).foregroundStyle(BrandTintStyle(key: brand.id))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L("Yapay zekâya sor: Ne yapmalıyım?")).font(.system(size: 12, weight: .semibold))
                        Text(L("Tüm kayıtları okur, görev önerir")).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.right").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(BrandTintStyle(key: brand.id).opacity(0.12)))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            Rectangle().fill(Design.line).frame(height: 1)
            VStack(alignment: .leading, spacing: 6) {
                TextField(kind == .task ? L("Görev adı") : L("Verdiğin söz"), text: $title)
                    .textFieldStyle(.plain).font(.system(size: 18, weight: .semibold)).focused($focused).onSubmit(add)
                SegmentedChoice(options: [(Kind.task, L("Görev")), (Kind.promise, L("Söz"))], selection: $kind)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Son tarih")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    chip(L("Yok"), .none); chip(L("Bugün"), .today); chip(L("Yarın"), .tomorrow); chip(L("1 hafta"), .week); chip(L("Seç…"), .pick)
                }
                if due == .pick { DatePicker("", selection: $pickedDay, displayedComponents: .date).labelsHidden().datePickerStyle(.compact) }
            }
            if kind == .task {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Öncelik")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    SegmentedChoice(options: [(0, L("Normal")), (2, L("Orta")), (3, L("Yüksek"))], selection: $priority)
                }
            }
            HStack {
                Spacer()
                Button(L("Vazgeç")) { isPresented = false }.actionSecondary().keyboardShortcut(.cancelAction)
                Button(L("Ekle"), action: add).actionPrimary().keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(18).frame(width: 340)
        .onAppear { focused = true }
    }

    private func chip(_ text: String, _ value: Due) -> some View {
        let on = due == value
        return Button { due = value } label: {
            Text(text).font(.system(size: 11, weight: on ? .semibold : .regular)).foregroundStyle(on ? AnyShapeStyle(Design.accent) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(on ? AnyShapeStyle(Design.accent.opacity(0.14)) : AnyShapeStyle(Design.panel)))
        }
        .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
    }

    private func add() {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let store = app.store else { return }
        let ok: Void? = app.perform(title: L("Eklenemedi"), context: "yapilacak.ekle") {
            switch kind {
            case .task: _ = try store.saveTask(WorkTask(brandId: brand.id, title: t, priority: priority, dueDate: day))
            case .promise: _ = try store.saveRecord(BrandRecord(brandId: brand.id, kind: .promise, title: t, dueDate: day))
            }
        }
        if ok != nil { isPresented = false }
    }
}
