import AppKit
import MarkaCore
import SwiftUI

// Akış ve Yapılacaklar'ın sağ ayrıntı paneli (~360 pt). Satıra tıklayınca açılır; başlıktaki "Kapat", aynı satıra yeniden
// tıklama, listenin boş yerine tıklama ya da Esc kapatır (VoiceOver: "Paneli kapat" eylemi).
// İş kaydında dolu sorular, bağlı dosyalar, Düzenle ve birincil Doğrula (doğrulamanın tek yeri; içerik görülerek);
// görev ve söz/karar/talepte satır içi düzenleme, açıksa altta İptal et ve Sil…; dosya/notta önizleme, Aç ve Arşivle;
// onaylanmış öneride Geri al. Eylemler içeriğin hemen altındadır.

/// Panelde açılan kayıt.
enum PanelTarget: Hashable {
    case workLog(String), task(String), record(String), source(String), proposal(String)

    init(_ item: FlowItem) {
        switch item.kind {
        case .workLog: self = .workLog(item.entityId)
        case .taskDone: self = .task(item.entityId)
        case .note, .file: self = .source(item.entityId)
        case .recordClosed: self = .record(item.entityId)
        case .proposalApplied: self = .proposal(item.entityId)
        }
    }

    init(_ item: TodoItem) {
        switch item.kind {
        case .task: self = .task(item.entityId)
        case .record: self = .record(item.entityId)
        }
    }
}

enum Panel {
    static let width: CGFloat = 360
    /// İş kaydını doğrulayan: Mac kullanıcısının adı.
    static var verifier: String {
        let name = NSFullUserName().trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? NSUserName() : name
    }
}

/// Liste + (seçim varsa) sağda ayrıntı paneli. Panel açılınca odağı alır; Esc onu kapatır. Başka yerden açılan kayıt
/// (`AppModel.panelTarget`: Bugün, arama, rapor dayanağı) burada karşılanır.
struct ListWithPanel<List: View>: View {
    @Environment(AppModel.self) private var app
    @Binding var selection: PanelTarget?
    @ViewBuilder var list: List
    @FocusState private var panelFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            list.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                // Listenin boş yerine tıklamak paneli kapatır (satırlar ve denetimler kendi tıklamalarını alır).
                .background { Color.clear.contentShape(Rectangle()).onTapGesture { selection = nil } }
            if let target = selection {
                Rectangle().fill(Design.line).frame(width: 1)
                DetailPanel(target: target)
                    .environment(\.panelClose) { selection = nil }
                    .frame(width: Panel.width)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .focusable()
                    .focusEffectDisabled()
                    .focused($panelFocused)
                    .accessibilityElement(children: .contain)
                    .accessibilityAction(.escape) { selection = nil }
                    .accessibilityAction(named: L("Paneli kapat")) { selection = nil }
            }
        }
        .onExitCommand { selection = nil }
        .onChange(of: selection) { _, new in panelFocused = new != nil }
        .onAppear(perform: takeTarget)
        .onChange(of: app.panelTarget) { _, _ in takeTarget() }
    }

    private func takeTarget() {
        guard let target = app.panelTarget else { return }
        selection = target
        app.panelTarget = nil
    }
}

struct DetailPanel: View {
    @Environment(AppModel.self) private var app
    let target: PanelTarget

    var body: some View {
        let _ = app.revision
        PageScroll {
            Group {
                if let store = app.store {
                    switch target {
                    case .workLog(let id):
                        if let d = try? store.workLogDetail(id) { WorkLogPanel(detail: d) } else { missing }
                    case .task(let id):
                        if let t = try? store.task(id) { TaskPanel(task: t).id(id) } else { missing }
                    case .record(let id):
                        if let r = try? store.read({ db in try BrandRecord.fetchOne(db, key: id) }) { RecordPanel(record: r).id(id) } else { missing }
                    case .source(let id):
                        if let s = try? store.source(id) { SourcePanel(source: s) } else { missing }
                    case .proposal(let id):
                        if let p = try? store.read({ db in try AIProposal.fetchOne(db, key: id) }) { ProposalPanel(proposal: p) } else { missing }
                    }
                }
            }
            // Üst boşluk listenin ilk satırıyla aynı hizada (liste üstte Space.s ile başlar).
            .padding(.horizontal, Design.Space.l).padding(.top, Design.Space.s).padding(.bottom, Design.Space.l)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var missing: some View {
        VStack(alignment: .leading, spacing: Design.Space.m) {
            PanelHeader(caption: "")
            EmptyStateView(message: L("Bu öğe silinmiş ya da geri alınmış olabilir."))
        }
    }
}

/// Panelin üst satırı: tür · durum (ek stil) ve sağda küçük "Kapat" (Esc ve boş yere tıklama da kapatır).
struct PanelHeader: View {
    @Environment(\.panelClose) private var close
    let caption: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Design.Space.s) {
            Text(caption).captionStyle().lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            if let close {
                Button(L("Kapat"), action: close).buttonStyle(.text).font(Design.Font.caption)
                    .help(L("Paneli kapat (Esc)"))
            }
        }
    }
}

/// Panelin eylem satırı: içeriğin hemen altında, sağa hizalı.
struct PanelActions<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: Design.Space.m) {
            Spacer()
            content
        }
        .padding(.top, Design.Space.s)
    }
}

/// Soru + cevap (ek stil başlık, gövde cevap). Boş cevap gösterilmez.
struct PanelQA: View {
    let q: String
    let a: String
    init(_ q: String, _ a: String) { self.q = q; self.a = a }
    var body: some View {
        if !a.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: Design.Space.xs) {
                Text(q).captionStyle()
                Text(a).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Panelde satır içi düzenlenen alan. Enter'da ya da odak ayrılınca kaydeder. Ekran çiziminde (AppKit denetimi) düz metin.
struct PanelField: View {
    @Environment(\.isSnapshot) private var isSnapshot
    let title: String
    @Binding var text: String
    var multiline = false
    let commit: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.xs) {
            Text(title).captionStyle()
            if isSnapshot {
                Text(text.isEmpty ? " " : text)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Design.Space.s).padding(.vertical, Design.Space.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Design.radius).fill(Design.bandBackground))
                    .overlay(RoundedRectangle(cornerRadius: Design.radius).strokeBorder(Design.line))
            } else {
                TextField(title, text: $text, axis: multiline ? .vertical : .horizontal)
                    .lineLimit(multiline ? 2...8 : 1...1)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .focused($focused)
                    .onSubmit(commit)
                    .onChange(of: focused) { _, now in if !now { commit() } }
                    .modifier(HoverHighlight(enabled: !focused))
            }
        }
    }
}

/// Panel içinde başka bir kayda geçen bağlantı: metin düğmesi (tek ikincil biçim).
@MainActor func link(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(title).multilineTextAlignment(.leading).underline()
    }
    .buttonStyle(.text)
    .padding(.horizontal, -Design.Space.xs)
}

// MARK: - İş kaydı

struct WorkLogPanel: View {
    @Environment(AppModel.self) private var app
    let detail: WorkLogDetail
    @State private var editing: WorkLogDetail?

    var body: some View {
        let log = detail.log
        VStack(alignment: .leading, spacing: Design.Space.m) {
            PanelHeader(caption: L("İş kaydı") + " · " + log.status.title)
            Text(log.title).font(Design.Font.section).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            PanelQA(L("Ne istendi?"), log.requested)
            files(L("Hangi dosyalar kullanıldı?"), detail.inputs)
            PanelQA(L("Ne yapıldı?"), log.performed)
            files(L("Hangi dosya veya bağlantı üretildi?"), detail.outputs)
            PanelQA(L("Ne kararlaştırıldı?"), log.decision)
            PanelQA(L("Kim onayladı?"), log.approvedBy)
            PanelQA(L("Müşteriye ne bildirildi?"), log.clientNotified)
            if let t = detail.task {
                VStack(alignment: .leading, spacing: Design.Space.xs) {
                    Text(L("Görev")).captionStyle()
                    link(t.title) { app.panelTarget = .task(t.id) }
                }
            }
            if log.status == .verified, let by = log.verifiedBy {
                PanelQA(L("Doğrulayan"), by)
            }
            if log.status == .draft, let problem = detail.verificationProblem {
                Text(problem).fixedSize(horizontal: false, vertical: true)
            }
            PanelActions {
                if log.status != .retracted {
                    Button(L("Düzenle")) { editing = detail }.buttonStyle(.text)
                }
                if log.status == .draft {
                    Button(L("Doğrula")) {
                        app.perform(title: L("Doğrulanamadı"), context: "akis.dogrula") {
                            try app.store?.verifyWorkLog(log.id, verifiedBy: Panel.verifier)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(detail.verificationProblem != nil)
                    .help(L("Rapora yalnız doğrulanmış iş kayıtları girer."))
                }
            }
        }
        .sheet(item: $editing) { d in WorkLogEditor(detail: d).environment(app) }
    }

    @ViewBuilder private func files(_ title: String, _ sources: [Source]) -> some View {
        if !sources.isEmpty {
            VStack(alignment: .leading, spacing: Design.Space.xs) {
                Text(title).captionStyle()
                ForEach(sources) { s in link(s.title) { app.panelTarget = .source(s.id) } }
            }
        }
    }
}

// MARK: - Görev

struct TaskPanel: View {
    @Environment(AppModel.self) private var app
    @Environment(\.panelClose) private var close
    let task: WorkTask
    @State private var title: String
    @State private var notes: String
    @State private var assignee: String
    @State private var deleting = false

    init(task: WorkTask) {
        self.task = task
        _title = State(initialValue: task.title)
        _notes = State(initialValue: task.notes)
        _assignee = State(initialValue: task.assignee)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.m) {
            PanelHeader(caption: L("Görev") + " · " + task.status.title)
            PanelField(title: L("Başlık"), text: $title, commit: commit)
            PanelField(title: L("Notlar"), text: $notes, multiline: true, commit: commit)
            // İptal durum menüsünde değil; açık görevde panelin altında "İptal et".
            let statuses = TaskStatus.allCases.filter { $0 != .cancelled }
            StatusMenu(current: task.status.title, options: statuses.map(\.title)) { i in save { $0.status = statuses[i] } }
            OptionalDayPicker(title: L("Son tarih"), day: Binding(get: { task.dueDate }, set: { d in save { $0.dueDate = d } }))
            PanelField(title: L("Sorumlu"), text: $assignee, commit: commit)
            if task.status.isOpen {
                OpenItemActions(title: task.title, isTask: true, deleting: $deleting,
                                cancel: { save { $0.status = .cancelled } },
                                delete: {
                                    if app.perform(context: "yapilacak.sil", { try app.store?.deleteTask(task.id) }) != nil { close?() }
                                })
            }
        }
        .onChange(of: task) { _, t in title = t.title; notes = t.notes; assignee = t.assignee }
    }

    private func commit() {
        guard title.trimmingCharacters(in: .whitespaces) != task.title || notes != task.notes || assignee != task.assignee else { return }
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { title = task.title; return }
        save { $0.title = title; $0.notes = notes; $0.assignee = assignee }
    }

    private func save(_ change: (inout WorkTask) -> Void) {
        var t = task
        change(&t)
        guard t != task else { return }
        app.perform(title: L("Görev kaydedilemedi"), context: "yapilacak.gorev") { try app.store?.saveTask(t) }
    }
}

/// Açık görev ve açık söz/karar/talep panelinin altı: *İptal et* ve *Sil…* (onaylı). Sağ tık menüsündekiyle aynı eylemler.
struct OpenItemActions: View {
    let title: String
    let isTask: Bool
    @Binding var deleting: Bool
    let cancel: () -> Void
    let delete: () -> Void

    var body: some View {
        PanelActions {
            Button(L("Sil…")) { deleting = true }.buttonStyle(.text)
            Button(L("İptal et"), action: cancel).buttonStyle(.text)
                .help(L("Listeden kalkar; silinmez."))
        }
        .confirmationDialog(L("Silinsin mi?"), isPresented: $deleting) {
            Button(L("Sil"), role: .destructive, action: delete)
        } message: {
            Text(isTask
                 ? LF("“%@” görevi kalıcı olarak silinir. Bağlı iş kayıtları kalır, yalnızca görev bağlantıları kalkar. Bu işlem geri alınamaz.", title)
                 : LF("“%@” kalıcı olarak silinir. Bu işlem geri alınamaz.", title))
        }
    }
}

// MARK: - Söz, karar bekleniyor, talep…

struct RecordPanel: View {
    @Environment(AppModel.self) private var app
    @Environment(\.panelClose) private var close
    let record: BrandRecord
    @State private var title: String
    @State private var detail: String
    @State private var deleting = false

    init(record: BrandRecord) {
        self.record = record
        _title = State(initialValue: record.title)
        _detail = State(initialValue: record.detail)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.m) {
            PanelHeader(caption: record.kind.title + " · " + record.status.title)
            PanelField(title: L("Başlık"), text: $title, commit: commit)
            PanelField(title: L("Açıklama"), text: $detail, multiline: true, commit: commit)
            let statuses = record.kind.statuses.filter { $0 != .cancelled }
            StatusMenu(current: record.status.title, options: statuses.map(\.title)) { i in save { $0.status = statuses[i] } }
            OptionalDayPicker(title: L("Son tarih"), day: Binding(get: { record.dueDate }, set: { d in save { $0.dueDate = d } }))
            if let sid = record.sourceId, let s = try? app.store?.source(sid) {
                VStack(alignment: .leading, spacing: Design.Space.xs) {
                    Text(L("Dayandığı dosya")).captionStyle()
                    link(s.title) { app.panelTarget = .source(s.id) }
                }
            }
            if record.isOpen {
                OpenItemActions(title: record.title, isTask: false, deleting: $deleting,
                                cancel: { save { $0.status = .cancelled } },
                                delete: {
                                    if app.perform(context: "yapilacak.sil", { try app.store?.deleteRecord(record.id) }) != nil { close?() }
                                })
            }
        }
        .onChange(of: record) { _, r in title = r.title; detail = r.detail }
    }

    private func commit() {
        guard title.trimmingCharacters(in: .whitespaces) != record.title || detail != record.detail else { return }
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { title = record.title; return }
        save { $0.title = title.trimmingCharacters(in: .whitespaces); $0.detail = detail }
    }

    private func save(_ change: (inout BrandRecord) -> Void) {
        var r = record
        change(&r)
        guard r != record else { return }
        app.perform(title: L("Kaydedilemedi"), context: "yapilacak.kayit") { try app.store?.saveRecord(r) }
    }
}

// MARK: - Dosya ve not

/// Dosya ya da not: başlık, tarih, içerik önizlemesi. Değiştirilemez; yalnız arşivlenir (arşivlenen Akış'tan kalkar).
struct SourcePanel: View {
    @Environment(AppModel.self) private var app
    let source: Source

    var body: some View {
        let file = app.store?.fileURL(for: source)
        VStack(alignment: .leading, spacing: Design.Space.m) {
            PanelHeader(caption: [file == nil ? L("Not") : L("Dosya"),
                                  source.capturedAt.formatted(.dateTime.day().month(.wide).hour().minute()),
                                  source.archivedAt == nil ? "" : L("Arşivlendi")].filter { !$0.isEmpty }.joined(separator: " · "))
            Text(source.title).font(Design.Font.section).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            if let name = source.fileName { Text(name).captionStyle().lineLimit(1).truncationMode(.middle) }
            if let file, source.mimeType?.hasPrefix("image/") == true, let image = NSImage(contentsOf: file) {
                Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 240)
            }
            if !source.body.isEmpty {
                Text(source.body.count > 4000 ? String(source.body.prefix(4000)) + "…" : source.body)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            } else if file != nil {
                Text(L("Bu dosyadan aranabilir metin çıkarılamadı. Orijinal dosya saklandı.")).captionStyle()
            }
            if let url = source.url, let u = URL(string: url) { Link(url, destination: u).foregroundStyle(.primary) }
            PanelActions {
                Button(source.archivedAt == nil ? L("Arşivle") : L("Arşivden çıkar")) {
                    app.perform(context: "kaynak.arsiv") { try app.store?.setSourceArchived(source.id, archived: source.archivedAt == nil) }
                }
                .buttonStyle(.text)
                .help(L("Dosya ve notlar silinmez; arşivlenen Akış'tan ve rapordan kalkar."))
                if let file {
                    Button(L("Aç")) { NSWorkspace.shared.open(file) }.buttonStyle(.text)
                }
            }
        }
    }
}

// MARK: - Onaylanmış öneri

struct ProposalPanel: View {
    @Environment(AppModel.self) private var app
    let proposal: AIProposal

    var body: some View {
        let undoable = canUndo(proposal, app: app)
        VStack(alignment: .leading, spacing: Design.Space.m) {
            let kind = proposal.kind == .createBrandRecord
                ? (proposal.payload(ProposalPayload.CreateBrandRecord.self)?.kind.title ?? proposal.kind.flowTitle)
                : proposal.kind.flowTitle
            PanelHeader(caption: kind + " · " + proposal.status.title)
            Text(proposal.displayTitle).font(Design.Font.section).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            if let d = proposal.decidedAt { PanelQA(L("Ne zaman onaylandı?"), d.formatted(.dateTime.day().month(.wide).hour().minute())) }
            if let target = resultTarget, proposal.status == .applied {
                link(L("Sonucu göster")) { app.panelTarget = target }
            }
            if proposal.kind == .wikiRevision && !undoable {
                Text(L("Sayfanın güncel sürümü artık bu değil ya da önceki sürümü yok; geri alınamaz.")).captionStyle()
                    .fixedSize(horizontal: false, vertical: true)
            }
            if undoable {
                PanelActions {
                    Button(L("Geri al")) { undo(proposal, app: app) }
                        .buttonStyle(.text)
                        .help(proposal.kind == .wikiRevision
                              ? L("Sayfa önceki sürümüne döner; bu sürüm geçmişte kalır.")
                              : L("Onayı geri alır; eklenen görev, iş kaydı ya da söz kaldırılır (dosya ve notlar arşivlenir)."))
                }
            }
        }
    }

    private var resultTarget: PanelTarget? {
        guard let rid = proposal.resultEntityId else { return nil }
        switch proposal.kind {
        case .createTask, .completeTask: return .task(rid)
        case .createWorkLog: return .workLog(rid)
        case .createNote, .createOutput: return .source(rid)
        case .createBrandRecord: return .record(rid)
        case .wikiRevision: return nil
        }
    }
}

/// Onaylanmış öneri geri alınabilir mi? Hafıza güncellemesi yalnız sayfanın güncel sürümüyse ve önceki sürümü varsa.
@MainActor
func canUndo(_ p: AIProposal, app: AppModel) -> Bool {
    guard p.status == .applied else { return false }
    guard p.kind == .wikiRevision else { return true }
    return ((try? app.store?.knowledgeUndo(proposalId: p.id)) ?? nil) != nil
}

/// Onaylanmış öneriyi geri alır (Akış paneli ve satırın erişilebilirlik eylemi). Hafıza güncellemesi mevcut "önceki sürüme
/// dön" yoluyla (`revertPage`) geri alınır: önceki içerikle yeni onaylı sürüm; geçmiş silinmez.
@MainActor
func undo(_ p: AIProposal, app: AppModel) {
    app.perform(title: L("Geri alınamadı"), context: "oneri.geri") {
        guard let store = app.store else { return }
        if p.kind == .wikiRevision {
            guard let target = try store.knowledgeUndo(proposalId: p.id) else {
                throw MarkaError.validation(L("Sayfanın güncel sürümü artık bu değil ya da önceki sürümü yok; geri alınamaz."))
            }
            try store.revertPage(target.pageId, to: target.revisionId)
        } else {
            try store.revertProposal(p.id)
        }
    }
}

extension ProposalKind {
    /// Öneri türünün kısa adı (panel başlığı).
    var flowTitle: String {
        switch self {
        case .createTask: L("Yeni görev")
        case .completeTask: L("Görevi bitir")
        case .createWorkLog: L("İş kaydı")
        case .createBrandRecord: L("Söz, talep ya da karar")
        case .createNote: L("Not")
        case .createOutput: L("Dosya")
        case .wikiRevision: L("Hafıza güncellemesi")
        }
    }
}
