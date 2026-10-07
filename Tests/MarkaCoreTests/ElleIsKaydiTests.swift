import Foundation
import GRDB
import Testing
@testable import MarkaCore

/// Elle iş kaydı (H2-03, U-09): yapay zekâ olmadan rapor boş kalmasın. Kullanıcının yazdığı kayıt `.user` aktörlü ve
/// doğrulanmış olarak kaydedilir; kural 4'ün en-az-bağlantı şartı (`verificationProblem`) gevşetilmez.
@Suite struct ElleIsKaydiTests {
    private func completedItems(_ store: Store, _ brandId: String, now: Date) throws -> [ReportItem] {
        let interval = ReportRange.thisWeek.interval(now: now)
        let preview = try store.reportPreview(brandId: brandId, period: .weekly, interval: interval, now: now)
        return preview.content.section(.completedWork)?.items ?? []
    }

    private func doneTask(_ store: Store, _ brandId: String, title: String = "Bayi listesini güncelle") throws -> WorkTask {
        var t = try store.saveTask(WorkTask(brandId: brandId, title: title))
        try store.setTaskStatus(t.id, .done)
        t = try #require(try store.tasks(brandId: brandId).first { $0.id == t.id })
        return t
    }

    @Test func yapayZekasizOrnekMarkadaElleIsKaydiRaporaMaddeOlarakGirer() throws {
        let store = try makeStore()
        let now = Date()
        let sample = try store.createSampleBrand(now: now)
        #expect(try store.brand(sample.id).allowedProviders.isEmpty)
        let before = try completedItems(store, sample.id, now: now)
        #expect(before.count >= 1)
        let task = try doneTask(store, sample.id)
        var draft = WorkLog.draft(for: task, now: now)
        draft.performed = "Bayi listesi yeni şehirlerle güncellendi."
        let log = try store.saveUserWorkLog(draft, inputSourceIds: [], outputSourceIds: [], verifiedBy: "Danışman")
        let after = try completedItems(store, sample.id, now: now)
        #expect(after.count == before.count + 1)
        #expect(after.contains { item in item.refs.contains { $0.kind == .workLog && $0.id == log.id } })
    }

    @Test func yapayZekasizKendiMarkamdaRaporElleKayitlaBosOlmaktanCikar() throws {
        let store = try makeStore()
        let now = Date()
        let b = try store.createBrand(name: "Kuzey Lojistik")
        let task = try doneTask(store, b.id)
        #expect(try completedItems(store, b.id, now: now).isEmpty)
        var draft = WorkLog.draft(for: task, now: now)
        draft.performed = "Liste güncellendi."
        try store.saveUserWorkLog(draft, inputSourceIds: [], outputSourceIds: [], verifiedBy: "Danışman")
        #expect(try completedItems(store, b.id, now: now).count == 1)
        #expect(try store.needsWorkLog(taskId: task.id) == false)
    }

    @Test func elleIsKaydiKullaniciAktorluVeDogrulanmisOlur() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Deneme Yangın")
        let note = try store.addTextSource(brandId: b.id, kind: .note, title: "Toplantı notu", body: "Görüşüldü.")
        // Aktör AI gibi gelse bile kullanıcı yolu `.user` yazar.
        let log = try store.saveUserWorkLog(WorkLog(brandId: b.id, title: "Görüşme özeti", performed: "Özet çıkarıldı.", actor: .ai),
                                            inputSourceIds: [note.id], outputSourceIds: [], verifiedBy: "Danışman")
        let stored = try store.workLogDetail(log.id)
        #expect(stored.log.actor == .user)
        #expect(stored.log.status == .verified)
        #expect(stored.log.verifiedBy == "Danışman")
        #expect(stored.log.verifiedAt != nil)
        #expect(stored.inputs.map(\.id) == [note.id])
    }

    @Test func elleIsKaydiBaskaMarkaninGorevineVeDosyasinaBaglanamaz() throws {
        let store = try makeStore()
        let a = try store.createBrand(name: "Kuzey Lojistik")
        let other = try store.createBrand(name: "Örnek Kafe Zinciri")
        let foreignTask = try store.saveTask(WorkTask(brandId: other.id, title: "Yabancı görev"))
        let foreignNote = try store.addTextSource(brandId: other.id, kind: .note, title: "Yabancı not", body: "x")
        #expect(throws: MarkaError.brandScope) {
            try store.saveUserWorkLog(WorkLog(brandId: a.id, taskId: foreignTask.id, title: "İş", performed: "Yapıldı"),
                                      inputSourceIds: [], outputSourceIds: [], verifiedBy: "Danışman")
        }
        #expect(throws: MarkaError.brandScope) {
            try store.saveUserWorkLog(WorkLog(brandId: a.id, title: "İş", performed: "Yapıldı"),
                                      inputSourceIds: [foreignNote.id], outputSourceIds: [], verifiedBy: "Danışman")
        }
        #expect(try store.workLogs(brandId: a.id).isEmpty)
        #expect(try store.workLogs(brandId: other.id).isEmpty)
    }

    @Test func elleIsKaydiKullaniciAktoruyleOlusturmaVeDogrulamaDenetimiBirakir() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Deneme Yangın")
        let task = try doneTask(store, b.id)
        var draft = WorkLog.draft(for: task)
        draft.performed = "Yapıldı."
        let log = try store.saveUserWorkLog(draft, inputSourceIds: [], outputSourceIds: [], verifiedBy: "Danışman")
        let events = try store.read { db in
            try AuditEvent.filter(Column("entity") == "workLog" && Column("entityId") == log.id).fetchAll(db)
        }
        #expect(events.map(\.action).sorted() == ["create", "verify"])
        #expect(events.allSatisfy { $0.actor == .user && $0.brandId == b.id })
    }

    @Test func bagsizElleIsKaydiDogrulanmazVeHicbirSeyYazilmaz() throws {
        // Kural 4 gevşetilmedi: görev ya da dosya bağı yoksa (veya "Ne yapıldı?" boşsa) kayıt da yazılmaz.
        let store = try makeStore()
        let b = try store.createBrand(name: "Kuzey Lojistik")
        #expect(throws: MarkaError.self) {
            try store.saveUserWorkLog(WorkLog(brandId: b.id, title: "Bağsız iş", performed: "Yapıldı"),
                                      inputSourceIds: [], outputSourceIds: [], verifiedBy: "Danışman")
        }
        let task = try doneTask(store, b.id)
        #expect(throws: MarkaError.self) {
            try store.saveUserWorkLog(WorkLog.draft(for: task), inputSourceIds: [], outputSourceIds: [], verifiedBy: "Danışman")
        }
        #expect(try store.workLogs(brandId: b.id).isEmpty)
        let audits = try store.read { db in try AuditEvent.filter(Column("entity") == "workLog").fetchCount(db) }
        #expect(audits == 0)
    }

    @Test func yapayZekaElleIsKaydiYolunuKullanamazVeTaslagiTaslakKalir() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Kuzey Lojistik")
        let t = try store.saveTask(WorkTask(brandId: b.id, title: "Görev"))
        #expect(throws: MarkaError.self) {
            try store.write { db in
                try store.saveUserWorkLog(db, WorkLog(brandId: b.id, taskId: t.id, title: "İş", performed: "Yapıldı"),
                                          inputs: [], outputs: [], verifiedBy: "X", actor: .ai)
            }
        }
        #expect(try store.workLogs(brandId: b.id).isEmpty)
        // AI'nin yazdığı taslak, kullanıcı yolundan "kendiliğinden" doğrulanmaz.
        let aiLog = try store.saveWorkLog(WorkLog(brandId: b.id, taskId: t.id, title: "AI taslağı", performed: "Yapıldı", actor: .ai),
                                          inputSourceIds: [], outputSourceIds: [], actor: .ai)
        #expect(throws: MarkaError.self) {
            try store.saveUserWorkLog(aiLog, inputSourceIds: [], outputSourceIds: [], verifiedBy: "Danışman")
        }
        let stored = try store.workLogDetail(aiLog.id).log
        #expect(stored.status == .draft)
        #expect(stored.actor == .ai)
    }
}
