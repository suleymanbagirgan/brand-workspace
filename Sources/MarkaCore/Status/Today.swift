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
        let week = CountDefinitions.week(containing: now, calendar: calendar)
        return try read { db in
            let brands = try Brand.filter(Column("status") == BrandStatus.active.rawValue).fetchAll(db)
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            let ids = brands.map(\.id)
            let order = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })

            // Sayımlar SQL'de gruplanır; satırlar çözülmez (yoğun veride binlerce kayıt). Sonuç önceki süzmeyle aynıdır.
            let marks = ids.map { _ in "?" }.joined(separator: ",")
            /// `pre`: marka listesinden önceki (SELECT'teki) parametreler; `post`: sonrakiler.
            func grouped(_ sql: String, pre: [any DatabaseValueConvertible] = [], _ post: [any DatabaseValueConvertible]) throws -> [Row] {
                ids.isEmpty ? [] : try Row.fetchAll(db, sql: sql, arguments: StatementArguments(pre + ids + post))
            }

            // Onay bekleyen: öneriler (bilgi önerisinin kendi satırı hariç; sürümü sayılır) + bilgi güncellemeleri.
            var terminalBy: [String: Int] = [:], otherBy: [String: Int] = [:]
            for r in try grouped("""
                SELECT brandId, COALESCE(origin = ?, 0) AS t, COUNT(*) AS n FROM aiProposal
                WHERE brandId IN (\(marks)) AND status = ? AND kind != ? GROUP BY brandId, t
                """, pre: [ProposalOrigin.terminal.rawValue], [ProposalStatus.pending.rawValue, ProposalKind.wikiRevision.rawValue]) {
                let id: String = r["brandId"], n: Int = r["n"]
                if r["t"] as Bool { terminalBy[id, default: 0] += n } else { otherBy[id, default: 0] += n }
            }
            for r in try grouped("SELECT brandId, COUNT(*) AS n FROM wikiRevision WHERE brandId IN (\(marks)) AND state = ? GROUP BY brandId",
                                 [RevisionState.proposed.rawValue]) {
                otherBy[r["brandId"] as String, default: 0] += r["n"] as Int
            }
            let pending: [TodaySummary.Pending] = ids.compactMap { id in
                let terminal = terminalBy[id] ?? 0, other = otherBy[id] ?? 0
                return terminal + other > 0 ? TodaySummary.Pending(brandId: id, terminal: terminal, other: other) : nil
            }

            // Geciken: açık ve son tarihi bugünden önce (`WorkTask.isOverdue`); yalnız gereken sütunlar okunur.
            let openStatuses = [TaskStatus.todo, .inProgress, .waiting].map(\.rawValue)
            let overdue = try grouped("""
                SELECT id, brandId, title, dueDate FROM workTask WHERE brandId IN (\(marks))
                AND status IN (?, ?, ?) AND dueDate IS NOT NULL AND dueDate < ?
                """, openStatuses + [today])
                .map { (id: $0["id"] as String, brandId: $0["brandId"] as String, title: $0["title"] as String, dueDate: $0["dueDate"] as String) }
                .sorted { ($0.dueDate, order[$0.brandId] ?? 0, $0.title) < ($1.dueDate, order[$1.brandId] ?? 0, $1.title) }
                .map { StatusLine(text: $0.title, detail: "", date: nil, dueDate: $0.dueDate, ref: RecordRef(.task, $0.id), brandId: $0.brandId) }

            var doneBy: [String: Int] = [:]
            for r in try grouped("""
                SELECT brandId, COUNT(*) AS n FROM workTask WHERE brandId IN (\(marks)) AND status = ?
                AND completedAt >= ? AND completedAt < ? GROUP BY brandId
                """, [TaskStatus.done.rawValue, week.start, week.end]) { doneBy[r["brandId"] as String] = r["n"] as Int }
            var logsBy: [String: Int] = [:], draftBy: [String: Int] = [:]
            for r in try grouped("""
                SELECT brandId, status = ? AS d, COUNT(*) AS n FROM workLog WHERE brandId IN (\(marks)) AND status != ?
                AND occurredAt >= ? AND occurredAt < ? GROUP BY brandId, d
                """, pre: [WorkLogStatus.draft.rawValue], [WorkLogStatus.retracted.rawValue, week.start, week.end]) {
                let id: String = r["brandId"], n: Int = r["n"]
                logsBy[id, default: 0] += n
                if r["d"] as Bool { draftBy[id, default: 0] += n }
            }
            let noteKinds: [SourceKind] = [.note, .meeting, .clientRequest]
            var filesBy: [String: Int] = [:], notesBy: [String: Int] = [:]
            for r in try grouped("""
                SELECT brandId, kind IN (?, ?, ?) AS isNote, COUNT(*) AS n FROM source WHERE brandId IN (\(marks)) AND archivedAt IS NULL
                AND capturedAt >= ? AND capturedAt < ? GROUP BY brandId, isNote
                """, pre: noteKinds.map(\.rawValue), [week.start, week.end]) {
                let id: String = r["brandId"], n: Int = r["n"]
                if r["isNote"] as Bool { notesBy[id, default: 0] += n } else { filesBy[id, default: 0] += n }
            }
            let weekRows: [TodaySummary.Week] = ids.compactMap { id in
                let row = TodaySummary.Week(brandId: id, tasksDone: doneBy[id] ?? 0, workLogs: logsBy[id] ?? 0,
                                            unverified: draftBy[id] ?? 0, files: filesBy[id] ?? 0, notes: notesBy[id] ?? 0)
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
        // Yalnız kimlik, marka ve başlık okunur (kayıt çözülmez). Sonuç `limit` ile kesildiğinden, sınır dolunca sonraki türlere
        // bakılmaz: sıra (görev → iş kaydı → marka kaydı → dosya) ve kesme önceki davranışla aynıdır.
        var hits: [TodaySearchHit] = try read { db in
            let ids = try String.fetchAll(db, sql: "SELECT id FROM brand WHERE status = ?", arguments: [BrandStatus.active.rawValue])
            guard !ids.isEmpty else { return [] }
            let marks = ids.map { _ in "?" }.joined(separator: ",")
            var out: [TodaySearchHit] = []
            /// Satırları sınır dolana kadar tarar; `true`: sınır doldu.
            func scan(_ sql: String, _ args: [any DatabaseValueConvertible], _ hit: (Row, String) -> TodaySearchHit) throws -> Bool {
                let cursor = try Row.fetchCursor(db, sql: sql, arguments: StatementArguments(args))
                while let r = try cursor.next() {
                    if out.count >= limit { return true }
                    let title: String = r["title"]
                    if matches(title) { out.append(hit(r, title)) }
                }
                return out.count >= limit
            }
            if try scan("SELECT id, brandId, title FROM workTask WHERE brandId IN (\(marks)) ORDER BY updatedAt DESC", ids, {
                TodaySearchHit(ref: RecordRef(.task, $0["id"]), brandId: $0["brandId"], title: $1)
            }) { return out }
            if try scan("SELECT id, brandId, title FROM workLog WHERE brandId IN (\(marks)) AND status != ? ORDER BY occurredAt DESC",
                        ids + [WorkLogStatus.retracted.rawValue], {
                TodaySearchHit(ref: RecordRef(.workLog, $0["id"]), brandId: $0["brandId"], title: $1)
            }) { return out }
            _ = try scan("SELECT id, brandId, title, kind FROM brandRecord WHERE brandId IN (\(marks)) ORDER BY updatedAt DESC", ids, {
                TodaySearchHit(ref: RecordRef(.brandRecord, $0["id"]), brandId: $0["brandId"], title: $1,
                               recordKind: BrandRecordKind(rawValue: $0["kind"]))
            })
            return out
        }
        guard hits.count < limit else { return Array(hits.prefix(limit)) }
        let active = Set(try brands().map(\.id))
        for s in try search(query, brandId: nil, limit: limit) where s.kind == .source && active.contains(s.brandId) {
            hits.append(TodaySearchHit(ref: RecordRef(.source, s.id), brandId: s.brandId, title: s.title))
        }
        return Array(hits.prefix(limit))
    }
}
