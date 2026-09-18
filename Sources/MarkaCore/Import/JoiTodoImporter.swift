import Foundation
import GRDB

/// cli-todo-for-agentic (joi-todo) verisini salt okunur içe aktarır.
/// Kaynak dosyalar asla değiştirilmez; aynı içe aktarım tekrar çalışınca kopya oluşmaz.
public struct JoiTodoImporter: Sendable {
    public struct LegacyTask: Sendable, Hashable {
        public var id: Int
        public var code: String?
        public var text: String
        public var project: String?
        public var priority: Int
        public var due: String?
        public var done: Bool
        public var status: String?
        public var timeSpent: Int
        public var createdAt: Date?
        public var doneAt: Date?
    }

    public struct StopEvent: Sendable, Hashable {
        public var taskId: Int
        public var seconds: Int
        public var endedAt: Date
        public var startedAt: Date?
    }

    public struct ProjectSummary: Sendable, Hashable, Identifiable {
        public var project: String
        public var category: String?
        public var categoryName: String?
        public var openCount: Int
        public var doneCount: Int
        public var seconds: Int
        public var suggestedBrand: String?
        public var id: String { project }
    }

    public struct Analysis: Sendable {
        public var directory: URL
        public var tasks: [LegacyTask]
        public var stops: [StopEvent]
        public var completionEvents: [Int: Date]
        public var projects: [ProjectSummary]
        public var malformedEventLines: Int
        public var statusDoneConflicts: Int
        public var totalSeconds: Int
        /// 12 saati aşan tek görev süreleri (joi-todo'da açık unutulmuş sayaç olabilir).
        public var suspiciousTimeTasks: [LegacyTask]
    }

    public enum Target: Sendable, Hashable {
        case skip
        case newBrand(String)
        case existingBrand(String)
    }

    public struct Result: Codable, Sendable, Hashable {
        public var createdBrands: Int
        public var importedTasks: Int
        public var skippedExistingTasks: Int
        public var skippedProjects: Int
        public var importedTimeEntries: Int
        public var importedSeconds: Int
        public var estimatedCompletionDates: Int
    }

    public init() {}

    /// Olası veri konumları: iCloud eşitlemesi açıksa önce oradaki klasör.
    public static func candidateDirectories(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [
            home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/joi-todo", isDirectory: true),
            home.appendingPathComponent(".joi-todo", isDirectory: true),
        ].filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("tasks.json").path) }
    }

    nonisolated(unsafe) static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) static let isoPlain = ISO8601DateFormatter()

    static func date(_ any: Any?) -> Date? {
        guard let s = any as? String else { return nil }
        return isoFrac.date(from: s) ?? isoPlain.date(from: s)
    }

    public func analyze(directory: URL) throws -> Analysis {
        let tasksURL = directory.appendingPathComponent("tasks.json")
        guard let root = try JSONSerialization.jsonObject(with: Data(contentsOf: tasksURL)) as? [String: Any],
              let rawTasks = root["tasks"] as? [[String: Any]] else {
            throw MarkaError.validation(L("tasks.json okunamadı veya beklenen biçimde değil."))
        }
        var tasks: [LegacyTask] = []
        var conflicts = 0
        for t in rawTasks {
            guard let id = t["id"] as? Int, let text = t["text"] as? String else { continue }
            let project = (t["project"] as? String) ?? (t["tag"] as? String)
            let done = (t["done"] as? Bool) ?? false
            let status = t["status"] as? String
            if let status, (status == "COMPLETE") != done { conflicts += 1 }
            let due = (t["due"] as? String).flatMap { DayString.isValid($0) ? $0 : nil }
            tasks.append(LegacyTask(id: id, code: t["code"] as? String, text: text, project: project?.lowercased(),
                                    priority: min(max((t["priority"] as? Int) ?? 0, 0), 3), due: due, done: done, status: status,
                                    timeSpent: max((t["timeSpent"] as? Int) ?? 0, 0), createdAt: Self.date(t["createdAt"]),
                                    doneAt: Self.date(t["doneAt"])))
        }

        var stops: [StopEvent] = []
        var completions: [Int: Date] = [:]
        var malformed = 0
        let logURL = directory.appendingPathComponent("events.jsonl")
        if let log = try? String(contentsOf: logURL, encoding: .utf8) {
            for line in log.split(separator: "\n") where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                guard let e = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let type = e["type"] as? String, let ts = Self.date(e["ts"]) else { malformed += 1; continue }
                switch type {
                case "stop":
                    if let id = e["id"] as? Int, let secs = e["seconds"] as? Int, secs > 0 {
                        stops.append(StopEvent(taskId: id, seconds: secs, endedAt: ts, startedAt: Self.date(e["startedAt"])))
                    }
                case "toggle":
                    if let id = e["id"] as? Int, (e["done"] as? Bool) == true { completions[id] = ts }
                case "status":
                    if let id = e["id"] as? Int, (e["after"] as? String) == "COMPLETE" { completions[id] = ts }
                case "done":
                    if let id = e["id"] as? Int { completions[id] = ts }
                default: break
                }
            }
        }

        var categories: [String: (code: String, name: String)] = [:]
        if let cfgData = try? Data(contentsOf: directory.appendingPathComponent("config.json")),
           let cfg = try? JSONSerialization.jsonObject(with: cfgData) as? [String: Any],
           let cats = cfg["categories"] as? [[String: Any]] {
            for c in cats {
                guard let code = c["code"] as? String else { continue }
                let name = (c["name"] as? String) ?? code
                categories[code.lowercased()] = (code, name)
                for child in (c["children"] as? [String]) ?? [] { categories[child.lowercased()] = (code, name) }
            }
        }

        let grouped = Dictionary(grouping: tasks, by: { $0.project ?? "" })
        let brandLike = Set(grouped.keys.filter { categories[$0]?.code == "BP" && $0 != "bp" })
        var projects: [ProjectSummary] = grouped.map { key, list in
            let cat = categories[key]
            var suggestion: String? = brandLike.contains(key) ? Self.displayName(key) : nil
            if suggestion == nil, key.count >= 3, let target = brandLike.first(where: { $0 != key && $0.hasPrefix(key) }) {
                suggestion = Self.displayName(target) // ör. "atla" → "Atlas" (yazım farkı)
            }
            return ProjectSummary(project: key, category: cat?.code, categoryName: cat?.name,
                                  openCount: list.filter { !Self.isDone($0) }.count, doneCount: list.filter(Self.isDone).count,
                                  seconds: list.reduce(0) { $0 + $1.timeSpent }, suggestedBrand: suggestion)
        }
        projects.sort { ($0.openCount + $0.doneCount) > ($1.openCount + $1.doneCount) }
        return Analysis(directory: directory, tasks: tasks, stops: stops, completionEvents: completions, projects: projects,
                        malformedEventLines: malformed, statusDoneConflicts: conflicts, totalSeconds: tasks.reduce(0) { $0 + $1.timeSpent },
                        suspiciousTimeTasks: tasks.filter { $0.timeSpent > 12 * 3600 })
    }

    static func displayName(_ project: String) -> String {
        let tr = Locale(identifier: "tr_TR")
        return project.split(separator: "-").map { $0.count <= 3 ? $0.uppercased(with: tr) : $0.capitalized(with: tr) }.joined(separator: " ")
    }

    /// `status` alanı `done` alanından yenidir; çelişkide `status` esas alınır.
    static func isDone(_ t: LegacyTask) -> Bool {
        if let s = t.status { return s == "COMPLETE" }
        return t.done
    }

    static func mapStatus(_ t: LegacyTask) -> TaskStatus {
        switch t.status {
        case "COMPLETE": .done
        case "ACTIVE": .inProgress
        case "HOLD": .waiting
        case "READY": .todo
        default: t.done ? .done : .todo
        }
    }

    public func run(_ analysis: Analysis, mapping: [String: Target], store: Store, snapshotDirectory: URL?) throws -> Result {
        // Anlık görüntü: içe aktarılan dosyaların kopyası (izlenebilirlik için).
        if let snapshotDirectory {
            try FileManager.default.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)
            for name in ["tasks.json", "events.jsonl", "config.json"] {
                let src = analysis.directory.appendingPathComponent(name)
                let dst = snapshotDirectory.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: src.path), !FileManager.default.fileExists(atPath: dst.path) {
                    try FileManager.default.copyItem(at: src, to: dst)
                }
            }
        }
        let stopsByTask = Dictionary(grouping: analysis.stops, by: \.taskId)
        return try store.writer.write { db in
            var result = Result(createdBrands: 0, importedTasks: 0, skippedExistingTasks: 0, skippedProjects: 0,
                                importedTimeEntries: 0, importedSeconds: 0, estimatedCompletionDates: 0)
            var brandIds: [String: String] = [:]  // yeni marka adı → id
            let tr = Locale(identifier: "tr_TR")
            for (project, target) in mapping.sorted(by: { $0.key < $1.key }) {
                switch target {
                case .skip: result.skippedProjects += 1
                case .existingBrand(let id):
                    guard try Brand.fetchOne(db, key: id) != nil else { throw MarkaError.notFound(id) }
                case .newBrand(let name):
                    let clean = name.trimmed
                    guard !clean.isEmpty else { throw MarkaError.validation(LF("“%@” için marka adı boş.", project)) }
                    let key = clean.lowercased(with: tr)
                    if brandIds[key] != nil { continue }
                    if let existing = try Brand.fetchAll(db).first(where: { $0.name.lowercased(with: tr) == key }) {
                        brandIds[key] = existing.id
                    } else {
                        let b = Brand(name: clean)
                        try b.insert(db)
                        try BrandRules(brandId: b.id, body: WikiRulesTemplate.defaultBody).insert(db)
                        try store.audit(db, actor: .import, brandId: b.id, entity: "brand", entityId: b.id, action: "create", before: Brand?.none, after: b)
                        brandIds[key] = b.id
                        result.createdBrands += 1
                    }
                }
            }
            for t in analysis.tasks {
                let target = mapping[t.project ?? ""] ?? .skip
                let brandId: String
                switch target {
                case .skip: continue
                case .existingBrand(let id): brandId = id
                case .newBrand(let name): brandId = brandIds[name.trimmed.lowercased(with: tr)]!
                }
                let legacyKey = "joi:\(t.id):\(t.createdAt.map { Int($0.timeIntervalSince1970) } ?? 0)"
                if try WorkTask.filter(Column("legacyKey") == legacyKey).fetchCount(db) > 0 {
                    result.skippedExistingTasks += 1
                    continue
                }
                let status = Self.mapStatus(t)
                let created = t.createdAt ?? Date()
                var completedAt: Date?
                if status == .done {
                    completedAt = t.doneAt ?? analysis.completionEvents[t.id]
                    if completedAt == nil { completedAt = created; result.estimatedCompletionDates += 1 }
                }
                var task = WorkTask(brandId: brandId, title: t.text, notes: t.code.map { LF("joi-todo kodu: %@", $0) } ?? "",
                                    priority: t.priority, dueDate: t.due, status: status, createdAt: created, updatedAt: completedAt ?? created,
                                    completedAt: completedAt, actor: .import, legacyKey: legacyKey, legacyCode: t.code)
                try task.insert(db)
                result.importedTasks += 1
                var covered = 0
                for (i, s) in (stopsByTask[t.id] ?? []).enumerated() {
                    let key = "\(legacyKey):stop:\(i):\(Int(s.endedAt.timeIntervalSince1970))"
                    let entry = TimeEntry(taskId: task.id, brandId: brandId, startedAt: s.startedAt ?? s.endedAt.addingTimeInterval(-Double(s.seconds)),
                                          endedAt: s.endedAt, seconds: s.seconds, note: L("joi-todo sayaç kaydı"), actor: .import, legacyKey: key)
                    try entry.insert(db)
                    covered += s.seconds
                    result.importedTimeEntries += 1
                }
                let remainder = t.timeSpent - covered
                if remainder >= 60 {
                    let end = completedAt ?? created
                    let entry = TimeEntry(taskId: task.id, brandId: brandId, startedAt: end.addingTimeInterval(-Double(remainder)), endedAt: end,
                                          seconds: remainder, note: L("İçe aktarılan toplam süre (ayrıntı yok)"), actor: .import,
                                          legacyKey: "\(legacyKey):remainder")
                    try entry.insert(db)
                    result.importedTimeEntries += 1
                }
                task.timeSpentSeconds = try Store.sumSeconds(db, taskId: task.id)
                try task.update(db)
                result.importedSeconds += task.timeSpentSeconds
            }
            let run = ImportRun(kind: "joi-todo", sourcePath: analysis.directory.path, summaryJSON: Store.json(result) ?? "{}",
                                snapshotPath: snapshotDirectory?.path ?? "")
            try run.insert(db)
            try store.audit(db, actor: .import, brandId: nil, entity: "importRun", entityId: run.id, action: "create", before: ImportRun?.none, after: run)
            return result
        }
    }
}
