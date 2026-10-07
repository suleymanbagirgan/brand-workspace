import Foundation
import GRDB

// MARK: - Eylem kayıt defteri (plan §4.1, F1 ilk dilim)
//
// Her yetenek bir `AppAction`: kimlik, başlık, risk kademesi, tipli parametre. Önizleme alan bazında önce/sonra verir,
// uygulama geri alma kaydı (`UndoRecord`) döndürür, geri alma önceki değerleri yükler. Her uygulama `Store.audit` bırakır;
// her işlem `brandId` ile kapsanır (başka markanın kaydı reddedilir). `needsApproval` eylemi yapay zekâ yalnız ÖNERİ olarak
// üretir (`ProposalKind.updateTask`); doğrudan uygulamayı yalnız kullanıcı (ya da kullanıcının onayladığı öneri) yapar.

/// Eylemin risk kademesi.
public enum ActionRisk: String, Codable, Sendable, CaseIterable {
    /// Yalnız okur.
    case read
    /// Kullanıcının eylem türü başına önceden verdiği izinle uygulanabilir (henüz kullanılmıyor).
    case safeWrite
    /// Yapay zekâ yalnız öneri üretir; kullanıcı onaylar.
    case needsApproval
    /// Hiçbir yoldan uygulanmaz.
    case forbidden
}

/// Görevin eylemlerle değişebilen alanı.
public enum TaskField: String, Codable, Sendable, CaseIterable {
    case title, dueDate, status

    public var label: String {
        switch self {
        case .title: L("Başlık")
        case .dueDate: L("Son tarih")
        case .status: L("Durum")
        }
    }
}

/// Bir alanın önce/sonra değeri (ham biçim: tarih `yyyy-MM-dd`, durum `TaskStatus.rawValue`; `nil`: boş).
public struct FieldChange: Codable, Sendable, Hashable {
    public var field: TaskField
    public var before: String?
    public var after: String?
    public init(field: TaskField, before: String?, after: String?) { self.field = field; self.before = before; self.after = after }

    /// Okunur satır, ör. "Son tarih: 12 Eki → 15 Eki".
    public func line(locale: Locale = .current) -> String {
        "\(field.label): \(display(before, locale: locale)) → \(display(after, locale: locale))"
    }

    func display(_ value: String?, locale: Locale) -> String {
        guard let value, !value.isEmpty else { return L("yok") }
        switch field {
        case .title: return "“\(value)”"
        case .status: return TaskStatus(rawValue: value)?.title ?? value
        case .dueDate:
            guard let d = DayString.date(value, calendar: Calendar(identifier: .gregorian)) else { return value }
            let f = DateFormatter()
            f.calendar = Calendar(identifier: .gregorian)
            f.locale = locale
            f.setLocalizedDateFormatFromTemplate("dMMM")
            return f.string(from: d)
        }
    }
}

/// Eylemin uygulanmadan önceki etkisi: hangi kayıtta hangi alan neden neye döner.
public struct ActionPreview: Sendable, Hashable {
    public var actionIds: [String]
    public var brandId: String
    public var entity: String
    public var entityId: String
    /// Kaydın şimdiki başlığı (gösterim için).
    public var entityTitle: String
    public var changes: [FieldChange]

    public func lines(locale: Locale = .current) -> [String] { changes.map { $0.line(locale: locale) } }
}

/// Geri alma kaydı: uygulanan değişikliğin önceki (`before`) ve uygulanan (`after`) değerleri.
public struct UndoRecord: Codable, Sendable, Hashable {
    public var actionIds: [String]
    public var brandId: String
    public var entity: String
    public var entityId: String
    public var changes: [FieldChange]
    public var appliedAt: Date
}

/// Görev alanlarına hedef değerler. `dueDate`: `nil` dokunma, `.some(nil)` tarihi kaldır.
public struct TaskEdit: Sendable, Hashable {
    public var taskId: String
    public var title: String?
    public var dueDate: String??
    public var status: TaskStatus?
    public var actionIds: [String] = []

    public init(taskId: String, title: String? = nil, dueDate: String?? = nil, status: TaskStatus? = nil) {
        self.taskId = taskId; self.title = title; self.dueDate = dueDate; self.status = status
    }

    public var isEmpty: Bool { title == nil && dueDate == nil && status == nil }

    /// Aynı görev için ikinci eylemin hedeflerini ekler (sonraki kazanır).
    mutating func merge(_ other: TaskEdit) {
        if let t = other.title { title = t }
        if let d = other.dueDate { dueDate = d }
        if let s = other.status { status = s }
        actionIds += other.actionIds.filter { !actionIds.contains($0) }
    }
}

/// Bir yetenek. Parametreler tiplidir; doğrulama `edit(_:)` içinde yapılır.
public protocol AppAction: Sendable {
    associatedtype Parameters: Codable & Sendable & Hashable
    static var id: String { get }
    static var title: String { get }
    static var risk: ActionRisk { get }
}

/// Görev alanlarını değiştiren eylem: parametreyi doğrulanmış `TaskEdit`'e çevirir; önizleme/uygulama/geri alma ortaktır.
public protocol TaskEditAction: AppAction {
    static func edit(_ params: Parameters) throws -> TaskEdit
}

// MARK: - İlk üç eylem

/// Son tarihi değiştirir (ertele / ileri al / kaldır).
public enum TaskReschedule: TaskEditAction {
    public struct Parameters: Codable, Sendable, Hashable {
        public var taskId: String
        /// `yyyy-MM-dd`; `nil`: son tarihi kaldır.
        public var dueDate: String?
        public init(taskId: String, dueDate: String?) { self.taskId = taskId; self.dueDate = dueDate }
    }
    public static let id = "task.reschedule"
    public static var title: String { L("Son tarihi değiştir") }
    public static let risk = ActionRisk.needsApproval

    public static func edit(_ p: Parameters) throws -> TaskEdit {
        if let d = p.dueDate, !DayString.isValid(d) { throw MarkaError.validation(L("Tarih geçersiz.")) }
        var e = TaskEdit(taskId: p.taskId, dueDate: .some(p.dueDate))
        e.actionIds = [id]
        return e
    }

    /// `day`'i `days` gün kaydırır (eksi: ileri al). Geçersiz günde `nil`.
    public static func shifted(_ day: String, by days: Int) -> String? {
        let cal = Calendar(identifier: .gregorian)
        guard DayString.isValid(day), let d = DayString.date(day, calendar: cal),
              let moved = cal.date(byAdding: .day, value: days, to: d) else { return nil }
        return DayString.from(moved, calendar: cal)
    }

    /// "N gün ertele": son tarihi varsa ondan, yoksa bugünden `days` gün sonrası.
    public static func postpone(_ task: WorkTask, days: Int, today: String = DayString.from(Date())) throws -> Parameters {
        guard let day = shifted(task.dueDate ?? today, by: days) else { throw MarkaError.validation(L("Tarih geçersiz.")) }
        return Parameters(taskId: task.id, dueDate: day)
    }
}

/// Görevin başlığını değiştirir.
public enum TaskRename: TaskEditAction {
    public struct Parameters: Codable, Sendable, Hashable {
        public var taskId: String
        public var title: String
        public init(taskId: String, title: String) { self.taskId = taskId; self.title = title }
    }
    public static let id = "task.rename"
    public static var title: String { L("Görevi yeniden adlandır") }
    public static let risk = ActionRisk.needsApproval

    public static func edit(_ p: Parameters) throws -> TaskEdit {
        let t = p.title.trimmed
        guard !t.isEmpty else { throw MarkaError.validation(L("Görev başlığı boş olamaz.")) }
        var e = TaskEdit(taskId: p.taskId, title: t)
        e.actionIds = [id]
        return e
    }
}

/// Görevin durumunu değiştirir.
public enum TaskSetStatus: TaskEditAction {
    public struct Parameters: Codable, Sendable, Hashable {
        public var taskId: String
        public var status: TaskStatus
        public init(taskId: String, status: TaskStatus) { self.taskId = taskId; self.status = status }
    }
    public static let id = "task.setStatus"
    public static var title: String { L("Görev durumunu değiştir") }
    public static let risk = ActionRisk.needsApproval

    public static func edit(_ p: Parameters) throws -> TaskEdit {
        var e = TaskEdit(taskId: p.taskId, status: p.status)
        e.actionIds = [id]
        return e
    }
}

/// Kayıtlı eylemlerin tek listesi (arayüz, ⌘K ve AI araçları ileride buradan türeyecek).
public enum ActionRegistry {
    public struct Descriptor: Sendable, Hashable {
        public var id: String
        public var title: String
        public var risk: ActionRisk
    }

    static func descriptor<A: AppAction>(_ a: A.Type) -> Descriptor { Descriptor(id: A.id, title: A.title, risk: A.risk) }

    public static var all: [Descriptor] { [descriptor(TaskReschedule.self), descriptor(TaskRename.self), descriptor(TaskSetStatus.self)] }

    public static func descriptor(id: String) -> Descriptor? { all.first { $0.id == id } }
}

// MARK: - Store: önizle, uygula, geri al

extension Store {
    /// Eylemin etkisini veriyi değiştirmeden döndürür. Başka markanın görevi reddedilir.
    public func preview<A: TaskEditAction>(_ action: A.Type, brandId: String, _ params: A.Parameters) throws -> ActionPreview {
        let edit = try A.edit(params)
        return try read { db in try previewTaskEdit(db, brandId: brandId, edit) }
    }

    /// Kullanıcının doğrudan uyguladığı eylem. `needsApproval` eylemi yapay zekâ adına doğrudan uygulanamaz (öneri yolu
    /// `applyProposal`'dır); `forbidden` hiç uygulanmaz.
    @discardableResult
    public func apply<A: TaskEditAction>(_ action: A.Type, brandId: String, _ params: A.Parameters, actor: Actor = .user) throws -> UndoRecord {
        try Self.requireAllowed(A.risk, actor: actor)
        let edit = try A.edit(params)
        return try writer.write { db in try applyTaskEdit(db, brandId: brandId, edit, actor: actor) }
    }

    /// Geri alma kaydındaki önceki değerleri yükler. Kayıt başka markanınsa ya da görev o eylemden sonra değiştiyse reddedilir.
    public func undo(_ record: UndoRecord, brandId: String, actor: Actor = .user) throws {
        try writer.write { db in try undoTaskEdit(db, record, brandId: brandId, actor: actor, auditAction: "undo") }
    }

    static func requireAllowed(_ risk: ActionRisk, actor: Actor) throws {
        switch risk {
        case .forbidden: throw MarkaError.validation(L("Bu eylem uygulanamaz."))
        case .needsApproval where actor != .user:
            throw MarkaError.validation(L("Bu eylem yalnız öneri olarak verilebilir; kullanıcı onaylar."))
        default: break
        }
    }

    func scopedTask(_ db: Database, _ id: String, brandId: String) throws -> WorkTask {
        guard let t = try WorkTask.fetchOne(db, key: id) else { throw MarkaError.notFound(id) }
        guard t.brandId == brandId else { throw MarkaError.brandScope }
        return t
    }

    static func value(_ t: WorkTask, _ f: TaskField) -> String? {
        switch f {
        case .title: t.title
        case .dueDate: t.dueDate
        case .status: t.status.rawValue
        }
    }

    static func setting(_ t: WorkTask, _ f: TaskField, _ v: String?) throws -> WorkTask {
        var t = t
        switch f {
        case .title:
            guard let v, !v.trimmed.isEmpty else { throw MarkaError.validation(L("Görev başlığı boş olamaz.")) }
            t.title = v
        case .dueDate:
            if let v, !DayString.isValid(v) { throw MarkaError.validation(L("Tarih geçersiz.")) }
            t.dueDate = v
        case .status:
            guard let v, let s = TaskStatus(rawValue: v) else { throw MarkaError.validation(L("Durum geçersiz.")) }
            t.status = s
        }
        return t
    }

    func previewTaskEdit(_ db: Database, brandId: String, _ edit: TaskEdit) throws -> ActionPreview {
        guard !edit.isEmpty else { throw MarkaError.validation(L("Değişiklik yok: başlık, son tarih ya da durumdan en az biri verilmeli.")) }
        let t = try scopedTask(db, edit.taskId, brandId: brandId)
        var wanted: [(TaskField, String?)] = []
        if let title = edit.title { wanted.append((.title, title.trimmed)) }
        if let due = edit.dueDate { wanted.append((.dueDate, due)) }
        if let status = edit.status { wanted.append((.status, status.rawValue)) }
        let changes = wanted.compactMap { f, v in Self.value(t, f) == v ? nil : FieldChange(field: f, before: Self.value(t, f), after: v) }
        guard !changes.isEmpty else { throw MarkaError.validation(L("Görevde değişecek bir alan yok.")) }
        return ActionPreview(actionIds: edit.actionIds, brandId: brandId, entity: "task", entityId: t.id, entityTitle: t.title, changes: changes)
    }

    func applyTaskEdit(_ db: Database, brandId: String, _ edit: TaskEdit, actor: Actor) throws -> UndoRecord {
        let preview = try previewTaskEdit(db, brandId: brandId, edit)
        var t = try scopedTask(db, edit.taskId, brandId: brandId)
        for c in preview.changes { t = try Self.setting(t, c.field, c.after) }
        _ = try saveTask(db, t, actor: actor, auditAction: edit.actionIds.joined(separator: ","))
        return UndoRecord(actionIds: edit.actionIds, brandId: brandId, entity: "task", entityId: t.id, changes: preview.changes, appliedAt: Date())
    }

    func undoTaskEdit(_ db: Database, _ record: UndoRecord, brandId: String, actor: Actor, auditAction: String) throws {
        guard record.brandId == brandId, record.entity == "task" else { throw MarkaError.brandScope }
        var t = try scopedTask(db, record.entityId, brandId: brandId)
        for c in record.changes where Self.value(t, c.field) != c.after {
            throw MarkaError.validation(L("Görev bu değişiklikten sonra yeniden değiştiği için geri alınamaz."))
        }
        for c in record.changes { t = try Self.setting(t, c.field, c.before) }
        _ = try saveTask(db, t, actor: actor, auditAction: auditAction)
    }
}
