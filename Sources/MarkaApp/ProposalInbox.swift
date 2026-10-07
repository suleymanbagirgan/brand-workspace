import AppKit
import MarkaCore
import SwiftUI

// Onay tek yerde (0.2.1 U2, U9): onay bandı ve inceleme sayfası. Terminal önerileri (`oneriler/*.json`, İ7), uygulama
// içinde oluşmuş bekleyen öneriler, hafıza güncellemeleri ve marka klasöründeki eklenmemiş dosyalar aynı sayfada;
// fiiller her yerde aynı: Onayla · Reddet · Geri al.

/// "N onay bekliyor · İncele". Marka ekranında sekmelerin üstünde; bekleyen yoksa görünmez. Tek kutu istisnası.
/// Sayı: bekleyen öneriler + klasördeki eklenmemiş dosyalar.
struct ApprovalBand: View {
    @Environment(AppModel.self) private var app
    let brand: Brand

    @ViewBuilder var body: some View {
        // Onaydan sonra "Geri al" bildirimi (H3-05); bekleyen kalmasa da görünür. İkisi de yoksa bant hiç yer kaplamaz.
        if let offer = ApprovalUndoCenter.shared.offers[brand.id] {
            VStack(alignment: .leading, spacing: Design.Space.s) {
                ApprovalUndoToast(brandId: brand.id, offer: offer)
                pill
            }
        } else {
            pill
        }
    }

    @ViewBuilder private var pill: some View {
        let count = app.approvalCount(brand.id)
        if count > 0 {
            // v3: kutu yok; tek satırlık, marka renginde yumuşak hap (tıklanınca inceleme açılır).
            Button { app.brandSheet = .approvals(brand.id) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill").font(Design.Icon.medium).foregroundStyle(Design.accent)
                    Text(LF("%d onay seni bekliyor", count)).font(Design.Font.body.weight(.medium))
                    Spacer(minLength: 8)
                    Text(L("İncele")).font(Design.Font.callout.weight(.semibold)).foregroundStyle(Design.accent)
                    Image(systemName: "chevron.right").font(Design.Icon.small.weight(.semibold)).foregroundStyle(Design.accent)
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(Capsule().fill(Design.accent.opacity(0.10)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(LF("%d onay seni bekliyor", count))
            .accessibilityHint(L("İncelemeyi açar"))
        }
    }
}

/// İnceleme sayfası (H3-05 onay ritüeli): bekleyen her öneri ve klasördeki her yeni dosya bir satır. **Varsayılan seçim
/// boştur** (kural 3: hiçbir öneri kendiliğinden onaylı gelmez). Klavye: ↑↓ satır · Boşluk seç/bırak · ⌘A tümü · ⌘↩ seçilenleri
/// onayla · ⌫ seçilenleri reddet (onaylı). Mevcut kaydı değiştiren öneri ayrı onay adımı ister. Seçim, yıkıcı ayrımı, toplu
/// sonuç ve geri alma kapsamı çekirdekte (`ProposalSelection`, `ApprovalBatch`, `ApprovalUndoScope`); burası ince kabuk.
struct ApprovalSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let brand: Brand
    @State private var rows: [ApprovalRow]
    @State private var selection: ProposalSelection
    @State private var confirmRejectAll = false
    @State private var confirmRejectSelected = false
    @State private var confirmDestructive = false
    @FocusState private var listFocused: Bool

    init(brand: Brand, pending: PendingApprovals, files: [URL] = []) {
        self.brand = brand
        let rows = ApprovalRow.rows(pending, files: files)
        _rows = State(initialValue: rows)
        _selection = State(initialValue: ProposalSelection(items: rows.map(\.item)))
    }

    private var proposalCount: Int { rows.filter { $0.source != .folder }.count }
    private var folder: URL? { try? app.folders?.folder(for: .brand(brand.id)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.horizontal, 28).padding(.top, 26).padding(.bottom, Design.Space.m)
            PageScroll {
                list
                    .padding(.horizontal, 28).padding(.vertical, Design.Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer.padding(.horizontal, 28).padding(.vertical, 14)
        }
        .frame(minWidth: 620, idealWidth: 700, minHeight: 460, idealHeight: 640)
        // Açılışta ilk odak düzenlenebilir başlıkta değil, listede (klavye hemen ↑↓/Boşluk alır).
        .onAppear {
            OpeningFocus.clearTextFocus()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { listFocused = true }
        }
        .confirmationDialog(LF("%d öneri reddedilsin mi?", proposalCount), isPresented: $confirmRejectAll) {
            Button(L("Tümünü reddet"), role: .destructive) { reject(rows.map(\.item)) }
        } message: {
            Text(L("Hiçbiri eklenmez; bu karar geri alınamaz. Klasördeki yeni dosyalar listede kalır."))
        }
        .confirmationDialog(LF("Seçilen öneriler reddedilsin mi? Sayı: %d", selection.rejectableSelected.count), isPresented: $confirmRejectSelected) {
            Button(L("Reddet"), role: .destructive) { reject(selection.rejectableSelected) }
        } message: {
            Text(L("Reddedilenler eklenmez; bu karar geri alınamaz. Seçilen dosyalar klasörde kalır."))
        }
        .confirmationDialog(LF("Mevcut kaydı değiştiren öneri: %d", selection.destructiveSelected.count), isPresented: $confirmDestructive) {
            Button(L("Değişiklikleri de uygula"), role: .destructive) { approveSelected(destructiveConfirmed: true) }
            Button(L("Yalnız yeni kayıtları uygula")) { approveSelected(destructiveConfirmed: false) }
        } message: {
            Text(L("Bu öneriler markadaki mevcut görevleri değiştirir (bitirme ya da düzenleme). Uygulanırsa bildirimdeki “Geri al” ile önceki hâline döner."))
        }
    }

    // MARK: Liste ve klavye

    private var list: some View {
        VStack(alignment: .leading, spacing: Design.Space.l) {
            if rows.isEmpty {
                EmptyStateView(title: L("Her şey onaylandı"), message: L("Onay bekleyen bir şey yok."), symbol: "checkmark.seal")
            } else {
                ForEach(ApprovalRow.Group.allCases, id: \.self) { group in
                    let indices = rows.indices.filter { rows[$0].group == group }
                    if !indices.isEmpty { groupSection(group, indices: indices) }
                }
            }
        }
        .focusable().focusEffectDisabled()
        .focused($listFocused)
        .onKeyPress(phases: .down) { press in handleKey(press) }
        .accessibilityHint(L("Ok tuşlarıyla satır değiştir, Boşlukla seç, Komut Return ile onayla, Sil ile reddet."))
    }

    private func groupSection(_ group: ApprovalRow.Group, indices: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: group.symbol).font(Design.Icon.small.weight(.semibold)).foregroundStyle(.secondary)
                Text(group.title).font(Design.Font.callout.weight(.semibold))
                Text(verbatim: "\(indices.count)").font(Design.Font.small).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(indices, id: \.self) { i in
                    if i != indices.first { Rectangle().fill(Design.line).frame(height: 1) }
                    let id = rows[i].id
                    ApprovalRowView(row: $rows[i], isSelected: selection.isSelected(id),
                                    isCursor: listFocused && selection.cursor == id,
                                    onToggle: { selection.setCursor(id); selection.toggle(id) },
                                    folder: folder, tintKey: brand.id)
                }
            }
            .flatList()
        }
    }

    /// Satır sırası görünen sırayla aynı olsun diye imleç gruplanmış sırada gezer.
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        let command = press.modifiers.contains(.command)
        switch press.key {
        case .upArrow where !command: selection.moveCursor(by: -1); return .handled
        case .downArrow where !command: selection.moveCursor(by: 1); return .handled
        case .space where !command: selection.toggleAtCursor(); return .handled
        case .delete, .deleteForward:
            if !selection.rejectableSelected.isEmpty { confirmRejectSelected = true }
            return .handled
        default:
            if command, press.characters.lowercased() == "a" { selection.selectAll(); return .handled }
            return .ignored
        }
    }

    // MARK: Başlık ve alt çubuk

    /// Başlık: marka renginde simge rozeti, ad, tek cümle ve (varsa) bekleyen sayısı.
    private var header: some View {
        let tint = BrandTintStyle(key: brand.id)
        return HStack(alignment: .center, spacing: 14) {
            Image(systemName: "checkmark.seal.fill").font(Design.Icon.large.weight(.semibold)).foregroundStyle(tint)
                .frame(width: 48, height: 48).background(RoundedRectangle(cornerRadius: Design.Radius.large, style: .continuous).fill(tint.opacity(0.14)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Onay bekliyor")).font(Design.Font.title.weight(.bold)).tracking(-0.5).accessibilityAddTraits(.isHeader)
                Text(LF("%1$@ · Seçip onayladıkların eklenir; Özet'ten geri alabilirsin.", brand.name)).font(Design.Font.callout).foregroundStyle(.secondary).lineLimit(1)
                // Üstteki sayı tüm grupları sayar; liste kaydırılmadan görünmeyen gruplar da burada adıyla görünür.
                if !rows.isEmpty {
                    Text(groupSummary).font(Design.Font.small.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Text(verbatim: "\(rows.count)").font(Design.Font.display.weight(.semibold)).monospacedDigit().foregroundStyle(tint)
                .accessibilityLabel(LF("Toplam onay bekleyen: %d", rows.count))
        }
    }

    /// "Yapılacaklar 3 · İş kayıtları 1 · Notlar 1": üstteki toplamın dökümü (aynı satırları sayar).
    private var groupSummary: String {
        ApprovalRow.Group.allCases.compactMap { group in
            let n = rows.filter { $0.group == group }.count
            return n > 0 ? "\(group.title) \(n)" : nil
        }.joined(separator: " · ")
    }

    private var footer: some View {
        HStack(spacing: Design.Space.m) {
            // Yıkıcı eylem kırmızı ve onay iletişimiyle (gp-8).
            Button { confirmRejectAll = true } label: {
                Text(L("Tümünü reddet…")).foregroundStyle(proposalCount == 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(Design.danger))
            }
            .buttonStyle(.text)
            .disabled(proposalCount == 0)
            Button(selection.allSelected ? L("Seçimi kaldır") : L("Tümünü seç")) {
                if selection.allSelected { selection.clearSelection() } else { selection.selectAll() }
            }
            .buttonStyle(.text).disabled(rows.isEmpty)
            .help(L("Tümünü seç (⌘A)"))
            Spacer()
            Button(L("Vazgeç")) { dismiss() }
                .actionSecondary().keyboardShortcut(.cancelAction)
            // Düz Return onaylamaz (yanlışlıkla toplu onay olmasın); ⌘↩ gerekir.
            Button(LF("Seçilenleri onayla (%d)", selection.selectedItems.count)) { requestApprove() }
                .actionPrimary().keyboardShortcut(.return, modifiers: .command)
                .disabled(!canApprove)
                .help(L("Seçilenler onaylanır; seçilmeyenler onay bekler (⌘↩)."))
        }
    }

    private var selectedRows: [ApprovalRow] { rows.filter { selection.isSelected($0.id) } }
    private var canApprove: Bool {
        let chosen = selectedRows
        return !chosen.isEmpty && !chosen.contains { $0.editableTitle && $0.title.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    // MARK: Karar

    private func requestApprove() {
        guard canApprove else { return }
        if selection.destructiveSelected.isEmpty { approveSelected(destructiveConfirmed: false) } else { confirmDestructive = true }
    }

    /// Yalnız seçilenler karara girer; seçilmeyenler bekler. Her satır kendi işleminde uygulanır: biri başarısız olursa
    /// diğerleri yine uygulanır (`ApprovalBatch`). Her uygulama denetim olayını çekirdekteki yazma yolunda bırakır.
    private func approveSelected(destructiveConfirmed: Bool) {
        guard let store = app.store else { return }
        let brandId = brand.id
        let byId = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let dir = try? app.folders?.folder(for: .brand(brandId))
        let result = ApprovalBatch.run(selection.selectedItems, destructiveConfirmed: destructiveConfirmed) { item in
            guard let r = byId[item.id] else { return }
            switch r.source {
            case .terminal:
                let decision = SuggestionDecision(proposalId: r.id, accept: true,
                                                  title: r.editableTitle && r.title != r.originalTitle ? r.title : nil,
                                                  changeDueDate: r.hasDueDate && r.dueDate != r.originalDueDate, dueDate: r.dueDate)
                _ = try store.decideSuggestions(brandId: brandId, decisions: [decision])
            case .app: _ = try store.applyProposal(r.id)
            case .knowledge: try store.approveRevision(r.id)
            case .folder:
                guard let url = r.file else { return }
                _ = try store.addFileSource(brandId: brandId, fileURL: url, kind: .workOutput, confineTo: dir)
                app.newFiles[brandId]?.removeAll { $0 == url }
            }
        }
        if !result.succeeded.isEmpty { ApprovalUndoCenter.shared.offer(brandId: brandId, scope: result.undo) }
        finish(result, failureTitle: L("Bazı öneriler onaylanamadı"))
    }

    private func reject(_ items: [ApprovalItem]) {
        guard let store = app.store else { return }
        let brandId = brand.id
        let byId = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let result = ApprovalBatch.reject(items) { item in
            guard let r = byId[item.id] else { return }
            switch r.source {
            case .terminal: _ = try store.decideSuggestions(brandId: brandId, decisions: [SuggestionDecision(proposalId: r.id, accept: false)])
            case .app: try store.rejectProposal(r.id)
            case .knowledge: try store.rejectRevision(r.id)
            case .folder: break
            }
        }
        finish(result, failureTitle: L("Bazı öneriler reddedilemedi"))
    }

    /// Sonuçlananlar listeden düşer. Hepsi bitti ve bekleyen ek onay yoksa sayfa kapanır; hata varsa satırlar veri
    /// tabanındaki güncel hâliyle yenilenir ve hata gösterilir.
    private func finish(_ result: ApprovalBatchResult, failureTitle: String) {
        let done = Set(result.succeeded.map(\.id))
        rows.removeAll { done.contains($0.id) }
        selection.remove(done)
        if !result.failures.isEmpty {
            let fresh = ApprovalRow.rows(app.read(or: PendingApprovals()) { try $0.pendingApprovals(brandId: brand.id) },
                                         files: app.newFiles[brand.id] ?? [])
            let keep = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            rows = fresh.map { keep[$0.id] ?? $0 }
            selection.replaceItems(rows.map(\.item))
            let lines = result.failures.map(\.message)
            app.show(error: MarkaError.validation(lines.joined(separator: "\n")), title: failureTitle, context: "oneri.toplu")
            return
        }
        if result.awaitingConfirmation.isEmpty && (rows.isEmpty || !done.isEmpty) { dismiss() }
    }
}

/// Onaydan sonraki "Geri al" bildirimi. Sayfa kapandığı için bildirim marka ekranındaki onay bandının yerinde durur;
/// marka başına son toplu onayı tutar, bir süre sonra kalkar.
@MainActor @Observable final class ApprovalUndoCenter {
    static let shared = ApprovalUndoCenter()
    struct Offer: Identifiable, Equatable {
        let id = UUID()
        let scope: ApprovalUndoScope
    }
    private(set) var offers: [String: Offer] = [:]

    func offer(brandId: String, scope: ApprovalUndoScope) {
        guard scope.appliedCount > 0 else { return }
        offers[brandId] = Offer(scope: scope)
    }

    func dismiss(brandId: String, id: UUID? = nil) {
        if id == nil || offers[brandId]?.id == id { offers[brandId] = nil }
    }
}

/// "Uygulanan öneri: N · Geri al". Düğme yalnız gerçekten geri alınabilen satır varsa görünür; geri alınamayanlar sayıyla söylenir.
struct ApprovalUndoToast: View {
    @Environment(AppModel.self) private var app
    let brandId: String
    let offer: ApprovalUndoCenter.Offer

    var body: some View {
        HStack(spacing: Design.Space.s) {
            Image(systemName: "checkmark.circle").foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(LF("Uygulanan öneri: %d", offer.scope.appliedCount)).font(Design.Font.callout.weight(.medium))
                if offer.scope.notUndoableCount > 0 {
                    Text(LF("Buradan geri alınamayan: %d", offer.scope.notUndoableCount)).font(Design.Font.small).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if offer.scope.showsUndo {
                Button(L("Geri al")) { undo() }
                    .actionSecondary()
                    .help(L("Bu onayla eklenenleri önceki hâline döndürür"))
            }
            Button { ApprovalUndoCenter.shared.dismiss(brandId: brandId) } label: { Image(systemName: "xmark").font(Design.Icon.small) }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help(L("Kapat")).accessibilityLabel(L("Bildirimi kapat"))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: Design.Radius.small, style: .continuous).fill(Design.panel))
        .accessibilityElement(children: .contain)
        .task(id: offer.id) {
            try? await Task.sleep(for: .seconds(15))
            if !Task.isCancelled { ApprovalUndoCenter.shared.dismiss(brandId: brandId, id: offer.id) }
        }
    }

    /// Ters sırayla, her öneri kendi işleminde ve marka kapsamıyla geri alınır (`revertSuggestions` denetim olayı bırakır).
    private func undo() {
        guard let store = app.store else { return }
        let brandId = brandId
        let outcome = offer.scope.revert { id in try store.revertSuggestions(brandId: brandId, proposalIds: [id]) }
        ApprovalUndoCenter.shared.dismiss(brandId: brandId)
        if !outcome.failures.isEmpty {
            app.show(error: MarkaError.validation(outcome.failures.values.sorted().joined(separator: "\n")),
                     title: L("Bazı öneriler geri alınamadı"), context: "oneri.geriAl")
        }
    }
}

/// İnceleme sayfasındaki bir satır: terminal önerisi, uygulama içi öneri, hafıza güncellemesi ya da klasördeki yeni dosya.
struct ApprovalRow: Identifiable {
    enum Source { case terminal, app, knowledge, folder }
    /// Önerinin sonuçta görüneceği yere göre gruplar.
    enum Group: CaseIterable {
        case todo, workLogs, notes, files, knowledge, team
        var symbol: String {
            switch self {
            case .todo: "checklist"
            case .workLogs: "seal"
            case .notes: "note.text"
            case .files: "doc"
            case .knowledge: "text.book.closed"
            case .team: "person.badge.plus"
            }
        }
        var title: String {
            switch self {
            case .todo: L("Yapılacaklar")
            case .workLogs: L("İş kayıtları")
            case .notes: L("Notlar")
            case .files: L("Dosyalar")
            case .knowledge: L("Hafıza güncellemeleri")
            case .team: L("Ekip")
            }
        }
    }

    let id: String
    let source: Source
    let proposal: AIProposal?
    let revision: WikiRevision?
    /// Klasördeki yeni dosya (yalnız `.folder`).
    var file: URL? = nil
    var title: String
    var dueDate: String?
    let originalTitle: String
    let originalDueDate: String?

    var group: Group {
        if source == .folder { return .files }
        guard let p = proposal else { return .knowledge }
        switch p.kind {
        case .createTask, .completeTask, .updateTask, .createBrandRecord: return .todo
        case .createWorkLog: return .workLogs
        case .createNote: return .notes
        case .createOutput: return .files
        case .wikiRevision, .createObservation: return .knowledge
        case .createTeamMember: return .team
        }
    }
    /// Başlık ve son tarih yalnızca terminal önerisinde düzeltilir (çekirdekteki `decideSuggestions` yolu).
    var editableTitle: Bool { source == .terminal && proposal?.kind != .completeTask && proposal?.kind != .updateTask }
    var hasDueDate: Bool { source == .terminal && (proposal?.kind == .createTask || proposal?.kind == .createBrandRecord) }
    /// Çekirdekteki seçim/yıkıcı/geri alma kurallarının gördüğü hâli.
    var item: ApprovalItem {
        switch source {
        case .folder: ApprovalItem(id: id, kind: .folderFile)
        case .knowledge: ApprovalItem(id: id, kind: .knowledge)
        case .terminal, .app: ApprovalItem(id: id, kind: proposal.map { .proposal($0.kind) } ?? .knowledge)
        }
    }
    var isDestructive: Bool { ApprovalPolicy.isDestructive(item.kind) }

    static func rows(_ pending: PendingApprovals, files: [URL] = []) -> [ApprovalRow] {
        let terminal = pending.suggestions.sorted {
            $0.suggestionOrder == $1.suggestionOrder ? $0.createdAt < $1.createdAt : $0.suggestionOrder < $1.suggestionOrder
        }
        let all = terminal.map { row($0, source: .terminal) } + pending.proposals.map { row($0, source: .app) }
            + pending.revisions.map { r in
                ApprovalRow(id: r.id, source: .knowledge, proposal: nil, revision: r, title: "", dueDate: nil, originalTitle: "", originalDueDate: nil)
            }
            + files.map { url in
                ApprovalRow(id: "dosya:" + url.path, source: .folder, proposal: nil, revision: nil, file: url,
                            title: url.lastPathComponent, dueDate: nil, originalTitle: url.lastPathComponent, originalDueDate: nil)
            }
        // Satır sırası görünen (gruplu) sırayla aynı: klavye imleci ekranda göründüğü sırayla gezer. Grup içi sıra korunur.
        let order = Dictionary(uniqueKeysWithValues: Group.allCases.enumerated().map { ($1, $0) })
        return all.enumerated().sorted { (order[$0.element.group]!, $0.offset) < (order[$1.element.group]!, $1.offset) }.map(\.element)
    }

    private static func row(_ p: AIProposal, source: Source) -> ApprovalRow {
        let (title, due) = titleAndDue(p)
        return ApprovalRow(id: p.id, source: source, proposal: p, revision: nil, title: title, dueDate: due, originalTitle: title, originalDueDate: due)
    }

    static func titleAndDue(_ p: AIProposal) -> (String, String?) {
        switch p.kind {
        case .createTask:
            let x = p.payload(ProposalPayload.CreateTask.self)
            return (x?.title ?? p.summary, x?.dueDate)
        case .createBrandRecord:
            let x = p.payload(ProposalPayload.CreateBrandRecord.self)
            return (x?.title ?? p.summary, x?.dueDate)
        default:
            return (p.displayTitle, nil)
        }
    }
}

struct ApprovalRowView: View {
    @Environment(AppModel.self) private var app
    @Binding var row: ApprovalRow
    let isSelected: Bool
    /// Klavye imleci bu satırda mı (yalnız liste odaktayken).
    var isCursor = false
    var onToggle: () -> Void = {}
    /// Marka klasörü (yeni dosyanın göreli yolu için).
    var folder: URL? = nil
    var tintKey: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            CheckBox(isOn: Binding(get: { isSelected }, set: { _ in onToggle() }), label: displayTitle).padding(.top, 2)
            Image(systemName: row.group.symbol).font(Design.Icon.medium.weight(.semibold))
                .foregroundStyle(tintKey.map { AnyShapeStyle(BrandTintStyle(key: $0)) } ?? AnyShapeStyle(Design.accent))
                .frame(width: 32, height: 32)
                .background(Circle().fill((tintKey.map { AnyShapeStyle(BrandTintStyle(key: $0)) } ?? AnyShapeStyle(Design.accent)).opacity(0.13)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                if row.editableTitle {
                    InputField(title: L("Başlık"), text: $row.title)
                } else {
                    Text(displayTitle).font(Design.Font.body.weight(.semibold)).lineLimit(2).truncationMode(.middle)
                }
                // E-17: dış ajan zarfının köken rozeti. Ad yalnız etikettir (çekirdekte tek satıra indirilmiş, ≤ 64 karakter).
                if let p = row.proposal, p.origin == .external {
                    Label(LF("Dış ajan: %@", p.originRef ?? L("adsız")), systemImage: "arrow.down.doc")
                        .font(Design.Font.small.weight(.medium)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                }
                if row.isDestructive {
                    Label(L("Mevcut kaydı değiştirir; ayrıca onay ister"), systemImage: "exclamationmark.triangle")
                        .font(Design.Font.small.weight(.medium)).foregroundStyle(Design.danger)
                }
                ForEach(details, id: \.self) { line in
                    Text(line).font(Design.Font.small).foregroundStyle(.secondary).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
                if row.hasDueDate { OptionalDayPicker(title: L("Son tarih"), day: $row.dueDate).controlSize(.small) }
                if let p = row.proposal { ProposalEvidenceView(proposal: p) } // E-22: dayanak çipleri ve dış ajan gerekçesi
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 14).padding(.horizontal, 16)
        // Tek satır stili: seçili satır vurgu zemini, imleç ince vurgu çerçevesi (gp-7).
        .background(isSelected ? AnyShapeStyle(Design.selection) : AnyShapeStyle(.clear))
        .overlay { if isCursor { RoundedRectangle(cornerRadius: Design.Radius.small).strokeBorder(Design.accent, lineWidth: 1.5) } }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    var displayTitle: String {
        if let r = row.revision { return (try? app.store?.wikiPageDetail(r.pageId).page.title) ?? L("Hafıza sayfası") }
        if let url = row.file { return Self.relative(url, to: folder) }
        return row.title
    }

    /// Marka klasörüne göre yol (ör. `ciktilar/rapor.md`); klasör dışındaysa yalnız ad.
    static func relative(_ url: URL, to folder: URL?) -> String {
        guard let base = folder?.resolvingSymlinksInPath().path else { return url.lastPathComponent }
        let full = url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent).path
        return full.hasPrefix(base + "/") ? String(full.dropFirst(base.count + 1)) : url.lastPathComponent
    }

    /// Öneri bir yapay zekâ çalışanın rolüyle açılmış sohbetten geldiyse "Önerdi: <ad>" satırı eklenir.
    var details: [String] {
        let base = baseDetails
        guard let p = row.proposal, let m = (try? app.store?.proposer(of: p)) ?? nil else { return base }
        return base + [LF("Önerdi: %1$@ (%2$@)", m.name, m.title)]
    }

    private var baseDetails: [String] {
        if row.source == .folder { return [L("Dosya olduğu gibi saklanır ve değiştirilmez.")] }
        if let r = row.revision {
            let isNew = (try? app.store?.wikiPageDetail(r.pageId).current) == nil
            return [isNew ? L("Yeni hafıza sayfası") : LF("%d. sürüm önerisi", r.number), String(r.body.prefix(240))]
        }
        guard let p = row.proposal else { return [] }
        var out: [String] = []
        switch p.kind {
        case .createTask:
            guard let x = p.payload(ProposalPayload.CreateTask.self) else { break }
            var meta: [String] = [L("Görev")]
            if let s = x.status, s != .todo { meta.append(s.title) }
            if let a = x.assignee, !a.isEmpty { meta.append(LF("Sorumlu: %@", a)) }
            if let pid = x.projectId, let name = try? app.store?.projects(brandId: p.brandId).first(where: { $0.id == pid })?.name {
                meta.append(LF("Proje: %@", name))
            }
            out.append(meta.joined(separator: " · "))
            if let n = x.notes, !n.isEmpty { out.append(n) }
        case .completeTask:
            out.append(L("Bu markadaki açık görev bitti olarak işaretlenir."))
        case .updateTask:
            // Önce → sonra (ör. "Son tarih: 12 Eki → 15 Eki"); görev artık değiştiyse ya da bulunamazsa uyarı.
            if let preview = app.store?.proposalPreview(p) {
                out += preview.lines()
            } else {
                out.append(L("Görev değişmiş ya da bulunamadı; bu öneri artık uygulanamaz."))
            }
        case .createBrandRecord:
            if let x = p.payload(ProposalPayload.CreateBrandRecord.self) {
                out.append(x.kind.title)
                if let d = x.detail, !d.isEmpty { out.append(d) }
            }
        case .createNote:
            if let x = p.payload(ProposalPayload.CreateNote.self) {
                out.append(String(x.body.prefix(240)))
                if let d = x.capturedOn { out.append(LF("Tarih: %@", d)) }
            }
        case .createOutput:
            if let x = p.payload(ProposalPayload.CreateOutput.self) { out.append(LF("Dosya: %@", x.fileName)) }
        case .createWorkLog:
            guard let x = p.payload(ProposalPayload.CreateWorkLog.self) else { break }
            out.append(L("“Doğrulanmadı” olarak eklenir; doğrulamayı Akış'ta sen yaparsın."))
            if !x.requested.isEmpty { out.append(LF("Ne istendi: %@", x.requested)) }
            out.append(LF("Ne yapıldı: %@", x.performed))
            if let d = x.decision, !d.isEmpty { out.append(LF("Ne kararlaştırıldı: %@", d)) }
            if let t = x.taskTitle { out.append(LF("Görev: %@", t)) }
            else if let tid = x.taskId, let t = try? app.store?.task(tid) { out.append(LF("Görev: %@", t.title)) }
            let inputs = (x.inputFiles ?? []).map(\.path), outputs = (x.outputFiles ?? []).map(\.path)
            if !inputs.isEmpty { out.append(LF("Girdi dosyaları: %@", inputs.joined(separator: ", "))) }
            if !outputs.isEmpty { out.append(LF("Çıktı dosyaları: %@", outputs.joined(separator: ", "))) }
        case .createTeamMember:
            guard let x = p.payload(ProposalPayload.CreateTeamMember.self) else { break }
            let level = MemberLevel(rawValue: x.level ?? "mid")?.title ?? ""
            out.append([L("Yapay zekâ çalışan"), x.title, level, x.department ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
            if let c = x.charter, !c.isEmpty { out.append(c) }
            if let sk = x.skills, !sk.isEmpty { out.append(LF("Yetenekler: %@", sk.joined(separator: ", "))) }
            if let boss = x.reportsToId, let name = try? app.store?.teamMembers(includeArchived: true).first(where: { $0.id == boss })?.name {
                out.append(LF("Bağlı: %@", name))
            }
        case .createObservation:
            // E-06: gözlem önerisi; çelişen gözlemin yerine geçiyorsa eskisi gösterilir (silinmez, kapatılır).
            guard let x = p.payload(ProposalPayload.CreateObservation.self) else { break }
            out.append(LF("Marka gözlemi · dayandığı kaynak sayısı: %d", Set(x.evidenceSourceIds).count))
            if let oldId = x.supersedesId {
                out.append(L("Var olan bir gözlemin yerine geçer; eskisi silinmez, kapatılır."))
                if let old = (try? app.store?.observations(brandId: p.brandId, includeInvalidated: true))?.first(where: { $0.id == oldId }) {
                    out.append(LF("Yerine geçtiği: %@", old.statement))
                }
            }
        case .wikiRevision:
            break
        }
        return out
    }
}

/// E-22: "Neden bu öneri". Önerinin dayandığı kaynak ve gözlemler küçük çipler, dış ajan önerisinde gerekçe tek satır.
/// Çip yalnız başlık gösterir (içerik önizlemesi yok) ve yalnız önerinin markasından gelir (`Store.proposalEvidence`).
/// Çipler odak almaz: klavye onay ritüeli (↑↓ · Boşluk · ⌘↩ · ⌫) listede kalır (H3-05).
struct ProposalEvidenceView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let proposal: AIProposal

    var body: some View {
        let evidence = app.read(or: ProposalEvidence()) { try $0.proposalEvidence(proposal) }
        VStack(alignment: .leading, spacing: Design.Space.xs) {
            if let r = evidence.rationale {
                Text(LF("Gerekçe: %@", r)).font(Design.Font.small).foregroundStyle(.secondary)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            if evidence.hasEvidence {
                FlowLayout(spacing: Design.Space.s) {
                    ForEach(evidence.chips) { chip($0) }
                }
            } else {
                Label(L("Dayanak yok"), systemImage: "questionmark.circle")
                    .font(Design.Font.small).foregroundStyle(.tertiary)
                    .help(L("Bu öneri markanın bir kaynağına ya da gözlemine dayanmıyor."))
            }
        }
    }

    private func chip(_ c: ProposalEvidence.Chip) -> some View {
        let isSource = c.kind == .source
        return Button { open(c) } label: {
            Label(c.title, systemImage: isSource ? "doc.text" : "lightbulb")
                .font(Design.Font.small.weight(.medium)).lineLimit(1).truncationMode(.tail)
                .padding(.horizontal, Design.Space.s).padding(.vertical, Design.Space.xs)
                .background(Capsule().fill(Design.accent.opacity(0.10)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain).foregroundStyle(Design.accent)
        .focusable(false)
        .help(isSource ? L("Kaynağı açar; onay sayfası kapanır, öneri bekler.") : L("Gözlemleri Marka Bilgileri'nde açar; onay sayfası kapanır, öneri bekler."))
        .accessibilityLabel(isSource ? LF("Dayanak kaynak: %@", c.title) : LF("Dayanak gözlem: %@", c.title))
    }

    /// Kaynak tek yerinde (Akış, sağ panel) açılır; gözlemin ayrı ekranı yok, Marka Bilgileri açılır.
    private func open(_ c: ProposalEvidence.Chip) {
        dismiss()
        switch c.kind {
        case .source: app.open(RecordRef(.source, c.id))
        case .observation: app.select(brand: proposal.brandId, tab: .info)
        }
    }
}
