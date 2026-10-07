import Foundation
import GRDB
import Testing
@testable import MarkaCore

/// Ölçek regresyonu: yoğun SENTETİK veride (8 marka × ~2.500 görev …) kritik sorguların süresi ve toplu sorgu düzeltmelerinin
/// eski davranışla aynı sonucu verdiği. Süre sınırları bilerek çok gevşektir (ölçülen medyanın en az 5 katı, en az 500 ms;
/// bkz. docs/performans-olcumu.md): amaç yalnız 10–100 katlık gerilemeyi yakalamak, makine hızını sınamak değil.
@Suite(.serialized) struct OlcekTests {
    var v: YogunVeri { YogunVeri.paylasilan }

    /// Sınır: `blok`'un 3 ölçümlük medyanı `sinirMs`'i aşmamalı.
    func sureSiniri(_ ad: String, _ sinirMs: Double = 500, _ blok: () throws -> Void) throws {
        let ms = try YogunVeri.medyanMs(3, blok)
        #expect(ms < sinirMs, "\(ad): \(ms) ms (sınır \(sinirMs) ms)")
    }

    @Test func yogunVeriBeklenenOlcekteVeBelirlenimli() throws {
        let counts = try v.store.read { db in
            (try Brand.fetchCount(db), try WorkTask.fetchCount(db), try Source.fetchCount(db), try WorkLog.fetchCount(db),
             try AIProposal.fetchCount(db), try TeamMember.fetchCount(db), try AuditEvent.fetchCount(db))
        }
        #expect(counts.0 == 8 && counts.1 == 20_000 && counts.2 == 12_000 && counts.3 == 6_400)
        #expect(counts.4 == 1_600 && counts.5 == 40 && counts.6 >= 40_000)
        #expect(try v.store.ownBrand()?.id == v.ownBrandId)
        // Aynı tohum aynı dağılımı verir (küçük ölçekte iki kez üret, durum dağılımı aynı).
        func dagilim() throws -> [String] {
            let k = try YogunVeri.uret(try makeStore(), olcek: .kucuk, now: v.now)
            return try k.store.read { try String.fetchAll($0, sql: "SELECT status || ':' || COUNT(*) FROM workTask GROUP BY status ORDER BY status") }
        }
        #expect(try dagilim() == dagilim())
    }

    // MARK: Süre sınırları (kenar çubuğu, Bugün, marka ekranı, asistan bağlamı, arama, rapor)

    @Test func kenarCubuguVeBugunYogunVerideHizli() throws {
        let s = v.store
        try sureSiniri("reloadBasics") { _ = try s.brands(); _ = try s.pendingApprovalCounts() }
        try sureSiniri("pendingApprovals × 8") { for id in v.brandIds { _ = try s.pendingApprovals(brandId: id) } }
        try sureSiniri("today") { _ = try s.today(now: v.now) }
        try sureSiniri("menü paneli ilk 5 açık görev") { _ = try s.tasks(brandId: nil, statuses: [.todo, .inProgress, .waiting], limit: 5) }
    }

    @Test func markaEkraniSorgulariYogunVerideHizli() throws {
        let s = v.store, b = v.brandIds[1]
        try sureSiniri("todo") { _ = try s.todo(brandId: b) }
        try sureSiniri("flow") { _ = try s.flow(brandId: b) }
        try sureSiniri("tasks") { _ = try s.tasks(brandId: b) }
        try sureSiniri("completedTaskCount") { _ = try s.completedTaskCount(brandId: b, since: v.now.addingTimeInterval(-30 * 86_400)) }
        try sureSiniri("profile + ekip + şema + etkinlik") {
            _ = try s.profile(brandId: b); _ = try s.brandTeam(brandId: b); _ = try s.brandTeam(brandId: v.ownBrandId)
            _ = try s.orgChart(); _ = try s.memberActivity()
        }
        let month = StatusService.turkishCalendar.dateInterval(of: .month, for: v.now)!
        try sureSiniri("reportPreview") { _ = try s.reportPreview(brandId: b, period: .monthly, interval: month, now: v.now) }
    }

    @Test func asistanBaglamiVeAramaYogunVerideHizli() throws {
        let s = v.store, b = v.brandIds[1]
        let ctx = ContextBuilder(store: s)
        try sureSiniri("brandContext") { _ = try ctx.brandContext(brandId: b, provider: .anthropic, now: v.now) }
        try sureSiniri("allBrandsContext") { _ = try ctx.allBrandsContext(allowedBrandIds: Set(v.brandIds), now: v.now) }
        try sureSiniri("search FTS") { _ = try s.search("kampanya bütçe", brandId: b); _ = try s.search("lansman", brandId: nil) }
        // Eşleşmesiz arama tüm başlıkları tarar (en kötü durum; ölçülen ~140 ms, sınır 1 sn).
        try sureSiniri("searchToday eşleşmesiz", 1_000) { _ = try s.searchToday("qqqzzz") }
    }

    // MARK: Davranış aynı kaldı

    @Test func gorevSqlSirasiDisplayOrderIleAyniVeLimitIlkElemanlari() throws {
        let s = v.store, b = v.brandIds[2]
        let all = try s.tasks(brandId: b)
        #expect(all.count == 2_500)
        #expect(zip(all, all.dropFirst()).allSatisfy { !WorkTask.displayOrder($1, $0) })
        // Swift sıralamasıyla aynı küme ve sıra (anahtar bazında; eşit anahtarlı görevlerin kendi aralarındaki sırası serbest).
        let raw = try s.read { try WorkTask.filter(Column("brandId") == b).fetchAll($0) }.sorted(by: WorkTask.displayOrder)
        #expect(Set(raw.map(\.id)) == Set(all.map(\.id)))
        func key(_ t: WorkTask) -> String { "\(t.status.isOpen)|\(t.dueDate ?? "-")|\(t.priority)|\(t.status.isOpen ? t.createdAt : (t.completedAt ?? t.updatedAt))" }
        #expect(raw.map(key) == all.map(key))
        let open: [TaskStatus] = [.todo, .inProgress, .waiting]
        let top = try s.tasks(brandId: nil, statuses: open, limit: 5)
        let full = try s.tasks(brandId: nil, statuses: open)
        #expect(top.count == 5 && top.map(key) == full.prefix(5).map(key))
        #expect(try s.tasks(brandId: b, limit: 0).isEmpty)
    }

    @Test func bugunOzetiToplanmisSorgularlaEskiHesaplaAyni() throws {
        let s = v.store, cal = StatusService.turkishCalendar, now = v.now
        let got = try s.today(now: now)
        // Eski hesap: tüm satırları çözüp Swift'te süz ve say.
        let today = DayString.from(now, calendar: cal)
        let week = cal.dateInterval(of: .weekOfYear, for: now)!
        let brands = try s.brands()
        let ids = brands.map(\.id)
        let order = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        let want = try s.read { db -> TodaySummary in
            let proposals = try AIProposal.filter(ids.contains(Column("brandId")) && Column("status") == "pending" && Column("kind") != "wikiRevision").fetchAll(db)
            let revisions = try WikiRevision.filter(ids.contains(Column("brandId")) && Column("state") == "proposed").fetchAll(db)
            let pending: [TodaySummary.Pending] = ids.compactMap { id in
                let mine = proposals.filter { $0.brandId == id }
                let terminal = mine.filter { $0.origin == .terminal }.count
                let other = mine.count - terminal + revisions.filter { $0.brandId == id }.count
                return terminal + other > 0 ? .init(brandId: id, terminal: terminal, other: other) : nil
            }
            let overdue = try WorkTask.filter(ids.contains(Column("brandId")) && ["todo", "inProgress", "waiting"].contains(Column("status")))
                .fetchAll(db).filter { $0.isOverdue(today: today) }
                .sorted { ($0.dueDate ?? "", order[$0.brandId] ?? 0, $0.title) < ($1.dueDate ?? "", order[$1.brandId] ?? 0, $1.title) }
                .map { StatusLine(text: $0.title, detail: "", date: nil, dueDate: $0.dueDate, ref: RecordRef(.task, $0.id), brandId: $0.brandId) }
            let done = try WorkTask.filter(ids.contains(Column("brandId")) && Column("status") == "done"
                                           && Column("completedAt") >= week.start && Column("completedAt") < week.end).fetchAll(db)
            let logs = try WorkLog.filter(ids.contains(Column("brandId")) && Column("status") != "retracted"
                                          && Column("occurredAt") >= week.start && Column("occurredAt") < week.end).fetchAll(db)
            let sources = try Source.filter(ids.contains(Column("brandId")) && Column("archivedAt") == nil
                                            && Column("capturedAt") >= week.start && Column("capturedAt") < week.end).fetchAll(db)
            let noteKinds: Set<SourceKind> = [.note, .meeting, .clientRequest]
            let weekRows: [TodaySummary.Week] = ids.compactMap { id in
                let l = logs.filter { $0.brandId == id }, src = sources.filter { $0.brandId == id }
                let row = TodaySummary.Week(brandId: id, tasksDone: done.filter { $0.brandId == id }.count, workLogs: l.count,
                                            unverified: l.filter { $0.status == .draft }.count,
                                            files: src.filter { !noteKinds.contains($0.kind) }.count, notes: src.filter { noteKinds.contains($0.kind) }.count)
                return row.tasksDone + row.workLogs + row.files + row.notes > 0 ? row : nil
            }
            return TodaySummary(pending: pending, overdue: overdue, week: weekRows, awaiting: [])
        }
        #expect(got.pending == want.pending)
        #expect(got.overdue == want.overdue)
        #expect(got.week == want.week)
        #expect(!got.overdue.isEmpty && !got.pending.isEmpty && !got.week.isEmpty)
    }

    @Test func bugunAramasiErkenKesmeyleEskiSonucuVerir() throws {
        let s = v.store
        // Eski hesap: tüm kayıtları çöz, başlıkları süz, sonra kes.
        func eski(_ query: String, limit: Int) throws -> [String] {
            let terms = Store.searchTerms(query)
            func m(_ t: String) -> Bool { let n = Store.normalize(t); return terms.allSatisfy { n.contains($0) } }
            var out: [String] = try s.read { db in
                let ids = try String.fetchAll(db, sql: "SELECT id FROM brand WHERE status = 'active'")
                var o: [String] = []
                o += try WorkTask.filter(ids.contains(Column("brandId"))).order(Column("updatedAt").desc).fetchAll(db).filter { m($0.title) }.map { "task" + $0.id }
                o += try WorkLog.filter(ids.contains(Column("brandId")) && Column("status") != "retracted").order(Column("occurredAt").desc).fetchAll(db)
                    .filter { m($0.title) }.map { "workLog" + $0.id }
                o += try BrandRecord.filter(ids.contains(Column("brandId"))).order(Column("updatedAt").desc).fetchAll(db).filter { m($0.title) }.map { "brandRecord" + $0.id }
                return o
            }
            out += try s.search(query, brandId: nil, limit: limit).filter { $0.kind == .source }.map { "source" + $0.id }
            return Array(out.prefix(limit))
        }
        for (q, limit) in [("kampanya", 50), ("İş ızgara", 50), ("Kayıt çiçek", 500), ("qqqzzz", 50), ("kaynak lansman", 40)] {
            #expect(try s.searchToday(q, limit: limit).map(\.id) == eski(q, limit: limit), "\(q)")
        }
    }

    @Test func tumMarkalarBaglamiTekSayimlaAyniSayilariYazar() throws {
        let s = v.store
        let counts = try s.openTaskCounts()
        for id in v.brandIds {
            #expect(counts[id] == (try s.tasks(brandId: id).filter(\.status.isOpen).count))
        }
        let text = try ContextBuilder(store: s).allBrandsContext(allowedBrandIds: Set(v.brandIds.prefix(3)), now: v.now)
        for id in v.brandIds.prefix(3) { #expect(text.contains("id=\(id)\nAçık görev: \(counts[id] ?? 0)\n")) }
        #expect(!text.contains(v.brandIds[5]))
    }

    @Test func markaBaglamiYalnizIlkKaynaklariOkurAmaToplamiDogruYazar() throws {
        let s = v.store, b = v.brandIds[3]
        let text = try ContextBuilder(store: s).brandContext(brandId: b, provider: nil, now: v.now)
        let sources = try s.sources(brandId: b)
        let tasks = try s.tasks(brandId: b).filter(\.status.isOpen)
        #expect(text.contains("… ve \(sources.count - ContextLimits.listItems) öğe daha var"))
        #expect(text.contains("… ve \(tasks.count - ContextLimits.listItems) öğe daha var"))
        for src in sources.prefix(ContextLimits.listItems) { #expect(text.contains("id=\(src.id)")) }
        #expect(!text.contains("id=\(sources[ContextLimits.listItems].id)"))
        for t in tasks.prefix(ContextLimits.listItems) { #expect(text.contains("id=\(t.id)")) }
        // Başka markanın kaynağı bağlama girmez.
        #expect(try !s.sources(brandId: v.brandIds[4]).prefix(5).contains { text.contains($0.id) })
    }

    @Test func raporToplucaOkunanDosyaBaglariKayitBasinaOkumaylaAyni() throws {
        let s = v.store, b = v.brandIds[1]
        let interval = DateInterval(start: v.now.addingTimeInterval(-90 * 86_400), end: v.now)
        let content = try ReportBuilder(store: s).build(brandId: b, period: interval, now: v.now)
        let logs = try s.workLogs(brandId: b, statuses: [.verified]).filter { interval.start <= $0.occurredAt && $0.occurredAt < interval.end }
            .sorted { $0.occurredAt < $1.occurredAt }
        let completed = try #require(content.section(.completedWork)).items
        #expect(completed.count == logs.count && logs.count > 50)
        // Eşit anlı kayıtların kendi aralarındaki sırası serbest: madde, dayandığı iş kaydıyla eşlenir.
        let byLog = Dictionary(uniqueKeysWithValues: completed.compactMap { i in i.refs.first.map { ($0.id, i) } })
        var outputs = 0
        for log in logs {
            let item = try #require(byLog[log.id])
            let d = try s.workLogDetail(log.id)
            var refs = [RecordRef(.workLog, log.id)] + d.inputs.map { RecordRef(.source, $0.id) }
            if let t = log.taskId { refs.append(RecordRef(.task, t)) }
            #expect(item.refs == refs)
            outputs += d.outputs.filter { $0.archivedAt == nil }.count
        }
        #expect(try #require(content.section(.deliverables)).items.count == outputs)
        #expect(try #require(content.section(.timeSpent)).items.allSatisfy { $0.refs.first?.kind == .task })
    }
}

@Suite struct V9IndeksMigrationTests {
    @Test func v9IndeksleriOlusurEskiVeriBozulmazYedekAlinir() throws {
        let dir = try tempDir("v9")
        let store = Store(database: try AppDatabase.open(at: dir))
        let k = try YogunVeri.uret(store, olcek: .kucuk)
        func indexes(_ s: Store) throws -> Set<String> {
            Set(try s.read { try String.fetchAll($0, sql: "SELECT name FROM sqlite_master WHERE type = 'index'") })
        }
        let names = Set(AppDatabase.v9Indexes.map(\.0))
        #expect(try names.count == 7 && names.isSubset(of: indexes(store)))
        // v9'dan sonra yalnız v10 gözlemler (E-01), v11 yetenek kökeni (E-07) ve v12 marka radarı (E-21) gelir; v9 öncesini
        // taklit ederken sonraki migration'lar da geri alınır.
        #expect(AppDatabase.migrationIdentifiers.suffix(4) == ["v9_olcek_indeksleri", "v10_gozlemler", "v11_yetenek_kokeni", "v12_marka_radari"])

        // v9 öncesi şemayı taklit et: indeksler yok, migration kaydı yok; veri yerinde.
        let before = try store.read { db in
            (try WorkTask.fetchCount(db), try Source.fetchCount(db), try String.fetchAll(db, sql: "SELECT id FROM workTask ORDER BY id"))
        }
        try store.write { db in
            for n in names { try db.execute(sql: "DROP INDEX \(n)") }
            try db.execute(sql: "DROP TABLE observation")
            try db.execute(sql: "DROP TABLE radarItem")
            for c in ["origin", "contentHash", "importedAt"] { try db.execute(sql: "ALTER TABLE skill DROP COLUMN \(c)") }
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier IN ('v9_olcek_indeksleri', 'v10_gozlemler', 'v11_yetenek_kokeni', 'v12_marka_radari')")
        }
        #expect(try indexes(store).isDisjoint(with: names))
        if let pool = store.database.writer as? DatabasePool { try pool.close() }

        let again = Store(database: try AppDatabase.open(at: dir))
        #expect(try names.isSubset(of: indexes(again)))
        let after = try again.read { db in
            (try WorkTask.fetchCount(db), try Source.fetchCount(db), try String.fetchAll(db, sql: "SELECT id FROM workTask ORDER BY id"))
        }
        #expect(before == after)
        #expect(try again.tasks(brandId: k.brandIds[1]).count == YogunVeri.Olcek.kucuk.tasksPerBrand)
        // FTS ve kaynak değişmezliği etkilenmez.
        #expect(try !again.search("kampanya", brandId: k.brandIds[1]).isEmpty)
        // Migration öncesi yedek alındı ve eski (indekssiz) şemada.
        let backups = dir.appendingPathComponent("Migration-Yedekleri")
        let files = try FileManager.default.contentsOfDirectory(atPath: backups.path).filter { $0.hasSuffix(".sqlite") }
        #expect(files.count == 1 && files[0].contains("v8_yetenekler"))
        let backup = try DatabaseQueue(path: backups.appendingPathComponent(files[0]).path)
        #expect(try backup.read { try WorkTask.fetchCount($0) } == before.0)
        #expect(try backup.read { try String.fetchAll($0, sql: "SELECT name FROM sqlite_master WHERE name = 'workLog_brand_occurred'") }.isEmpty)
    }
}
