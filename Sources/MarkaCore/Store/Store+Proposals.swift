import Foundation
import GRDB

/// AI önerilerinin yük biçimleri. AI veri değiştirmez; bu yükler kullanıcı onayıyla uygulanır.
public enum ProposalPayload {
    public struct CreateTask: Codable, Sendable, Hashable {
        public var title: String
        public var notes: String?
        public var priority: Int?
        public var dueDate: String?
        public var assignee: String?
        /// Markanın bir projesi (terminal önerisinde proje adından eşlenir). Başka markanın projesi reddedilir.
        public var projectId: String?
        /// Başlangıç durumu (terminal önerisi: yapılacak / sürüyor / bekliyor / bitti). `nil`: yapılacak.
        public var status: TaskStatus?
        public init(title: String, notes: String? = nil, priority: Int? = nil, dueDate: String? = nil, assignee: String? = nil,
                    projectId: String? = nil, status: TaskStatus? = nil) {
            self.title = title; self.notes = notes; self.priority = priority; self.dueDate = dueDate; self.assignee = assignee
            self.projectId = projectId; self.status = status
        }
    }

    public struct CompleteTask: Codable, Sendable, Hashable {
        public var taskId: String
        public init(taskId: String) { self.taskId = taskId }
    }

    public struct CreateWorkLog: Codable, Sendable, Hashable {
        public var title: String
        public var requested: String
        public var performed: String
        public var decision: String?
        public var clientNotified: String?
        public var taskId: String?
        public var inputSourceIds: [String]
        public var outputSourceIds: [String]
        /// Kim onayladı? (terminal önerisi)
        public var approvedBy: String?
        /// İşin yapıldığı gün (`yyyy-MM-dd`); `nil`: onay anı.
        public var occurredOn: String?
        /// Görev kimliği verilmediyse görev başlığı: onay anında markanın aynı başlıklı görevine bağlanır
        /// (aynı dosyadaki görev önerisi önce uygulandığı için ona da bağlanabilir). Bulunamazsa bağlanmaz.
        public var taskTitle: String?
        /// Marka klasöründen okunup içerik adresli depoya alınmış dosyalar. Kaynak kaydı yalnızca onayla oluşur.
        public var inputFiles: [StagedFile]?
        public var outputFiles: [StagedFile]?
        /// Onay anında bu öneri için yeni oluşturulan kaynaklar; geri almada arşivlenir.
        public var createdSourceIds: [String]?
        public init(title: String, requested: String, performed: String, decision: String? = nil, clientNotified: String? = nil,
                    taskId: String? = nil, inputSourceIds: [String] = [], outputSourceIds: [String] = [],
                    approvedBy: String? = nil, occurredOn: String? = nil, taskTitle: String? = nil,
                    inputFiles: [StagedFile]? = nil, outputFiles: [StagedFile]? = nil) {
            self.title = title; self.requested = requested; self.performed = performed; self.decision = decision
            self.clientNotified = clientNotified; self.taskId = taskId; self.inputSourceIds = inputSourceIds
            self.outputSourceIds = outputSourceIds; self.approvedBy = approvedBy; self.occurredOn = occurredOn
            self.taskTitle = taskTitle; self.inputFiles = inputFiles; self.outputFiles = outputFiles
        }
    }

    /// Öneriye bağlı, depoya alınmış dosya (kaynak kaydı değil).
    public struct StagedFile: Codable, Sendable, Hashable {
        /// Marka klasörüne göreli yol (gösterim için).
        public var path: String
        public var fileName: String
        public var storedPath: String
        public var sha256: String
        public var byteSize: Int
        public var mimeType: String
        public init(path: String, fileName: String, storedPath: String, sha256: String, byteSize: Int, mimeType: String) {
            self.path = path; self.fileName = fileName; self.storedPath = storedPath; self.sha256 = sha256
            self.byteSize = byteSize; self.mimeType = mimeType
        }
    }

    /// Metin kaynağı önerisi (not veya görüşme notu).
    public struct CreateNote: Codable, Sendable, Hashable {
        public var kind: SourceKind
        public var title: String
        public var body: String
        /// Görüşmenin/notun günü (`yyyy-MM-dd`); `nil`: onay anı.
        public var capturedOn: String?
        public init(kind: SourceKind, title: String, body: String, capturedOn: String? = nil) {
            self.kind = kind; self.title = title; self.body = body; self.capturedOn = capturedOn
        }
    }

    public struct CreateOutput: Codable, Sendable, Hashable {
        public var fileName: String
        public var title: String
        public var content: String
        public var inputSourceIds: [String]
        public init(fileName: String, title: String, content: String, inputSourceIds: [String] = []) {
            self.fileName = fileName; self.title = title; self.content = content; self.inputSourceIds = inputSourceIds
        }
    }

    public struct CreateBrandRecord: Codable, Sendable, Hashable {
        public var kind: BrandRecordKind
        public var title: String
        public var detail: String?
        public var dueDate: String?
        public var sourceId: String?
        public init(kind: BrandRecordKind, title: String, detail: String? = nil, dueDate: String? = nil, sourceId: String? = nil) {
            self.kind = kind; self.title = title; self.detail = detail; self.dueDate = dueDate; self.sourceId = sourceId
        }
    }
}

extension Store {
    public func proposals(sessionId: String) throws -> [AIProposal] {
        try read { db in try AIProposal.filter(Column("sessionId") == sessionId).order(Column("createdAt")).fetchAll(db) }
    }

    public func proposals(brandId: String, status: ProposalStatus? = nil) throws -> [AIProposal] {
        try read { db in
            var q = AIProposal.filter(Column("brandId") == brandId)
            if let status { q = q.filter(Column("status") == status.rawValue) }
            return try q.order(Column("createdAt").desc).fetchAll(db)
        }
    }

    /// Öneri oluşturur. Yük, markaya ait olmayan kimlik içeriyorsa reddedilir.
    @discardableResult
    public func createProposal<P: Encodable>(sessionId: String?, brandId: String, kind: ProposalKind, summary: String,
                                             payload: P) throws -> AIProposal {
        let json = Self.json(payload) ?? "{}"
        return try writer.write { db in
            try validateProposal(db, brandId: brandId, kind: kind, json: json)
            let p = AIProposal(sessionId: sessionId, brandId: brandId, kind: kind, summary: summary, payloadJSON: json)
            try p.insert(db)
            return p
        }
    }

    func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        do { return try Self.decoder.decode(T.self, from: Data(json.utf8)) } catch {
            throw MarkaError.validation(L("Öneri biçimi geçersiz."))
        }
    }

    /// "oneri:<id>" biçimindeki kimlikleri, uygulanmış çıktı önerisinin kaynak kimliğine çevirir.
    func resolveSourceIds(_ db: Database, _ ids: [String], brandId: String, requireApplied: Bool) throws -> [String] {
        try ids.compactMap { id in
            guard id.hasPrefix("oneri:") else { return id }
            let pid = String(id.dropFirst("oneri:".count))
            guard let p = try AIProposal.fetchOne(db, key: pid), p.brandId == brandId, p.kind == .createOutput else {
                throw MarkaError.validation(LF("Çıktı önerisi bulunamadı: %@", pid))
            }
            if p.status == .applied, let sid = p.resultEntityId { return sid }
            if requireApplied { throw MarkaError.validation(L("Bu iş kaydı henüz onaylanmamış bir dosya önerisine bağlı. Önce o öneriyi onayla.")) }
            return nil
        }
    }

    private func requireSources(_ db: Database, _ ids: [String], brandId: String) throws {
        for id in try resolveSourceIds(db, ids, brandId: brandId, requireApplied: false) {
            guard let s = try Source.fetchOne(db, key: id) else { throw MarkaError.validation(LF("Kaynak bulunamadı: %@", id)) }
            guard s.brandId == brandId else { throw MarkaError.brandScope }
        }
    }

    func validateProposal(_ db: Database, brandId: String, kind: ProposalKind, json: String) throws {
        switch kind {
        case .createTask:
            let p = try decode(ProposalPayload.CreateTask.self, json)
            guard !p.title.trimmed.isEmpty else { throw MarkaError.validation(L("Görev başlığı boş olamaz.")) }
            if let d = p.dueDate, !DayString.isValid(d) { throw MarkaError.validation(L("Tarih geçersiz.")) }
            if let pid = p.projectId {
                guard let project = try Project.fetchOne(db, key: pid) else { throw MarkaError.notFound(pid) }
                guard project.brandId == brandId else { throw MarkaError.brandScope }
            }
        case .completeTask:
            let p = try decode(ProposalPayload.CompleteTask.self, json)
            guard let t = try WorkTask.fetchOne(db, key: p.taskId) else { throw MarkaError.notFound(p.taskId) }
            guard t.brandId == brandId else { throw MarkaError.brandScope }
        case .createWorkLog:
            let p = try decode(ProposalPayload.CreateWorkLog.self, json)
            guard !p.title.trimmed.isEmpty else { throw MarkaError.validation(L("Başlık boş olamaz.")) }
            if let d = p.occurredOn, !DayString.isValid(d) { throw MarkaError.validation(L("Tarih geçersiz.")) }
            for f in (p.inputFiles ?? []) + (p.outputFiles ?? []) where f.sha256.count != 64 || f.storedPath.contains("..") {
                throw MarkaError.validation(L("Öneri biçimi geçersiz."))
            }
            try requireSources(db, p.inputSourceIds + p.outputSourceIds, brandId: brandId)
            if let tid = p.taskId {
                guard let t = try WorkTask.fetchOne(db, key: tid) else { throw MarkaError.notFound(tid) }
                guard t.brandId == brandId else { throw MarkaError.brandScope }
            }
        case .createOutput:
            let p = try decode(ProposalPayload.CreateOutput.self, json)
            guard !p.content.trimmed.isEmpty else { throw MarkaError.validation(L("Çıktı içeriği boş olamaz.")) }
            try requireSources(db, p.inputSourceIds, brandId: brandId)
        case .createBrandRecord:
            let p = try decode(ProposalPayload.CreateBrandRecord.self, json)
            guard !p.title.trimmed.isEmpty else { throw MarkaError.validation(L("Kayıt başlığı boş olamaz.")) }
            if let d = p.dueDate, !DayString.isValid(d) { throw MarkaError.validation(L("Tarih geçersiz.")) }
            if let sid = p.sourceId { try requireSources(db, [sid], brandId: brandId) }
        case .createNote:
            let p = try decode(ProposalPayload.CreateNote.self, json)
            guard p.kind == .note || p.kind == .meeting else { throw MarkaError.validation(L("Öneri biçimi geçersiz.")) }
            guard !p.title.trimmed.isEmpty else { throw MarkaError.validation(L("Başlık boş olamaz.")) }
            guard !p.body.trimmed.isEmpty else { throw MarkaError.validation(L("Metin boş olamaz.")) }
            if let d = p.capturedOn, !DayString.isValid(d) { throw MarkaError.validation(L("Tarih geçersiz.")) }
        case .wikiRevision:
            break // Bilgi sürümleri öneri olarak doğrudan `wikiRevision` tablosuna yazılır.
        }
    }

    /// Kullanıcı onayı: öneriyi uygular ve oluşan kaydın kimliğini saklar.
    @discardableResult
    public func applyProposal(_ id: String) throws -> AIProposal {
        try writer.write { db in try applyProposal(db, id) }
    }

    func applyProposal(_ db: Database, _ id: String) throws -> AIProposal {
        do {
            guard var p = try AIProposal.fetchOne(db, key: id) else { throw MarkaError.notFound(id) }
            guard p.status == .pending else { throw MarkaError.validation(L("Bu öneri zaten sonuçlandırılmış.")) }
            try validateProposal(db, brandId: p.brandId, kind: p.kind, json: p.payloadJSON)
            var resultId: String?
            switch p.kind {
            case .createTask:
                let x = try decode(ProposalPayload.CreateTask.self, p.payloadJSON)
                let t = try saveTask(db, WorkTask(brandId: p.brandId, projectId: x.projectId, title: x.title, notes: x.notes ?? "",
                                                  assignee: x.assignee ?? "", priority: min(max(x.priority ?? 0, 0), 3),
                                                  dueDate: x.dueDate, status: x.status ?? .todo, actor: .ai), actor: .ai)
                resultId = t.id
            case .completeTask:
                let x = try decode(ProposalPayload.CompleteTask.self, p.payloadJSON)
                guard var t = try WorkTask.fetchOne(db, key: x.taskId) else { throw MarkaError.notFound(x.taskId) }
                t.status = .done
                resultId = try saveTask(db, t, actor: .ai).id
            case .createWorkLog:
                var x = try decode(ProposalPayload.CreateWorkLog.self, p.payloadJSON)
                let taskId = try x.taskId ?? x.taskTitle.flatMap { try taskMatching(db, title: $0, brandId: p.brandId)?.id }
                var created: [String] = []
                let inputFiles = try (x.inputFiles ?? []).map { try stagedSource(db, $0, kind: .file, brandId: p.brandId, created: &created) }
                let outputFiles = try (x.outputFiles ?? []).map { try stagedSource(db, $0, kind: .workOutput, brandId: p.brandId, created: &created) }
                let log = WorkLog(brandId: p.brandId, taskId: taskId, title: x.title, requested: x.requested, performed: x.performed,
                                  decision: x.decision ?? "", approvedBy: x.approvedBy ?? "", clientNotified: x.clientNotified ?? "",
                                  status: .draft, occurredAt: x.occurredOn.flatMap { DayString.date($0) } ?? Date(),
                                  actor: .ai, sessionId: p.sessionId)
                resultId = try saveWorkLog(db, log, inputs: try resolveSourceIds(db, x.inputSourceIds, brandId: p.brandId, requireApplied: true) + inputFiles,
                                           outputs: try resolveSourceIds(db, x.outputSourceIds, brandId: p.brandId, requireApplied: true) + outputFiles,
                                           actor: .ai).id
                if !created.isEmpty {
                    x.createdSourceIds = created
                    p.payloadJSON = Self.json(x) ?? p.payloadJSON
                }
            case .createOutput:
                let x = try decode(ProposalPayload.CreateOutput.self, p.payloadJSON)
                let data = Data(x.content.utf8)
                let ext = (x.fileName as NSString).pathExtension.isEmpty ? "md" : (x.fileName as NSString).pathExtension
                let stored = try vault.store(data: data, fileExtension: ext)
                let s = Source(brandId: p.brandId, kind: .workOutput, title: x.title.trimmed.isEmpty ? x.fileName : x.title,
                               body: x.content, fileName: x.fileName, filePath: stored.relativePath, mimeType: "text/markdown",
                               sha256: stored.sha256, byteSize: stored.byteSize, actor: .ai)
                try s.insert(db)
                try audit(db, actor: .ai, brandId: p.brandId, entity: "source", entityId: s.id, action: "create",
                          before: Source?.none, after: SourceAuditView(s))
                resultId = s.id
            case .createBrandRecord:
                let x = try decode(ProposalPayload.CreateBrandRecord.self, p.payloadJSON)
                let r = BrandRecord(brandId: p.brandId, kind: x.kind, title: x.title, detail: x.detail ?? "", dueDate: x.dueDate, sourceId: x.sourceId)
                try r.insert(db)
                try audit(db, actor: .ai, brandId: p.brandId, entity: "brandRecord", entityId: r.id, action: "create",
                          before: BrandRecord?.none, after: r)
                resultId = r.id
            case .createNote:
                let x = try decode(ProposalPayload.CreateNote.self, p.payloadJSON)
                let data = Data(x.body.utf8)
                let s = Source(brandId: p.brandId, kind: x.kind, title: x.title.trimmed, body: x.body, sha256: FileVault.sha256(data),
                               byteSize: data.count, capturedAt: x.capturedOn.flatMap { DayString.date($0) } ?? Date(), actor: .ai)
                try s.insert(db)
                try audit(db, actor: .ai, brandId: p.brandId, entity: "source", entityId: s.id, action: "create",
                          before: Source?.none, after: SourceAuditView(s))
                resultId = s.id
            case .wikiRevision:
                throw MarkaError.validation(L("Bilgi güncellemeleri öneriler sayfasından onaylanır."))
            }
            p.status = .applied
            p.decidedAt = Date()
            p.resultEntityId = resultId
            try p.update(db)
            return p
        }
    }

    public func rejectProposal(_ id: String) throws {
        try writer.write { db in try rejectProposal(db, id) }
    }

    func rejectProposal(_ db: Database, _ id: String) throws {
        do {
            guard var p = try AIProposal.fetchOne(db, key: id) else { throw MarkaError.notFound(id) }
            guard p.status == .pending else { return }
            if p.kind == .wikiRevision, let rid = p.resultEntityId,
               var r = try WikiRevision.fetchOne(db, key: rid), r.state == .proposed {
                r.state = .rejected
                r.decidedAt = Date()
                try r.update(db)
            }
            let before = p
            p.status = .rejected
            p.decidedAt = Date()
            try p.update(db)
            try audit(db, actor: .user, brandId: p.brandId, entity: "aiProposal", entityId: p.id, action: "reject", before: before, after: p)
        }
    }

    /// Uygulanmış AI önerisini geri alır. Kullanıcı sonradan kaydı değiştirdiyse geri alma reddedilir.
    public func revertProposal(_ id: String) throws {
        try writer.write { db in try revertProposal(db, id) }
    }

    func revertProposal(_ db: Database, _ id: String) throws {
        do {
            guard var p = try AIProposal.fetchOne(db, key: id) else { throw MarkaError.notFound(id) }
            guard p.status == .applied, let rid = p.resultEntityId else { throw MarkaError.validation(L("Yalnızca onaylanmış öneri geri alınabilir.")) }
            let userEditedAfter = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM auditEvent WHERE entityId = ? AND actor = 'user' AND at > ?",
                                                   arguments: [rid, p.decidedAt ?? p.createdAt]) ?? 0
            switch p.kind {
            case .createTask:
                guard userEditedAfter == 0 else { throw MarkaError.validation(L("Görev sonradan düzenlendiği için otomatik geri alınamaz.")) }
                let linked = (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM timeEntry WHERE taskId = ?", arguments: [rid]) ?? 0)
                    + (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM workLog WHERE taskId = ?", arguments: [rid]) ?? 0)
                guard linked == 0 else { throw MarkaError.validation(L("Göreve süre ya da iş kaydı bağlandığı için geri alınamaz; görevi iptal edebilirsin.")) }
                if let t = try WorkTask.fetchOne(db, key: rid) {
                    try t.delete(db)
                    try audit(db, actor: .user, brandId: t.brandId, entity: "task", entityId: rid, action: "revertAI", before: t, after: WorkTask?.none)
                }
            case .completeTask:
                guard var t = try WorkTask.fetchOne(db, key: rid) else { break }
                let before = t
                t.status = .todo
                t.completedAt = nil
                t.updatedAt = Date()
                try t.update(db)
                try audit(db, actor: .user, brandId: t.brandId, entity: "task", entityId: rid, action: "revertAI", before: before, after: t)
            case .createWorkLog:
                guard let l = try WorkLog.fetchOne(db, key: rid) else { break }
                guard l.status == .draft, userEditedAfter == 0 else {
                    throw MarkaError.validation(L("Kayıt doğrulandığı veya düzenlendiği için geri alınamaz; istersen geri çek."))
                }
                try l.delete(db)
                try audit(db, actor: .user, brandId: l.brandId, entity: "workLog", entityId: rid, action: "revertAI", before: l, after: WorkLog?.none)
                // Bu onayla oluşturulan kaynaklar silinmez, arşivlenir (başka bir kayda bağlanmadıysa).
                let x = try? decode(ProposalPayload.CreateWorkLog.self, p.payloadJSON)
                for sid in x?.createdSourceIds ?? [] {
                    let links = try WorkLogSource.filter(Column("sourceId") == sid).fetchCount(db)
                    if links == 0, var s = try Source.fetchOne(db, key: sid), s.archivedAt == nil, s.brandId == p.brandId {
                        let before = SourceAuditView(s)
                        s.archivedAt = Date()
                        try s.update(db, columns: ["archivedAt"])
                        try audit(db, actor: .user, brandId: s.brandId, entity: "source", entityId: sid, action: "revertAI", before: before, after: SourceAuditView(s))
                    }
                }
            case .createOutput, .createNote:
                // Kaynaklar silinmez; arşivlenir.
                if var s = try Source.fetchOne(db, key: rid), s.archivedAt == nil {
                    let before = SourceAuditView(s)
                    s.archivedAt = Date()
                    try s.update(db, columns: ["archivedAt"])
                    try audit(db, actor: .user, brandId: s.brandId, entity: "source", entityId: rid, action: "revertAI", before: before, after: SourceAuditView(s))
                }
            case .createBrandRecord:
                if let r = try BrandRecord.fetchOne(db, key: rid) {
                    try r.delete(db)
                    try audit(db, actor: .user, brandId: r.brandId, entity: "brandRecord", entityId: rid, action: "revertAI", before: r, after: BrandRecord?.none)
                }
            case .wikiRevision:
                throw MarkaError.validation(L("Bilgi güncellemesi Akış'taki “Geri al” ile önceki sürüme döner."))
            }
            p.status = .reverted
            p.decidedAt = Date()
            try p.update(db)
        }
    }
}
