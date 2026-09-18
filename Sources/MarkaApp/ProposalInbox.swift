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

    var body: some View {
        let count = app.approvalCount(brand.id)
        if count > 0 {
            HStack(spacing: Design.Space.s) {
                Text(verbatim: "\(count)").monospacedDigit().foregroundStyle(Design.accent)
                Text(L("onay bekliyor"))
                Spacer(minLength: Design.Space.s)
                Button(L("İncele")) { app.brandSheet = .approvals(brand.id) }
                    .buttonStyle(.text)
            }
            .accessibilityElement(children: .combine)
            .padding(.horizontal, Design.Space.m).padding(.vertical, Design.Space.s)
            .background(RoundedRectangle(cornerRadius: Design.radius).fill(Design.bandBackground))
            .overlay(RoundedRectangle(cornerRadius: Design.radius).strokeBorder(Design.line))
        }
    }
}

/// İnceleme sayfası: bekleyen her öneri ve klasördeki her yeni dosya bir satır (varsayılan seçili); terminal önerisinin
/// başlığı ve son tarihi düzeltilebilir. *Seçilenleri onayla* yalnız seçilenleri onaylar; **seçilmeyenler bekler kalır**
/// (U9). *Tümünü reddet* ayrı ve onaylıdır (dosyalar reddedilmez; klasörde kalır). Onaylananlar Akış'ta satır olur ve
/// oradan geri alınır.
struct ApprovalSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let brand: Brand
    @State private var rows: [ApprovalRow]
    @State private var confirmRejectAll = false

    init(brand: Brand, pending: PendingApprovals, files: [URL] = []) {
        self.brand = brand
        _rows = State(initialValue: ApprovalRow.rows(pending, files: files))
    }

    private var proposalCount: Int { rows.filter { $0.source != .folder }.count }
    private var folder: URL? { try? app.folders?.folder(for: .brand(brand.id)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(Design.Space.l)
            Divider()
            PageScroll {
                VStack(alignment: .leading, spacing: Design.Space.l) {
                    if rows.isEmpty {
                        EmptyStateView(message: L("Onay bekleyen bir şey yok."))
                    } else {
                        ForEach(ApprovalRow.Group.allCases, id: \.self) { group in
                            let indices = rows.indices.filter { rows[$0].group == group }
                            if !indices.isEmpty {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(group.title).captionStyle().padding(.bottom, Design.Space.xs)
                                        .accessibilityAddTraits(.isHeader)
                                    ForEach(indices, id: \.self) { i in ApprovalRowView(row: $rows[i], folder: folder) }
                                }
                            }
                        }
                    }
                }
                .padding(Design.Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer.padding(.horizontal, Design.Space.l).padding(.vertical, Design.Space.m)
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 440, idealHeight: 600)
        .confirmationDialog(LF("%d öneri reddedilsin mi?", proposalCount), isPresented: $confirmRejectAll) {
            Button(L("Tümünü reddet"), role: .destructive) { rejectAll() }
        } message: {
            Text(L("Hiçbiri eklenmez; bu karar geri alınamaz. Klasördeki yeni dosyalar listede kalır."))
        }
    }

    /// Başlık + tek görünür cümle (açıklama paragrafı ve dosya yolu yok).
    private var header: some View {
        VStack(alignment: .leading, spacing: Design.Space.xs) {
            Text(L("Onay bekliyor")).font(Design.Font.title)
            Text(L("Onayladıkların eklenir; Akış'tan geri alabilirsin.")).captionStyle()
        }
    }

    private var footer: some View {
        HStack(spacing: Design.Space.m) {
            Button(L("Tümünü reddet…")) { confirmRejectAll = true }
                .buttonStyle(.text)
                .disabled(proposalCount == 0)
            Spacer()
            Button(L("Vazgeç")) { dismiss() }
                .buttonStyle(.text).keyboardShortcut(.cancelAction)
            let selected = rows.filter(\.include)
            Button(LF("Seçilenleri onayla (%d)", selected.count)) { approveSelected() }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty || selected.contains { $0.editableTitle && $0.title.trimmingCharacters(in: .whitespaces).isEmpty })
                .help(L("Seçilenler onaylanır; seçilmeyenler onay bekler."))
        }
    }

    /// Yalnız seçilenler karara girer; seçilmeyenler veri tabanında (ya da klasörde) bekler. Terminal önerileri tek işlemde
    /// (`decideSuggestions`), uygulama içi öneriler ve hafıza güncellemeleri tek tek, dosyalar klasörden eklenerek.
    private func approveSelected() {
        guard let store = app.store else { return }
        let chosen = rows.filter(\.include)
        let ok: Void? = app.perform(title: L("Öneriler onaylanamadı"), context: "oneri.onay") {
            let terminal = chosen.filter { $0.source == .terminal }
            if !terminal.isEmpty {
                let decisions = terminal.map { r in
                    SuggestionDecision(proposalId: r.id, accept: true,
                                       title: r.editableTitle && r.title != r.originalTitle ? r.title : nil,
                                       changeDueDate: r.hasDueDate && r.dueDate != r.originalDueDate, dueDate: r.dueDate)
                }
                _ = try store.decideSuggestions(brandId: brand.id, decisions: decisions)
            }
            for r in chosen where r.source == .app { _ = try store.applyProposal(r.id) }
            for r in chosen where r.source == .knowledge { try store.approveRevision(r.id) }
            let dir = try app.folders?.folder(for: .brand(brand.id))
            for r in chosen where r.source == .folder {
                guard let url = r.file else { continue }
                _ = try store.addFileSource(brandId: brand.id, fileURL: url, kind: .workOutput, confineTo: dir)
                app.newFiles[brand.id]?.removeAll { $0 == url }
            }
        }
        finish(ok)
    }

    /// Önerilerin hepsi reddedilir (dosyalar klasörde kalır).
    private func rejectAll() {
        guard let store = app.store else { return }
        let ok: Void? = app.perform(title: L("Öneriler reddedilemedi"), context: "oneri.ret") {
            let terminal = rows.filter { $0.source == .terminal }
            if !terminal.isEmpty {
                _ = try store.decideSuggestions(brandId: brand.id, decisions: terminal.map { SuggestionDecision(proposalId: $0.id, accept: false) })
            }
            for r in rows where r.source == .app { try store.rejectProposal(r.id) }
            for r in rows where r.source == .knowledge { try store.rejectRevision(r.id) }
        }
        finish(ok)
    }

    private func finish(_ ok: Void?) {
        guard ok != nil else {
            // Yarıda kalan karar: sayfa veri tabanındaki güncel bekleyenlerle yenilenir.
            rows = ApprovalRow.rows((try? app.store?.pendingApprovals(brandId: brand.id)) ?? PendingApprovals(),
                                    files: app.newFiles[brand.id] ?? [])
            return
        }
        dismiss()
    }
}

/// İnceleme sayfasındaki bir satır: terminal önerisi, uygulama içi öneri, hafıza güncellemesi ya da klasördeki yeni dosya.
struct ApprovalRow: Identifiable {
    enum Source { case terminal, app, knowledge, folder }
    /// Önerinin sonuçta görüneceği yere göre gruplar.
    enum Group: CaseIterable {
        case todo, workLogs, notes, files, knowledge
        var title: String {
            switch self {
            case .todo: L("Yapılacaklar")
            case .workLogs: L("İş kayıtları")
            case .notes: L("Notlar")
            case .files: L("Dosyalar")
            case .knowledge: L("Hafıza güncellemeleri")
            }
        }
    }

    let id: String
    let source: Source
    let proposal: AIProposal?
    let revision: WikiRevision?
    /// Klasördeki yeni dosya (yalnız `.folder`).
    var file: URL? = nil
    var include = true
    var title: String
    var dueDate: String?
    let originalTitle: String
    let originalDueDate: String?

    var group: Group {
        if source == .folder { return .files }
        guard let p = proposal else { return .knowledge }
        switch p.kind {
        case .createTask, .completeTask, .createBrandRecord: return .todo
        case .createWorkLog: return .workLogs
        case .createNote: return .notes
        case .createOutput: return .files
        case .wikiRevision: return .knowledge
        }
    }
    /// Başlık ve son tarih yalnızca terminal önerisinde düzeltilir (çekirdekteki `decideSuggestions` yolu).
    var editableTitle: Bool { source == .terminal && proposal?.kind != .completeTask }
    var hasDueDate: Bool { source == .terminal && (proposal?.kind == .createTask || proposal?.kind == .createBrandRecord) }

    static func rows(_ pending: PendingApprovals, files: [URL] = []) -> [ApprovalRow] {
        let terminal = pending.suggestions.sorted {
            $0.suggestionOrder == $1.suggestionOrder ? $0.createdAt < $1.createdAt : $0.suggestionOrder < $1.suggestionOrder
        }
        return terminal.map { row($0, source: .terminal) } + pending.proposals.map { row($0, source: .app) }
            + pending.revisions.map { r in
                ApprovalRow(id: r.id, source: .knowledge, proposal: nil, revision: r, title: "", dueDate: nil, originalTitle: "", originalDueDate: nil)
            }
            + files.map { url in
                ApprovalRow(id: "dosya:" + url.path, source: .folder, proposal: nil, revision: nil, file: url,
                            title: url.lastPathComponent, dueDate: nil, originalTitle: url.lastPathComponent, originalDueDate: nil)
            }
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
    /// Marka klasörü (yeni dosyanın göreli yolu için).
    var folder: URL? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Design.Space.s) {
            CheckBox(isOn: $row.include, label: displayTitle)
            VStack(alignment: .leading, spacing: Design.Space.xs) {
                if row.editableTitle {
                    InputField(title: L("Başlık"), text: $row.title)
                } else {
                    Text(displayTitle).lineLimit(1).truncationMode(.middle)
                }
                ForEach(details, id: \.self) { line in
                    Text(line).captionStyle().lineLimit(3)
                }
                if row.hasDueDate { OptionalDayPicker(title: L("Son tarih"), day: $row.dueDate).controlSize(.small) }
            }
            .disabled(!row.include)
            .opacity(row.include ? 1 : 0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Design.Space.s)
        .overlay(alignment: .bottom) { Rectangle().fill(Design.line).frame(height: 1) }
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

    var details: [String] {
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
        case .wikiRevision:
            break
        }
        return out
    }
}
