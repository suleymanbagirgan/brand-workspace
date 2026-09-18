import Foundation
import GRDB

extension Store {
    public func tasks(brandId: String?, statuses: [TaskStatus]? = nil) throws -> [WorkTask] {
        try read { db in
            var q = WorkTask.all()
            if let brandId { q = q.filter(Column("brandId") == brandId) }
            if let statuses { q = q.filter(statuses.map(\.rawValue).contains(Column("status"))) }
            return try q.fetchAll(db).sorted(by: WorkTask.displayOrder)
        }
    }

    public func task(_ id: String) throws -> WorkTask {
        guard let t = try read({ db in try WorkTask.fetchOne(db, key: id) }) else { throw MarkaError.notFound(id) }
        return t
    }

    @discardableResult
    public func saveTask(_ task: WorkTask, actor: Actor = .user) throws -> WorkTask {
        guard !task.title.trimmed.isEmpty else { throw MarkaError.validation(L("Görev başlığı boş olamaz.")) }
        if let d = task.dueDate, !DayString.isValid(d) { throw MarkaError.validation(L("Tarih geçersiz.")) }
        guard (0...3).contains(task.priority) else { throw MarkaError.validation(L("Öncelik 0–3 arasında olmalı.")) }
        return try writer.write { db in try saveTask(db, task, actor: actor) }
    }

    func saveTask(_ db: Database, _ task: WorkTask, actor: Actor) throws -> WorkTask {
        if let pid = task.projectId {
            guard let p = try Project.fetchOne(db, key: pid), p.brandId == task.brandId else { throw MarkaError.brandScope }
        }
        let before = try WorkTask.fetchOne(db, key: task.id)
        var t = task
        t.title = t.title.trimmed
        t.updatedAt = Date()
        if t.status == .done, before?.status != .done { t.completedAt = t.completedAt ?? Date() }
        if t.status != .done { t.completedAt = nil }
        if !t.status.isOpen { try stopRunningTimer(db, onlyTaskId: t.id) }
        // Süre alanı süre kayıtlarından türetilir; dışarıdan gelen değer yok sayılır.
        if before != nil { t.timeSpentSeconds = try Self.sumSeconds(db, taskId: t.id) }
        try t.save(db)
        try audit(db, actor: actor, brandId: t.brandId, entity: "task", entityId: t.id,
                  action: before == nil ? "create" : "update", before: before, after: t)
        return t
    }

    public func setTaskStatus(_ id: String, _ status: TaskStatus, actor: Actor = .user) throws {
        var t = try task(id)
        t.status = status
        try saveTask(t, actor: actor)
    }

    public func deleteTask(_ id: String) throws {
        try writer.write { db in
            guard let t = try WorkTask.fetchOne(db, key: id) else { return }
            try t.delete(db)
            try audit(db, actor: .user, brandId: t.brandId, entity: "task", entityId: id, action: "delete",
                      before: t, after: WorkTask?.none)
        }
    }

    // MARK: Süre

    public func runningTimer() throws -> TimeEntry? {
        try read { db in try TimeEntry.filter(Column("endedAt") == nil).fetchOne(db) }
    }

    /// Sayacı başlatır; başka görevde çalışan sayaç varsa önce onu durdurur.
    @discardableResult
    public func startTimer(taskId: String, at: Date = Date()) throws -> TimeEntry {
        try writer.write { db in
            guard var t = try WorkTask.fetchOne(db, key: taskId) else { throw MarkaError.notFound(taskId) }
            guard t.status.isOpen else { throw MarkaError.validation(L("Bitmiş göreve süre başlatılamaz. Önce görevi yeniden aç.")) }
            if let running = try TimeEntry.filter(Column("endedAt") == nil).fetchOne(db) {
                if running.taskId == taskId { return running }
                try stopRunningTimer(db, at: at)
            }
            let entry = TimeEntry(taskId: taskId, brandId: t.brandId, startedAt: at)
            try entry.insert(db)
            if t.status == .todo || t.status == .waiting {
                let before = t
                t.status = .inProgress
                t.updatedAt = Date()
                try t.update(db)
                try audit(db, actor: .user, brandId: t.brandId, entity: "task", entityId: t.id, action: "update", before: before, after: t)
            }
            try audit(db, actor: .user, brandId: t.brandId, entity: "timeEntry", entityId: entry.id, action: "start",
                      before: TimeEntry?.none, after: entry)
            return entry
        }
    }

    @discardableResult
    public func stopTimer(at: Date = Date()) throws -> TimeEntry? {
        try writer.write { db in try stopRunningTimer(db, at: at) }
    }

    @discardableResult
    func stopRunningTimer(_ db: Database, at: Date = Date(), onlyTaskId: String? = nil) throws -> TimeEntry? {
        guard var entry = try TimeEntry.filter(Column("endedAt") == nil).fetchOne(db) else { return nil }
        if let onlyTaskId, entry.taskId != onlyTaskId { return nil }
        let before = entry
        entry.endedAt = max(at, entry.startedAt)
        entry.seconds = Int(entry.endedAt!.timeIntervalSince(entry.startedAt).rounded())
        try entry.update(db)
        try db.execute(sql: "UPDATE workTask SET timeSpentSeconds = ? WHERE id = ?",
                       arguments: [try Self.sumSeconds(db, taskId: entry.taskId), entry.taskId])
        try audit(db, actor: .user, brandId: entry.brandId, entity: "timeEntry", entityId: entry.id, action: "stop",
                  before: before, after: entry)
        return entry
    }

    /// Elle süre ekleme (ör. unutulan çalışma).
    @discardableResult
    public func addManualTime(taskId: String, seconds: Int, endingAt: Date = Date(), note: String = "") throws -> TimeEntry {
        guard seconds > 0, seconds < 24 * 3600 else { throw MarkaError.validation(L("Süre 1 sn ile 24 saat arasında olmalı.")) }
        return try writer.write { db in
            guard let t = try WorkTask.fetchOne(db, key: taskId) else { throw MarkaError.notFound(taskId) }
            let entry = TimeEntry(taskId: taskId, brandId: t.brandId, startedAt: endingAt.addingTimeInterval(-Double(seconds)),
                                  endedAt: endingAt, seconds: seconds, note: note)
            try entry.insert(db)
            try db.execute(sql: "UPDATE workTask SET timeSpentSeconds = ? WHERE id = ?",
                           arguments: [try Self.sumSeconds(db, taskId: taskId), taskId])
            try audit(db, actor: .user, brandId: t.brandId, entity: "timeEntry", entityId: entry.id, action: "create",
                      before: TimeEntry?.none, after: entry)
            return entry
        }
    }

    public func timeEntries(brandId: String?, from: Date, to: Date) throws -> [TimeEntry] {
        try read { db in
            var q = TimeEntry.filter(Column("endedAt") != nil && Column("endedAt") >= from && Column("endedAt") < to)
            if let brandId { q = q.filter(Column("brandId") == brandId) }
            return try q.order(Column("startedAt")).fetchAll(db)
        }
    }

    static func sumSeconds(_ db: Database, taskId: String) throws -> Int {
        try Int.fetchOne(db, sql: "SELECT COALESCE(SUM(seconds), 0) FROM timeEntry WHERE taskId = ? AND endedAt IS NOT NULL",
                         arguments: [taskId]) ?? 0
    }
}

extension WorkTask {
    /// Açık görevler önce; geciken/yakın tarihli, sonra yüksek öncelik.
    public static func displayOrder(_ a: WorkTask, _ b: WorkTask) -> Bool {
        if a.status.isOpen != b.status.isOpen { return a.status.isOpen }
        if !a.status.isOpen { return (a.completedAt ?? a.updatedAt) > (b.completedAt ?? b.updatedAt) }
        switch (a.dueDate, b.dueDate) {
        case let (x?, y?) where x != y: return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: break
        }
        if a.priority != b.priority { return a.priority > b.priority }
        return a.createdAt < b.createdAt
    }

    public func isOverdue(today: String) -> Bool {
        guard status.isOpen, let dueDate else { return false }
        return dueDate < today
    }
}
