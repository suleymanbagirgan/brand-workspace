import Foundation
import GRDB

// 0.2.1 Akış (ne yapıldı) ve Yapılacaklar (ne bekliyor): marka ekranının iki birleşik listesi.
// Yalnızca okur; yazma mevcut yollardan yapılır (`verifyWorkLog`, `setTaskStatus`, `saveRecord`, `revertProposal`…).

/// Akış'ta tek satır: yapılmış bir şey.
public struct FlowItem: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        /// İş kaydı (durumu satırda: doğrulanmadıysa "Doğrula").
        case workLog(WorkLogStatus)
        /// Biten görev (tamamlanma anında).
        case taskDone
        /// Metin kaynağı (not, görüşme notu, müşteri talebi, bağlantı).
        case note
        /// Dosya kaynağı.
        case file
        /// Söz, karar bekleniyor ya da talep kapandı (Bitti / İptal). Açılışı Akış'ta satır değildir (Yapılacaklar'da görünür).
        case recordClosed(BrandRecordKind, RecordStatus)
        /// Uygulanmış (onaylanmış) öneri; geri alınabilir.
        case proposalApplied(ProposalKind)
    }

    /// Türle birlikte tekil: aynı kayıt hem oluşturulma hem kapanma satırı verebilir.
    public var id: String
    public var kind: Kind
    /// Satırın dayandığı kaydın kimliği (iş kaydı, görev, kaynak, marka kaydı ya da öneri).
    public var entityId: String
    public var title: String
    public var date: Date

    public init(kind: Kind, entityId: String, title: String, date: Date) {
        self.kind = kind; self.entityId = entityId; self.title = title; self.date = date
        id = Self.idPrefix(kind) + entityId
    }

    static func idPrefix(_ kind: Kind) -> String {
        switch kind {
        case .workLog: "w:"
        case .taskDone: "t:"
        case .note, .file: "s:"
        case .recordClosed: "rc:"
        case .proposalApplied: "p:"
        }
    }

    /// Akış'ta kapanışı görünen marka kaydı türleri (hedef, teklif, sözleşme ve önemli tarih Bilgiler'de salt okunur listede).
    public static let recordKinds: [BrandRecordKind] = [.promise, .decision, .request]

    /// En yeni üstte; eşit anlarda kimliğe göre (kararlı sıra).
    public static func newestFirst(_ a: FlowItem, _ b: FlowItem) -> Bool {
        a.date == b.date ? a.id < b.id : a.date > b.date
    }
}

/// Bilgi güncellemesini geri almak için dönülecek sürüm (`Store.knowledgeUndo`).
public struct KnowledgeUndo: Sendable, Hashable {
    public var pageId: String
    public var revisionId: String
}

/// Akış'ın bir günü (en yeni gün üstte).
public struct FlowDay: Sendable, Hashable, Identifiable {
    public var day: Date
    public var items: [FlowItem]
    public var id: Date { day }
}

extension FlowItem {
    /// Sıralı öğeleri takvim gününe göre gruplar; girdi sırası korunur.
    public static func days(_ items: [FlowItem], calendar: Calendar = StatusService.turkishCalendar) -> [FlowDay] {
        var out: [FlowDay] = []
        for item in items {
            let day = calendar.startOfDay(for: item.date)
            if let last = out.last, last.day == day { out[out.count - 1].items.append(item) }
            else { out.append(FlowDay(day: day, items: [item])) }
        }
        return out
    }
}

/// Yapılacaklar'da tek satır: açık bir görev ya da açık marka kaydı.
public struct TodoItem: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        case task(TaskStatus)
        case record(BrandRecordKind, RecordStatus)
    }

    public var id: String
    public var kind: Kind
    public var entityId: String
    public var title: String
    /// `yyyy-MM-dd`.
    public var dueDate: String?
    public var assignee: String
    public var priority: Int
    public var createdAt: Date

    public init(kind: Kind, entityId: String, title: String, dueDate: String?, assignee: String = "", priority: Int = 0, createdAt: Date) {
        self.kind = kind; self.entityId = entityId; self.title = title; self.dueDate = dueDate
        self.assignee = assignee; self.priority = priority; self.createdAt = createdAt
        switch kind {
        case .task: id = "t:" + entityId
        case .record: id = "r:" + entityId
        }
    }

    public init(_ t: WorkTask) {
        self.init(kind: .task(t.status), entityId: t.id, title: t.title, dueDate: t.dueDate, assignee: t.assignee,
                  priority: t.priority, createdAt: t.createdAt)
    }

    public init(_ r: BrandRecord) {
        self.init(kind: .record(r.kind, r.status), entityId: r.id, title: r.title, dueDate: r.dueDate, createdAt: r.createdAt)
    }

    /// Ana listedeki kayıt türleri; diğerleri (hedef, teklif, sözleşme, önemli tarih) en altta.
    public static let primaryRecordKinds: Set<BrandRecordKind> = [.promise, .decision, .request]

    /// Görev ya da söz / karar bekleniyor / talep: ana liste. Diğer kayıtlar en alta.
    public var isPrimary: Bool {
        switch kind {
        case .task: true
        case .record(let k, _): Self.primaryRecordKinds.contains(k)
        }
    }

    /// Sıra: ana liste önce; her grupta son tarihe göre (gecikenler doğal olarak üstte), tarihsizler sonda;
    /// eşitlikte yüksek öncelik, sonra eski olan.
    public static func order(_ a: TodoItem, _ b: TodoItem) -> Bool {
        if a.isPrimary != b.isPrimary { return a.isPrimary }
        switch (a.dueDate, b.dueDate) {
        case let (x?, y?) where x != y: return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: break
        }
        if a.priority != b.priority { return a.priority > b.priority }
        if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
        return a.id < b.id
    }

    public func isOverdue(today: String) -> Bool {
        guard let dueDate else { return false }
        return dueDate < today
    }
}

extension WorkLogDetail {
    /// Doğrulamayı engelleyen ilk eksik (çekirdekteki doğrulama kuralı; `verifyWorkLog` de bunu kullanır). `nil`: doğrulanabilir.
    public var verificationProblem: String? {
        if log.status == .retracted { return L("Geri çekilmiş kayıt doğrulanamaz.") }
        if log.performed.trimmed.isEmpty { return L("Doğrulamak için “Ne yapıldı?” alanı dolu olmalı.") }
        if inputs.isEmpty && outputs.isEmpty && task == nil { return L("Doğrulamak için en az bir dosya ya da görev bağlanmalı.") }
        return nil
    }
}

extension AIProposal {
    /// Önerinin tek satırlık başlığı: yükteki başlık, yoksa özet.
    public var displayTitle: String {
        switch kind {
        case .createTask: payload(ProposalPayload.CreateTask.self)?.title ?? summary
        case .createBrandRecord: payload(ProposalPayload.CreateBrandRecord.self)?.title ?? summary
        case .createWorkLog: payload(ProposalPayload.CreateWorkLog.self)?.title ?? summary
        case .createNote: payload(ProposalPayload.CreateNote.self)?.title ?? summary
        case .createOutput: payload(ProposalPayload.CreateOutput.self)?.title ?? summary
        case .completeTask, .wikiRevision: summary
        }
    }
}

extension Store {
    /// Akış: markada yapılanlar, en yeni üstte, en çok `limit` öğe. İş kayıtları, biten görevler (iş kaydı bağlı olan görev
    /// yalnız iş kaydı satırıyla görünür), not/dosyalar (arşivlenmemiş), söz / karar bekleniyor / talep kapanışları, onaylanmış
    /// (geri alınabilir) öneriler — hafıza güncellemesi dahil. Açık söz/talep/karar Yapılacaklar'dadır (0.2.1 U9).
    /// Yalnız bu markanın verisi.
    public func flow(brandId: String, limit: Int = 200) throws -> [FlowItem] {
        guard limit > 0 else { return [] }
        return try read { db in
            var items: [FlowItem] = []
            let logs = try WorkLog.filter(Column("brandId") == brandId).order(Column("occurredAt").desc).limit(limit).fetchAll(db)
            items += logs.map { FlowItem(kind: .workLog($0.status), entityId: $0.id, title: $0.title, date: $0.occurredAt) }

            let done = try WorkTask.filter(Column("brandId") == brandId && Column("status") == TaskStatus.done.rawValue
                                           && Column("completedAt") != nil)
                .order(Column("completedAt").desc).limit(limit).fetchAll(db)
            // İş kaydı bağlı biten görev Akış'ta tek satırdır: iş kaydı satırı ("görev bitti" satırı gizlenir).
            let logged = Set(try String?.fetchAll(db, sql: "SELECT DISTINCT taskId FROM workLog WHERE brandId = ? AND taskId IS NOT NULL",
                                                  arguments: [brandId]).compactMap { $0 })
            items += done.filter { !logged.contains($0.id) }
                .compactMap { t in t.completedAt.map { FlowItem(kind: .taskDone, entityId: t.id, title: t.title, date: $0) } }

            let sources = try Source.filter(Column("brandId") == brandId && Column("archivedAt") == nil)
                .order(Column("capturedAt").desc).limit(limit).fetchAll(db)
            items += sources.map { FlowItem(kind: $0.filePath == nil ? .note : .file, entityId: $0.id, title: $0.title, date: $0.capturedAt) }

            let kinds = FlowItem.recordKinds.map(\.rawValue)
            let closed = try BrandRecord.filter(Column("brandId") == brandId && kinds.contains(Column("kind")) && Column("closedAt") != nil)
                .order(Column("closedAt").desc).limit(limit).fetchAll(db)
            items += closed.compactMap { r in
                r.closedAt.map { FlowItem(kind: .recordClosed(r.kind, r.status), entityId: r.id, title: r.title, date: $0) }
            }

            // Bilgi güncellemesi de (0.2.1 U8): Bilgi ekranı kalktığından onaylanmış sürüm Akış'tan geri alınır (`knowledgeUndo`).
            let applied = try AIProposal.filter(Column("brandId") == brandId && Column("status") == ProposalStatus.applied.rawValue)
                .order(Column("decidedAt").desc).limit(limit).fetchAll(db)
            items += applied.map { FlowItem(kind: .proposalApplied($0.kind), entityId: $0.id, title: $0.displayTitle, date: $0.decidedAt ?? $0.createdAt) }

            return Array(items.sorted(by: FlowItem.newestFirst).prefix(limit))
        }
    }

    /// Onaylanmış bilgi güncellemesinin geri alma hedefi: öneri uygulanmış, oluşturduğu sürüm sayfanın hâlâ güncel sürümü ve
    /// öncesinde bir sürüm var. Geri alma mevcut `revertPage(_:to:)` yoluyla yapılır (önceki içerikle yeni onaylı sürüm;
    /// geçmiş silinmez). Yeni sayfa açan güncellemenin önceki sürümü olmadığından `nil`. Salt okunur.
    public func knowledgeUndo(proposalId: String) throws -> KnowledgeUndo? {
        try read { db in
            guard let p = try AIProposal.fetchOne(db, key: proposalId), p.kind == .wikiRevision, p.status == .applied,
                  let rid = p.resultEntityId, let r = try WikiRevision.fetchOne(db, key: rid),
                  let previous = r.basedOnRevisionId,
                  let page = try WikiPage.fetchOne(db, key: r.pageId), page.currentRevisionId == r.id,
                  page.brandId == p.brandId else { return nil }
            return KnowledgeUndo(pageId: page.id, revisionId: previous)
        }
    }

    /// Yapılacaklar: açık görevler ve açık söz / karar bekleniyor / talep, `TodoItem.order` sırasıyla. Hedef, teklif, sözleşme
    /// ve önemli tarih burada değil, Bilgiler'de (`referenceRecords`). Yalnız bu markanın verisi.
    public func todo(brandId: String) throws -> [TodoItem] {
        try read { db in
            let open = TaskStatus.allCases.filter(\.isOpen).map(\.rawValue)
            let tasks = try WorkTask.filter(Column("brandId") == brandId && open.contains(Column("status"))).fetchAll(db)
            let kinds = TodoItem.primaryRecordKinds.map(\.rawValue)
            let records = try BrandRecord.filter(Column("brandId") == brandId && kinds.contains(Column("kind"))).fetchAll(db).filter(\.isOpen)
            return (tasks.map(TodoItem.init) + records.map(TodoItem.init)).sorted(by: TodoItem.order)
        }
    }

    /// Bilgiler'deki salt okunur liste: hedef, teklif, sözleşme ve önemli tarih (terminal önerisiyle ya da eski sürümde gelen
    /// kayıtlar), iptal edilmişler hariç. Tarihliler tarih sırasıyla önce, sonra en yeni. Yalnız bu markanın verisi.
    public func referenceRecords(brandId: String) throws -> [BrandRecord] {
        try read { db in
            let kinds = BrandRecordKind.allCases.filter { !TodoItem.primaryRecordKinds.contains($0) }.map(\.rawValue)
            let list = try BrandRecord.filter(Column("brandId") == brandId && kinds.contains(Column("kind"))
                                              && Column("status") != RecordStatus.cancelled.rawValue).fetchAll(db)
            return list.sorted { a, b in
                switch (a.dueDate, b.dueDate) {
                case let (x?, y?) where x != y: return x < y
                case (_?, nil): return true
                case (nil, _?): return false
                default: return a.createdAt > b.createdAt
                }
            }
        }
    }
}
