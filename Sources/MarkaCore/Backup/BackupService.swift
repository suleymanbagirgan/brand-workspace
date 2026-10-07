import CryptoKit
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
    /// Biçim 2: yedek klasörüne göre göreli yol → SHA-256 (onaltılık). `workspace.sqlite` ve `Files/…` altındaki her dosya.
    /// Biçim 1 (eski) yedeklerde yoktur; o yedekler yalnız veri tabanı bütünlük denetimiyle kabul edilir.
    public var files: [String: String]?

    public init(format: Int, createdAt: Date, appVersion: String, migrations: [String], brandCount: Int, sourceCount: Int,
                taskCount: Int, reason: String, files: [String: String]? = nil) {
        self.format = format; self.createdAt = createdAt; self.appVersion = appVersion; self.migrations = migrations
        self.brandCount = brandCount; self.sourceCount = sourceCount; self.taskCount = taskCount; self.reason = reason
        self.files = files
    }

    /// Dosya özetleri var mı (biçim 2 ve sonrası).
    public var hasChecksums: Bool { files != nil }
}

public struct BackupInfo: Sendable, Hashable, Identifiable {
    public var url: URL
    public var manifest: BackupManifest
    public var id: URL { url }
    public init(url: URL, manifest: BackupManifest) { self.url = url; self.manifest = manifest }
}

/// Yedek bütünlüğü hataları. Mesajlar dosya adı ya da yol taşımaz (tanı kaydına yalnız vaka adı düşer); yalnız sayı söyler.
public enum BackupIntegrityError: LocalizedError, Equatable, Sendable {
    /// `manifest.json` yok: yedek yarım kalmış ya da elle oluşturulmuş.
    case missingManifest
    case unreadableManifest
    /// Manifestteki özetle uyuşmayan dosyalar (göreli yollar).
    case modifiedFiles([String])
    /// Manifestte olup yedekte bulunmayan dosyalar.
    case missingFiles([String])
    /// Yedekte olup manifestte olmayan dosyalar.
    case unexpectedFiles([String])

    public var errorDescription: String? {
        switch self {
        case .missingManifest: L("Yedek reddedildi: manifest.json yok, yedeğin eksiksiz olduğu doğrulanamıyor.")
        case .unreadableManifest: L("Yedek reddedildi: manifest.json okunamadı.")
        case .modifiedFiles(let f): LF("Yedek reddedildi: %d dosya yedek alındıktan sonra değiştirilmiş.", f.count)
        case .missingFiles(let f): LF("Yedek reddedildi: %d dosya eksik.", f.count)
        case .unexpectedFiles(let f): LF("Yedek reddedildi: manifestte olmayan %d dosya var.", f.count)
        }
    }
}

/// Yedekleme, geri yükleme ve dışa aktarma. Yedek = SQLite çevrimiçi yedeği + dosya deposu + manifest (dosya başına SHA-256).
public struct BackupService: Sendable {
    public let workspace: URL
    /// Varsayılan yedek yeri: veri klasörünün içi, yani aynı Mac ve aynı disk. Başka diske yedek `createBackup(destination:)` ile.
    public var backupsRoot: URL { workspace.appendingPathComponent("Yedekler", isDirectory: true) }

    public init(workspace: URL) { self.workspace = workspace }

    /// Şu anki manifest biçimi.
    public static let manifestFormat = 2
    /// Bütünlük denetiminde sayılmayan dosyalar: Finder'ın eklediği `.DS_Store` ve SQLite'ın salt okunur açılışta
    /// oluşturabildiği paylaşılan bellek dizini (`-shm`, veri taşımaz). `-wal`/`-journal` sayılır: veri değiştirebilir.
    static let ignoredNames: Set<String> = [".DS_Store", "workspace.sqlite-shm"]

    static let stampFormatter: DateFormatter = {
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
        // WAL'dan dönüşte kalan paylaşılan bellek dosyası yedeğin parçası değil.
        for suffix in ["-shm", "-wal"] {
            let side = dir.appendingPathComponent("workspace.sqlite\(suffix)")
            if fm.fileExists(atPath: side.path) { try fm.removeItem(at: side) }
        }
        // Dosyalar değişmez; mümkünse sabit bağlantı (yer kaplamaz), değilse kopya (başka disk).
        let filesDst = dir.appendingPathComponent("Files", isDirectory: true)
        try copyTree(from: database.filesRoot, to: filesDst)
        let counts = try database.writer.read { db in
            (try Brand.fetchCount(db), try Source.fetchCount(db), try WorkTask.fetchCount(db))
        }
        let manifest = BackupManifest(format: Self.manifestFormat, createdAt: now, appVersion: MarkaCoreVersion.string,
                                      migrations: try appliedMigrations(database), brandCount: counts.0, sourceCount: counts.1,
                                      taskCount: counts.2, reason: reason, files: try checksums(in: dir))
        try Store.encoder.encode(manifest).write(to: dir.appendingPathComponent("manifest.json"))
        return dir
    }

    private func appliedMigrations(_ database: AppDatabase) throws -> [String] {
        try database.writer.read { db in
            try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid")
        }
    }

    /// `src` altındaki her dosyanın `dst` altında aynı göreli yolla bulunmasını sağlar. Var olan dosya ezilmez
    /// (dosya deposu değişmezdir); hata sessizce yutulmaz.
    private func copyTree(from src: URL, to dst: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        guard fm.fileExists(atPath: src.path) else { return }
        for rel in try relativeFiles(in: src, includeDirectories: true) {
            let url = src.appendingPathComponent(rel)
            let out = dst.appendingPathComponent(rel)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                try fm.createDirectory(at: out, withIntermediateDirectories: true)
            } else if !fm.fileExists(atPath: out.path) {
                try fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
                do { try fm.linkItem(at: url, to: out) } catch { try fm.copyItem(at: url, to: out) }
            }
        }
    }

    /// Klasör altındaki göreli yollar (`/` ayraçlı, sıralı). `includeDirectories` yanlışsa yalnız dosyalar.
    private func relativeFiles(in root: URL, includeDirectories: Bool = false) throws -> [String] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return [] }
        guard let e = fm.enumerator(atPath: root.path) else {
            throw CocoaError(.fileReadUnknown)
        }
        var out: [String] = []
        while let rel = e.nextObject() as? String {
            if Self.ignoredNames.contains((rel as NSString).lastPathComponent) { continue }
            var isDir: ObjCBool = false
            _ = fm.fileExists(atPath: root.appendingPathComponent(rel).path, isDirectory: &isDir)
            if isDir.boolValue && !includeDirectories { continue }
            out.append(rel)
        }
        return out.sorted()
    }

    /// Yedek klasöründeki (manifest hariç) her dosyanın SHA-256 özeti.
    private func checksums(in dir: URL) throws -> [String: String] {
        var out: [String: String] = [:]
        for rel in try relativeFiles(in: dir) where rel != "manifest.json" {
            out[rel] = try Self.sha256(of: dir.appendingPathComponent(rel))
        }
        return out
    }

    /// Dosyanın SHA-256 özeti; büyük dosyalar parça parça okunur.
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Varsayılan yedek klasöründeki okunabilir yedekler (yenisi önce). Manifesti okunamayan klasörler listede yoktur;
    /// `validate` onları ayrıca reddeder.
    public func listBackups() -> [BackupInfo] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: backupsRoot.path),
              let dirs = try? fm.contentsOfDirectory(at: backupsRoot, includingPropertiesForKeys: nil) else { return [] }
        return dirs.compactMap { dir in
            guard let m = try? readManifest(dir) else { return nil }
            return BackupInfo(url: dir, manifest: m)
        }.sorted { $0.manifest.createdAt > $1.manifest.createdAt }
    }

    private func readManifest(_ backup: URL) throws -> BackupManifest {
        let url = backup.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: url.path) else { throw BackupIntegrityError.missingManifest }
        do { return try Store.decoder.decode(BackupManifest.self, from: Data(contentsOf: url)) } catch {
            throw BackupIntegrityError.unreadableManifest
        }
    }

    /// Eski otomatik yedek silinemedi (yeni yedek alındı; yalnız temizlik başarısız).
    public struct PruneError: LocalizedError {
        public var count: Int
        public var errorDescription: String? { LF("Yedek alındı ama %d eski otomatik yedek silinemedi.", count) }
    }

    /// Günde bir otomatik yedek; son `keep` otomatik yedek tutulur. Eski yedek silinemezse yeni yedek yine alınır, sonra
    /// `PruneError` atılır (sessizce yutulmaz).
    @discardableResult
    public func autoBackupIfNeeded(database: AppDatabase, now: Date = Date(), keep: Int = 14) throws -> URL? {
        let autos = listBackups().filter { $0.manifest.reason == "auto" }
        guard BackupSchedule.shouldBackup(lastBackupAt: autos.first?.manifest.createdAt, now: now) else { return nil }
        let url = try createBackup(database: database, reason: "auto", now: now)
        var failed = 0
        for old in listBackups().filter({ $0.manifest.reason == "auto" }).dropFirst(keep) {
            do { try FileManager.default.removeItem(at: old.url) } catch { failed += 1 }
        }
        if failed > 0 { throw PruneError(count: failed) }
        return url
    }

    /// Yedeğin eksiksiz, değiştirilmemiş ve bu sürümle açılabilir olduğunu doğrular.
    /// Sıra: manifest var ve okunur → veri tabanı bütünlüğü ve göç uyumu → (biçim 2) dosya başına SHA-256, eksik ve fazla dosya.
    /// Biçim 1 (özetsiz, eski) yedekler yalnız veri tabanı denetimiyle kabul edilir.
    public func validate(backup: URL) throws -> BackupManifest {
        let fm = FileManager.default
        let manifest = try readManifest(backup)
        let dbURL = backup.appendingPathComponent("workspace.sqlite")
        guard fm.fileExists(atPath: dbURL.path) else {
            if manifest.hasChecksums { throw BackupIntegrityError.missingFiles(["workspace.sqlite"]) }
            throw MarkaError.incompatibleBackup(L("workspace.sqlite yok"))
        }
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
        if let expected = manifest.files { try verifyChecksums(backup: backup, expected: expected) }
        return manifest
    }

    private func verifyChecksums(backup: URL, expected: [String: String]) throws {
        let fm = FileManager.default
        let present = Set(try relativeFiles(in: backup).filter { $0 != "manifest.json" })
        let missing = expected.keys.filter { !present.contains($0) }.sorted()
        guard missing.isEmpty else { throw BackupIntegrityError.missingFiles(missing) }
        let extra = present.subtracting(expected.keys).sorted()
        guard extra.isEmpty else { throw BackupIntegrityError.unexpectedFiles(extra) }
        var modified: [String] = []
        for (rel, hash) in expected where fm.fileExists(atPath: backup.appendingPathComponent(rel).path) {
            if try Self.sha256(of: backup.appendingPathComponent(rel)) != hash { modified.append(rel) }
        }
        guard modified.isEmpty else { throw BackupIntegrityError.modifiedFiles(modified.sorted()) }
    }

    /// Geri yükleme. Çağıran, çalışan veri tabanını önce kapatmalıdır (`closeCurrent`).
    /// Mevcut veri önce "geri-yukleme-oncesi" yedeğine alınır. Sonra dosya deposu yedekteki kümeyle **aynı** olur:
    /// yedekte olmayan dosyalar kaldırılır (pre-restore yedeğinde durur), yedekteki her dosya yerine konur.
    public func restore(backup: URL, current: AppDatabase, closeCurrent: () throws -> Void) throws {
        let manifest = try validate(backup: backup)
        try createBackup(database: current, reason: "pre-restore")
        let fm = FileManager.default
        // Önce geçici kopyalar: silme sonrası kopyalama başarısız olup boş veri tabanı ya da yarım dosya deposu kalmasın.
        let staged = workspace.appendingPathComponent("workspace.sqlite.restoring")
        if fm.fileExists(atPath: staged.path) { try fm.removeItem(at: staged) }
        try fm.copyItem(at: backup.appendingPathComponent("workspace.sqlite"), to: staged)
        if let expected = manifest.files?["workspace.sqlite"], try Self.sha256(of: staged) != expected {
            try fm.removeItem(at: staged)
            throw BackupIntegrityError.modifiedFiles(["workspace.sqlite"])
        }
        let files = workspace.appendingPathComponent("Files", isDirectory: true)
        let stagedFiles = workspace.appendingPathComponent("Files.restoring", isDirectory: true)
        if fm.fileExists(atPath: stagedFiles.path) { try fm.removeItem(at: stagedFiles) }
        try copyTree(from: backup.appendingPathComponent("Files", isDirectory: true), to: stagedFiles)

        try closeCurrent()
        let dbURL = workspace.appendingPathComponent("workspace.sqlite")
        for suffix in ["", "-wal", "-shm"] {
            let u = URL(fileURLWithPath: dbURL.path + suffix)
            if fm.fileExists(atPath: u.path) { try fm.removeItem(at: u) }
        }
        try fm.moveItem(at: staged, to: dbURL)
        // Dosya deposunu takas et: eskisi kenara, yenisi yerine, eskisi silinir (içeriği pre-restore yedeğinde).
        if fm.fileExists(atPath: files.path) {
            let old = workspace.appendingPathComponent("Files.eski-\(Self.stampFormatter.string(from: Date()))", isDirectory: true)
            try fm.moveItem(at: files, to: old)
            try fm.moveItem(at: stagedFiles, to: files)
            try fm.removeItem(at: old)
        } else {
            try fm.moveItem(at: stagedFiles, to: files)
        }
    }

    // MARK: Dışa aktarma

    /// Marka profili bölümü (dışa aktarımda).
    public struct ProfileEntry: Codable, Sendable, Hashable, FetchableRecord, TableRecord {
        public static let databaseTableName = "brandProfile"
        public var brandId: String
        public var section: String
        public var body: String
        public var updatedAt: Date
    }

    /// Dışa aktarılamayan dosya: kaynak kaydı var, dosya depoda yok.
    public struct MissingFile: Codable, Sendable, Hashable {
        public var sourceId: String
        public var fileName: String
    }

    public struct BrandExport: Codable, Sendable {
        public var exportedAt: Date
        public var appVersion: String
        public var brand: Brand
        public var profile: [ProfileEntry]
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
        public var wikiLinks: [WikiLink]
        public var rules: BrandRules?
        public var reports: [Report]
        public var reportVersions: [ReportVersion]
        public var reportShares: [ReportShare]
        public var financeEntries: [FinanceEntry]
        public var deliveryPlans: [DeliveryPlan]
        public var deliveryRuns: [DeliveryRun]
        public var aiSessions: [AISession]
        public var aiMessages: [AIMessage]
        public var aiProposals: [AIProposal]
        public var usageEntries: [UsageEntry]
        public var auditEvents: [AuditEvent]
        public var assignments: [BrandAssignment]
        /// Kanıt sayılı gözlemler (E-01), kapatılmış geçmiş dahil.
        public var observations: [BrandObservation]
        /// Marka radarı maddeleri (E-21), arşivlenmişler dahil.
        public var radarItems: [RadarItem]
        /// Depoda bulunamadığı için `dosyalar/` altına konamayan kaynak dosyaları. Boş değilse dışa aktarım eksiktir.
        public var missingFiles: [MissingFile]
    }

    /// `brandId` sütunu taşıyan her tablonun dışa aktarımdaki yeri. Şema taraması testi (`brandIdSutunluHerTablo…`) bu
    /// listeyi veri tabanıyla karşılaştırır: yeni bir marka tablosu eklenip buraya yazılmazsa test kırılır.
    public static let exportedBrandTables: Set<String> = [
        "brand", "brandProfile", "contact", "project", "brandRecord", "source", "workTask", "timeEntry", "workLog",
        "wikiPage", "wikiRevision", "wikiClaim", "brandRules", "report", "financeEntry", "deliveryPlan", "aiSession",
        "aiProposal", "usageEntry", "auditEvent", "brandAssignment", "observation", "radarItem",
    ]
    /// Bilerek dışarıda bırakılan marka tabloları ve gerekçesi.
    public static let excludedBrandTables: [String: String] = [
        "suggestionFile": "İşlenmiş öneri dosyalarının iç defteri (özet + ad); aynı dosyanın iki kez işlenmesini önler. "
            + "Önerilerin kendisi aiProposals içinde.",
    ]

    /// Dışa aktarım sonucu.
    public struct ExportResult: Sendable {
        public var folder: URL
        public var missingFiles: [MissingFile]
    }

    /// Bir markanın tüm verisini okunabilir JSON + orijinal dosyalar olarak dışa aktarır. API anahtarı içermez.
    /// Depoda bulunamayan dosya sessizce atlanmaz: `missingFiles` içinde döner ve `veri.json`'a yazılır; kopyalama hatası atılır.
    @discardableResult
    public func exportBrand(_ brandId: String, store: Store, to destination: URL) throws -> ExportResult {
        var export = try store.read { db -> BrandExport in
            guard let brand = try Brand.fetchOne(db, key: brandId) else { throw MarkaError.notFound(brandId) }
            let f = Column("brandId") == brandId
            let logs = try WorkLog.filter(f).fetchAll(db)
            let reports = try Report.filter(f).fetchAll(db)
            let reportIds = reports.map(\.id)
            let pages = try WikiPage.filter(f).fetchAll(db)
            let pageIds = pages.map(\.id)
            let plans = try DeliveryPlan.filter(f).fetchAll(db)
            let sessions = try AISession.filter(f).fetchAll(db)
            return BrandExport(
                exportedAt: Date(), appVersion: MarkaCoreVersion.string, brand: brand,
                profile: try ProfileEntry.filter(f).order(Column("section")).fetchAll(db),
                contacts: try Contact.filter(f).fetchAll(db), projects: try Project.filter(f).fetchAll(db),
                records: try BrandRecord.filter(f).fetchAll(db), sources: try Source.filter(f).fetchAll(db),
                tasks: try WorkTask.filter(f).fetchAll(db), timeEntries: try TimeEntry.filter(f).fetchAll(db),
                workLogs: logs, workLogSources: try WorkLogSource.filter(logs.map(\.id).contains(Column("workLogId"))).fetchAll(db),
                wikiPages: pages, wikiRevisions: try WikiRevision.filter(f).fetchAll(db),
                wikiClaims: try WikiClaim.filter(f).fetchAll(db),
                wikiLinks: try WikiLink.filter(pageIds.contains(Column("fromPageId"))).fetchAll(db),
                rules: try BrandRules.fetchOne(db, key: brandId),
                reports: reports, reportVersions: try ReportVersion.filter(reportIds.contains(Column("reportId"))).fetchAll(db),
                reportShares: try ReportShare.filter(reportIds.contains(Column("reportId"))).fetchAll(db),
                financeEntries: try FinanceEntry.filter(f).fetchAll(db),
                deliveryPlans: plans, deliveryRuns: try DeliveryRun.filter(plans.map(\.id).contains(Column("planId"))).fetchAll(db),
                aiSessions: sessions, aiMessages: try AIMessage.filter(sessions.map(\.id).contains(Column("sessionId"))).fetchAll(db),
                aiProposals: try AIProposal.filter(f).fetchAll(db), usageEntries: try UsageEntry.filter(f).fetchAll(db),
                auditEvents: try AuditEvent.filter(f).fetchAll(db), assignments: try BrandAssignment.filter(f).fetchAll(db),
                observations: try BrandObservation.filter(f).order(Column("createdAt")).fetchAll(db),
                radarItems: try RadarItem.filter(f).order(Column("createdAt")).fetchAll(db),
                missingFiles: [])
        }
        let safeName = export.brand.name.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-")
        let dir = destination.appendingPathComponent("\(safeName) dışa aktarım \(Self.stampFormatter.string(from: Date()))", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: dir.appendingPathComponent("dosyalar"), withIntermediateDirectories: true)
        for s in export.sources {
            guard let path = s.filePath else { continue }
            let src = store.vault.url(for: path)
            let fileName = s.fileName ?? (path as NSString).lastPathComponent
            guard fm.fileExists(atPath: src.path) else {
                export.missingFiles.append(MissingFile(sourceId: s.id, fileName: fileName))
                continue
            }
            try fm.copyItem(at: src, to: dir.appendingPathComponent("dosyalar").appendingPathComponent("\(s.id.prefix(8))-\(fileName)"))
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(export).write(to: dir.appendingPathComponent("veri.json"))
        return ExportResult(folder: dir, missingFiles: export.missingFiles)
    }
}
