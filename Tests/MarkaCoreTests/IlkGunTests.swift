import Foundation
import GRDB
import Testing
@testable import MarkaCore

/// D2: Masa'da ilk gün çıkmazı. D3: görevden çalışma kaydına yol.
@Suite struct IlkGunTests {
    @Test func yalnizcaKaynakVarkenSiradakiAdimGorevVeyaSozEklemeyiIster() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Deneme Mobilya")
        let service = StatusService(store: store)
        #expect(try service.brandStatus(brandId: b.id).nextStep.reason == .addFirstSource)
        try store.addTextSource(brandId: b.id, kind: .meeting, title: "18 Eylül görüşmesi", body: "Teklif istendi.")
        let s = try service.brandStatus(brandId: b.id)
        #expect(s.nextStep.reason == .nothingOpen)
        #expect(s.nextStep.ref == nil)
        #expect(!s.isEmpty)
        // Söz eklenince sıradaki adım bir kayda bağlanır.
        try store.saveRecord(BrandRecord(brandId: b.id, kind: .promise, title: "Teklif gönderilecek", dueDate: DayString.from(Date())))
        #expect(try service.brandStatus(brandId: b.id).nextStep.reason == .promiseDueSoon)
    }

    @Test func musteriTalebiKaynagiIsteneAcikTalepKaydiniTekIslemdeOlusturur() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Deneme Mobilya")
        let s = try store.addTextSource(brandId: b.id, kind: .clientRequest, title: "E-posta: katalog talebi",
                                        body: "Yeni katalog PDF'i istendi.", openRequest: true)
        let requests = try store.records(brandId: b.id, kinds: [.request])
        #expect(requests.count == 1)
        let r = try #require(requests.first)
        #expect(r.sourceId == s.id)
        #expect(r.title == "E-posta: katalog talebi")
        #expect(r.status == .open && r.isOpen)
        // Her iki yazma denetim olayı bırakır.
        #expect(try store.auditTrail(entity: "source", entityId: s.id).map(\.action) == ["create"])
        #expect(try store.auditTrail(entity: "brandRecord", entityId: r.id).map(\.action) == ["create"])
        // Masa: açık talep görünür ve sıradaki adım talebe bağlanır (artık "açık iş yok" değil).
        let status = try StatusService(store: store).brandStatus(brandId: b.id)
        #expect(status.openRequests.count == 1)
        #expect(status.nextStep.reason == .openRequest)
        #expect(status.nextStep.ref == RecordRef(.brandRecord, r.id))
    }

    @Test func acikTalepIstenmezseYalnizcaKaynakEklenir() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "M")
        try store.addTextSource(brandId: b.id, kind: .clientRequest, title: "Talep", body: "metin")
        #expect(try store.records(brandId: b.id).isEmpty)
        #expect(try store.sources(brandId: b.id).count == 1)
    }

    @Test func musteriTalebiDisindakiTurdeAcikTalepIstenirseHicbirSeyYazilmaz() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "M")
        #expect(throws: MarkaError.self) {
            try store.addTextSource(brandId: b.id, kind: .meeting, title: "Görüşme", body: "metin", openRequest: true)
        }
        #expect(try store.sources(brandId: b.id).isEmpty)
        #expect(try store.records(brandId: b.id).isEmpty)
    }

    @Test func talepKaydiYazilamazsaKaynakDaGeriAlinir() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "M")
        // Talep kaydı eklemeyi SQL düzeyinde engelle: işlem bütünse kaynak da kalmamalı.
        try store.writer.write { db in
            try db.execute(sql: "CREATE TRIGGER test_talep_engeli BEFORE INSERT ON brandRecord BEGIN SELECT RAISE(ABORT, 'engel'); END")
        }
        #expect(throws: (any Error).self) {
            try store.addTextSource(brandId: b.id, kind: .clientRequest, title: "Talep", body: "metin", openRequest: true)
        }
        #expect(try store.sources(brandId: b.id).isEmpty)
        #expect(try store.read { db in try AuditEvent.fetchCount(db) } == 1, "yalnızca markanın oluşturulma olayı kalmalı")
    }

    @Test func calismaKaydiOnerisiKaydiOlmayanGorevIcinYapilir() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "M")
        let t = try store.saveTask(WorkTask(brandId: b.id, title: "Teklifi hazırla"))
        #expect(try store.needsWorkLog(taskId: t.id))
        let log = try store.saveWorkLog(WorkLog(brandId: b.id, taskId: t.id, title: "Teklif"), inputSourceIds: [], outputSourceIds: [])
        #expect(try !store.needsWorkLog(taskId: t.id))
        // Kayıt geri çekilirse yeniden önerilir.
        try store.writer.write { db in try db.execute(sql: "UPDATE workLog SET status = 'verified' WHERE id = ?", arguments: [log.id]) }
        try store.retractWorkLog(log.id)
        #expect(try store.needsWorkLog(taskId: t.id))
        // Silinmiş görev için öneri yapılmaz.
        try store.deleteTask(t.id)
        #expect(try !store.needsWorkLog(taskId: t.id))
    }

    @Test func gorevdenCalismaKaydiTaslagiTamamlanmaTarihiniVeGoreviTasir() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "M")
        var t = try store.saveTask(WorkTask(brandId: b.id, title: "Katalog"))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(WorkLog.draft(for: t, now: now).occurredAt == now)
        try store.setTaskStatus(t.id, .done)
        t = try store.task(t.id)
        let draft = WorkLog.draft(for: t, now: now)
        #expect(draft.taskId == t.id && draft.brandId == b.id && draft.title == "Katalog")
        #expect(draft.occurredAt == t.completedAt)
        #expect(draft.status == .draft)
    }
}
