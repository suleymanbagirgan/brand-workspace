import Foundation
import GRDB

/// Uygulamanın tek doğruluk kaynağı: SQLite (WAL) + içerik adresli dosya deposu.
public final class AppDatabase: Sendable {
    public let writer: any DatabaseWriter
    /// Kaynak dosyalarının saklandığı kök (`Files/`). Bellek içi test veri tabanında geçici dizin.
    public let filesRoot: URL

    public init(writer: any DatabaseWriter, filesRoot: URL) throws {
        self.writer = writer
        self.filesRoot = filesRoot
        try FileManager.default.createDirectory(at: filesRoot, withIntermediateDirectories: true)
        try Self.migrator.migrate(writer)
    }

    /// Diskteki çalışma alanını açar.
    public static func open(at directory: URL) throws -> AppDatabase {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var config = Configuration()
        config.foreignKeysEnabled = true
        config.busyMode = .timeout(5)
        let pool = try DatabasePool(path: directory.appendingPathComponent("workspace.sqlite").path, configuration: config)
        return try AppDatabase(writer: pool, filesRoot: directory.appendingPathComponent("Files", isDirectory: true))
    }

    /// Testler için bellek içi veri tabanı.
    public static func inMemory() throws -> AppDatabase {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let queue = try DatabaseQueue(configuration: config)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("marka-test-\(UUID().uuidString)")
        return try AppDatabase(writer: queue, filesRoot: dir)
    }

    public static var migrationIdentifiers: [String] { migrator.migrations }

    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        #if DEBUG
        m.eraseDatabaseOnSchemaChange = false
        #endif

        m.registerMigration("v1_cekirdek") { db in
            try db.create(table: "brand") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("summary", .text).notNull().defaults(to: "")
                t.column("sector", .text).notNull().defaults(to: "")
                t.column("logoPath", .text)
                t.column("status", .text).notNull().defaults(to: "active")
                t.column("aiProviders", .text).notNull().defaults(to: "")
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(table: "contact") { t in
                t.primaryKey("id", .text)
                t.belongsTo("brand", onDelete: .cascade).notNull()
                t.column("name", .text).notNull()
                t.column("role", .text).notNull().defaults(to: "")
                t.column("email", .text).notNull().defaults(to: "")
                t.column("phone", .text).notNull().defaults(to: "")
                t.column("notes", .text).notNull().defaults(to: "")
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "project") { t in
                t.primaryKey("id", .text)
                t.belongsTo("brand", onDelete: .cascade).notNull()
                t.column("name", .text).notNull()
                t.column("goal", .text).notNull().defaults(to: "")
                t.column("status", .text).notNull()
                t.column("dueDate", .text)
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "source") { t in
                t.primaryKey("id", .text)
                t.belongsTo("brand", onDelete: .cascade).notNull()
                t.column("kind", .text).notNull()
                t.column("title", .text).notNull()
                t.column("body", .text).notNull().defaults(to: "")
                t.column("fileName", .text)
                t.column("filePath", .text)
                t.column("mimeType", .text)
                t.column("sha256", .text).notNull()
                t.column("byteSize", .integer).notNull().defaults(to: 0)
                t.column("url", .text)
                t.column("capturedAt", .datetime).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("actor", .text).notNull()
                t.column("archivedAt", .datetime)
            }
            try db.create(index: "source_brand_captured", on: "source", columns: ["brandId", "capturedAt"])
            // Ham kaynaklar değişmez: yalnızca arşiv damgası değişebilir.
            try db.execute(sql: """
                CREATE TRIGGER source_immutable BEFORE UPDATE ON source
                WHEN OLD.brandId IS NOT NEW.brandId OR OLD.kind IS NOT NEW.kind OR OLD.title IS NOT NEW.title
                  OR OLD.body IS NOT NEW.body OR OLD.fileName IS NOT NEW.fileName OR OLD.filePath IS NOT NEW.filePath
                  OR OLD.sha256 IS NOT NEW.sha256 OR OLD.byteSize IS NOT NEW.byteSize OR OLD.url IS NOT NEW.url
                  OR OLD.capturedAt IS NOT NEW.capturedAt OR OLD.actor IS NOT NEW.actor OR OLD.mimeType IS NOT NEW.mimeType
                BEGIN SELECT RAISE(ABORT, 'kaynak_degistirilemez'); END;
                """)
            try db.create(table: "brandRecord") { t in
                t.primaryKey("id", .text)
                t.belongsTo("brand", onDelete: .cascade).notNull()
                t.column("kind", .text).notNull()
                t.column("title", .text).notNull()
                t.column("detail", .text).notNull().defaults(to: "")
                t.column("status", .text).notNull()
                t.column("dueDate", .text)
                t.belongsTo("source", onDelete: .setNull)
                t.belongsTo("project", onDelete: .setNull)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("closedAt", .datetime)
            }
            try db.create(table: "workTask") { t in
                t.primaryKey("id", .text)
                t.belongsTo("brand", onDelete: .cascade).notNull()
                t.belongsTo("project", onDelete: .setNull)
                t.column("title", .text).notNull()
                t.column("notes", .text).notNull().defaults(to: "")
                t.column("assignee", .text).notNull().defaults(to: "")
                t.column("priority", .integer).notNull().defaults(to: 0)
                t.column("dueDate", .text)
                t.column("status", .text).notNull()
                t.column("timeSpentSeconds", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("completedAt", .datetime)
                t.column("actor", .text).notNull()
                t.column("legacyKey", .text).unique()
                t.column("legacyCode", .text)
            }
            try db.create(index: "task_brand_status", on: "workTask", columns: ["brandId", "status", "dueDate"])
            try db.create(table: "timeEntry") { t in
                t.primaryKey("id", .text)
                t.belongsTo("task", inTable: "workTask", onDelete: .cascade).notNull()
                t.belongsTo("brand", onDelete: .cascade).notNull()
                t.column("startedAt", .datetime).notNull()
                t.column("endedAt", .datetime)
                t.column("seconds", .integer).notNull().defaults(to: 0)
                t.column("note", .text).notNull().defaults(to: "")
                t.column("actor", .text).notNull()
                t.column("legacyKey", .text).unique()
            }
            // Aynı anda yalnızca bir çalışan sayaç.
            try db.execute(sql: "CREATE UNIQUE INDEX timeEntry_single_running ON timeEntry((1)) WHERE endedAt IS NULL")
            try db.create(table: "workLog") { t in
                t.primaryKey("id", .text)
                t.belongsTo("brand", onDelete: .cascade).notNull()
                t.belongsTo("task", inTable: "workTask", onDelete: .setNull)
                t.column("title", .text).notNull()
                t.column("requested", .text).notNull().defaults(to: "")
                t.column("performed", .text).notNull().defaults(to: "")
                t.column("decision", .text).notNull().defaults(to: "")
                t.column("approvedBy", .text).notNull().defaults(to: "")
                t.column("clientNotified", .text).notNull().defaults(to: "")
                t.column("status", .text).notNull()
                t.column("verifiedAt", .datetime)
                t.column("verifiedBy", .text)
                t.column("occurredAt", .datetime).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("actor", .text).notNull()
                t.column("sessionId", .text)
            }
            try db.create(table: "workLogSource") { t in
                t.belongsTo("workLog", onDelete: .cascade).notNull()
                t.belongsTo("source", onDelete: .restrict).notNull()
                t.column("role", .text).notNull()
                t.primaryKey(["workLogId", "sourceId", "role"])
            }
            try db.create(table: "wikiPage") { t in
                t.primaryKey("id", .text)
                t.belongsTo("brand", onDelete: .cascade).notNull()
                t.column("kind", .text).notNull()
                t.column("title", .text).notNull()
                t.column("slug", .text).notNull()
                t.column("currentRevisionId", .text)
                t.column("status", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.uniqueKey(["brandId", "slug"])
            }
            try db.create(table: "wikiRevision") { t in
                t.primaryKey("id", .text)
                t.belongsTo("page", inTable: "wikiPage", onDelete: .cascade).notNull()
                t.belongsTo("brand", onDelete: .cascade).notNull()
                t.column("number", .integer).notNull()
                t.column("body", .text).notNull()
                t.column("note", .text).notNull().defaults(to: "")
                t.column("state", .text).notNull()
                t.column("actor", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("decidedAt", .datetime)
                t.column("basedOnRevisionId", .text)
                t.uniqueKey(["pageId", "number"])
            }
            try db.create(table: "wikiClaim") { t in
                t.primaryKey("id", .text)
                t.belongsTo("revision", inTable: "wikiRevision", onDelete: .cascade).notNull()
                t.belongsTo("brand", onDelete: .cascade).notNull()
                t.column("text", .text).notNull()
                t.belongsTo("source", onDelete: .restrict)
                t.column("sourceDate", .datetime)
                t.column("status", .text).notNull()
                t.column("flagNote", .text).notNull().defaults(to: "")
            }
            try db.create(table: "wikiLink") { t in
                t.belongsTo("fromPage", inTable: "wikiPage", onDelete: .cascade).notNull()
                t.belongsTo("toPage", inTable: "wikiPage", onDelete: .cascade).notNull()
                t.primaryKey(["fromPageId", "toPageId"])
            }
            try db.create(table: "brandRules") { t in
                t.primaryKey("brandId", .text).references("brand", onDelete: .cascade)
                t.column("body", .text).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(table: "report") { t in
                t.primaryKey("id", .text)
                t.belongsTo("brand", onDelete: .cascade).notNull()
                t.column("period", .text).notNull()
                t.column("periodStart", .datetime).notNull()
                t.column("periodEnd", .datetime).notNull()
                t.column("status", .text).notNull()
                t.column("currentVersionId", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(table: "reportVersion") { t in
                t.primaryKey("id", .text)
                t.belongsTo("report", onDelete: .cascade).notNull()
                t.column("number", .integer).notNull()
                t.column("contentJSON", .text).notNull()
                t.column("note", .text).notNull().defaults(to: "")
                t.column("actor", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("approvedAt", .datetime)
                t.uniqueKey(["reportId", "number"])
            }
            try db.create(table: "reportShare") { t in
                t.primaryKey("id", .text)
                t.belongsTo("report", onDelete: .cascade).notNull()
                t.belongsTo("version", inTable: "reportVersion", onDelete: .cascade).notNull()
                t.column("channel", .text).notNull()
                t.column("recipient", .text).notNull().defaults(to: "")
                t.column("filePath", .text).notNull().defaults(to: "")
                t.column("note", .text).notNull().defaults(to: "")
                t.column("sharedAt", .datetime).notNull()
            }
            try db.create(table: "deliveryPlan") { t in
                t.primaryKey("id", .text)
                t.belongsTo("brand", onDelete: .cascade).notNull()
                t.column("recipients", .text).notNull()
                t.column("period", .text).notNull()
                t.column("dayOfPeriod", .integer).notNull()
                t.column("enabled", .boolean).notNull()
                t.column("lastRunAt", .datetime)
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "deliveryRun") { t in
                t.primaryKey("id", .text)
                t.belongsTo("plan", inTable: "deliveryPlan", onDelete: .cascade).notNull()
                t.column("at", .datetime).notNull()
                t.column("outcome", .text).notNull()
                t.column("reportId", .text)
                t.column("note", .text).notNull().defaults(to: "")
            }
            try db.create(table: "aiSession") { t in
                t.primaryKey("id", .text)
                t.belongsTo("brand", onDelete: .cascade)
                t.column("scope", .text).notNull()
                t.column("provider", .text).notNull()
                t.column("model", .text).notNull()
                t.column("title", .text).notNull()
                t.column("providerThreadId", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                // Marka kapsamında marka zorunlu; tüm markalar kapsamında boş.
                t.check(sql: "(scope = 'brand' AND brandId IS NOT NULL) OR (scope = 'allBrands' AND brandId IS NULL)")
            }
            try db.execute(sql: """
                CREATE TRIGGER aiSession_scope_fixed BEFORE UPDATE ON aiSession
                WHEN OLD.brandId IS NOT NEW.brandId OR OLD.scope IS NOT NEW.scope OR OLD.provider IS NOT NEW.provider
                BEGIN SELECT RAISE(ABORT, 'oturum_kapsami_degistirilemez'); END;
                """)
            try db.create(table: "aiMessage") { t in
                t.primaryKey("id", .text)
                t.belongsTo("session", inTable: "aiSession", onDelete: .cascade).notNull()
                t.column("role", .text).notNull()
                t.column("text", .text).notNull()
                t.column("eventsJSON", .text).notNull().defaults(to: "[]")
                t.column("rawJSON", .text).notNull().defaults(to: "")
                t.column("state", .text).notNull()
                t.column("inputTokens", .integer).notNull().defaults(to: 0)
                t.column("outputTokens", .integer).notNull().defaults(to: 0)
                t.column("costMicros", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "aiProposal") { t in
                t.primaryKey("id", .text)
                t.belongsTo("session", inTable: "aiSession", onDelete: .setNull)
                t.belongsTo("brand", onDelete: .cascade).notNull()
                t.column("kind", .text).notNull()
                t.column("summary", .text).notNull()
                t.column("payloadJSON", .text).notNull()
                t.column("status", .text).notNull()
                t.column("resultEntityId", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("decidedAt", .datetime)
            }
            try db.create(table: "auditEvent") { t in
                t.primaryKey("id", .text)
                t.column("at", .datetime).notNull()
                t.column("actor", .text).notNull()
                t.column("brandId", .text)
                t.column("entity", .text).notNull()
                t.column("entityId", .text).notNull()
                t.column("action", .text).notNull()
                t.column("beforeJSON", .text)
                t.column("afterJSON", .text)
            }
            try db.create(index: "audit_entity", on: "auditEvent", columns: ["entity", "entityId"])
            try db.create(table: "usageEntry") { t in
                t.primaryKey("id", .text)
                t.column("at", .datetime).notNull()
                t.column("provider", .text).notNull()
                t.column("model", .text).notNull()
                t.column("sessionId", .text)
                t.column("brandId", .text)
                t.column("purpose", .text).notNull()
                t.column("inputTokens", .integer).notNull()
                t.column("outputTokens", .integer).notNull()
                t.column("cacheReadTokens", .integer).notNull()
                t.column("cacheWriteTokens", .integer).notNull()
                t.column("costMicros", .integer)
            }
            try db.create(table: "importRun") { t in
                t.primaryKey("id", .text)
                t.column("at", .datetime).notNull()
                t.column("kind", .text).notNull()
                t.column("sourcePath", .text).notNull()
                t.column("summaryJSON", .text).notNull()
                t.column("snapshotPath", .text).notNull()
            }
            try db.create(table: "setting") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }
        }

        m.registerMigration("v1_arama") { db in
            // Arama dizini normalleştirilmiş metni saklar (Türkçe "ı" → "i", aksanlar ve büyük/küçük harf yok sayılır).
            // Gösterilen özetler özgün metinden üretilir.
            try db.execute(sql: """
                CREATE VIRTUAL TABLE sourceFts USING fts5(title, body, tokenize="unicode61 remove_diacritics 2");
                CREATE TRIGGER sourceFts_ai AFTER INSERT ON source BEGIN
                    INSERT INTO sourceFts(rowid, title, body)
                    VALUES (new.rowid, replace(replace(new.title, 'ı', 'i'), 'İ', 'i'), replace(replace(new.body, 'ı', 'i'), 'İ', 'i'));
                END;
                CREATE TRIGGER sourceFts_ad AFTER DELETE ON source BEGIN
                    DELETE FROM sourceFts WHERE rowid = old.rowid;
                END;
                CREATE VIRTUAL TABLE wikiFts USING fts5(body, tokenize="unicode61 remove_diacritics 2");
                CREATE TRIGGER wikiFts_ai AFTER INSERT ON wikiRevision BEGIN
                    INSERT INTO wikiFts(rowid, body) VALUES (new.rowid, replace(replace(new.body, 'ı', 'i'), 'İ', 'i'));
                END;
                CREATE TRIGGER wikiFts_ad AFTER DELETE ON wikiRevision BEGIN
                    DELETE FROM wikiFts WHERE rowid = old.rowid;
                END;
                CREATE TRIGGER wikiFts_au AFTER UPDATE OF body ON wikiRevision BEGIN
                    DELETE FROM wikiFts WHERE rowid = old.rowid;
                    INSERT INTO wikiFts(rowid, body) VALUES (new.rowid, replace(replace(new.body, 'ı', 'i'), 'İ', 'i'));
                END;
                """)
        }

        m.registerMigration("v2_terminal_onerileri") { db in
            // Terminal/CLI öneri köprüsü (İ7): öneri kaynağı ve işlenmiş öneri dosyaları.
            // `origin` NULL = sohbet (Claude/Codex aracı); "terminal" = marka klasöründeki `oneriler/*.json`.
            try db.alter(table: "aiProposal") { t in
                t.add(column: "origin", .text)
                t.add(column: "originRef", .text)
            }
            try db.create(table: "suggestionFile") { t in
                t.primaryKey("id", .text)
                t.belongsTo("brand", onDelete: .cascade).notNull()
                t.column("sha256", .text).notNull()
                t.column("fileName", .text).notNull()
                t.column("itemCount", .integer).notNull()
                t.column("processedAt", .datetime).notNull()
                t.uniqueKey(["brandId", "sha256"])
            }
        }
        return m
    }
}
