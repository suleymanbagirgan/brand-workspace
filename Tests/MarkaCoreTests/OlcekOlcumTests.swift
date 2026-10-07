import Foundation
import GRDB
import Testing
@testable import MarkaCore

/// Ölçüm aracı (yalnız `MARKA_OLCUM=1` ile çalışır; CI'da atlanır): yoğun sentetik veride sorgu medyanlarını ve
/// sorgu planlarını yazdırır. Sonuçlar `docs/performans-olcumu.md`'ye elle aktarılır.
@Suite struct OlcekOlcumTests {
    static var etkin: Bool { ProcessInfo.processInfo.environment["MARKA_OLCUM"] == "1" }

    static func olc(_ v: YogunVeri, etiket: String) throws {
        let s = v.store
        let b = v.brandIds[1]
        let cal = StatusService.turkishCalendar
        let month = cal.dateInterval(of: .month, for: v.now)!
        let ctx = ContextBuilder(store: s)
        let olcumler: [(String, () throws -> Void)] = [
            ("reloadBasics: brands()", { _ = try s.brands() }),
            ("reloadBasics: pendingApprovalCounts()", { _ = try s.pendingApprovalCounts() }),
            ("today()", { _ = try s.today(now: v.now) }),
            ("todo(brandId:)", { _ = try s.todo(brandId: b) }),
            ("flow(brandId:)", { _ = try s.flow(brandId: b) }),
            ("tasks(brandId:)", { _ = try s.tasks(brandId: b) }),
            ("tasks(brandId:, açık durumlar)", { _ = try s.tasks(brandId: b, statuses: [.todo, .inProgress, .waiting]) }),
            ("tasks(brandId: nil)", { _ = try s.tasks(brandId: nil) }),
            ("pendingApprovals × 8 marka", { for id in v.brandIds { _ = try s.pendingApprovals(brandId: id) } }),
            ("completedTaskCount", { _ = try s.completedTaskCount(brandId: b, since: v.now.addingTimeInterval(-30 * 86400)) }),
            ("ContextBuilder.brandContext", { _ = try ctx.brandContext(brandId: b, provider: .anthropic, now: v.now) }),
            ("brandContext (Stüdyo)", { _ = try ctx.brandContext(brandId: v.ownBrandId, provider: .anthropic, now: v.now) }),
            ("search (FTS, marka)", { _ = try s.search("kampanya bütçe", brandId: b) }),
            ("search (FTS, tüm markalar)", { _ = try s.search("lansman", brandId: nil) }),
            ("searchToday", { _ = try s.searchToday("kampanya") }),
            ("searchToday (eşleşmesiz, tam tarama)", { _ = try s.searchToday("qqqzzz") }),
            ("tasks(nil, açık, limit 5) — menü paneli", { _ = try s.tasks(brandId: nil, statuses: [.todo, .inProgress, .waiting], limit: 5) }),
            ("ChatEngine tüm markalar: openTaskCounts", { _ = try s.openTaskCounts() }),
            ("orgChart", { _ = try s.orgChart() }),
            ("brandTeam", { _ = try s.brandTeam(brandId: b) }),
            ("brandTeam (Stüdyo)", { _ = try s.brandTeam(brandId: v.ownBrandId) }),
            ("memberActivity", { _ = try s.memberActivity() }),
            ("profile", { _ = try s.profile(brandId: b) }),
            ("reportPreview (ay)", { _ = try s.reportPreview(brandId: b, period: .monthly, interval: month, now: v.now) }),
            ("workLogs(brandId:)", { _ = try s.workLogs(brandId: b) }),
            ("sources(brandId:)", { _ = try s.sources(brandId: b) }),
            ("records(brandId:)", { _ = try s.records(brandId: b) }),
            ("referenceRecords", { _ = try s.referenceRecords(brandId: b) }),
            ("financeEntries", { _ = try s.financeEntries(brandId: b) }),
            ("recentlyAppliedProposals", { _ = try s.recentlyAppliedProposals(brandId: b) }),
            ("runningTimer", { _ = try s.runningTimer() }),
            ("auditTrail", { _ = try s.auditTrail(entity: "task", entityId: UUID().uuidString) }),
        ]
        print("OLCUM [\(etiket)] sorgu | medyan ms")
        for (ad, blok) in olcumler {
            let ms = try YogunVeri.medyanMs(5, blok)
            print(String(format: "OLCUM [%@] %@ | %.2f", etiket, ad, ms))
        }
    }

    static func planlar(_ s: Store) throws {
        let sorgular = [
            "SELECT brandId, COUNT(*) FROM aiProposal WHERE status = 'pending' AND kind != 'wikiRevision' GROUP BY brandId",
            "SELECT brandId, COUNT(*) FROM wikiRevision WHERE state = 'proposed' GROUP BY brandId",
            "SELECT * FROM aiProposal WHERE brandId = 'x' AND status = 'pending' AND kind != 'wikiRevision' ORDER BY createdAt",
            "SELECT * FROM wikiRevision WHERE brandId = 'x' AND state = 'proposed' ORDER BY createdAt",
            "SELECT * FROM workLog WHERE brandId = 'x' ORDER BY occurredAt DESC LIMIT 200",
            "SELECT * FROM workTask WHERE brandId = 'x' AND status = 'done' AND completedAt IS NOT NULL ORDER BY completedAt DESC LIMIT 200",
            "SELECT DISTINCT taskId FROM workLog WHERE brandId = 'x' AND taskId IS NOT NULL",
            "SELECT * FROM source WHERE brandId = 'x' AND archivedAt IS NULL ORDER BY capturedAt DESC LIMIT 200",
            "SELECT * FROM brandRecord WHERE brandId = 'x' AND kind IN ('promise','decision','request') AND closedAt IS NOT NULL ORDER BY closedAt DESC LIMIT 200",
            "SELECT * FROM aiProposal WHERE brandId = 'x' AND status = 'applied' ORDER BY decidedAt DESC LIMIT 200",
            "SELECT * FROM workTask WHERE brandId = 'x' AND status IN ('todo','inProgress','waiting')",
            "SELECT * FROM brandRecord WHERE brandId = 'x' AND kind IN ('promise','decision','request')",
            "SELECT * FROM workLog WHERE brandId = 'x' AND status = 'verified' AND occurredAt >= 'a' AND occurredAt < 'b' ORDER BY occurredAt",
            "SELECT * FROM workLogSource WHERE workLogId = 'x'",
            "SELECT * FROM timeEntry WHERE brandId = 'x' AND endedAt IS NOT NULL AND endedAt >= 'a' AND endedAt < 'b'",
            "SELECT COALESCE(SUM(seconds), 0) FROM timeEntry WHERE taskId = 'x' AND endedAt IS NOT NULL",
            "SELECT * FROM timeEntry WHERE endedAt IS NULL LIMIT 1",
            "SELECT COUNT(*) FROM workTask WHERE brandId = 'x' AND status = 'done' AND completedAt >= 'a'",
            "SELECT * FROM source WHERE brandId = 'x' AND archivedAt IS NULL ORDER BY capturedAt DESC",
            "SELECT * FROM brandRecord WHERE brandId = 'x' ORDER BY createdAt DESC",
            "SELECT * FROM contact WHERE brandId = 'x' ORDER BY name",
            "SELECT * FROM wikiPage WHERE brandId = 'x' ORDER BY kind, title",
            "SELECT s.memberId, p.status, COUNT(*) FROM aiProposal p JOIN aiSession s ON s.id = p.sessionId WHERE s.memberId IS NOT NULL GROUP BY s.memberId, p.status",
            "SELECT memberId, MAX(updatedAt) FROM aiSession WHERE memberId IS NOT NULL GROUP BY memberId",
            "SELECT * FROM brandAssignment WHERE brandId = 'x'",
            "SELECT * FROM financeEntry WHERE brandId = 'x'",
            "SELECT * FROM auditEvent WHERE entity = 'task' AND entityId = 'x' ORDER BY at DESC",
        ]
        try s.read { db in
            for q in sorgular {
                let rows = try Row.fetchAll(db, sql: "EXPLAIN QUERY PLAN " + q)
                print("PLAN \(q)\n" + rows.map { "PLAN    -> " + ($0["detail"] as String? ?? "") }.joined(separator: "\n"))
            }
        }
    }

    /// Yavaş sorguların bileşenleri: SQL + çözme mi, Swift sıralama/süzme mi?
    static func kirilim(_ v: YogunVeri) throws {
        let s = v.store, b = v.brandIds[1]
        func p(_ ad: String, _ blok: () throws -> Void) rethrows { print(String(format: "KIRILIM %@ | %.2f", ad, try YogunVeri.medyanMs(5, blok))) }
        try p("WorkTask.fetchAll marka (çözme)") { _ = try s.read { try WorkTask.filter(Column("brandId") == b).fetchAll($0) } }
        try p("Row.fetchAll marka (çözmesiz)") { _ = try s.read { try Row.fetchAll($0, sql: "SELECT * FROM workTask WHERE brandId = ?", arguments: [b]) } }
        let all = try s.read { try WorkTask.filter(Column("brandId") == b).fetchAll($0) }
        try p("displayOrder sıralama 2500") { _ = all.sorted(by: WorkTask.displayOrder) }
        try p("WorkTask açık tüm markalar") { _ = try s.read { try WorkTask.filter(["todo", "inProgress", "waiting"].contains(Column("status"))).fetchAll($0) } }
        try p("açık + gecikmiş SQL") { _ = try s.read { try WorkTask.filter(["todo", "inProgress", "waiting"].contains(Column("status")) && Column("dueDate") < "2026-10-04").fetchAll($0) } }
        try p("searchToday başlık satırları") { _ = try s.read { try Row.fetchAll($0, sql: "SELECT id, brandId, title FROM workTask") } }
        let titles = try s.read { try String.fetchAll($0, sql: "SELECT title FROM workTask") }
        try p("normalize 20000 başlık") { for t in titles { _ = Store.normalize(t) } }
        try p("sources marka (gövdeli)") { _ = try s.sources(brandId: b) }
        // Eski yolların birebir kopyası (önce/sonra karşılaştırması için).
        try p("ESKİ menü paneli: açık tüm görevler + sırala + ilk 5") {
            _ = try s.read { try WorkTask.filter(["todo", "inProgress", "waiting"].contains(Column("status"))).fetchAll($0) }
                .sorted(by: WorkTask.displayOrder).prefix(5)
        }
        try p("ESKİ tüm markalar: marka başına görev listesi") {
            for id in v.brandIds { _ = try s.read { try WorkTask.filter(Column("brandId") == id).fetchAll($0) }.sorted(by: WorkTask.displayOrder).filter(\.status.isOpen).count }
        }
        try p("ESKİ pano bırakma: 20 görev × marka listesi") {
            let ids = try s.tasks(brandId: b, statuses: [.todo]).prefix(20).map(\.id)
            _ = ids.compactMap { id in (try? s.read { try WorkTask.filter(Column("brandId") == b).fetchAll($0) }.sorted(by: WorkTask.displayOrder))?.first { $0.id == id } }
        }
        try p("YENİ pano bırakma: tek liste + sözlük") {
            let ids = try s.tasks(brandId: b, statuses: [.todo]).prefix(20).map(\.id)
            let byId = Dictionary(uniqueKeysWithValues: try s.tasks(brandId: b).map { ($0.id, $0) })
            _ = ids.compactMap { byId[$0] }
        }
    }

    @Test(.enabled(if: OlcekOlcumTests.etkin)) func yogunVerideSorgulariOlcVePlanlariYazdir() throws {
        let clock = ContinuousClock()
        var v: YogunVeri!
        let uretim = try clock.measure { v = try YogunVeri.uret(Store(database: try AppDatabase.inMemory())) }
        print("OLCUM üretim (bellek içi): \(uretim)")
        try Self.olc(v, etiket: "bellek")
        try Self.planlar(v.store)
        try Self.kirilim(v)

        let dir = try tempDir("olcum")
        defer { try? FileManager.default.removeItem(at: dir) }
        var d: YogunVeri!
        let uretimDisk = try clock.measure { d = try YogunVeri.uret(Store(database: try AppDatabase.open(at: dir))) }
        print("OLCUM üretim (disk): \(uretimDisk)")
        try Self.olc(d, etiket: "disk")
    }
}
