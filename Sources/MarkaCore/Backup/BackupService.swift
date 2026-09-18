import Foundation
import GRDB

public struct BackupManifest: Codable, Sendable, Hashable {
    public var format: Int
    public var createdAt: Date
    public var appVersion: String
    public var migrations: [String]
    public var brandCount: Int
    public var sourceCount: Int
    public var taskCount: Int
    public var reason: String
}

public struct BackupInfo: Sendable, Hashable, Identifiable {
    public var url: URL
    public var manifest: BackupManifest
    public var id: URL { url }
}

/// Yedekleme, geri yükleme ve dışa aktarma. Yedek = SQLite çevrimiçi yedeği + dosya deposu + manifest.
public struct BackupService: Sendable {
    public let workspace: URL
    public var backupsRoot: URL { workspace.appendingPathComponent("Yedekler", isDirectory: true) }

    public init(workspace: URL) { self.workspace = workspace }

    nonisolated(unsafe) static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HHmmss_SSS"
        return f
    }()

    @discardableResult
    public func createBackup(database: AppDatabase, reason: String, destination: URL? = nil, now: Date = Date()) throws -> URL {
        let fm = FileManager.default
        let base = (destination ?? backupsRoot)
        var dir = base.appendingPathComponent("yedek_\(Self.stampFormatter.string(from: now))_\(reason)", isDirectory: true)
        var n = 2
        while fm.fileExists(atPath: dir.path) {
            dir = base.appendingPathComponent("yedek_\(Self.stampFormatter.string(from: now))_\(reason)_\(n)", isDirectory: true)
            n += 1
        }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = try DatabaseQueue(path: dir.appendingPathComponent("workspace.sqlite").path)
        try database.writer.backup(to: target)
        // Yedek tek dosya olarak taşınabilir olsun: WAL kipi başlığını kaldır.
        try target.writeWithoutTransaction { db in try db.execute(sql: "PRAGMA journal_mode=DELETE") }
        try target.close()
        // Dosyalar değişmez; mümkünse sabit bağlantı (yer kaplamaz), değilse kopya.
        let filesDst = dir.appendingPathComponent("Files", isDirectory: true)
        try copyTree(from: database.filesRoot, to: filesDst)
        let counts = try database.writer.read { db in
            (try Brand.fetchCount(db), try Source.fetchCount(db), try WorkTask.fetchCount(db))
        }
        let manifest = BackupManifest(format: 1, createdAt: now, appVersion: MarkaCoreVersion.string,
                                      migrations: try appliedMigrations(database), brandCount: counts.0, sourceCount: counts.1,
                                      taskCount: counts.2, reason: reason)
        try Store.encoder.encode(manifest).write(to: dir.appendingPathComponent("manifest.json"))
        return dir
    }

    private func appliedMigrations(_ database: AppDatabase) throws -> [String] {
        try database.writer.read { db in
            try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid")
        }
    }

    private func copyTree(from src: URL, to dst: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        guard let e = fm.enumerator(at: src, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for case let url as URL in e {
            let rel = url.path.replacingOccurrences(of: src.path + "/", with: "")
            let out = dst.appendingPathComponent(rel)
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                try fm.createDirectory(at: out, withIntermediateDirectories: true)
            } else if !fm.fileExists(atPath: out.path) {
                do { try fm.linkItem(at: url, to: out) } catch { try fm.copyItem(at: url, to: out) }
            }
        }
    }

    public func listBackups() -> [BackupInfo] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: backupsRoot, includingPropertiesForKeys: nil) else { return [] }
        return dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")),
                  let m = try? Store.decoder.decode(BackupManifest.self, from: data) else { return nil }
            return BackupInfo(url: dir, manifest: m)
        }.sorted { $0.manifest.createdAt > $1.manifest.createdAt }
    }

    /// Günde bir otomatik yedek; son `keep` otomatik yedek tutulur.
    @discardableResult
    public func autoBackupIfNeeded(database: AppDatabase, now: Date = Date(), keep: Int = 14) throws -> URL? {
        let autos = listBackups().filter { $0.manifest.reason == "auto" }
        if let last = autos.first, Calendar.current.isDate(last.manifest.createdAt, inSameDayAs: now) { return nil }
        let url = try createBackup(database: database, reason: "auto", now: now)
        for old in listBackups().filter({ $0.manifest.reason == "auto" }).dropFirst(keep) {
            try? FileManager.default.removeItem(at: old.url)
        }
        return url
    }

    /// Yedeğin bu sürümle açılabilir olduğunu doğrular.
    public func validate(backup: URL) throws -> BackupManifest {
        let fm = FileManager.default
        let dbURL = backup.appendingPathComponent("workspace.sqlite")
        guard fm.fileExists(atPath: dbURL.path) else { throw MarkaError.incompatibleBackup(L("workspace.sqlite yok")) }
        let manifest = try? Store.decoder.decode(BackupManifest.self, from: Data(contentsOf: backup.appendingPathComponent("manifest.json")))
        var config = Configuration()
        config.readonly = true
        let q = try DatabaseQueue(path: dbURL.path, configuration: config)
        defer { try? q.close() }
        let applied = try q.read { db -> [String] in
            let ok = try String.fetchOne(db, sql: "PRAGMA integrity_check")
            guard ok == "ok" else { throw MarkaError.incompatibleBackup(L("veri tabanı bütünlük denetimi başarısız")) }
            return try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations")
        }
        let known = Set(AppDatabase.migrationIdentifiers)
        let unknown = applied.filter { !known.contains($0) }
        guard unknown.isEmpty else {
            throw MarkaError.incompatibleBackup(LF("daha yeni bir sürümle oluşturulmuş (%@)", unknown.joined(separator: ", ")))
        }
        return manifest ?? BackupManifest(format: 1, createdAt: Date(), appVersion: "?", migrations: applied, brandCount: 0, sourceCount: 0, taskCount: 0, reason: "?")
    }

    /// Geri yükleme. Çağıran, çalışan veri tabanını önce kapatmalıdır (`closeCurrent`).
    /// Mevcut veri önce "geri-yukleme-oncesi" yedeğine alınır.
    public func restore(backup: URL, current: AppDatabase, closeCurrent: () throws -> Void) throws {
        _ = try validate(backup: backup)
        try createBackup(database: current, reason: "pre-restore")
        let fm = FileManager.default
        // Önce geçici kopya: silme sonrası kopyalama başarısız olup boş veri tabanı kalmasın.
        let staged = workspace.appendingPathComponent("workspace.sqlite.restoring")
        if fm.fileExists(atPath: staged.path) { try fm.removeItem(at: staged) }
        try fm.copyItem(at: backup.appendingPathComponent("workspace.sqlite"), to: staged)
        try closeCurrent()
        let dbURL = workspace.appendingPathComponent("workspace.sqlite")
        for suffix in ["", "-wal", "-shm"] {
            let u = URL(fileURLWithPath: dbURL.path + suffix)
            if fm.fileExists(atPath: u.path) { try fm.removeItem(at: u) }
        }
        try fm.moveItem(at: staged, to: dbURL)
        let files = workspace.appendingPathComponent("Files", isDirectory: true)
        try copyTree(from: backup.appendingPathComponent("Files", isDirectory: true), to: files)
    }

    // MARK: Dışa aktarma

    public struct BrandExport: Codable, Sendable {
        public var exportedAt: Date
        public var appVersion: String
        public var brand: Brand
        public var contacts: [Contact]
        public var projects: [Project]
        public var records: [BrandRecord]
        public var sources: [Source]
        public var tasks: [WorkTask]
        public var timeEntries: [TimeEntry]
        public var workLogs: [WorkLog]
        public var workLogSources: [WorkLogSource]
        public var wikiPages: [WikiPage]
        public var wikiRevisions: [WikiRevision]
        public var wikiClaims: [WikiClaim]
        public var rules: BrandRules?
        public var reports: [Report]
        public var reportVersions: [ReportVersion]
        public var reportShares: [ReportShare]
    }

    /// Bir markanın tüm verisini okunabilir JSON + orijinal dosyalar olarak dışa aktarır. API anahtarı içermez.
    @discardableResult
    public func exportBrand(_ brandId: String, store: Store, to destination: URL) throws -> URL {
        let export = try store.read { db -> BrandExport in
            guard let brand = try Brand.fetchOne(db, key: brandId) else { throw MarkaError.notFound(brandId) }
            let f = Column("brandId") == brandId
            let logs = try WorkLog.filter(f).fetchAll(db)
            let reports = try Report.filter(f).fetchAll(db)
            let reportIds = reports.map(\.id)
            return BrandExport(
                exportedAt: Date(), appVersion: MarkaCoreVersion.string, brand: brand,
                contacts: try Contact.filter(f).fetchAll(db), projects: try Project.filter(f).fetchAll(db),
                records: try BrandRecord.filter(f).fetchAll(db), sources: try Source.filter(f).fetchAll(db),
                tasks: try WorkTask.filter(f).fetchAll(db), timeEntries: try TimeEntry.filter(f).fetchAll(db),
                workLogs: logs, workLogSources: try WorkLogSource.filter(logs.map(\.id).contains(Column("workLogId"))).fetchAll(db),
                wikiPages: try WikiPage.filter(f).fetchAll(db), wikiRevisions: try WikiRevision.filter(f).fetchAll(db),
                wikiClaims: try WikiClaim.filter(f).fetchAll(db), rules: try BrandRules.fetchOne(db, key: brandId),
                reports: reports, reportVersions: try ReportVersion.filter(reportIds.contains(Column("reportId"))).fetchAll(db),
                reportShares: try ReportShare.filter(reportIds.contains(Column("reportId"))).fetchAll(db))
        }
        let safeName = export.brand.name.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-")
        let dir = destination.appendingPathComponent("\(safeName) dışa aktarım \(Self.stampFormatter.string(from: Date()))", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: dir.appendingPathComponent("dosyalar"), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(export).write(to: dir.appendingPathComponent("veri.json"))
        for s in export.sources {
            guard let path = s.filePath else { continue }
            let src = store.vault.url(for: path)
            let name = "\(s.id.prefix(8))-\(s.fileName ?? (path as NSString).lastPathComponent)"
            if fm.fileExists(atPath: src.path) {
                try? fm.copyItem(at: src, to: dir.appendingPathComponent("dosyalar").appendingPathComponent(name))
            }
        }
        return dir
    }
}
