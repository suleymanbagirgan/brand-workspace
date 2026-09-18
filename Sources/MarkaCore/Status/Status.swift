import Foundation
import GRDB

/// Bir durum satırının dayandığı kayıt.
public struct RecordRef: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
        case task, source, workLog, brandRecord, wikiPage, timeEntry, report
    }
    public var kind: Kind
    public var id: String
    public init(_ kind: Kind, _ id: String) { self.kind = kind; self.id = id }
}

public struct StatusLine: Sendable, Hashable, Identifiable {
    public var id: String { ref.kind.rawValue + ref.id }
    public var text: String
    public var detail: String
    public var date: Date?
    public var dueDate: String?
    public var ref: RecordRef
    public var brandId: String? = nil
}

public struct NextStep: Sendable, Hashable {
    /// Sıradaki adımın seçim sırası (arayüzde yardım metni olarak gösterilir).
    public static var ruleDescription: String {
        L("Sıradaki adım sırası: gecikmiş görev › 3 gün içindeki söz › kontrol bekleyen taslak › 7 günü geçen karar › öncelikli görev › açık müşteri talebi")
    }

    public enum Reason: String, Sendable {
        case overdueTask, promiseDueSoon, draftToReview, staleDecision, topTask, openRequest
        /// Markada hiç kaynak yok: ilk kaynağı ekle.
        case addFirstSource
        /// Kaynak var ama açık iş yok: görev veya söz ekle (ekranda eylem düğmeleri gösterilir).
        case nothingOpen
    }
    public var reason: Reason
    public var text: String
    public var ref: RecordRef?
}

/// Masa durum kartı: tamamen kayıtlardan hesaplanır.
public struct BrandStatusSnapshot: Sendable, Hashable {
    public var brand: Brand
    public var lastContact: StatusLine?
    public var openPromises: [StatusLine]
    public var pendingDecisions: [StatusLine]
    public var openRequests: [StatusLine]
    public var drafts: [StatusLine]
    public var overdueTasks: [StatusLine]
    public var nextStep: NextStep
    public var isEmpty: Bool
}

public struct OverviewSnapshot: Sendable, Hashable {
    public var overdueTasks: [StatusLine]
    public var dueThisWeek: [StatusLine]
    public var lastContacts: [(brand: Brand, line: StatusLine?)]
    public var awaiting: [StatusLine]
    public var verifiedThisWeek: [StatusLine]
    public var brandNames: [String: String]

    public static func == (a: OverviewSnapshot, b: OverviewSnapshot) -> Bool {
        a.overdueTasks == b.overdueTasks && a.dueThisWeek == b.dueThisWeek && a.awaiting == b.awaiting
            && a.verifiedThisWeek == b.verifiedThisWeek && a.lastContacts.map(\.brand) == b.lastContacts.map(\.brand)
            && a.lastContacts.map(\.line) == b.lastContacts.map(\.line)
    }

    public func hash(into h: inout Hasher) {
        h.combine(overdueTasks); h.combine(dueThisWeek); h.combine(awaiting); h.combine(verifiedThisWeek)
    }
}

public struct StatusService: Sendable {
    public let store: Store
    public var calendar: Calendar

    public init(store: Store, calendar: Calendar = StatusService.turkishCalendar) {
        self.store = store
        self.calendar = calendar
    }

    public static var turkishCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "tr_TR")
        c.firstWeekday = 2
        c.timeZone = .current
        return c
    }

    public func weekInterval(containing date: Date) -> DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: date) ?? DateInterval(start: date, duration: 7 * 86400)
    }

    public func brandStatus(brandId: String, now: Date = Date()) throws -> BrandStatusSnapshot {
        let today = DayString.from(now, calendar: calendar)
        let soon = DayString.from(calendar.date(byAdding: .day, value: 3, to: now)!, calendar: calendar)
        return try store.read { db in
            guard let brand = try Brand.fetchOne(db, key: brandId) else { throw MarkaError.notFound(brandId) }
            let contactKinds = SourceKind.allCases.filter(\.isContact).map(\.rawValue)
            let lastContact = try Source.filter(Column("brandId") == brandId && contactKinds.contains(Column("kind")) && Column("archivedAt") == nil)
                .order(Column("capturedAt").desc).fetchOne(db)
            let records = try BrandRecord.filter(Column("brandId") == brandId).fetchAll(db).filter(\.isOpen)
            func lines(_ kind: BrandRecordKind) -> [StatusLine] {
                records.filter { $0.kind == kind }
                    .sorted { ($0.dueDate ?? "9999") < ($1.dueDate ?? "9999") }
                    .map { StatusLine(text: $0.title, detail: $0.detail, date: $0.createdAt, dueDate: $0.dueDate, ref: RecordRef(.brandRecord, $0.id)) }
            }
            let promises = lines(.promise)
            let decisions = lines(.decision)
            let requests = lines(.request)
            let draftProposals = records.filter { $0.kind == .proposal && $0.status == .draft }
                .map { StatusLine(text: $0.title, detail: L("Teklif taslağı"), date: $0.updatedAt, dueDate: $0.dueDate, ref: RecordRef(.brandRecord, $0.id)) }
            let draftLogs = try WorkLog.filter(Column("brandId") == brandId && Column("status") == WorkLogStatus.draft.rawValue)
                .order(Column("updatedAt").desc).fetchAll(db)
                .map { StatusLine(text: $0.title, detail: L("Doğrulanmamış çalışma kaydı"), date: $0.updatedAt, dueDate: nil, ref: RecordRef(.workLog, $0.id)) }
            let openTasks = try WorkTask.filter(Column("brandId") == brandId).fetchAll(db).filter(\.status.isOpen).sorted(by: WorkTask.displayOrder)
            let overdue = openTasks.filter { $0.isOverdue(today: today) }
                .map { StatusLine(text: $0.title, detail: "", date: nil, dueDate: $0.dueDate, ref: RecordRef(.task, $0.id)) }
            let sourceCount = try Source.filter(Column("brandId") == brandId).fetchCount(db)

            let next: NextStep
            if let t = overdue.first {
                next = NextStep(reason: .overdueTask, text: LF("Geciken görevi bitir: %@", t.text), ref: t.ref)
            } else if let p = promises.first(where: { ($0.dueDate ?? "9999") <= soon }) {
                next = NextStep(reason: .promiseDueSoon, text: LF("Sözü yerine getir: %@", p.text), ref: p.ref)
            } else if let d = (draftProposals + draftLogs).first {
                next = NextStep(reason: .draftToReview, text: LF("Taslağı kontrol et: %@", d.text), ref: d.ref)
            } else if let d = decisions.first(where: { ($0.date ?? now) < now.addingTimeInterval(-7 * 86400) }) {
                next = NextStep(reason: .staleDecision, text: LF("Müşteriye kararı sor: %@", d.text), ref: d.ref)
            } else if let t = openTasks.first {
                next = NextStep(reason: .topTask, text: LF("Sıradaki görev: %@", t.title), ref: RecordRef(.task, t.id))
            } else if let r = requests.first {
                next = NextStep(reason: .openRequest, text: LF("Talebi yanıtla: %@", r.text), ref: r.ref)
            } else if sourceCount == 0 {
                next = NextStep(reason: .addFirstSource, text: L("İlk kaynağı ekle: son görüşme notu veya müşteri talebi."), ref: nil)
            } else {
                next = NextStep(reason: .nothingOpen, text: L("Açık iş yok. Görüşmeden çıkan görevi veya verdiğin sözü ekle."), ref: nil)
            }
            return BrandStatusSnapshot(
                brand: brand,
                lastContact: lastContact.map { StatusLine(text: $0.title, detail: String($0.body.prefix(240)), date: $0.capturedAt, dueDate: nil, ref: RecordRef(.source, $0.id)) },
                openPromises: promises, pendingDecisions: decisions, openRequests: requests,
                drafts: draftProposals + draftLogs, overdueTasks: overdue, nextStep: next,
                isEmpty: sourceCount == 0 && records.isEmpty && openTasks.isEmpty)
        }
    }

    public func overview(now: Date = Date()) throws -> OverviewSnapshot {
        let today = DayString.from(now, calendar: calendar)
        let weekEnd = DayString.from(calendar.date(byAdding: .day, value: 7, to: now)!, calendar: calendar)
        let week = weekInterval(containing: now)
        return try store.read { db in
            let brands = try Brand.filter(Column("status") == BrandStatus.active.rawValue).fetchAll(db)
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            let activeIds = Set(brands.map(\.id))
            let names = Dictionary(uniqueKeysWithValues: brands.map { ($0.id, $0.name) })
            let open = try WorkTask.filter([TaskStatus.todo, .inProgress, .waiting].map(\.rawValue).contains(Column("status")))
                .fetchAll(db).filter { activeIds.contains($0.brandId) }.sorted(by: WorkTask.displayOrder)
            func taskLine(_ t: WorkTask) -> StatusLine {
                StatusLine(text: t.title, detail: names[t.brandId] ?? "", date: nil, dueDate: t.dueDate, ref: RecordRef(.task, t.id), brandId: t.brandId)
            }
            let overdue = open.filter { $0.isOverdue(today: today) }.map(taskLine)
            let dueSoon = open.filter { if let d = $0.dueDate { return d >= today && d <= weekEnd } else { return false } }.map(taskLine)
            let contactKinds = SourceKind.allCases.filter(\.isContact).map(\.rawValue)
            var contacts: [(Brand, StatusLine?)] = []
            for b in brands {
                let s = try Source.filter(Column("brandId") == b.id && contactKinds.contains(Column("kind")) && Column("archivedAt") == nil)
                    .order(Column("capturedAt").desc).fetchOne(db)
                contacts.append((b, s.map { StatusLine(text: $0.title, detail: b.name, date: $0.capturedAt, dueDate: nil, ref: RecordRef(.source, $0.id)) }))
            }
            let awaiting = try BrandRecord.filter([BrandRecordKind.request, .decision].map(\.rawValue).contains(Column("kind")))
                .fetchAll(db).filter { $0.isOpen && activeIds.contains($0.brandId) }
                .sorted { $0.createdAt < $1.createdAt }
                .map { StatusLine(text: $0.title, detail: names[$0.brandId] ?? "", date: $0.createdAt, dueDate: $0.dueDate, ref: RecordRef(.brandRecord, $0.id), brandId: $0.brandId) }
            let verified = try WorkLog.filter(Column("status") == WorkLogStatus.verified.rawValue && Column("occurredAt") >= week.start && Column("occurredAt") < week.end)
                .order(Column("occurredAt").desc).fetchAll(db).filter { activeIds.contains($0.brandId) }
                .map { StatusLine(text: $0.title, detail: names[$0.brandId] ?? "", date: $0.occurredAt, dueDate: nil, ref: RecordRef(.workLog, $0.id), brandId: $0.brandId) }
            return OverviewSnapshot(overdueTasks: overdue, dueThisWeek: dueSoon, lastContacts: contacts, awaiting: awaiting,
                                    verifiedThisWeek: verified, brandNames: names)
        }
    }
}
