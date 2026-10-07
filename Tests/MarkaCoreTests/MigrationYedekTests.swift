import Foundation
import GRDB
import Testing
@testable import MarkaCore

@Suite struct MigrationYedekTests {
    @Test func bekleyenMigrationVarsaOnceYedekAlinirYoksaAlinmaz() throws {
        let dir = try tempDir("mig")
        let first = try AppDatabase.open(at: dir)                       // yeni dosya: yedek yok
        let store = Store(database: first)
        _ = try store.createBrand(name: "Deneme Yangın")
        let backups = dir.appendingPathComponent("Migration-Yedekleri")
        #expect(!FileManager.default.fileExists(atPath: backups.path))
        _ = try AppDatabase.open(at: dir)                               // güncel şema: yedek yok
        #expect(!FileManager.default.fileExists(atPath: backups.path))

        // Eski şemayı taklit et: v7 sonrası migration'lar (v8 yetenekler, v9 ölçek indeksleri, v10 gözlemler, v11 yetenek kökeni,
        // v12 marka radarı) geri alınmış gibi (v11'in sütunları `skill` tablosuyla birlikte gider).
        try store.write { db in
            try db.execute(sql: "DROP TABLE skill")
            for (name, _, _) in AppDatabase.v9Indexes { try db.execute(sql: "DROP INDEX \(name)") }
            try db.execute(sql: "DROP TABLE observation")
            try db.execute(sql: "DROP TABLE radarItem")
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier IN ('v8_yetenekler', 'v9_olcek_indeksleri', 'v10_gozlemler', 'v11_yetenek_kokeni', 'v12_marka_radari')")
        }
        let again = Store(database: try AppDatabase.open(at: dir))
        let files = try FileManager.default.contentsOfDirectory(atPath: backups.path).filter { $0.hasSuffix(".sqlite") }
        #expect(files.count == 1 && files[0].contains("v7_kendi_sirket"))
        // Yedek tutarlı ve eski şemada; asıl veri yeni şemada ve eksiksiz.
        let backup = try DatabaseQueue(path: backups.appendingPathComponent(files[0]).path)
        #expect(try backup.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM brand") } == 1)
        #expect(try backup.read { try String.fetchAll($0, sql: "SELECT name FROM sqlite_master WHERE name = 'skill'") }.isEmpty)
        #expect(try again.brands().count == 1)
        _ = try again.saveSkill(Skill(name: "deneme", description: "çalışıyor"))
    }

    @Test func yedeklerEnYeniBesiyleSinirlidir() throws {
        let dir = try tempDir("mig5")
        _ = try AppDatabase.open(at: dir)
        let backups = dir.appendingPathComponent("Migration-Yedekleri")
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        for i in 1...7 { FileManager.default.createFile(atPath: backups.appendingPathComponent("workspace-2020010\(i)-000000-v1.sqlite").path, contents: Data()) }
        let q = try DatabaseQueue(path: dir.appendingPathComponent("workspace.sqlite").path)
        try q.write { try $0.execute(sql: "DELETE FROM grdb_migrations WHERE identifier IN ('v8_yetenekler', 'v11_yetenek_kokeni')"); try $0.execute(sql: "DROP TABLE skill") }
        _ = try AppDatabase.open(at: dir)
        let files = try FileManager.default.contentsOfDirectory(atPath: backups.path).filter { $0.hasSuffix(".sqlite") }
        #expect(files.count == 5)
    }
}

@Suite struct VeriAlaniKilidiTests {
    @Test func ayniVeriAlaniniIkinciKilitAlamazBirakincaAlir() throws {
        let dir = try tempDir("kilit")
        let first = try #require(WorkspaceLock.acquire(directory: dir))
        #expect(WorkspaceLock.acquire(directory: dir) == nil)                  // aynı alan: reddedilir
        let other = try tempDir("kilit2")
        let second = try #require(WorkspaceLock.acquire(directory: other))     // başka alan: serbest
        first.release()
        let again = try #require(WorkspaceLock.acquire(directory: dir))        // bırakılınca alınır
        second.release(); again.release()
    }
}
