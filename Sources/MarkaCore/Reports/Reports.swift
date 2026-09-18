import Foundation
import GRDB

public enum ReportSectionKind: String, Codable, Sendable, CaseIterable {
    case completedWork, deliverables, openIssues, awaitingClient, timeSpent, nextSteps
}

public struct ReportItem: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var text: String
    public var refs: [RecordRef]
    /// Kullanıcı metni değiştirdiyse işaretlenir (kaynak bağlantısı korunur).
    public var edited: Bool
    public init(id: String = newID(), text: String, refs: [RecordRef], edited: Bool = false) {
        self.id = id; self.text = text; self.refs = refs; self.edited = edited
    }
}

public struct ReportSection: Codable, Sendable, Hashable, Identifiable {
    public var kind: ReportSectionKind
    public var items: [ReportItem]
    public var id: String { kind.rawValue }
}

public struct ReportSummarySentence: Codable, Sendable, Hashable {
    public var text: String
    /// Dayandığı rapor maddesi kimlikleri.
    public var itemIds: [String]
}

public struct ReportContent: Codable, Sendable, Hashable {
    public var brandName: String
    public var title: String
    public var periodStart: Date
    public var periodEnd: Date
    public var intro: String
    public var summary: [ReportSummarySentence]
    public var sections: [ReportSection]
    /// Rapora girmeyen ama kullanıcının bilmesi gereken uyarılar (doğrulanmamış tamamlanan görevler).
    public var warnings: [ReportItem]
    public var totalSeconds: Int

    public func section(_ kind: ReportSectionKind) -> ReportSection? { sections.first { $0.kind == kind } }
    public var allItemIds: Set<String> { Set(sections.flatMap(\.items).map(\.id)) }

    public var isEmpty: Bool { sections.allSatisfy { $0.items.isEmpty } }
}

public struct ReportBuilder: Sendable {
    public let store: Store
    public var calendar: Calendar

    public init(store: Store, calendar: Calendar = StatusService.turkishCalendar) {
        self.store = store
        self.calendar = calendar
    }

    public func period(_ kind: ReportPeriod, containing date: Date) -> DateInterval {
        let component: Calendar.Component = kind == .weekly ? .weekOfYear : .month
        return calendar.dateInterval(of: component, for: date)!
    }

    /// Deterministik taslak: yalnızca doğrulanmış çalışma kayıtları "yapılan iş" sayılır.
    public func build(brandId: String, period: DateInterval, now: Date = Date()) throws -> ReportContent {
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "tr_TR")
        dayFormatter.dateFormat = "d MMM"
        let endDay = DayString.from(calendar.date(byAdding: .day, value: 14, to: period.end)!, calendar: calendar)

        return try store.read { db in
            guard let brand = try Brand.fetchOne(db, key: brandId) else { throw MarkaError.notFound(brandId) }
            let logs = try WorkLog.filter(Column("brandId") == brandId && Column("status") == WorkLogStatus.verified.rawValue
                                          && Column("occurredAt") >= period.start && Column("occurredAt") < period.end)
                .order(Column("occurredAt")).fetchAll(db)

            var completed: [ReportItem] = []
            var deliverables: [ReportItem] = []
            var coveredTaskIds = Set<String>()
            for log in logs {
                let detail = try Store.workLogDetail(db, log.id)
                var refs = [RecordRef(.workLog, log.id)]
                refs += detail.inputs.map { RecordRef(.source, $0.id) }
                if let t = log.taskId { refs.append(RecordRef(.task, t)); coveredTaskIds.insert(t) }
                var text = log.title
                if !log.performed.trimmed.isEmpty { text += ": " + log.performed.trimmed }
                if !log.decision.trimmed.isEmpty {
                    if !text.hasSuffix(".") { text += "." }
                    text += " " + LF("Karar: %@", log.decision.trimmed)
                }
                completed.append(ReportItem(text: text, refs: refs))
                for out in detail.outputs where out.archivedAt == nil {
                    deliverables.append(ReportItem(text: out.fileName.map { "\(out.title) (\($0))" } ?? out.title,
                                                   refs: [RecordRef(.source, out.id), RecordRef(.workLog, log.id)]))
                }
            }

            let doneTasks = try WorkTask.filter(Column("brandId") == brandId && Column("status") == TaskStatus.done.rawValue
                                                && Column("completedAt") >= period.start && Column("completedAt") < period.end).fetchAll(db)
            let warnings = doneTasks.filter { !coveredTaskIds.contains($0.id) }.map {
                ReportItem(text: LF("“%@” bitti olarak işaretli ama doğrulanmış iş kaydı yok; rapora eklenmedi.", $0.title),
                           refs: [RecordRef(.task, $0.id)])
            }

            let records = try BrandRecord.filter(Column("brandId") == brandId).fetchAll(db).filter(\.isOpen)
            let openIssues = records.filter { $0.kind == .request || $0.kind == .promise }
                .sorted { ($0.dueDate ?? "9999") < ($1.dueDate ?? "9999") }
                .map { r in
                    ReportItem(text: r.dueDate.flatMap { DayString.date($0, calendar: calendar) }.map { "\(r.title) — \(LF("hedef tarih %@", dayFormatter.string(from: $0)))" } ?? r.title,
                               refs: [RecordRef(.brandRecord, r.id)] + (r.sourceId.map { [RecordRef(.source, $0)] } ?? []))
                }
            let awaiting = records.filter { $0.kind == .decision || ($0.kind == .proposal && $0.status == .sent) }
                .map { ReportItem(text: $0.title, refs: [RecordRef(.brandRecord, $0.id)] + ($0.sourceId.map { [RecordRef(.source, $0)] } ?? [])) }

            let entries = try TimeEntry.filter(Column("brandId") == brandId && Column("endedAt") != nil
                                               && Column("endedAt") >= period.start && Column("endedAt") < period.end).fetchAll(db)
            let total = entries.reduce(0) { $0 + $1.seconds }
            var timeItems: [ReportItem] = []
            let byTask = Dictionary(grouping: entries, by: \.taskId)
            for (taskId, list) in byTask.sorted(by: { $0.value.reduce(0) { $0 + $1.seconds } > $1.value.reduce(0) { $0 + $1.seconds } }) {
                let secs = list.reduce(0) { $0 + $1.seconds }
                guard secs > 0, let t = try WorkTask.fetchOne(db, key: taskId) else { continue }
                timeItems.append(ReportItem(text: "\(t.title) — \(DurationFormat.short(secs))",
                                            refs: [RecordRef(.task, taskId)] + list.map { RecordRef(.timeEntry, $0.id) }))
            }

            let nextTasks = try WorkTask.filter(Column("brandId") == brandId).fetchAll(db)
                .filter { $0.status.isOpen && ($0.dueDate.map { $0 <= endDay } ?? ($0.priority >= 2)) }
                .sorted(by: WorkTask.displayOrder).prefix(8)
                .map { t in ReportItem(text: t.dueDate.flatMap { DayString.date($0, calendar: calendar) }.map { "\(t.title) — \(dayFormatter.string(from: $0))" } ?? t.title,
                                       refs: [RecordRef(.task, t.id)]) }

            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "tr_TR")
            fmt.dateFormat = "d MMMM yyyy"
            let lastDay = period.end.addingTimeInterval(-1)
            let title = LF("%1$@ çalışma raporu · %2$@ – %3$@", brand.name, fmt.string(from: period.start), fmt.string(from: lastDay))
            return ReportContent(
                brandName: brand.name, title: title, periodStart: period.start, periodEnd: period.end, intro: "", summary: [],
                sections: [
                    ReportSection(kind: .completedWork, items: completed),
                    ReportSection(kind: .deliverables, items: deliverables),
                    ReportSection(kind: .openIssues, items: openIssues),
                    ReportSection(kind: .awaitingClient, items: awaiting),
                    ReportSection(kind: .timeSpent, items: timeItems),
                    ReportSection(kind: .nextSteps, items: Array(nextTasks)),
                ],
                warnings: warnings, totalSeconds: total)
        }
    }

    /// AI özet cümlelerini doğrular: yalnızca var olan maddelere dayanan cümleler kalır.
    public static func validatedSummary(_ sentences: [ReportSummarySentence], content: ReportContent) -> (kept: [ReportSummarySentence], dropped: [ReportSummarySentence]) {
        let valid = content.allItemIds
        var kept: [ReportSummarySentence] = []
        var dropped: [ReportSummarySentence] = []
        for s in sentences {
            let text = s.text.trimmed
            if !text.isEmpty, !s.itemIds.isEmpty, s.itemIds.allSatisfy(valid.contains) {
                kept.append(ReportSummarySentence(text: text, itemIds: s.itemIds))
            } else {
                dropped.append(s)
            }
        }
        return (kept, dropped)
    }
}

public enum DurationFormat {
    public static func short(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h == 0 { return LF("%d dk", max(m, seconds > 0 ? 1 : 0)) }
        if m == 0 { return LF("%d sa", h) }
        return LF("%1$d sa %2$d dk", h, m)
    }

    public static func clock(_ seconds: Int) -> String {
        String(format: "%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
    }
}

extension Store {
    public func reports(brandId: String) throws -> [Report] {
        try read { db in try Report.filter(Column("brandId") == brandId).order(Column("periodStart").desc).fetchAll(db) }
    }

    public func reportVersions(reportId: String) throws -> [ReportVersion] {
        try read { db in try ReportVersion.filter(Column("reportId") == reportId).order(Column("number").desc).fetchAll(db) }
    }

    public func reportShares(reportId: String) throws -> [ReportShare] {
        try read { db in try ReportShare.filter(Column("reportId") == reportId).order(Column("sharedAt").desc).fetchAll(db) }
    }

    public func content(of version: ReportVersion) throws -> ReportContent {
        try Self.decoder.decode(ReportContent.self, from: Data(version.contentJSON.utf8))
    }

    /// Dönem için rapor bulur veya oluşturur ve yeni taslak sürüm ekler.
    @discardableResult
    public func createReportDraft(brandId: String, period: ReportPeriod, interval: DateInterval, content: ReportContent,
                                  actor: Actor = .user) throws -> (Report, ReportVersion) {
        try writer.write { db in
            var report = try Report.filter(Column("brandId") == brandId && Column("period") == period.rawValue
                                           && Column("periodStart") == interval.start).fetchOne(db)
                ?? Report(brandId: brandId, period: period, periodStart: interval.start, periodEnd: interval.end)
            if try Report.fetchOne(db, key: report.id) == nil { try report.insert(db) }
            let version = try addVersion(db, report: &report, content: content, note: L("Kayıtlardan oluşturuldu"), actor: actor)
            return (report, version)
        }
    }

    /// Düzenlenmiş içeriği yeni sürüm olarak kaydeder. Her madde en az bir kayda bağlı kalmalıdır.
    @discardableResult
    public func saveReportVersion(reportId: String, content: ReportContent, note: String) throws -> ReportVersion {
        for item in content.sections.flatMap(\.items) where item.refs.isEmpty {
            throw MarkaError.validation(LF("Kaynağı olmayan madde kaydedilemez: “%@”", item.text))
        }
        let (kept, _) = ReportBuilder.validatedSummary(content.summary, content: content)
        guard kept.count == content.summary.count else {
            throw MarkaError.validation(L("Özet cümlelerinden biri artık var olmayan bir maddeye dayanıyor. Cümleyi düzelt veya kaldır."))
        }
        return try writer.write { db in
            guard var report = try Report.fetchOne(db, key: reportId) else { throw MarkaError.notFound(reportId) }
            // Referanslar bu markaya ait olmalı.
            try Self.validateRefs(db, content: content, brandId: report.brandId)
            return try addVersion(db, report: &report, content: content, note: note, actor: .user)
        }
    }

    static func validateRefs(_ db: Database, content: ReportContent, brandId: String) throws {
        // "Yapılan işler" yalnızca hâlâ doğrulanmış çalışma kayıtlarına dayanabilir.
        for item in content.section(.completedWork)?.items ?? [] {
            let logs = item.refs.filter { $0.kind == .workLog }
            guard !logs.isEmpty else { throw MarkaError.validation(LF("“%@” maddesi doğrulanmış bir iş kaydına dayanmıyor.", item.text)) }
            for ref in logs {
                let status = try String.fetchOne(db, sql: "SELECT status FROM workLog WHERE id = ?", arguments: [ref.id])
                guard status == WorkLogStatus.verified.rawValue else {
                    throw MarkaError.validation(LF("“%@” maddesinin iş kaydı artık doğrulanmış değil. İş kaydını yeniden doğrula ya da raporu iş kayıtlarından yenile.", item.text))
                }
            }
        }
        for ref in content.sections.flatMap(\.items).flatMap(\.refs) {
            let table: String
            switch ref.kind {
            case .task: table = "workTask"
            case .source: table = "source"
            case .workLog: table = "workLog"
            case .brandRecord: table = "brandRecord"
            case .wikiPage: table = "wikiPage"
            case .timeEntry: table = "timeEntry"
            case .report: table = "report"
            }
            let owner = try String.fetchOne(db, sql: "SELECT brandId FROM \(table) WHERE id = ?", arguments: [ref.id])
            guard owner == brandId else { throw MarkaError.brandScope }
        }
    }

    private func addVersion(_ db: Database, report: inout Report, content: ReportContent, note: String, actor: Actor) throws -> ReportVersion {
        let number = (try Int.fetchOne(db, sql: "SELECT MAX(number) FROM reportVersion WHERE reportId = ?", arguments: [report.id]) ?? 0) + 1
        let version = ReportVersion(reportId: report.id, number: number, contentJSON: Self.json(content) ?? "{}", note: note, actor: actor)
        try version.insert(db)
        let before = report
        report.currentVersionId = version.id
        report.status = .draft
        report.updatedAt = Date()
        try report.update(db)
        try audit(db, actor: actor, brandId: report.brandId, entity: "report", entityId: report.id, action: "version", before: before, after: report)
        return version
    }

    public func approveReport(reportId: String, versionId: String) throws {
        try writer.write { db in
            guard var report = try Report.fetchOne(db, key: reportId) else { throw MarkaError.notFound(reportId) }
            guard var v = try ReportVersion.fetchOne(db, key: versionId), v.reportId == reportId else { throw MarkaError.notFound(versionId) }
            guard report.currentVersionId == versionId else { throw MarkaError.validation(L("Yalnızca son sürüm onaylanabilir.")) }
            let content = try Self.decoder.decode(ReportContent.self, from: Data(v.contentJSON.utf8))
            try Self.validateRefs(db, content: content, brandId: report.brandId)
            v.approvedAt = Date()
            try v.update(db)
            let before = report
            report.status = .approved
            report.updatedAt = Date()
            try report.update(db)
            try audit(db, actor: .user, brandId: report.brandId, entity: "report", entityId: reportId, action: "approve", before: before, after: report)
        }
    }

    @discardableResult
    public func recordShare(reportId: String, versionId: String, channel: ShareChannel, recipient: String = "",
                            filePath: String = "", note: String = "") throws -> ReportShare {
        try writer.write { db in
            guard let report = try Report.fetchOne(db, key: reportId) else { throw MarkaError.notFound(reportId) }
            let share = ReportShare(reportId: reportId, versionId: versionId, channel: channel, recipient: recipient, filePath: filePath, note: note)
            try share.insert(db)
            try audit(db, actor: .user, brandId: report.brandId, entity: "reportShare", entityId: share.id, action: "create",
                      before: ReportShare?.none, after: share)
            return share
        }
    }

    // MARK: Planlı gönderim

    public func deliveryPlans(brandId: String) throws -> [DeliveryPlan] {
        try read { db in try DeliveryPlan.filter(Column("brandId") == brandId).order(Column("createdAt")).fetchAll(db) }
    }

    public func deliveryRuns(planId: String) throws -> [DeliveryRun] {
        try read { db in try DeliveryRun.filter(Column("planId") == planId).order(Column("at").desc).fetchAll(db) }
    }

    public func saveDeliveryPlan(_ plan: DeliveryPlan) throws {
        let recipients = plan.recipients.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !recipients.isEmpty, recipients.allSatisfy({ $0.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil }) else {
            throw MarkaError.validation(L("En az bir geçerli e-posta adresi gir (virgülle ayır)."))
        }
        let maxDay = plan.period == .weekly ? 7 : 28
        guard (1...maxDay).contains(plan.dayOfPeriod) else { throw MarkaError.validation(L("Gün seçimi geçersiz.")) }
        try writer.write { db in
            let before = try DeliveryPlan.fetchOne(db, key: plan.id)
            try plan.save(db)
            try audit(db, actor: .user, brandId: plan.brandId, entity: "deliveryPlan", entityId: plan.id,
                      action: before == nil ? "create" : "update", before: before, after: plan)
        }
    }

    public func deleteDeliveryPlan(_ id: String) throws {
        try writer.write { db in
            guard let p = try DeliveryPlan.fetchOne(db, key: id) else { return }
            try p.delete(db)
            try audit(db, actor: .user, brandId: p.brandId, entity: "deliveryPlan", entityId: id, action: "delete", before: p, after: DeliveryPlan?.none)
        }
    }
}

/// Planlı gönderim: zamanı gelen plan için taslak üretir. Beta sürümünde e-posta göndermez;
/// kullanıcı taslağı onaylayıp kendisi paylaşır.
public struct DeliveryScheduler: Sendable {
    public let store: Store
    public var calendar: Calendar

    public init(store: Store, calendar: Calendar = StatusService.turkishCalendar) {
        self.store = store
        self.calendar = calendar
    }

    public func isDue(_ plan: DeliveryPlan, now: Date) -> Bool {
        guard plan.enabled else { return false }
        let comps = calendar.dateComponents([.weekday, .day], from: now)
        let todayMatches: Bool
        switch plan.period {
        case .weekly:
            // Calendar.weekday: 1=Pazar … 7=Cumartesi → 1=Pazartesi … 7=Pazar
            let isoDay = ((comps.weekday ?? 1) + 5) % 7 + 1
            todayMatches = isoDay == plan.dayOfPeriod
        case .monthly:
            todayMatches = comps.day == plan.dayOfPeriod
        }
        guard todayMatches else { return false }
        if let last = plan.lastRunAt, calendar.isDate(last, inSameDayAs: now) { return false }
        return true
    }

    /// Zamanı gelen planlar için önceki tamamlanmış dönemin taslağını üretir.
    @discardableResult
    public func runDuePlans(now: Date = Date()) throws -> [DeliveryRun] {
        var runs: [DeliveryRun] = []
        let builder = ReportBuilder(store: store, calendar: calendar)
        for brand in try store.brands() {
            for var plan in try store.deliveryPlans(brandId: brand.id) where isDue(plan, now: now) {
                let reference = calendar.date(byAdding: plan.period == .weekly ? .weekOfYear : .month, value: -1, to: now)!
                let interval = builder.period(plan.period, containing: reference)
                let content = try builder.build(brandId: brand.id, period: interval, now: now)
                var run: DeliveryRun
                if content.isEmpty {
                    run = DeliveryRun(planId: plan.id, at: now, outcome: .skippedNoData, note: L("Dönemde doğrulanmış kayıt yok; taslak oluşturulmadı."))
                } else {
                    let (report, version) = try store.createReportDraft(brandId: brand.id, period: plan.period, interval: interval, content: content, actor: .system)
                    run = DeliveryRun(planId: plan.id, at: now, outcome: .draftCreated, reportId: report.id,
                                      note: LF("Taslak %d oluşturuldu. Gönderim için onayın bekleniyor (alıcılar: %@).", version.number, plan.recipients))
                    try store.recordShare(reportId: report.id, versionId: version.id, channel: .scheduledDraft, recipient: plan.recipients,
                                          note: L("Planlı taslak — gönderilmedi"))
                }
                plan.lastRunAt = now
                try store.writer.write { db in
                    try plan.update(db)
                    try run.insert(db)
                }
                runs.append(run)
            }
        }
        return runs
    }
}
