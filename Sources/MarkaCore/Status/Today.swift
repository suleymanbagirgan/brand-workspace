import Foundation
import GRDB

/// Bugün ekranının özeti (0.2.1, plan §4): tüm etkin markalarda onay bekleyen, geciken, bu hafta yapılan ve müşteriden
/// beklenen. Salt okunur; sayımlar kayıtlardan yapılır. Arşivlenmiş markalar hiçbir bölümde görünmez. Markalar ada göre sıralı.
public struct TodaySummary: Sendable, Hashable {
    public struct Pending: Sendable, Hashable, Identifiable {
        public var brandId: String
        /// Terminalden gelen (`oneriler/*.json`) bekleyen öneriler.
        public var terminal: Int
        /// Uygulama içinde oluşmuş bekleyen öneriler ve onay bekleyen bilgi güncellemeleri.
        public var other: Int
        public var total: Int { terminal + other }
        public var id: String { brandId }
    }

    public struct Week: Sendable, Hashable, Identifiable {
        public var brandId: String
        /// Bu hafta biten görev.
        public var tasksDone: Int
        /// Bu hafta yapılan iş kaydı (geri çekilenler hariç).
        public var workLogs: Int
        /// Bunlardan doğrulanmamış olan.
        public var unverified: Int
        /// Bu hafta eklenen dosya ve not (arşivlenenler hariç).
        public var files: Int
        public var notes: Int
        public var id: String { brandId }
    }

    public struct Awaiting: Sendable, Hashable, Identifiable {
        public var brandId: String
        /// Açık "Karar bekleniyor" kayıtları, eskiden yeniye.
        public var titles: [String]
        public var refs: [RecordRef]
        public var id: String { brandId }
    }

    public var pending: [Pending]
    public var overdue: [StatusLine]
    public var week: [Week]
    public var awaiting: [Awaiting]
}

/// Bugün ekranında tüm markalarda arama sonucu (marka · tür · başlık).
public struct TodaySearchHit: Sendable, Hashable, Identifiable {
    public var ref: RecordRef
    public var brandId: String
    public var title: String
    /// Marka kaydıysa türü (Söz, Karar bekleniyor …).
    public var recordKind: BrandRecordKind? = nil
    public var id: String { ref.kind.rawValue + ref.id }
}

extension Store {
    public func today(now: Date = Date(), calendar: Calendar = StatusService.turkishCalendar) throws -> TodaySummary {
        let today = DayString.from(now, calendar: calendar)
        let week = calendar.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(start: now, duration: 7 * 86400)
        return try read { db in
            let brands = try Brand.filter(Column("status") == BrandStatus.active.rawValue).fetchAll(db)
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            let ids = brands.map(\.id)
            let order = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })

            // Onay bekleyen: öneriler (bilgi önerisinin kendi satırı hariç; sürümü sayılır) + bilgi güncellemeleri.
            let proposals = try AIProposal.filter(ids.contains(Column("brandId")) && Column("status") == ProposalStatus.pending.rawValue
                                                  && Column("kind") != ProposalKind.wikiRevision.rawValue).fetchAll(db)
            let revisions = try WikiRevision.filter(ids.contains(Column("brandId")) && Column("state") == RevisionState.proposed.rawValue).fetchAll(db)
            let pending: [TodaySummary.Pending] = ids.compactMap { id in
                let mine = proposals.filter { $0.brandId == id }
                let terminal = mine.filter { $0.origin == .terminal }.count
                let other = mine.count - terminal + revisions.filter { $0.brandId == id }.count
                return terminal + other > 0 ? TodaySummary.Pending(brandId: id, terminal: terminal, other: other) : nil
            }

            let overdue = try WorkTask.filter(ids.contains(Column("brandId"))
                                              && [TaskStatus.todo, .inProgress, .waiting].map(\.rawValue).contains(Column("status")))
                .fetchAll(db).filter { $0.isOverdue(today: today) }
                .sorted { ($0.dueDate ?? "", order[$0.brandId] ?? 0, $0.title) < ($1.dueDate ?? "", order[$1.brandId] ?? 0, $1.title) }
                .map { StatusLine(text: $0.title, detail: "", date: nil, dueDate: $0.dueDate, ref: RecordRef(.task, $0.id), brandId: $0.brandId) }

            let done = try WorkTask.filter(ids.contains(Column("brandId")) && Column("status") == TaskStatus.done.rawValue
                                           && Column("completedAt") >= week.start && Column("completedAt") < week.end).fetchAll(db)
            let logs = try WorkLog.filter(ids.contains(Column("brandId")) && Column("status") != WorkLogStatus.retracted.rawValue
                                          && Column("occurredAt") >= week.start && Column("occurredAt") < week.end).fetchAll(db)
            let sources = try Source.filter(ids.contains(Column("brandId")) && Column("archivedAt") == nil
                                            && Column("capturedAt") >= week.start && Column("capturedAt") < week.end).fetchAll(db)
            let noteKinds: Set<SourceKind> = [.note, .meeting, .clientRequest]
            let weekRows: [TodaySummary.Week] = ids.compactMap { id in
                let l = logs.filter { $0.brandId == id }
                let s = sources.filter { $0.brandId == id }
                let row = TodaySummary.Week(brandId: id, tasksDone: done.filter { $0.brandId == id }.count, workLogs: l.count,
                                            unverified: l.filter { $0.status == .draft }.count,
                                            files: s.filter { !noteKinds.contains($0.kind) }.count,
                                            notes: s.filter { noteKinds.contains($0.kind) }.count)
                return row.tasksDone + row.workLogs + row.files + row.notes > 0 ? row : nil
            }

            let decisions = try BrandRecord.filter(ids.contains(Column("brandId")) && Column("kind") == BrandRecordKind.decision.rawValue)
                .order(Column("createdAt")).fetchAll(db).filter(\.isOpen)
            let awaiting: [TodaySummary.Awaiting] = ids.compactMap { id in
                let mine = decisions.filter { $0.brandId == id }
                return mine.isEmpty ? nil : TodaySummary.Awaiting(brandId: id, titles: mine.map(\.title),
                                                                  refs: mine.map { RecordRef(.brandRecord, $0.id) })
            }
            return TodaySummary(pending: pending, overdue: overdue, week: weekRows, awaiting: awaiting)
        }
    }

    /// Tüm etkin markalarda başlık araması: görev, iş kaydı, marka kaydı (Söz, Karar bekleniyor …) ve dosya/not.
    /// Dosya/not içeriği tam metin dizininden (`search`) de aranır. Arşivlenmiş markalar ve dosyalar hariç. Salt okunur.
    public func searchToday(_ query: String, limit: Int = 50) throws -> [TodaySearchHit] {
        let terms = Self.searchTerms(query)
        guard !terms.isEmpty else { return [] }
        func matches(_ title: String) -> Bool {
            let t = Self.normalize(title)
            return terms.allSatisfy { t.contains($0) }
        }
        var hits: [TodaySearchHit] = try read { db in
            let ids = try String.fetchAll(db, sql: "SELECT id FROM brand WHERE status = ?", arguments: [BrandStatus.active.rawValue])
            var out: [TodaySearchHit] = []
            for t in try WorkTask.filter(ids.contains(Column("brandId"))).order(Column("updatedAt").desc).fetchAll(db) where matches(t.title) {
                out.append(TodaySearchHit(ref: RecordRef(.task, t.id), brandId: t.brandId, title: t.title))
            }
            for l in try WorkLog.filter(ids.contains(Column("brandId")) && Column("status") != WorkLogStatus.retracted.rawValue)
                .order(Column("occurredAt").desc).fetchAll(db) where matches(l.title) {
                out.append(TodaySearchHit(ref: RecordRef(.workLog, l.id), brandId: l.brandId, title: l.title))
            }
            for r in try BrandRecord.filter(ids.contains(Column("brandId"))).order(Column("updatedAt").desc).fetchAll(db) where matches(r.title) {
                out.append(TodaySearchHit(ref: RecordRef(.brandRecord, r.id), brandId: r.brandId, title: r.title, recordKind: r.kind))
            }
            return out
        }
        let active = Set(try brands().map(\.id))
        for s in try search(query, brandId: nil, limit: limit) where s.kind == .source && active.contains(s.brandId) {
            hits.append(TodaySearchHit(ref: RecordRef(.source, s.id), brandId: s.brandId, title: s.title))
        }
        return Array(hits.prefix(limit))
    }
}
