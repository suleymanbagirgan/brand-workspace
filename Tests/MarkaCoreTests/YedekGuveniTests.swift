import Foundation
import GRDB
import Testing
@testable import MarkaCore

/// H1-01 (U-04, U-05, G-03, G-11): yedek, geri yükleme ve dışa aktarım bütünlüğü. Tümü geçici klasörde çalışır.
@Suite struct YedekGuveniTests {
    /// Geçici veri alanı: bir marka, bir dosya kaynağı, bir yedek.
    private func hazirla() throws -> (workspace: URL, db: AppDatabase, store: Store, brand: Brand, service: BackupService, backup: URL) {
        let workspace = try tempDir("yedek-guveni")
        let db = try AppDatabase.open(at: workspace)
        let store = Store(database: db)
        let b = try store.createBrand(name: "Kuzey Lojistik")
        let f = workspace.appendingPathComponent("brif.txt")
        try "ilk brif".write(to: f, atomically: true, encoding: .utf8)
        try store.addFileSource(brandId: b.id, fileURL: f)
        let service = BackupService(workspace: workspace)
        let backup = try service.createBackup(database: db, reason: "manual")
        return (workspace, db, store, b, service, backup)
    }

    private func yedektekiDosyalar(_ backup: URL) throws -> [String] {
        let files = backup.appendingPathComponent("Files")
        let e = try #require(FileManager.default.enumerator(atPath: files.path))
        return (e.allObjects as? [String] ?? []).filter { rel in
            var d: ObjCBool = false
            return FileManager.default.fileExists(atPath: files.appendingPathComponent(rel).path, isDirectory: &d) && !d.boolValue
        }.sorted()
    }

    @Test func manifestDosyaBasinaSha256Tasir() throws {
        let h = try hazirla()
        let manifest = try h.service.validate(backup: h.backup)
        #expect(manifest.format == 2)
        let files = try #require(manifest.files)
        #expect(files["workspace.sqlite"]?.count == 64)
        let dosyalar = try yedektekiDosyalar(h.backup)
        #expect(dosyalar.count == 1)
        for rel in dosyalar { #expect(files["Files/\(rel)"]?.count == 64) }
        #expect(files.count == dosyalar.count + 1, "\(files.keys.sorted())")
    }

    @Test func degistirilmisDosyaliYedekReddedilir() throws {
        let h = try hazirla()
        let rel = try #require(try yedektekiDosyalar(h.backup).first)
        let url = h.backup.appendingPathComponent("Files").appendingPathComponent(rel)
        // Atomik yazma yeni dosya oluşturur: sabit bağlantıyla paylaşılan çalışma alanı dosyası değişmez.
        try "kurcalanmış içerik".write(to: url, atomically: true, encoding: .utf8)
        #expect(throws: BackupIntegrityError.modifiedFiles(["Files/\(rel)"])) { try h.service.validate(backup: h.backup) }
        // Geri yükleme de reddeder ve çalışan veriye dokunmaz.
        var closed = false
        #expect(throws: BackupIntegrityError.self) {
            try h.service.restore(backup: h.backup, current: h.db) { closed = true }
        }
        #expect(!closed)
        #expect(try h.store.brands().count == 1)
    }

    @Test func eksikDosyaliYedekReddedilir() throws {
        let h = try hazirla()
        let rel = try #require(try yedektekiDosyalar(h.backup).first)
        try FileManager.default.removeItem(at: h.backup.appendingPathComponent("Files").appendingPathComponent(rel))
        #expect(throws: BackupIntegrityError.missingFiles(["Files/\(rel)"])) { try h.service.validate(backup: h.backup) }
        // Manifestte olmayan fazladan dosya da reddedilir.
        let h2 = try hazirla()
        try "sonradan".write(to: h2.backup.appendingPathComponent("Files/ek.txt"), atomically: true, encoding: .utf8)
        #expect(throws: BackupIntegrityError.unexpectedFiles(["Files/ek.txt"])) { try h2.service.validate(backup: h2.backup) }
    }

    @Test func manifestsizYedekReddedilir() throws {
        let h = try hazirla()
        try FileManager.default.removeItem(at: h.backup.appendingPathComponent("manifest.json"))
        #expect(throws: BackupIntegrityError.missingManifest) { try h.service.validate(backup: h.backup) }
        #expect(!h.service.listBackups().contains { $0.url.lastPathComponent == h.backup.lastPathComponent })
        // Okunamayan manifest de reddedilir.
        try Data("{bozuk".utf8).write(to: h.backup.appendingPathComponent("manifest.json"))
        #expect(throws: BackupIntegrityError.unreadableManifest) { try h.service.validate(backup: h.backup) }
    }

    /// Eski (biçim 1, özetsiz) yedekler kabul edilir: uyum korunur, yalnız veri tabanı bütünlüğü denetlenir.
    @Test func eskiBicimOzetsizYedekKabulEdilirVeGeriYuklenir() throws {
        var h = try hazirla()
        let mURL = h.backup.appendingPathComponent("manifest.json")
        var m = try Store.decoder.decode(BackupManifest.self, from: Data(contentsOf: mURL))
        m.format = 1
        m.files = nil
        // Eski biçim `files` anahtarını hiç taşımıyordu.
        var json = try #require(try JSONSerialization.jsonObject(with: Store.encoder.encode(m)) as? [String: Any])
        json.removeValue(forKey: "files")
        try JSONSerialization.data(withJSONObject: json).write(to: mURL)
        let okunan = try h.service.validate(backup: h.backup)
        #expect(okunan.format == 1 && !okunan.hasChecksums)
        try h.store.createBrand(name: "Sonradan Eklenen")
        try h.service.restore(backup: h.backup, current: h.db) { try (h.db.writer as? DatabasePool)?.close() }
        h.db = try AppDatabase.open(at: h.workspace)
        #expect(try Store(database: h.db).brands().map(\.name) == ["Kuzey Lojistik"])
    }

    @Test func geriYuklemeSonrasiDosyaKumesiYedekleAyni() throws {
        var h = try hazirla()
        let yedekteki = try yedektekiDosyalar(h.backup)
        // Yedekten sonra yeni dosya eklenir ve var olan dosya depodan kaybolur.
        let f2 = h.workspace.appendingPathComponent("sonra.txt")
        try "sonradan gelen".write(to: f2, atomically: true, encoding: .utf8)
        try h.store.addFileSource(brandId: h.brand.id, fileURL: f2)
        let ilk = try #require(yedekteki.first)
        try FileManager.default.removeItem(at: h.db.filesRoot.appendingPathComponent(ilk))

        try h.service.restore(backup: h.backup, current: h.db) { try (h.db.writer as? DatabasePool)?.close() }
        h.db = try AppDatabase.open(at: h.workspace)
        let filesRoot = h.db.filesRoot
        let e = try #require(FileManager.default.enumerator(atPath: filesRoot.path))
        let sonra = (e.allObjects as? [String] ?? []).filter { rel in
            var d: ObjCBool = false
            return FileManager.default.fileExists(atPath: filesRoot.appendingPathComponent(rel).path, isDirectory: &d) && !d.boolValue
        }.sorted()
        #expect(sonra == yedekteki)
        // İçerik de aynı.
        let manifest = try h.service.validate(backup: h.backup)
        for rel in sonra {
            #expect(try BackupService.sha256(of: filesRoot.appendingPathComponent(rel)) == manifest.files?["Files/\(rel)"])
        }
        // Geri yükleme öncesi durum ayrı yedekte durur ve o da doğrulanır.
        let pre = try #require(h.service.listBackups().first { $0.manifest.reason == "pre-restore" })
        #expect(try h.service.validate(backup: pre.url).files?.count == 2)   // veri tabanı + sonradan eklenen dosya
    }

    @Test func yedekBaskaYereAlinabilirVeDogrulanir() throws {
        let h = try hazirla()
        let harici = try tempDir("harici-disk")
        let out = try h.service.createBackup(database: h.db, reason: "manual", destination: harici)
        #expect(out.deletingLastPathComponent().standardizedFileURL == harici.standardizedFileURL)
        #expect(try h.service.validate(backup: out).brandCount == 1)
        // Varsayılan yedek klasörüne bir şey eklenmedi.
        #expect(h.service.listBackups().count == 1)
    }

    @Test func disaAktarimEksikDosyayiRaporlar() throws {
        let h = try hazirla()
        let s = try #require(try h.store.sources(brandId: h.brand.id).first)
        try FileManager.default.removeItem(at: try #require(h.store.fileURL(for: s)))
        let result = try h.service.exportBrand(h.brand.id, store: h.store, to: try tempDir("disa"))
        #expect(result.missingFiles.map(\.sourceId) == [s.id])
        let json = try String(contentsOf: result.folder.appendingPathComponent("veri.json"), encoding: .utf8)
        #expect(json.contains("\"missingFiles\""))
        #expect(json.contains(s.id))
    }

    @Test func disaAktarimFinansVeMarkaProfiliniIcerir() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Örnek Kafe Zinciri")
        let diger = try store.createBrand(name: "Deneme Yangın")
        try store.saveFinanceEntry(FinanceEntry(brandId: b.id, kind: .payment, title: "Ekim taksiti", amountMinor: 4_500_000, date: "2026-10-15"))
        try store.saveFinanceEntry(FinanceEntry(brandId: diger.id, kind: .budget, title: "Başka markanın bütçesi"))
        try store.setProfileSection(brandId: b.id, .audience, body: "Şehir içi kahve severler")
        let result = try BackupService(workspace: try tempDir()).exportBrand(b.id, store: store, to: try tempDir("disa"))
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let export = try dec.decode(BackupService.BrandExport.self, from: Data(contentsOf: result.folder.appendingPathComponent("veri.json")))
        #expect(export.financeEntries.map(\.title) == ["Ekim taksiti"])          // marka yalıtımı: diğer markanınki yok
        #expect(export.financeEntries.first?.amountMinor == 4_500_000)
        #expect(export.profile.map(\.section) == ["audience"])
        #expect(export.profile.first?.body == "Şehir içi kahve severler")
        #expect(export.auditEvents.allSatisfy { $0.brandId == b.id })
        #expect(!export.auditEvents.isEmpty)
    }

    /// Şema taraması: `brandId` sütunu taşıyan her tablo ya dışa aktarılır ya da gerekçeyle dışarıda bırakılır.
    /// Yeni bir marka tablosu eklenip `BackupService` listelerine yazılmazsa bu test kırılır.
    @Test func brandIdSutunluHerTabloDisaAktarimdaYaDaGerekceliDislamada() throws {
        let store = try makeStore()
        let tables = try store.read { db -> [String] in
            let names = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'")
            return try names.filter { name in
                try db.columns(in: name).contains { $0.name == "brandId" } || name == "brand"
            }.sorted()
        }
        #expect(tables.count >= 20)
        let covered = BackupService.exportedBrandTables.union(BackupService.excludedBrandTables.keys)
        let eksik = tables.filter { !covered.contains($0) }
        #expect(eksik == [], "Dışa aktarım kapsamında olmayan marka tablosu: \(eksik)")
        // Liste eskimesin: yazılan her tablo şemada var; dışlama gerekçesi boş değil; iki listede birden olan yok.
        #expect(covered.subtracting(tables).isEmpty)
        #expect(BackupService.excludedBrandTables.values.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        #expect(BackupService.exportedBrandTables.isDisjoint(with: BackupService.excludedBrandTables.keys))
        // BrandExport gerçekten bu tabloları taşıyor: JSON anahtarları tablo başına bir alan.
        let alanlar: [String: String] = [
            "brand": "brand", "brandProfile": "profile", "contact": "contacts", "project": "projects", "brandRecord": "records",
            "source": "sources", "workTask": "tasks", "timeEntry": "timeEntries", "workLog": "workLogs", "wikiPage": "wikiPages",
            "wikiRevision": "wikiRevisions", "wikiClaim": "wikiClaims", "brandRules": "rules", "report": "reports",
            "financeEntry": "financeEntries", "deliveryPlan": "deliveryPlans", "aiSession": "aiSessions",
            "aiProposal": "aiProposals", "usageEntry": "usageEntries", "auditEvent": "auditEvents", "brandAssignment": "assignments",
            "observation": "observations", "radarItem": "radarItems",
        ]
        #expect(Set(alanlar.keys) == BackupService.exportedBrandTables)
        let b = try store.createBrand(name: "Deneme Yangın")
        let result = try BackupService(workspace: try tempDir()).exportBrand(b.id, store: store, to: try tempDir("disa"))
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: result.folder.appendingPathComponent("veri.json"))) as? [String: Any])
        for (tablo, alan) in alanlar { #expect(json[alan] != nil, "\(tablo) → \(alan) dışa aktarımda yok") }
    }
}
