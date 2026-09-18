import Foundation
import GRDB

public struct WorkLogDetail: Sendable, Hashable, Identifiable {
    public var log: WorkLog
    public var inputs: [Source]
    public var outputs: [Source]
    public var task: WorkTask?
    public var id: String { log.id }

    public init(log: WorkLog, inputs: [Source], outputs: [Source], task: WorkTask?) {
        self.log = log; self.inputs = inputs; self.outputs = outputs; self.task = task
    }
}

extension Store {
    public func workLogs(brandId: String?, statuses: [WorkLogStatus]? = nil) throws -> [WorkLog] {
        try read { db in
            var q = WorkLog.all()
            if let brandId { q = q.filter(Column("brandId") == brandId) }
            if let statuses { q = q.filter(statuses.map(\.rawValue).contains(Column("status"))) }
            return try q.order(Column("occurredAt").desc).fetchAll(db)
        }
    }

    public func workLogDetail(_ id: String) throws -> WorkLogDetail {
        try read { db in try Self.workLogDetail(db, id) }
    }

    static func workLogDetail(_ db: Database, _ id: String) throws -> WorkLogDetail {
        guard let log = try WorkLog.fetchOne(db, key: id) else { throw MarkaError.notFound(id) }
        let links = try WorkLogSource.filter(Column("workLogId") == id).fetchAll(db)
        func load(_ role: WorkLogSourceRole) throws -> [Source] {
            try links.filter { $0.role == role }.compactMap { try Source.fetchOne(db, key: $0.sourceId) }
        }
        let task = try log.taskId.flatMap { try WorkTask.fetchOne(db, key: $0) }
        return WorkLogDetail(log: log, inputs: try load(.input), outputs: try load(.output), task: task)
    }

    /// Çalışma kaydını ve kaynak bağlantılarını kaydeder. Doğrulanmış kayıt içerik değişince taslağa düşer.
    @discardableResult
    public func saveWorkLog(_ log: WorkLog, inputSourceIds: [String], outputSourceIds: [String],
                            actor: Actor = .user) throws -> WorkLog {
        guard !log.title.trimmed.isEmpty else { throw MarkaError.validation(L("Başlık boş olamaz.")) }
        return try writer.write { db in
            try saveWorkLog(db, log, inputs: inputSourceIds, outputs: outputSourceIds, actor: actor)
        }
    }

    func saveWorkLog(_ db: Database, _ log: WorkLog, inputs: [String], outputs: [String], actor: Actor) throws -> WorkLog {
        for sid in Set(inputs + outputs) {
            guard let s = try Source.fetchOne(db, key: sid), s.brandId == log.brandId else { throw MarkaError.brandScope }
        }
        if let tid = log.taskId {
            guard let t = try WorkTask.fetchOne(db, key: tid), t.brandId == log.brandId else { throw MarkaError.brandScope }
        }
        let before = try WorkLog.fetchOne(db, key: log.id)
        var l = log
        l.updatedAt = Date()
        if let before, before.status == .verified {
            let beforeLinks = Set(try WorkLogSource.filter(Column("workLogId") == l.id).fetchAll(db).map { "\($0.role.rawValue):\($0.sourceId)" })
            let newLinks = Set(inputs.map { "input:\($0)" } + outputs.map { "output:\($0)" })
            if !before.sameContent(as: l) || beforeLinks != newLinks {
                l.status = .draft
                l.verifiedAt = nil
                l.verifiedBy = nil
            }
        }
        try l.save(db)
        try WorkLogSource.filter(Column("workLogId") == l.id).deleteAll(db)
        for sid in Set(inputs) { try WorkLogSource(workLogId: l.id, sourceId: sid, role: .input).insert(db) }
        for sid in Set(outputs) { try WorkLogSource(workLogId: l.id, sourceId: sid, role: .output).insert(db) }
        try audit(db, actor: actor, brandId: l.brandId, entity: "workLog", entityId: l.id,
                  action: before == nil ? "create" : "update", before: before, after: l)
        return l
    }

    /// Kaydı doğrular. Doğrulama kullanıcı eylemidir; AI doğrulayamaz.
    public func verifyWorkLog(_ id: String, verifiedBy: String) throws {
        try writer.write { db in
            let detail = try Self.workLogDetail(db, id)
            var l = detail.log
            // Kural tek yerde (`WorkLogDetail.verificationProblem`); Akış'taki satır içi "Doğrula" da onu sorar.
            if let problem = detail.verificationProblem { throw MarkaError.validation(problem) }
            guard !verifiedBy.trimmed.isEmpty else { throw MarkaError.validation(L("Doğrulayan kişi boş olamaz.")) }
            let before = l
            l.status = .verified
            l.verifiedAt = Date()
            l.verifiedBy = verifiedBy.trimmed
            l.updatedAt = Date()
            try l.update(db)
            try audit(db, actor: .user, brandId: l.brandId, entity: "workLog", entityId: id, action: "verify", before: before, after: l)
        }
    }

    /// Görev için çalışma kaydı önerilmeli mi? Görevin geri çekilmemiş bir çalışma kaydı varsa önerilmez.
    /// Görev yoksa (silinmişse) önerilmez.
    public func needsWorkLog(taskId: String) throws -> Bool {
        try read { db in
            guard try WorkTask.fetchOne(db, key: taskId) != nil else { return false }
            let existing = try WorkLog.filter(Column("taskId") == taskId && Column("status") != WorkLogStatus.retracted.rawValue).fetchCount(db)
            return existing == 0
        }
    }

    public func retractWorkLog(_ id: String) throws {
        try writer.write { db in
            guard var l = try WorkLog.fetchOne(db, key: id) else { throw MarkaError.notFound(id) }
            let before = l
            l.status = .retracted
            l.updatedAt = Date()
            try l.update(db)
            try audit(db, actor: .user, brandId: l.brandId, entity: "workLog", entityId: id, action: "retract", before: before, after: l)
        }
    }
}

extension WorkLog {
    /// Görevden önceden doldurulmuş çalışma kaydı taslağı. Tamamlanmış görevde işin tarihi tamamlanma anıdır; böylece
    /// kayıt, görevin tamamlandığı dönemin raporuna girer.
    public static func draft(for task: WorkTask, now: Date = Date()) -> WorkLog {
        WorkLog(brandId: task.brandId, taskId: task.id, title: task.title, occurredAt: task.completedAt ?? now)
    }

    func sameContent(as other: WorkLog) -> Bool {
        title == other.title && requested == other.requested && performed == other.performed && decision == other.decision
            && approvedBy == other.approvedBy && clientNotified == other.clientNotified && taskId == other.taskId
            && occurredAt == other.occurredAt
    }
}
