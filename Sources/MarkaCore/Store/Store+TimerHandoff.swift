import Foundation
import GRDB

/// Sayaç başlatılırken sessizce olanlar (H1-08, U-19): tek çalışan sayaç kuralı yüzünden başka görevdeki sayaç durdu mu,
/// başlatılan görev "Sürüyor"a geçti mi. Arayüz bunu kısa, sakin bir bildirimle gösterir; veri değiştirmez.
public struct TimerHandoff: Equatable, Sendable {
    /// Durdurulan sayacın görevi, markası ve süresi (saniye). Başka sayaç yoksa ya da aynı görevse `nil`.
    public struct Stopped: Equatable, Sendable {
        public let taskTitle: String
        public let brandId: String
        public let brandName: String
        public let seconds: Int
    }

    public let stopped: Stopped?
    /// Başlatılan görevin durumu "Yapılacak"/"Bekliyor"dan "Sürüyor"a geçti.
    public let movedToInProgress: Bool
    public let taskTitle: String

    /// Kullanıcıya söylenecek bir şey var mı.
    public var isWorthTelling: Bool { stopped != nil || movedToInProgress }
}

extension Store {
    /// `startTimer` ile aynıdır; ek olarak durdurulan sayacı ve durum değişikliğini döndürür (bildirim için).
    @discardableResult
    public func startTimerReportingHandoff(taskId: String, at: Date = Date()) throws -> TimerHandoff {
        let before: (running: TimeEntry?, status: TaskStatus) = try read { db in
            guard let t = try WorkTask.fetchOne(db, key: taskId) else { throw MarkaError.notFound(taskId) }
            return (try TimeEntry.filter(Column("endedAt") == nil).fetchOne(db), t.status)
        }
        try startTimer(taskId: taskId, at: at)
        return try read { db in
            let task = try WorkTask.fetchOne(db, key: taskId)
            var stopped: TimerHandoff.Stopped?
            if let old = before.running, old.taskId != taskId,
               let ended = try TimeEntry.fetchOne(db, key: old.id) {
                let oldTask = try WorkTask.fetchOne(db, key: old.taskId)
                let brand = try Brand.fetchOne(db, key: old.brandId)
                // Kayda yazılan süre (yuvarlanmış); bildirim ile süre listesi aynı sayıyı söyler.
                stopped = .init(taskTitle: oldTask?.title ?? "", brandId: old.brandId, brandName: brand?.name ?? "",
                                seconds: ended.seconds)
            }
            let moved = before.status != .inProgress && task?.status == .inProgress
            return TimerHandoff(stopped: stopped, movedToInProgress: moved, taskTitle: task?.title ?? "")
        }
    }
}
