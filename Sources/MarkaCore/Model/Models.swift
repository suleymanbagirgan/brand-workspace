import Foundation
import GRDB

// MARK: - Ortak

public enum Actor: String, Codable, Sendable, CaseIterable {
    case user, ai, `import`, system
}

public func newID() -> String { UUID().uuidString.lowercased() }

/// `yyyy-MM-dd` biçiminde gün değeri (son tarih gibi saat içermeyen alanlar).
public enum DayString {
    public static func from(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public static func date(_ day: String, calendar: Calendar = .current) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    public static func isValid(_ day: String) -> Bool {
        guard day.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              let d = date(day, calendar: Calendar(identifier: .gregorian)) else { return false }
        return from(d, calendar: Calendar(identifier: .gregorian)) == day
    }
}

// MARK: - Marka

public enum BrandStatus: String, Codable, Sendable { case active, archived }

public enum AIProviderKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case anthropic, codex
    public var id: String { rawValue }
}

public struct Brand: Codable, Sendable, Hashable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "brand"
    public var id: String
    public var name: String
    public var summary: String
    public var sector: String
    public var logoPath: String?
    public var status: BrandStatus
    /// Bu markanın verisinin gönderilebileceği AI sağlayıcıları (virgülle ayrılmış). Varsayılan boş: izin yok.
    public var aiProviders: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = newID(), name: String, summary: String = "", sector: String = "",
                logoPath: String? = nil, status: BrandStatus = .active, aiProviders: String = "",
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id; self.name = name; self.summary = summary; self.sector = sector
        self.logoPath = logoPath; self.status = status; self.aiProviders = aiProviders
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    public var allowedProviders: Set<AIProviderKind> {
        Set(aiProviders.split(separator: ",").compactMap { AIProviderKind(rawValue: String($0).trimmingCharacters(in: .whitespaces)) })
    }

    public func allows(_ provider: AIProviderKind) -> Bool { allowedProviders.contains(provider) }
}

public struct Contact: Codable, Sendable, Hashable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "contact"
    public var id: String
    public var brandId: String
    public var name: String
    public var role: String
    public var email: String
    public var phone: String
    public var notes: String
    public var createdAt: Date

    public init(id: String = newID(), brandId: String, name: String, role: String = "", email: String = "",
                phone: String = "", notes: String = "", createdAt: Date = Date()) {
        self.id = id; self.brandId = brandId; self.name = name; self.role = role
        self.email = email; self.phone = phone; self.notes = notes; self.createdAt = createdAt
    }
}

public enum ProjectStatus: String, Codable, Sendable, CaseIterable { case active, paused, done }

public struct Project: Codable, Sendable, Hashable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "project"
    public var id: String
    public var brandId: String
    public var name: String
    public var goal: String
    public var status: ProjectStatus
    public var dueDate: String?
    public var createdAt: Date

    public init(id: String = newID(), brandId: String, name: String, goal: String = "",
                status: ProjectStatus = .active, dueDate: String? = nil, createdAt: Date = Date()) {
        self.id = id; self.brandId = brandId; self.name = name; self.goal = goal
        self.status = status; self.dueDate = dueDate; self.createdAt = createdAt
    }
}

/// Markanın yapılandırılmış maddeleri.
public enum BrandRecordKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case goal          // hedef
    case request       // müşteri talebi
    case promise       // verdiğim söz
    case decision      // müşteriden beklenen karar
    case proposal      // teklif
    case contract      // sözleşme
    case milestone     // önemli tarih
    public var id: String { rawValue }
}

public enum RecordStatus: String, Codable, Sendable, CaseIterable {
    case open, done, cancelled
    // teklif/sözleşme yaşam döngüsü
    case draft, sent, accepted, rejected, active, expired
}

public struct BrandRecord: Codable, Sendable, Hashable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "brandRecord"
    public var id: String
    public var brandId: String
    public var kind: BrandRecordKind
    public var title: String
    public var detail: String
    public var status: RecordStatus
    public var dueDate: String?
    public var sourceId: String?
    public var projectId: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var closedAt: Date?

    public init(id: String = newID(), brandId: String, kind: BrandRecordKind, title: String, detail: String = "",
                status: RecordStatus? = nil, dueDate: String? = nil, sourceId: String? = nil, projectId: String? = nil,
                createdAt: Date = Date(), updatedAt: Date = Date(), closedAt: Date? = nil) {
        self.id = id; self.brandId = brandId; self.kind = kind; self.title = title; self.detail = detail
        self.status = status ?? BrandRecord.defaultStatus(for: kind)
        self.dueDate = dueDate; self.sourceId = sourceId; self.projectId = projectId
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.closedAt = closedAt
    }

    public static func defaultStatus(for kind: BrandRecordKind) -> RecordStatus {
        switch kind {
        case .proposal: .draft
        case .contract: .active
        default: .open
        }
    }

    /// Kayıt hâlâ ilgilenilmesi gereken bir madde mi?
    public var isOpen: Bool {
        switch status {
        case .open, .draft, .sent: true
        default: false
        }
    }
}

// MARK: - Kaynak (değişmez)

public enum SourceKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case file, note, meeting, clientRequest, workOutput, link, imported
    public var id: String { rawValue }
    /// Müşteriyle temas sayılan türler.
    public var isContact: Bool { self == .meeting || self == .clientRequest }
}

public struct Source: Codable, Sendable, Hashable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "source"
    public var id: String
    public var brandId: String
    public var kind: SourceKind
    public var title: String
    /// Not metni veya dosyadan çıkarılan metin (aranabilir).
    public var body: String
    public var fileName: String?
    /// `Files/` altındaki içerik adresli göreli yol.
    public var filePath: String?
    public var mimeType: String?
    public var sha256: String
    public var byteSize: Int
    public var url: String?
    /// Olayın gerçekleştiği an (ör. görüşme tarihi).
    public var capturedAt: Date
    public var createdAt: Date
    public var actor: Actor
    public var archivedAt: Date?

    public init(id: String = newID(), brandId: String, kind: SourceKind, title: String, body: String = "",
                fileName: String? = nil, filePath: String? = nil, mimeType: String? = nil, sha256: String,
                byteSize: Int = 0, url: String? = nil, capturedAt: Date = Date(), createdAt: Date = Date(),
                actor: Actor = .user, archivedAt: Date? = nil) {
        self.id = id; self.brandId = brandId; self.kind = kind; self.title = title; self.body = body
        self.fileName = fileName; self.filePath = filePath; self.mimeType = mimeType; self.sha256 = sha256
        self.byteSize = byteSize; self.url = url; self.capturedAt = capturedAt; self.createdAt = createdAt
        self.actor = actor; self.archivedAt = archivedAt
    }
}

// MARK: - Görev ve süre

public enum TaskStatus: String, Codable, Sendable, CaseIterable, Identifiable {
    case todo, inProgress, waiting, done, cancelled
    public var id: String { rawValue }
    public var isOpen: Bool { self != .done && self != .cancelled }
}

public struct WorkTask: Codable, Sendable, Hashable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "workTask"
    public var id: String
    public var brandId: String
    public var projectId: String?
    public var title: String
    public var notes: String
    public var assignee: String
    /// 0 yok, 1 düşük, 2 orta, 3 yüksek
    public var priority: Int
    public var dueDate: String?
    public var status: TaskStatus
    public var timeSpentSeconds: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?
    public var actor: Actor
    /// İçe aktarımda kopyayı önleyen anahtar (ör. `joi:21`).
    public var legacyKey: String?
    public var legacyCode: String?

    public init(id: String = newID(), brandId: String, projectId: String? = nil, title: String, notes: String = "",
                assignee: String = "", priority: Int = 0, dueDate: String? = nil, status: TaskStatus = .todo,
                timeSpentSeconds: Int = 0, createdAt: Date = Date(), updatedAt: Date = Date(),
                completedAt: Date? = nil, actor: Actor = .user, legacyKey: String? = nil, legacyCode: String? = nil) {
        self.id = id; self.brandId = brandId; self.projectId = projectId; self.title = title; self.notes = notes
        self.assignee = assignee; self.priority = priority; self.dueDate = dueDate; self.status = status
        self.timeSpentSeconds = timeSpentSeconds; self.createdAt = createdAt; self.updatedAt = updatedAt
        self.completedAt = completedAt; self.actor = actor; self.legacyKey = legacyKey; self.legacyCode = legacyCode
    }
}

public struct TimeEntry: Codable, Sendable, Hashable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "timeEntry"
    public var id: String
    public var taskId: String
    public var brandId: String
    public var startedAt: Date
    public var endedAt: Date?
    public var seconds: Int
    public var note: String
    public var actor: Actor
    public var legacyKey: String?

    public init(id: String = newID(), taskId: String, brandId: String, startedAt: Date, endedAt: Date? = nil,
                seconds: Int = 0, note: String = "", actor: Actor = .user, legacyKey: String? = nil) {
        self.id = id; self.taskId = taskId; self.brandId = brandId; self.startedAt = startedAt
        self.endedAt = endedAt; self.seconds = seconds; self.note = note; self.actor = actor; self.legacyKey = legacyKey
    }
}

// MARK: - Çalışma kaydı

public enum WorkLogStatus: String, Codable, Sendable, CaseIterable { case draft, verified, retracted }

public struct WorkLog: Codable, Sendable, Hashable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "workLog"
    public var id: String
    public var brandId: String
    public var taskId: String?
    public var title: String
    /// Ne istendi?
    public var requested: String
    /// Ne yapıldı?
    public var performed: String
    /// Hangi karar alındı?
    public var decision: String
    /// Kim onayladı?
    public var approvedBy: String
    /// Müşteriye ne bildirildi?
    public var clientNotified: String
    public var status: WorkLogStatus
    public var verifiedAt: Date?
    public var verifiedBy: String?
    public var occurredAt: Date
    public var createdAt: Date
    public var updatedAt: Date
    public var actor: Actor
    public var sessionId: String?

    public init(id: String = newID(), brandId: String, taskId: String? = nil, title: String, requested: String = "",
                performed: String = "", decision: String = "", approvedBy: String = "", clientNotified: String = "",
                status: WorkLogStatus = .draft, verifiedAt: Date? = nil, verifiedBy: String? = nil,
                occurredAt: Date = Date(), createdAt: Date = Date(), updatedAt: Date = Date(),
                actor: Actor = .user, sessionId: String? = nil) {
        self.id = id; self.brandId = brandId; self.taskId = taskId; self.title = title; self.requested = requested
        self.performed = performed; self.decision = decision; self.approvedBy = approvedBy
        self.clientNotified = clientNotified; self.status = status; self.verifiedAt = verifiedAt
        self.verifiedBy = verifiedBy; self.occurredAt = occurredAt; self.createdAt = createdAt
        self.updatedAt = updatedAt; self.actor = actor; self.sessionId = sessionId
    }
}

public enum WorkLogSourceRole: String, Codable, Sendable { case input, output }

public struct WorkLogSource: Codable, Sendable, Hashable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "workLogSource"
    public var workLogId: String
    public var sourceId: String
    public var role: WorkLogSourceRole
    public init(workLogId: String, sourceId: String, role: WorkLogSourceRole) {
        self.workLogId = workLogId; self.sourceId = sourceId; self.role = role
    }
}

// MARK: - Bilgi hafızası

public enum WikiPageKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case overview, person, goal, project, decision, preference, process
    public var id: String { rawValue }
}

public enum WikiPageStatus: String, Codable, Sendable { case current, stale, conflict }

public struct WikiPage: Codable, Sendable, Hashable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "wikiPage"
    public var id: String
    public var brandId: String
    public var kind: WikiPageKind
    public var title: String
    public var slug: String
    public var currentRevisionId: String?
    public var status: WikiPageStatus
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = newID(), brandId: String, kind: WikiPageKind, title: String, slug: String,
                currentRevisionId: String? = nil, status: WikiPageStatus = .current,
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id; self.brandId = brandId; self.kind = kind; self.title = title; self.slug = slug
        self.currentRevisionId = currentRevisionId; self.status = status
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public enum RevisionState: String, Codable, Sendable { case proposed, approved, rejected, superseded }

public struct WikiRevision: Codable, Sendable, Hashable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "wikiRevision"
    public var id: String
    public var pageId: String
    public var brandId: String
    public var number: Int
    public var body: String
    public var note: String
    public var state: RevisionState
    public var actor: Actor
    public var createdAt: Date
    public var decidedAt: Date?
    public var basedOnRevisionId: String?

    public init(id: String = newID(), pageId: String, brandId: String, number: Int, body: String, note: String = "",
                state: RevisionState, actor: Actor, createdAt: Date = Date(), decidedAt: Date? = nil,
                basedOnRevisionId: String? = nil) {
        self.id = id; self.pageId = pageId; self.brandId = brandId; self.number = number; self.body = body
        self.note = note; self.state = state; self.actor = actor; self.createdAt = createdAt
        self.decidedAt = decidedAt; self.basedOnRevisionId = basedOnRevisionId
    }
}

public enum ClaimStatus: String, Codable, Sendable, CaseIterable { case current, conflict, stale }

public struct WikiClaim: Codable, Sendable, Hashable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "wikiClaim"
    public var id: String
    public var revisionId: String
    public var brandId: String
    public var text: String
    public var sourceId: String?
    public var sourceDate: Date?
    public var status: ClaimStatus
    public var flagNote: String

    public init(id: String = newID(), revisionId: String, brandId: String, text: String, sourceId: String? = nil,
                sourceDate: Date? = nil, status: ClaimStatus = .current, flagNote: String = "") {
        self.id = id; self.revisionId = revisionId; self.brandId = brandId; self.text = text
        self.sourceId = sourceId; self.sourceDate = sourceDate; self.status = status; self.flagNote = flagNote
    }
}

public struct WikiLink: Codable, Sendable, Hashable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "wikiLink"
    public var fromPageId: String
    public var toPageId: String
    public init(fromPageId: String, toPageId: String) { self.fromPageId = fromPageId; self.toPageId = toPageId }
}

public struct BrandRules: Codable, Sendable, Hashable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "brandRules"
    public var brandId: String
    public var body: String
    public var updatedAt: Date
    public init(brandId: String, body: String, updatedAt: Date = Date()) {
        self.brandId = brandId; self.body = body; self.updatedAt = updatedAt
    }
}

// MARK: - Raporlar

public enum ReportPeriod: String, Codable, Sendable, CaseIterable, Identifiable {
    case weekly, monthly
    public var id: String { rawValue }
}

public enum ReportStatus: String, Codable, Sendable { case draft, approved }

public struct Report: Codable, Sendable, Hashable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "report"
    public var id: String
    public var brandId: String
    public var period: ReportPeriod
    public var periodStart: Date
    public var periodEnd: Date
    public var status: ReportStatus
    public var currentVersionId: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = newID(), brandId: String, period: ReportPeriod, periodStart: Date, periodEnd: Date,
                status: ReportStatus = .draft, currentVersionId: String? = nil,
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id; self.brandId = brandId; self.period = period; self.periodStart = periodStart
        self.periodEnd = periodEnd; self.status = status; self.currentVersionId = currentVersionId
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public struct ReportVersion: Codable, Sendable, Hashable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "reportVersion"
    public var id: String
    public var reportId: String
    public var number: Int
    public var contentJSON: String
    public var note: String
    public var actor: Actor
    public var createdAt: Date
    public var approvedAt: Date?

    public init(id: String = newID(), reportId: String, number: Int, contentJSON: String, note: String = "",
                actor: Actor = .user, createdAt: Date = Date(), approvedAt: Date? = nil) {
        self.id = id; self.reportId = reportId; self.number = number; self.contentJSON = contentJSON
        self.note = note; self.actor = actor; self.createdAt = createdAt; self.approvedAt = approvedAt
    }
}

public enum ShareChannel: String, Codable, Sendable { case pdfExport, mailDraft, scheduledDraft }

public struct ReportShare: Codable, Sendable, Hashable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "reportShare"
    public var id: String
    public var reportId: String
    public var versionId: String
    public var channel: ShareChannel
    public var recipient: String
    public var filePath: String
    public var note: String
    public var sharedAt: Date

    public init(id: String = newID(), reportId: String, versionId: String, channel: ShareChannel,
                recipient: String = "", filePath: String = "", note: String = "", sharedAt: Date = Date()) {
        self.id = id; self.reportId = reportId; self.versionId = versionId; self.channel = channel
        self.recipient = recipient; self.filePath = filePath; self.note = note; self.sharedAt = sharedAt
    }
}

public struct DeliveryPlan: Codable, Sendable, Hashable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "deliveryPlan"
    public var id: String
    public var brandId: String
    public var recipients: String
    public var period: ReportPeriod
    /// Haftalık için 1=Pazartesi … 7=Pazar; aylık için ayın günü.
    public var dayOfPeriod: Int
    public var enabled: Bool
    public var lastRunAt: Date?
    public var createdAt: Date

    public init(id: String = newID(), brandId: String, recipients: String, period: ReportPeriod, dayOfPeriod: Int,
                enabled: Bool = true, lastRunAt: Date? = nil, createdAt: Date = Date()) {
        self.id = id; self.brandId = brandId; self.recipients = recipients; self.period = period
        self.dayOfPeriod = dayOfPeriod; self.enabled = enabled; self.lastRunAt = lastRunAt; self.createdAt = createdAt
    }
}

public enum DeliveryOutcome: String, Codable, Sendable { case draftCreated, skippedNoData, paused }

public struct DeliveryRun: Codable, Sendable, Hashable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "deliveryRun"
    public var id: String
    public var planId: String
    public var at: Date
    public var outcome: DeliveryOutcome
    public var reportId: String?
    public var note: String

    public init(id: String = newID(), planId: String, at: Date = Date(), outcome: DeliveryOutcome,
                reportId: String? = nil, note: String = "") {
        self.id = id; self.planId = planId; self.at = at; self.outcome = outcome; self.reportId = reportId; self.note = note
    }
}

// MARK: - AI

public enum AIScope: String, Codable, Sendable { case brand, allBrands }

public struct AISession: Codable, Sendable, Hashable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "aiSession"
    public var id: String
    /// `allBrands` kapsamında nil.
    public var brandId: String?
    public var scope: AIScope
    public var provider: AIProviderKind
    public var model: String
    public var title: String
    public var providerThreadId: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = newID(), brandId: String?, scope: AIScope, provider: AIProviderKind, model: String,
                title: String, providerThreadId: String? = nil, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id; self.brandId = brandId; self.scope = scope; self.provider = provider; self.model = model
        self.title = title; self.providerThreadId = providerThreadId; self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public enum AIMessageRole: String, Codable, Sendable { case user, assistant }
public enum AIMessageState: String, Codable, Sendable { case complete, partial, failed }

public struct AIMessage: Codable, Sendable, Hashable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "aiMessage"
    public var id: String
    public var sessionId: String
    public var role: AIMessageRole
    public var text: String
    /// Görünür etkinlikler (araç kullanımı, dosyalar, öneriler) JSON dizisi.
    public var eventsJSON: String
    /// Sağlayıcıya geri gönderilecek ham içerik blokları (Anthropic) JSON.
    public var rawJSON: String
    public var state: AIMessageState
    public var inputTokens: Int
    public var outputTokens: Int
    public var costMicros: Int
    public var createdAt: Date

    public init(id: String = newID(), sessionId: String, role: AIMessageRole, text: String, eventsJSON: String = "[]",
                rawJSON: String = "", state: AIMessageState = .complete, inputTokens: Int = 0, outputTokens: Int = 0,
                costMicros: Int = 0, createdAt: Date = Date()) {
        self.id = id; self.sessionId = sessionId; self.role = role; self.text = text; self.eventsJSON = eventsJSON
        self.rawJSON = rawJSON; self.state = state; self.inputTokens = inputTokens; self.outputTokens = outputTokens
        self.costMicros = costMicros; self.createdAt = createdAt
    }
}

public enum ProposalKind: String, Codable, Sendable, CaseIterable {
    case createTask, completeTask, createWorkLog, wikiRevision, createOutput, createBrandRecord
    /// Metin kaynağı (not / görüşme notu). Yalnızca terminal önerisinden gelir.
    case createNote
}

public enum ProposalStatus: String, Codable, Sendable { case pending, applied, rejected, reverted }

/// Önerinin nereden geldiği. `nil`: sohbet (Claude/Codex aracı). `.terminal`: marka klasöründeki `oneriler/*.json`.
public enum ProposalOrigin: String, Codable, Sendable { case terminal }

public struct AIProposal: Codable, Sendable, Hashable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "aiProposal"
    public var id: String
    public var sessionId: String?
    public var brandId: String
    public var kind: ProposalKind
    public var summary: String
    public var payloadJSON: String
    public var status: ProposalStatus
    public var resultEntityId: String?
    public var createdAt: Date
    public var decidedAt: Date?
    public var origin: ProposalOrigin?
    /// Kaynağın insan okur adı (terminal önerisinde dosya adı, ör. `gorevler.json`).
    public var originRef: String?

    public init(id: String = newID(), sessionId: String?, brandId: String, kind: ProposalKind, summary: String,
                payloadJSON: String, status: ProposalStatus = .pending, resultEntityId: String? = nil,
                createdAt: Date = Date(), decidedAt: Date? = nil, origin: ProposalOrigin? = nil, originRef: String? = nil) {
        self.id = id; self.sessionId = sessionId; self.brandId = brandId; self.kind = kind; self.summary = summary
        self.payloadJSON = payloadJSON; self.status = status; self.resultEntityId = resultEntityId
        self.createdAt = createdAt; self.decidedAt = decidedAt; self.origin = origin; self.originRef = originRef
    }
}

/// İşlenmiş terminal öneri dosyası: aynı içerik (sha256) aynı markaya ikinci kez önerilmez.
public struct SuggestionFile: Codable, Sendable, Hashable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "suggestionFile"
    public var id: String
    public var brandId: String
    public var sha256: String
    public var fileName: String
    public var itemCount: Int
    public var processedAt: Date

    public init(id: String = newID(), brandId: String, sha256: String, fileName: String, itemCount: Int, processedAt: Date = Date()) {
        self.id = id; self.brandId = brandId; self.sha256 = sha256; self.fileName = fileName
        self.itemCount = itemCount; self.processedAt = processedAt
    }
}

public struct AuditEvent: Codable, Sendable, Hashable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "auditEvent"
    public var id: String
    public var at: Date
    public var actor: Actor
    public var brandId: String?
    public var entity: String
    public var entityId: String
    public var action: String
    public var beforeJSON: String?
    public var afterJSON: String?

    public init(id: String = newID(), at: Date = Date(), actor: Actor, brandId: String?, entity: String,
                entityId: String, action: String, beforeJSON: String? = nil, afterJSON: String? = nil) {
        self.id = id; self.at = at; self.actor = actor; self.brandId = brandId; self.entity = entity
        self.entityId = entityId; self.action = action; self.beforeJSON = beforeJSON; self.afterJSON = afterJSON
    }
}

public struct UsageEntry: Codable, Sendable, Hashable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "usageEntry"
    public var id: String
    public var at: Date
    public var provider: AIProviderKind
    public var model: String
    public var sessionId: String?
    public var brandId: String?
    public var purpose: String
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheReadTokens: Int
    public var cacheWriteTokens: Int
    /// Tahmini maliyet (mikro USD). Codex/ChatGPT planında nil.
    public var costMicros: Int?

    public init(id: String = newID(), at: Date = Date(), provider: AIProviderKind, model: String, sessionId: String?,
                brandId: String?, purpose: String, inputTokens: Int, outputTokens: Int, cacheReadTokens: Int = 0,
                cacheWriteTokens: Int = 0, costMicros: Int?) {
        self.id = id; self.at = at; self.provider = provider; self.model = model; self.sessionId = sessionId
        self.brandId = brandId; self.purpose = purpose; self.inputTokens = inputTokens; self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens; self.cacheWriteTokens = cacheWriteTokens; self.costMicros = costMicros
    }
}

public struct ImportRun: Codable, Sendable, Hashable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "importRun"
    public var id: String
    public var at: Date
    public var kind: String
    public var sourcePath: String
    public var summaryJSON: String
    public var snapshotPath: String

    public init(id: String = newID(), at: Date = Date(), kind: String, sourcePath: String, summaryJSON: String,
                snapshotPath: String) {
        self.id = id; self.at = at; self.kind = kind; self.sourcePath = sourcePath
        self.summaryJSON = summaryJSON; self.snapshotPath = snapshotPath
    }
}
