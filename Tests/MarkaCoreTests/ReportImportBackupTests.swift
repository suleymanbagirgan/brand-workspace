import Foundation
import GRDB
import Testing
@testable import MarkaCore

@Suite struct RaporTests {
    func fixture() throws -> (Store, Brand, DateInterval, Date) {
        let store = try makeStore()
        let b = try store.createBrand(name: "Örnek Yangın")
        let builder = ReportBuilder(store: store)
        let now = DayString.date("2026-09-17")!.addingTimeInterval(12 * 3600)
        return (store, b, builder.period(.weekly, containing: now), now)
    }

    @Test func yalnizcaDogrulanmisKayitRaporaGirer() throws {
        let (store, b, week, now) = try fixture()
        let src = try store.addTextSource(brandId: b.id, kind: .clientRequest, title: "Teklif talebi", body: "x", capturedAt: now)
        let out = try store.addGeneratedOutput(brandId: b.id, fileName: "teklif.md", content: "# Teklif", title: "Teklif v1", actor: .user)
        var t1 = try store.saveTask(WorkTask(brandId: b.id, title: "Teklif hazırla"))
        var t2 = try store.saveTask(WorkTask(brandId: b.id, title: "Kaydı olmayan iş"))
        try store.addManualTime(taskId: t1.id, seconds: 5400, endingAt: now)
        t1.status = .done; t1 = try store.saveTask(t1)
        t2.status = .done; t2 = try store.saveTask(t2)
        let log = try store.saveWorkLog(WorkLog(brandId: b.id, taskId: t1.id, title: "Teklif hazırlandı", requested: "Fiyat teklifi",
                                                performed: "42 kalem fiyatlandırıldı", decision: "KDV hariç", occurredAt: now),
                                        inputSourceIds: [src.id], outputSourceIds: [out.id])
        // Doğrulanmadan önce: yapılan işler boş, iki uyarı.
        var c = try ReportBuilder(store: store).build(brandId: b.id, period: week, now: now)
        #expect(c.section(.completedWork)?.items.isEmpty == true)
        #expect(c.warnings.count == 2)

        try store.verifyWorkLog(log.id, verifiedBy: "Danışman")
        c = try ReportBuilder(store: store).build(brandId: b.id, period: week, now: now)
        let item = try #require(c.section(.completedWork)?.items.first)
        #expect(item.refs.contains(RecordRef(.workLog, log.id)))
        #expect(item.refs.contains(RecordRef(.source, src.id)))
        #expect(c.section(.deliverables)?.items.first?.refs.first == RecordRef(.source, out.id))
        #expect(c.warnings.count == 1)
        #expect(c.warnings[0].refs == [RecordRef(.task, t2.id)])
        #expect(c.totalSeconds == 5400)
        // Her madde en az bir kayda bağlı.
        #expect(c.sections.flatMap(\.items).allSatisfy { !$0.refs.isEmpty })
    }

    @Test func aiOzetiGecersizReferansiAtar() throws {
        let (store, b, week, now) = try fixture()
        let src = try store.addTextSource(brandId: b.id, kind: .note, title: "n", body: "x")
        let log = try store.saveWorkLog(WorkLog(brandId: b.id, title: "İş", performed: "yapıldı", occurredAt: now), inputSourceIds: [src.id], outputSourceIds: [])
        try store.verifyWorkLog(log.id, verifiedBy: "S")
        let c = try ReportBuilder(store: store).build(brandId: b.id, period: week, now: now)
        let valid = try #require(c.section(.completedWork)?.items.first?.id)
        let (kept, dropped) = ReportBuilder.validatedSummary([
            ReportSummarySentence(text: "Bu hafta iş tamamlandı.", itemIds: [valid]),
            ReportSummarySentence(text: "Müşteri çok memnun kaldı.", itemIds: []),
            ReportSummarySentence(text: "Uydurma.", itemIds: ["yok"]),
        ], content: c)
        #expect(kept.count == 1)
        #expect(dropped.count == 2)
    }

    @Test func surumOnayPaylasimVeKaynaksizMaddeEngeli() throws {
        let (store, b, week, now) = try fixture()
        let src = try store.addTextSource(brandId: b.id, kind: .note, title: "n", body: "x")
        let log = try store.saveWorkLog(WorkLog(brandId: b.id, title: "İş", performed: "yapıldı", occurredAt: now), inputSourceIds: [src.id], outputSourceIds: [])
        try store.verifyWorkLog(log.id, verifiedBy: "S")
        var c = try ReportBuilder(store: store).build(brandId: b.id, period: week, now: now)
        let (report, v1) = try store.createReportDraft(brandId: b.id, period: .weekly, interval: week, content: c)
        c.sections[0].items[0].text = "Düzenlenmiş metin"
        c.sections[0].items[0].edited = true
        let v2 = try store.saveReportVersion(reportId: report.id, content: c, note: "düzenleme")
        #expect(v2.number == v1.number + 1)
        #expect(throws: MarkaError.self) { try store.approveReport(reportId: report.id, versionId: v1.id) }
        try store.approveReport(reportId: report.id, versionId: v2.id)
        var bad = c
        bad.sections[0].items.append(ReportItem(text: "Kaynaksız", refs: []))
        #expect(throws: MarkaError.self) { try store.saveReportVersion(reportId: report.id, content: bad, note: "") }

        let pdf = ReportPDFRenderer(content: c, isDraft: false, versionNumber: 2, describe: { try? store.describe($0) }).render()
        #expect(pdf.count > 1000)
        #expect(String(data: pdf.prefix(4), encoding: .ascii) == "%PDF")
        try store.recordShare(reportId: report.id, versionId: v2.id, channel: .pdfExport, filePath: "/tmp/x.pdf")
        #expect(try store.reportShares(reportId: report.id).count == 1)
    }

    @Test func geriCekilenKayitlaRaporOnaylanamaz() throws {
        let (store, b, week, now) = try fixture()
        let src = try store.addTextSource(brandId: b.id, kind: .note, title: "n", body: "x")
        let log = try store.saveWorkLog(WorkLog(brandId: b.id, title: "İş", performed: "yapıldı", occurredAt: now), inputSourceIds: [src.id], outputSourceIds: [])
        try store.verifyWorkLog(log.id, verifiedBy: "S")
        let c = try ReportBuilder(store: store).build(brandId: b.id, period: week, now: now)
        let (report, v1) = try store.createReportDraft(brandId: b.id, period: .weekly, interval: week, content: c)
        try store.retractWorkLog(log.id)
        #expect(throws: MarkaError.self) { try store.approveReport(reportId: report.id, versionId: v1.id) }
    }

    @Test func baskaMarkaninReferansiRaporaKonamaz() throws {
        let (store, b, week, now) = try fixture()
        let other = try store.createBrand(name: "Diğer")
        let foreign = try store.addTextSource(brandId: other.id, kind: .note, title: "gizli", body: "x")
        let c = try ReportBuilder(store: store).build(brandId: b.id, period: week, now: now)
        let (report, _) = try store.createReportDraft(brandId: b.id, period: .weekly, interval: week, content: c)
        var bad = c
        bad.sections[2].items.append(ReportItem(text: "Sızıntı", refs: [RecordRef(.source, foreign.id)]))
        #expect(throws: MarkaError.brandScope) { try store.saveReportVersion(reportId: report.id, content: bad, note: "") }
    }

    @Test func planliGonderimYalnizcaTaslakUretirGondermez() throws {
        let (store, b, _, _) = try fixture()
        let monday = DayString.date("2026-09-21")!.addingTimeInterval(9 * 3600)
        let src = try store.addTextSource(brandId: b.id, kind: .note, title: "n", body: "x")
        let log = try store.saveWorkLog(WorkLog(brandId: b.id, title: "Geçen hafta işi", performed: "yapıldı",
                                                occurredAt: monday.addingTimeInterval(-3 * 86400)), inputSourceIds: [src.id], outputSourceIds: [])
        try store.verifyWorkLog(log.id, verifiedBy: "S")
        #expect(throws: MarkaError.self) {
            try store.saveDeliveryPlan(DeliveryPlan(brandId: b.id, recipients: "gecersiz", period: .weekly, dayOfPeriod: 1))
        }
        let plan = DeliveryPlan(brandId: b.id, recipients: "musteri@example.com", period: .weekly, dayOfPeriod: 1)
        try store.saveDeliveryPlan(plan)
        let scheduler = DeliveryScheduler(store: store)
        #expect(scheduler.isDue(plan, now: monday))
        let runs = try scheduler.runDuePlans(now: monday)
        #expect(runs.map(\.outcome) == [.draftCreated])
        #expect(try scheduler.runDuePlans(now: monday.addingTimeInterval(3600)).isEmpty) // aynı gün tekrar çalışmaz
        let report = try #require(try store.reports(brandId: b.id).first)
        #expect(report.status == .draft)
        #expect(try store.reportShares(reportId: report.id).map(\.channel) == [.scheduledDraft])
        var paused = plan
        paused.enabled = false
        #expect(!scheduler.isDue(paused, now: monday.addingTimeInterval(7 * 86400)))
    }
}

@Suite struct AktarimTests {
    func writeFixture() throws -> URL {
        let dir = try tempDir("joi")
        let tasks = """
        {"tasks":[
          {"id":1,"text":"Teklif hazırla","project":"örnek","priority":3,"due":"2026-08-24","done":false,"status":"COMPLETE","timeSpent":3700,"createdAt":"2026-08-18T13:13:11.153Z","doneAt":null,"code":"BP-1"},
          {"id":2,"text":"Web QA","project":"abc","priority":2,"due":null,"done":false,"status":"READY","timeSpent":0,"createdAt":"2026-08-18T13:13:11.389Z","doneAt":null,"code":"BP-2"},
          {"id":3,"text":"Kişisel iş","project":"personal","priority":0,"done":true,"createdAt":"2026-08-18T13:13:11.389Z","doneAt":"2026-08-19T10:00:00.000Z"},
          {"id":4,"text":"Yazım farkı","project":"atla","priority":1,"status":"HOLD","timeSpent":0,"createdAt":"2026-08-20T10:00:00.000Z"},
          {"id":5,"text":"Doğru yazım","project":"atlas","priority":1,"status":"ACTIVE","timeSpent":120,"createdAt":"2026-08-20T10:00:00.000Z"}
        ],"nextId":6,"stats":{"completed":2}}
        """
        let events = """
        {"ts":"2026-08-18T13:13:11.153Z","type":"add","id":1,"text":"Teklif hazırla"}
        {"ts":"2026-08-20T09:00:00.000Z","type":"stop","id":1,"seconds":3600,"startedAt":"2026-08-20T08:00:00.000Z","toState":"HOLD"}
        bozuk satır
        {"ts":"2026-08-21T09:00:00.000Z","type":"status","id":1,"before":"HOLD","after":"COMPLETE"}
        """
        let config = """
        {"categories":[{"code":"BP","name":"Business Partner","children":["abc","örnek","atlas"]},{"code":"PS","name":"Personal","children":["personal"]}]}
        """
        try tasks.write(to: dir.appendingPathComponent("tasks.json"), atomically: true, encoding: .utf8)
        try events.write(to: dir.appendingPathComponent("events.jsonl"), atomically: true, encoding: .utf8)
        try config.write(to: dir.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        return dir
    }

    @Test func analizOnerileriVeTutarsizliklar() throws {
        let a = try JoiTodoImporter().analyze(directory: try writeFixture())
        #expect(a.tasks.count == 5)
        #expect(a.malformedEventLines == 1)
        #expect(a.statusDoneConflicts == 1)
        let byName = Dictionary(uniqueKeysWithValues: a.projects.map { ($0.project, $0) })
        #expect(byName["örnek"]?.suggestedBrand == "Örnek")
        #expect(byName["atla"]?.suggestedBrand == "Atlas")
        #expect(JoiTodoImporter.displayName("abc") == "ABC")
        #expect(a.suspiciousTimeTasks.isEmpty)
        #expect(byName["personal"]?.suggestedBrand == nil)
    }

    @Test func iceAktarimTekrarlanabilirVeKaynagiDegistirmez() throws {
        let dir = try writeFixture()
        let before = try Data(contentsOf: dir.appendingPathComponent("tasks.json"))
        let store = try makeStore()
        let importer = JoiTodoImporter()
        let analysis = try importer.analyze(directory: dir)
        let mapping: [String: JoiTodoImporter.Target] = [
            "örnek": .newBrand("Örnek Yangın"), "abc": .newBrand("ABC"), "atla": .newBrand("ATLAS"), "atlas": .newBrand("atlas"), "personal": .skip,
        ]
        let r1 = try importer.run(analysis, mapping: mapping, store: store, snapshotDirectory: dir.appendingPathComponent("snap"))
        #expect(r1.createdBrands == 3)
        #expect(r1.importedTasks == 4)
        let r2 = try importer.run(analysis, mapping: mapping, store: store, snapshotDirectory: nil)
        #expect(r2.importedTasks == 0)
        #expect(r2.skippedExistingTasks == 4)
        #expect(try store.brands().count == 3)
        #expect(try Data(contentsOf: dir.appendingPathComponent("tasks.json")) == before)

        let oz = try #require(try store.brands().first { $0.name == "Örnek Yangın" })
        let t = try #require(try store.tasks(brandId: oz.id).first)
        #expect(t.status == .done)                       // status alanı done alanına üstün
        #expect(t.completedAt == JoiTodoImporter.date("2026-08-21T09:00:00.000Z")) // olay günlüğünden
        #expect(t.timeSpentSeconds == 3700)              // 3600 sayaç + 100 sn altı fark aktarılmaz? (100 < 60 değil)
        let atlas = try #require(try store.brands().first { $0.name == "ATLAS" })
        #expect(try store.tasks(brandId: atlas.id).map(\.status).sorted { $0.rawValue < $1.rawValue } == [.inProgress, .waiting])
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("snap/tasks.json").path))
    }
}

@Suite struct YedekTests {
    @Test func yedekDogrulaGeriYukleVeUyumsuzYedegiReddet() throws {
        let workspace = try tempDir("ws")
        var db: AppDatabase? = try AppDatabase.open(at: workspace)
        var store = Store(database: db!)
        let b = try store.createBrand(name: "Yedeklenen")
        let f = workspace.appendingPathComponent("not.txt")
        try "içerik".write(to: f, atomically: true, encoding: .utf8)
        try store.addFileSource(brandId: b.id, fileURL: f)
        let service = BackupService(workspace: workspace)
        let backup = try service.createBackup(database: db!, reason: "manual")
        #expect(try service.validate(backup: backup).brandCount == 1)

        try store.createBrand(name: "Sonradan eklenen")
        #expect(try store.brands().count == 2)
        try service.restore(backup: backup, current: db!) {
            try (db!.writer as? DatabasePool)?.close()
        }
        db = nil
        db = try AppDatabase.open(at: workspace)
        store = Store(database: db!)
        #expect(try store.brands().map(\.name) == ["Yedeklenen"])
        let s = try #require(try store.sources(brandId: b.id).first)
        #expect(try String(contentsOf: store.fileURL(for: s)!, encoding: .utf8) == "içerik")
        #expect(service.listBackups().contains { $0.manifest.reason == "pre-restore" })

        // Gelecek sürümden yedek reddedilir.
        let future = try service.createBackup(database: db!, reason: "manual", now: Date().addingTimeInterval(5))
        let q = try DatabaseQueue(path: future.appendingPathComponent("workspace.sqlite").path)
        try q.write { db in try db.execute(sql: "INSERT INTO grdb_migrations VALUES ('v99_gelecek')") }
        try q.close()
        #expect(throws: MarkaError.self) { try service.validate(backup: future) }
    }

    @Test func markaDisaAktarimiDosyaVeVeriIcerir() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Dış/Aktar")
        try store.addGeneratedOutput(brandId: b.id, fileName: "rapor.md", content: "# x", title: "Rapor", actor: .user)
        let out = try BackupService(workspace: try tempDir()).exportBrand(b.id, store: store, to: try tempDir("exp"))
        let json = try String(contentsOf: out.appendingPathComponent("veri.json"), encoding: .utf8)
        #expect(json.contains("Dış/Aktar"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: out.appendingPathComponent("dosyalar").path).count == 1)
    }
}
