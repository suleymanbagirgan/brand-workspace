import Foundation
import GRDB

/// Görevin süre kayıtlarının özeti: kayıt sayısı (çalışan sayaç dahil) ve toplam saniye (çalışan sayacın şu ana kadarki
/// süresi dahil). Silme engeli ve onay metni bunu kullanır.
public struct TaskTimeSummary: Sendable, Hashable {
    public var count: Int
    public var seconds: Int
    public init(count: Int, seconds: Int) { self.count = count; self.seconds = seconds }
}

extension TimeEntry {
    /// Açık sayaç bu süreden uzun çalışıyorsa "unutulmuş olabilir" uyarısı gösterilir (U-03).
    public static let longRunningThreshold: TimeInterval = 8 * 3600

    public var isRunning: Bool { endedAt == nil }

    /// Uyarı kararı çekirdekte: yalnız çalışan sayaç, eşik aşılınca (eşiğin kendisi uyarı değil).
    public func isLongRunning(now: Date = Date()) -> Bool {
        isRunning && now.timeIntervalSince(startedAt) > Self.longRunningThreshold
    }
}

extension Store {
    /// Gelecek saat toleransı: saat ayarı farkı ve "şimdi"ye yuvarlanan dakika seçimi için.
    static let futureTolerance: TimeInterval = 60

    // MARK: Okuma (markaya yalıtılı)

    /// Görevin süre kayıtları, en yenisi önce. Görev başka markanınsa reddedilir.
    public func timeEntries(taskId: String, brandId: String) throws -> [TimeEntry] {
        try read { db in
            _ = try Self.task(db, taskId, brandId: brandId)
            return try TimeEntry.filter(Column("taskId") == taskId && Column("brandId") == brandId)
                .order(Column("startedAt").desc).fetchAll(db)
        }
    }

    public func taskTimeSummary(taskId: String, brandId: String, now: Date = Date()) throws -> TaskTimeSummary {
        try read { db in
            _ = try Self.task(db, taskId, brandId: brandId)
            return try Self.timeSummary(db, taskId: taskId, now: now)
        }
    }

    /// Çalışan sayaç 8 saati aştıysa o kayıt; yoksa `nil`.
    public func longRunningTimer(now: Date = Date()) throws -> TimeEntry? {
        guard let running = try runningTimer(), running.isLongRunning(now: now) else { return nil }
        return running
    }

    static func timeSummary(_ db: Database, taskId: String, now: Date = Date()) throws -> TaskTimeSummary {
        let count = try TimeEntry.filter(Column("taskId") == taskId).fetchCount(db)
        var seconds = try sumSeconds(db, taskId: taskId)
        if let running = try TimeEntry.filter(Column("taskId") == taskId && Column("endedAt") == nil).fetchOne(db) {
            seconds += max(0, Int(now.timeIntervalSince(running.startedAt)))
        }
        return TaskTimeSummary(count: count, seconds: seconds)
    }

    // MARK: Yazma (her biri denetim olayı bırakır)

    /// Elle süre kaydı (unutulan çalışma). Kurallar: `validateTimeRange`.
    @discardableResult
    public func addTimeEntry(taskId: String, brandId: String, startedAt: Date, endedAt: Date, note: String = "",
                             now: Date = Date()) throws -> TimeEntry {
        try writer.write { db in
            let t = try Self.task(db, taskId, brandId: brandId)
            try Self.validateTimeRange(db, brandId: brandId, startedAt: startedAt, endedAt: endedAt, excluding: nil, now: now)
            let entry = TimeEntry(taskId: t.id, brandId: brandId, startedAt: startedAt, endedAt: endedAt,
                                  seconds: Self.seconds(startedAt, endedAt), note: note.trimmed)
            try entry.insert(db)
            try Self.refreshTimeSpent(db, taskId: t.id)
            try audit(db, actor: .user, brandId: brandId, entity: "timeEntry", entityId: entry.id, action: "create",
                      before: TimeEntry?.none, after: entry)
            return entry
        }
    }

    /// Yanlış süreyi düzeltir (ör. kapatılmayı unutulan sayaç). Çalışan sayaç düzenlenmez; önce durdurulur.
    @discardableResult
    public func updateTimeEntry(_ id: String, brandId: String, startedAt: Date, endedAt: Date, note: String,
                                now: Date = Date()) throws -> TimeEntry {
        try writer.write { db in
            let before = try Self.timeEntry(db, id, brandId: brandId)
            guard !before.isRunning else { throw MarkaError.validation(L("Çalışan zamanlayıcı düzenlenemez. Önce durdur.")) }
            try Self.validateTimeRange(db, brandId: brandId, startedAt: startedAt, endedAt: endedAt, excluding: id, now: now)
            var e = before
            e.startedAt = startedAt
            e.endedAt = endedAt
            e.seconds = Self.seconds(startedAt, endedAt)
            e.note = note.trimmed
            guard e != before else { return e }
            try e.update(db)
            try Self.refreshTimeSpent(db, taskId: e.taskId)
            try audit(db, actor: .user, brandId: brandId, entity: "timeEntry", entityId: id, action: "update", before: before, after: e)
            return e
        }
    }

    public func deleteTimeEntry(_ id: String, brandId: String) throws {
        try writer.write { db in
            let e = try Self.timeEntry(db, id, brandId: brandId)
            guard !e.isRunning else { throw MarkaError.validation(L("Çalışan zamanlayıcı silinemez. Önce durdur.")) }
            try e.delete(db)
            try Self.refreshTimeSpent(db, taskId: e.taskId)
            try audit(db, actor: .user, brandId: brandId, entity: "timeEntry", entityId: id, action: "delete",
                      before: e, after: TimeEntry?.none)
        }
    }

    // MARK: Kurallar

    /// Bitiş başlangıçtan sonra (sıfır/negatif süre yok), en çok 24 saat, gelecekte değil ve aynı markanın başka bir süre
    /// kaydıyla (çalışan sayaç dahil) üst üste binmez. Yan yana gelen (biri bitince öteki başlayan) kayıt binme sayılmaz.
    static func validateTimeRange(_ db: Database, brandId: String, startedAt: Date, endedAt: Date, excluding: String?,
                                  now: Date) throws {
        guard endedAt > startedAt else { throw MarkaError.validation(L("Bitiş, başlangıçtan sonra olmalı.")) }
        guard endedAt.timeIntervalSince(startedAt) <= 24 * 3600 else {
            throw MarkaError.validation(L("Süre 1 sn ile 24 saat arasında olmalı."))
        }
        guard endedAt <= now.addingTimeInterval(futureTolerance) else {
            throw MarkaError.validation(L("Süre kaydı gelecekte bitemez."))
        }
        var q = TimeEntry.filter(Column("brandId") == brandId && Column("startedAt") < endedAt)
        if let excluding { q = q.filter(Column("id") != excluding) }
        let overlaps = try q.fetchAll(db).contains { other in (other.endedAt ?? now) > startedAt }
        guard !overlaps else { throw MarkaError.validation(L("Bu aralık başka bir süre kaydıyla çakışıyor.")) }
    }

    static func seconds(_ start: Date, _ end: Date) -> Int { Int(end.timeIntervalSince(start).rounded()) }

    static func refreshTimeSpent(_ db: Database, taskId: String) throws {
        try db.execute(sql: "UPDATE workTask SET timeSpentSeconds = ? WHERE id = ?",
                       arguments: [try sumSeconds(db, taskId: taskId), taskId])
    }

    static func task(_ db: Database, _ id: String, brandId: String) throws -> WorkTask {
        guard let t = try WorkTask.fetchOne(db, key: id) else { throw MarkaError.notFound(id) }
        guard t.brandId == brandId else { throw MarkaError.brandScope }
        return t
    }

    static func timeEntry(_ db: Database, _ id: String, brandId: String) throws -> TimeEntry {
        guard let e = try TimeEntry.fetchOne(db, key: id) else { throw MarkaError.notFound(id) }
        guard e.brandId == brandId else { throw MarkaError.brandScope }
        return e
    }
}
