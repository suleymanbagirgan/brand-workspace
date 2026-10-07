import Foundation
import GRDB

/// AI önerilerinin yük biçimleri. AI veri değiştirmez; bu yükler kullanıcı onayıyla uygulanır.
public enum ProposalPayload {
    /// Yeni yapay zekâ çalışan önerisi. Tür her zaman yapay zekâdır; insan eklemek kullanıcıya aittir.
    public struct CreateTeamMember: Codable, Sendable, Hashable {
        public var name: String
        public var title: String
        public var level: String?
        public var department: String?
        public var reportsToId: String?
        public var provider: String?
        public var model: String?
        public var charter: String?
        public var skills: [String]?
        public init(name: String, title: String, level: String? = nil, department: String? = nil, reportsToId: String? = nil,
                    provider: String? = nil, model: String? = nil, charter: String? = nil, skills: [String]? = nil) {
            self.name = name; self.title = title; self.level = level; self.department = department; self.reportsToId = reportsToId
            self.provider = provider; self.model = model; self.charter = charter; self.skills = skills
        }
        func member() throws -> TeamMember {
            guard let lvl = MemberLevel(rawValue: level ?? "mid") else { throw MarkaError.validation(L("Öneri biçimi geçersiz.")) }
            return try Store.normalized(TeamMember(kind: .ai, name: name, title: title, level: lvl, department: department ?? "",
                                                   reportsToId: reportsToId, provider: provider ?? "", model: model ?? "",
                                                   charter: charter ?? "", skills: skills ?? []))
        }
    }

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
        /// Uygulanınca görevin önceki durumu ve bitiş damgası yazılır; geri alma görevi bu duruma döndürür (H3-05).
        /// Öneri üretilirken boştur; uygulama her seferinde üzerine yazar.
        public var previousStatus: TaskStatus? = nil
        public var previousCompletedAt: Date? = nil
        public init(taskId: String) { self.taskId = taskId }
    }

    /// Mevcut görevi değiştirme önerisi: alanların hepsi opsiyonel, en az biri dolu. Onayla eylem kaydı üzerinden uygulanır
    /// (`task.rename` / `task.reschedule` / `task.setStatus`); uygulanınca önceki değerler `previous`'a yazılır (geri alma için).
    public struct UpdateTask: Codable, Sendable, Hashable {
        public var taskId: String
        public var title: String?
        /// `yyyy-MM-dd`.
        public var dueDate: String?
        public var status: TaskStatus?
        /// Onay anında doldurulur; öneri oluşturulurken boş olmalı.
        public var previous: UndoRecord?
        public init(taskId: String, title: String? = nil, dueDate: String? = nil, status: TaskStatus? = nil) {
            self.taskId = taskId; self.title = title; self.dueDate = dueDate; self.status = status
        }

        static let allowedKeys: Set<String> = ["taskId", "title", "dueDate", "status", "previous"]

        /// Değişiklikleri kayıtlı eylemlerin doğrulamasından geçirip tek düzenlemede birleştirir.
        public func edit() throws -> TaskEdit {
            var e = TaskEdit(taskId: taskId)
            if let title { e.merge(try TaskRename.edit(.init(taskId: taskId, title: title))) }
            if let dueDate { e.merge(try TaskReschedule.edit(.init(taskId: taskId, dueDate: dueDate))) }
            if let status { e.merge(try TaskSetStatus.edit(.init(taskId: taskId, status: status))) }
            guard !e.isEmpty else { throw MarkaError.validation(L("Değişiklik yok: başlık, son tarih ya da durumdan en az biri verilmeli.")) }
            return e
        }
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

    /// E-06: marka gözlemi önerisi. `supersedesId` doluysa gözlem var olan geçerli bir gözlemin yerine geçer: onayda eskisi
    /// silinmez, kapatılır; geri almada yeniden açılır.
    public struct CreateObservation: Codable, Sendable, Hashable {
        public var statement: String
        public var evidenceSourceIds: [String]
        public var supersedesId: String?
        public init(statement: String, evidenceSourceIds: [String], supersedesId: String? = nil) {
            self.statement = statement; self.evidenceSourceIds = evidenceSourceIds; self.supersedesId = supersedesId
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

    /// Görev değiştirme önerisinin önce→sonra görünümü: bekleyende görevin şimdiki değerleri → önerilen, uygulanmışta
    /// onay anındaki önceki → uygulanan değerler. Başka tür ya da artık geçerli olmayan öneride `nil`.
    public func proposalPreview(_ p: AIProposal) -> ActionPreview? {
        guard p.kind == .updateTask, let x = p.payload(ProposalPayload.UpdateTask.self) else { return nil }
        if let r = x.previous {
            return ActionPreview(actionIds: r.actionIds, brandId: r.brandId, entity: r.entity, entityId: r.entityId,
                                 entityTitle: (try? task(r.entityId).title) ?? "", changes: r.changes)
        }
        guard p.status == .pending, let edit = try? x.edit() else { return nil }
        return try? read { db in try previewTaskEdit(db, brandId: p.brandId, edit) }
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
        case .updateTask:
            // Bilinmeyen alan (ör. öncelik) sessizce yok sayılmaz, reddedilir.
            let object = ((try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]) ?? [:]
            guard Set(object.keys).isSubset(of: ProposalPayload.UpdateTask.allowedKeys) else { throw MarkaError.validation(L("Öneri biçimi geçersiz.")) }
            let p = try decode(ProposalPayload.UpdateTask.self, json)
            // Geri alma kaydını yalnız onay yazar; dışarıdan gelen `previous` reddedilir.
            guard p.previous == nil else { throw MarkaError.validation(L("Öneri biçimi geçersiz.")) }
            _ = try previewTaskEdit(db, brandId: brandId, try p.edit())
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
        case .createTeamMember:
            guard try Brand.fetchOne(db, key: brandId)?.isOwn == true else {
                throw MarkaError.validation(L("Çalışan önerisi yalnız şirket sohbetinde verilebilir."))
            }
            let m = try decode(ProposalPayload.CreateTeamMember.self, json).member()
            if let boss = m.reportsToId, try TeamMember.fetchOne(db, key: boss) == nil { throw MarkaError.notFound(boss) }
        case .createObservation:
            try validateObservationProposal(db, brandId: brandId, try decode(ProposalPayload.CreateObservation.self, json))
        case .wikiRevision:
            break // Bilgi sürümleri öneri olarak doğrudan `wikiRevision` tablosuna yazılır.
        }
    }

    /// Gözlem önerisinin kuralları (`insertObservation` ile aynı): tek cümle, sınırlı uzunluk, en az bir kaynak, her kaynak
    /// ve yerine geçilen gözlem bu markaya ait; yerine geçilen gözlem hâlâ geçerli.
    private func validateObservationProposal(_ db: Database, brandId: String, _ p: ProposalPayload.CreateObservation) throws {
        let text = p.statement.trimmed
        guard !text.isEmpty else { throw MarkaError.validation(L("Gözlem boş olamaz.")) }
        guard !text.contains(where: \.isNewline) else { throw MarkaError.validation(L("Gözlem tek cümle olmalı; satır sonu içeremez.")) }
        guard text.count <= BrandObservation.maxStatementLength else {
            throw MarkaError.validation(LF("Gözlem çok uzun (en çok %d).", BrandObservation.maxStatementLength))
        }
        let ids = Set(p.evidenceSourceIds.map(\.trimmed).filter { !$0.isEmpty })
        guard !ids.isEmpty else { throw MarkaError.validation(L("Gözlem en az bir kaynağa dayanmalı.")) }
        guard ids.count <= BrandObservation.maxEvidence else {
            throw MarkaError.validation(LF("Bir gözlem en çok şu kadar kaynağa dayanabilir: %d", BrandObservation.maxEvidence))
        }
        for id in ids {
            guard let s = try Source.fetchOne(db, key: id) else { throw MarkaError.validation(LF("Kaynak bulunamadı: %@", id)) }
            guard s.brandId == brandId else { throw MarkaError.brandScope }
        }
        if let oldId = p.supersedesId {
            guard let old = try BrandObservation.fetchOne(db, key: oldId) else { throw MarkaError.notFound(oldId) }
            guard old.brandId == brandId else { throw MarkaError.brandScope }
            guard old.isValid else { throw MarkaError.validation(L("Bu gözlem zaten kapatılmış; yerine yalnız geçerli bir gözlem geçebilir.")) }
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
                var x = try decode(ProposalPayload.CompleteTask.self, p.payloadJSON)
                guard var t = try WorkTask.fetchOne(db, key: x.taskId) else { throw MarkaError.notFound(x.taskId) }
                x.previousStatus = t.status
                x.previousCompletedAt = t.completedAt
                p.payloadJSON = Self.json(x) ?? p.payloadJSON
                t.status = .done
                resultId = try saveTask(db, t, actor: .ai).id
            case .updateTask:
                var x = try decode(ProposalPayload.UpdateTask.self, p.payloadJSON)
                x.previous = try applyTaskEdit(db, brandId: p.brandId, try x.edit(), actor: .ai)
                p.payloadJSON = Self.json(x) ?? p.payloadJSON
                resultId = x.taskId
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
            case .createTeamMember:
                let member = try decode(ProposalPayload.CreateTeamMember.self, p.payloadJSON).member()
                resultId = try persistMember(db, member, actor: .ai).id
            case .createObservation:
                // Onay yolu: `.ai` gözlemi yalnız bu onaylanan önerinin kimliğiyle yazabilir (`insertObservation`).
                let x = try decode(ProposalPayload.CreateObservation.self, p.payloadJSON)
                let new = try insertObservation(db, brandId: p.brandId, statement: x.statement, evidenceSourceIds: x.evidenceSourceIds,
                                                actor: .ai, approvedProposalId: p.id)
                if let oldId = x.supersedesId, var old = try BrandObservation.fetchOne(db, key: oldId) {
                    let before = old
                    old.status = .superseded
                    old.invalidatedAt = new.validFrom
                    old.supersededBy = new.id
                    try old.update(db)
                    try audit(db, actor: .ai, brandId: p.brandId, entity: "observation", entityId: old.id, action: "supersede",
                              before: before, after: old)
                }
                resultId = new.id
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
            let userEditedAfter = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM auditEvent WHERE entityId = ? AND actor = 'user' AND at >= ?",
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
                // Uygulama öncesi duruma döner (H3-05); eski biçimli kayıtta önceki durum yoksa "yapılacak".
                let x = try? decode(ProposalPayload.CompleteTask.self, p.payloadJSON)
                t.status = x?.previousStatus ?? .todo
                t.completedAt = t.status == .done ? x?.previousCompletedAt : nil
                t.updatedAt = Date()
                try t.update(db)
                try audit(db, actor: .user, brandId: t.brandId, entity: "task", entityId: rid, action: "revertAI", before: before, after: t)
            case .updateTask:
                guard userEditedAfter == 0 else { throw MarkaError.validation(L("Görev sonradan düzenlendiği için otomatik geri alınamaz.")) }
                guard let record = try decode(ProposalPayload.UpdateTask.self, p.payloadJSON).previous, record.entityId == rid else {
                    throw MarkaError.validation(L("Öneri biçimi geçersiz."))
                }
                try undoTaskEdit(db, record, brandId: p.brandId, actor: .user, auditAction: "revertAI")
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
            case .createTeamMember:
                // Kullanıcı üyeyi sonradan düzenlediyse (atama değil, üyenin kendisi) geri alma reddedilir (B3).
                let memberEdited = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM auditEvent WHERE entity = 'teamMember' AND entityId = ? AND actor = 'user' AND at >= ?",
                                                    arguments: [rid, p.decidedAt ?? p.createdAt]) ?? 0
                guard memberEdited == 0 else { throw MarkaError.validation(L("Çalışan sonradan düzenlendiği için otomatik geri alınamaz; istersen arşivleyebilirsin.")) }
                // Çalışan silinmez, arşivlenir; astları üstüne devredilir.
                if let m = try TeamMember.fetchOne(db, key: rid), m.status == .active { try archiveMember(db, rid, actor: .user, action: "revertAI") }
            case .createBrandRecord:
                if let r = try BrandRecord.fetchOne(db, key: rid) {
                    try r.delete(db)
                    try audit(db, actor: .user, brandId: r.brandId, entity: "brandRecord", entityId: rid, action: "revertAI", before: r, after: BrandRecord?.none)
                }
            case .createObservation:
                try revertObservation(db, p, observationId: rid, userEditedAfter: userEditedAfter)
            case .wikiRevision:
                throw MarkaError.validation(L("Bilgi güncellemesi Akış'taki “Geri al” ile önceki sürüme döner."))
            }
            p.status = .reverted
            p.decidedAt = Date()
            try p.update(db)
        }
    }

    /// E-06 geri alma: onayla eklenen gözlem silinir; yerine geçtiği eski gözlem yeniden açılır. Kullanıcı gözleme sonradan
    /// dokunduysa (kapattı ya da yerine başka gözlem koydu) geri alma reddedilir.
    private func revertObservation(_ db: Database, _ p: AIProposal, observationId rid: String, userEditedAfter: Int) throws {
        guard let new = try BrandObservation.fetchOne(db, key: rid) else { return }
        guard new.brandId == p.brandId else { throw MarkaError.brandScope }
        guard userEditedAfter == 0, new.isValid else {
            throw MarkaError.validation(L("Gözlem sonradan değiştirildiği için otomatik geri alınamaz."))
        }
        try new.delete(db)
        try audit(db, actor: .user, brandId: p.brandId, entity: "observation", entityId: rid, action: "revertAI",
                  before: new, after: BrandObservation?.none)
        let x = try? decode(ProposalPayload.CreateObservation.self, p.payloadJSON)
        guard let oldId = x?.supersedesId, let old = try BrandObservation.fetchOne(db, key: oldId),
              old.brandId == p.brandId, old.supersededBy == rid else { return }
        // Kapatılmış satır tetikleyiciyle (`observation_immutable`) güncellenemez; aynı kimlik ve aynı içerikle yeniden
        // yazılır. Cümle, kanıt, başlangıç ve oluşturma tarihi değişmez; yalnız kapanış alanları boşalır.
        var reopened = old
        reopened.status = .active
        reopened.invalidatedAt = nil
        reopened.supersededBy = nil
        try old.delete(db)
        try reopened.insert(db)
        try audit(db, actor: .user, brandId: p.brandId, entity: "observation", entityId: oldId, action: "revertAI",
                  before: old, after: reopened)
    }
}
