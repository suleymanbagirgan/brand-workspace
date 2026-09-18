import Foundation
import GRDB

/// Terminal öneri dosyasından çıkan, henüz kaydedilmemiş öneri.
public struct SuggestionDraft: Sendable, Hashable {
    public var kind: ProposalKind
    public var summary: String
    public var payloadJSON: String

    public init<P: Encodable>(kind: ProposalKind, summary: String, payload: P) {
        self.kind = kind; self.summary = summary; self.payloadJSON = Store.json(payload) ?? "{}"
    }
}

/// İnceleme sayfasındaki karar: öneri eklensin mi, başlığı/son tarihi düzeltildi mi.
public struct SuggestionDecision: Sendable, Hashable {
    public var proposalId: String
    public var accept: Bool
    /// `nil`: başlık değişmedi.
    public var title: String?
    /// `true` ise son tarih `dueDate` ile değiştirilir (`nil` = tarih yok).
    public var changeDueDate: Bool
    public var dueDate: String?

    public init(proposalId: String, accept: Bool, title: String? = nil, changeDueDate: Bool = false, dueDate: String? = nil) {
        self.proposalId = proposalId; self.accept = accept; self.title = title
        self.changeDueDate = changeDueDate; self.dueDate = dueDate
    }
}

extension AIProposal {
    /// Öneri yükünü çözer (arayüzdeki inceleme sayfası için).
    public func payload<T: Decodable>(_ type: T.Type) -> T? {
        try? Store.decoder.decode(T.self, from: Data(payloadJSON.utf8))
    }

    /// Terminal önerisinin inceleme ve uygulama sırası: önce görevler (çalışma kaydı görevine bağlanabilsin), en son çalışma kayıtları.
    public var suggestionOrder: Int {
        switch kind {
        case .createTask: 0
        case .completeTask: 1
        case .createBrandRecord: 2
        case .createNote: 3
        case .createOutput: 4
        case .createWorkLog: 5
        case .wikiRevision: 6
        }
    }
}

extension Store {
    // MARK: Terminal öneri kutusu (İ7)

    public func isSuggestionFileProcessed(brandId: String, sha256: String) throws -> Bool {
        try read { db in
            try SuggestionFile.filter(Column("brandId") == brandId && Column("sha256") == sha256).fetchCount(db) > 0
        }
    }

    /// Öneri dosyasını tek işlemde kaydeder: işlenmiş dosya kaydı + bekleyen öneriler + denetim olayı.
    /// Aynı içerik (sha256) bu markada daha önce işlendiyse hiçbir şey yazılmaz ve boş dizi döner.
    @discardableResult
    public func ingestSuggestionFile(brandId: String, fileName: String, sha256: String, drafts: [SuggestionDraft]) throws -> [AIProposal] {
        try writer.write { db in
            guard try Brand.fetchOne(db, key: brandId) != nil else { throw MarkaError.notFound(brandId) }
            if try SuggestionFile.filter(Column("brandId") == brandId && Column("sha256") == sha256).fetchCount(db) > 0 { return [] }
            let file = SuggestionFile(brandId: brandId, sha256: sha256, fileName: fileName, itemCount: drafts.count)
            try file.insert(db)
            var out: [AIProposal] = []
            let now = Date()
            for (i, d) in drafts.enumerated() {
                try validateProposal(db, brandId: brandId, kind: d.kind, json: d.payloadJSON)
                // Aynı işlemdeki öneriler dosyadaki sırayı korusun: oluşturulma anı milisaniye farkla artar.
                let p = AIProposal(sessionId: nil, brandId: brandId, kind: d.kind, summary: d.summary, payloadJSON: d.payloadJSON,
                                   createdAt: now.addingTimeInterval(Double(i) / 1000), origin: .terminal, originRef: fileName)
                try p.insert(db)
                out.append(p)
            }
            try audit(db, actor: .ai, brandId: brandId, entity: "suggestionFile", entityId: file.id, action: "ingest",
                      before: SuggestionFile?.none, after: file)
            return out
        }
    }

    /// Bu markanın onay bekleyen terminal önerileri (dosya sırasıyla).
    public func pendingSuggestions(brandId: String) throws -> [AIProposal] {
        try read { db in
            try AIProposal.filter(Column("brandId") == brandId && Column("status") == ProposalStatus.pending.rawValue
                                  && Column("origin") == ProposalOrigin.terminal.rawValue)
                .order(Column("createdAt")).fetchAll(db)
        }
    }

    /// İnceleme sayfasının kararı tek işlemde uygulanır: düzeltmeler yüke yazılır, seçilenler uygulanır, seçilmeyenler reddedilir.
    /// Önerilerin hepsi bu markanın bekleyen terminal önerisi olmalı. Biri başarısız olursa hiçbiri uygulanmaz.
    @discardableResult
    public func decideSuggestions(brandId: String, decisions: [SuggestionDecision]) throws -> [AIProposal] {
        try writer.write { db in
            var accepted: [AIProposal] = []
            for d in decisions {
                guard var p = try AIProposal.fetchOne(db, key: d.proposalId) else { throw MarkaError.notFound(d.proposalId) }
                guard p.brandId == brandId else { throw MarkaError.brandScope }
                guard p.origin == .terminal, p.status == .pending else { throw MarkaError.validation(L("Bu öneri zaten sonuçlandırılmış.")) }
                guard d.accept else { try rejectProposal(db, p.id); continue }
                if d.title != nil || d.changeDueDate {
                    let before = p
                    p.payloadJSON = try editedPayload(p, title: d.title, changeDueDate: d.changeDueDate, dueDate: d.dueDate)
                    if p.payloadJSON != before.payloadJSON {
                        try validateProposal(db, brandId: brandId, kind: p.kind, json: p.payloadJSON)
                        try p.update(db, columns: ["payloadJSON"])
                        try audit(db, actor: .user, brandId: brandId, entity: "aiProposal", entityId: p.id, action: "edit", before: before, after: p)
                    }
                }
                accepted.append(p)
            }
            return try accepted.sorted { $0.suggestionOrder < $1.suggestionOrder }.map { try applyProposal(db, $0.id) }
        }
    }

    /// Bir inceleme turunda uygulanan önerileri tek işlemde geri alır (çalışma kayıtları önce, görevler en son).
    public func revertSuggestions(brandId: String, proposalIds: [String]) throws {
        try writer.write { db in
            let proposals = try proposalIds.map { id -> AIProposal in
                guard let p = try AIProposal.fetchOne(db, key: id) else { throw MarkaError.notFound(id) }
                guard p.brandId == brandId else { throw MarkaError.brandScope }
                return p
            }
            for p in proposals.sorted(by: { $0.suggestionOrder > $1.suggestionOrder }) where p.status == .applied {
                try revertProposal(db, p.id)
            }
        }
    }

    private func editedPayload(_ p: AIProposal, title: String?, changeDueDate: Bool, dueDate: String?) throws -> String {
        let t = title?.trimmed
        switch p.kind {
        case .createTask:
            var x = try decode(ProposalPayload.CreateTask.self, p.payloadJSON)
            if let t { x.title = t }
            if changeDueDate { x.dueDate = dueDate }
            return Self.json(x) ?? p.payloadJSON
        case .createBrandRecord:
            var x = try decode(ProposalPayload.CreateBrandRecord.self, p.payloadJSON)
            if let t { x.title = t }
            if changeDueDate { x.dueDate = dueDate }
            return Self.json(x) ?? p.payloadJSON
        case .createWorkLog:
            var x = try decode(ProposalPayload.CreateWorkLog.self, p.payloadJSON)
            if let t { x.title = t }
            return Self.json(x) ?? p.payloadJSON
        case .createNote:
            var x = try decode(ProposalPayload.CreateNote.self, p.payloadJSON)
            if let t { x.title = t }
            return Self.json(x) ?? p.payloadJSON
        case .completeTask, .createOutput, .wikiRevision:
            return p.payloadJSON
        }
    }

    /// Markanın aynı başlıklı görevi (büyük/küçük harf ve baştaki/sondaki boşluk duyarsız, Türkçe kurallarla); en son güncellenen.
    public func taskMatching(title: String, brandId: String, openOnly: Bool = false) throws -> WorkTask? {
        try read { db in try taskMatching(db, title: title, brandId: brandId, openOnly: openOnly) }
    }

    func taskMatching(_ db: Database, title: String, brandId: String, openOnly: Bool = false) throws -> WorkTask? {
        let wanted = title.trimmed
        guard !wanted.isEmpty else { return nil }
        let tr = Locale(identifier: "tr_TR")
        return try WorkTask.filter(Column("brandId") == brandId).order(Column("updatedAt").desc).fetchAll(db).first {
            (!openOnly || $0.status.isOpen) && $0.title.trimmed.compare(wanted, options: .caseInsensitive, range: nil, locale: tr) == .orderedSame
        }
    }

    /// Depoya alınmış dosyayı kaynağa çevirir: markada aynı içerikli kaynak varsa o kullanılır, yoksa yenisi oluşturulur.
    func stagedSource(_ db: Database, _ f: ProposalPayload.StagedFile, kind: SourceKind, brandId: String,
                      created: inout [String]) throws -> String {
        let existing = try Source.filter(Column("brandId") == brandId && Column("sha256") == f.sha256)
            .order(Column("archivedAt") != nil, Column("createdAt")).fetchOne(db)
        if let existing { return existing.id }
        let url = vault.url(for: f.storedPath)
        // Depodaki dosya içerik adreslidir; içerik öneri anındakiyle aynı olmalı.
        guard let data = try? FileImportGuard.readNoFollow(url), FileVault.sha256(data) == f.sha256 else {
            throw MarkaError.validation(LF("Öneriye bağlı dosya bulunamadı: %@", f.fileName))
        }
        let s = Source(brandId: brandId, kind: kind, title: (f.fileName as NSString).deletingPathExtension,
                       body: TextExtractor.extract(from: url), fileName: f.fileName, filePath: f.storedPath, mimeType: f.mimeType,
                       sha256: f.sha256, byteSize: f.byteSize, actor: .ai)
        try s.insert(db)
        try audit(db, actor: .ai, brandId: brandId, entity: "source", entityId: s.id, action: "create",
                  before: Source?.none, after: SourceAuditView(s))
        created.append(s.id)
        return s.id
    }
}
