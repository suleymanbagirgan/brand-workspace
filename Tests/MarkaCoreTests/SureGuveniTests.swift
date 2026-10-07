import Foundation
import GRDB
import Testing
@testable import MarkaCore

/// H1-03 Süre güveni (U-01 + U-03): faturalık süre kayıtları sessizce kaybolmaz; yanlış kayıt düzeltilebilir.
@Suite struct SureGuveniTests {
    private func timeEntryCount(_ store: Store, taskId: String) throws -> Int {
        try store.read { db in try TimeEntry.filter(Column("taskId") == taskId).fetchCount(db) }
    }

    @Test func sureKaydiOlanGorevSilinceSureKayitlariKaybolmaz() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Deneme Yangın")
        let t = try store.saveTask(WorkTask(brandId: b.id, title: "Katalog"))
        try store.addManualTime(taskId: t.id, seconds: 2 * 3600 + 15 * 60)
        try? store.deleteTask(t.id)
        #expect(try timeEntryCount(store, taskId: t.id) == 1)
        #expect(try store.read { db in try WorkTask.fetchOne(db, key: t.id) } != nil)
        // Engel çekirdekte: hata, iptal etmeyi önerir ve süreyi "N sa M dk" diye söyler.
        #expect(throws: MarkaError.validation(LF("Bu görevde süre kaydı var; silinirse süreler de kaybolur. Görevi iptal et, süre kayıtları korunur. Süre: %@",
                                                 "2 sa 15 dk"))) { try store.deleteTask(t.id) }
        #expect(try store.taskTimeSummary(taskId: t.id, brandId: b.id) == TaskTimeSummary(count: 1, seconds: 8100))
        // İptal yolu açık; süre kayıtları kalır, rapordaki toplam değişmez.
        try store.setTaskStatus(t.id, .cancelled)
        #expect(try timeEntryCount(store, taskId: t.id) == 1)
        #expect(try store.task(t.id).timeSpentSeconds == 8100)
        // Süre kaydı olmayan görev eskisi gibi silinir ve denetim bırakır.
        let bos = try store.saveTask(WorkTask(brandId: b.id, title: "Yanlış açılan"))
        try store.deleteTask(bos.id)
        #expect(try store.auditTrail(entity: "task", entityId: bos.id).first?.action == "delete")
        // Çalışan sayaç da süre kaydıdır: o görev de silinmez.
        let calisan = try store.saveTask(WorkTask(brandId: b.id, title: "Sayaçlı"))
        try store.startTimer(taskId: calisan.id)
        #expect(throws: MarkaError.self) { try store.deleteTask(calisan.id) }
    }

    @Test func sureKaydiGorevPanelindenEklenirDuzenlenirSilinirVeHerYazmaDenetimBirakir() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Kuzey Lojistik")
        let t = try store.saveTask(WorkTask(brandId: b.id, title: "Sevkiyat raporu"))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        // Unutulan çalışma elle eklenir.
        let e = try store.addTimeEntry(taskId: t.id, brandId: b.id, startedAt: now.addingTimeInterval(-3 * 3600),
                                       endedAt: now.addingTimeInterval(-3600), note: "  Toplantı ", now: now)
        #expect(e.seconds == 7200 && e.note == "Toplantı")
        #expect(try store.task(t.id).timeSpentSeconds == 7200)
        #expect(try store.timeEntries(taskId: t.id, brandId: b.id).map(\.id) == [e.id])
        // 14 saat yazan kayıt 1 saate düzeltilir; görevdeki toplam da düzelir.
        let fixed = try store.updateTimeEntry(e.id, brandId: b.id, startedAt: e.startedAt,
                                              endedAt: e.startedAt.addingTimeInterval(3600), note: "Toplantı", now: now)
        #expect(fixed.seconds == 3600)
        #expect(try store.task(t.id).timeSpentSeconds == 3600)
        try store.deleteTimeEntry(e.id, brandId: b.id)
        #expect(try store.task(t.id).timeSpentSeconds == 0)
        #expect(try store.timeEntries(taskId: t.id, brandId: b.id).isEmpty)
        let actions = try store.auditTrail(entity: "timeEntry", entityId: e.id).map(\.action)
        #expect(Set(actions) == ["create", "update", "delete"] && actions.count == 3)
        #expect(try store.auditTrail(entity: "timeEntry", entityId: e.id).allSatisfy { $0.brandId == b.id && $0.actor == .user })
        // Çalışan sayaç düzenlenmez ve silinmez; önce durdurulur.
        let running = try store.startTimer(taskId: t.id)
        #expect(throws: MarkaError.self) { try store.deleteTimeEntry(running.id, brandId: b.id) }
        #expect(throws: MarkaError.self) {
            try store.updateTimeEntry(running.id, brandId: b.id, startedAt: running.startedAt,
                                      endedAt: running.startedAt.addingTimeInterval(60), note: "")
        }
    }

    @Test func sureKaydiNegatifGelecekVeUstUsteBinenAraligiReddeder() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Örnek Kafe Zinciri")
        let t = try store.saveTask(WorkTask(brandId: b.id, title: "Menü"))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let h = 3600.0
        func add(_ s: Double, _ e: Double) throws {
            try store.addTimeEntry(taskId: t.id, brandId: b.id, startedAt: now.addingTimeInterval(s),
                                   endedAt: now.addingTimeInterval(e), now: now)
        }
        // Negatif ve sıfır süre.
        #expect(throws: MarkaError.validation(L("Bitiş, başlangıçtan sonra olmalı."))) { try add(-h, -2 * h) }
        #expect(throws: MarkaError.validation(L("Bitiş, başlangıçtan sonra olmalı."))) { try add(-h, -h) }
        // Gelecekte biten (1 dk tolerans dışı) ve 24 saati aşan.
        #expect(throws: MarkaError.validation(L("Süre kaydı gelecekte bitemez."))) { try add(-h, 10 * 60) }
        #expect(throws: MarkaError.validation(L("Süre 1 sn ile 24 saat arasında olmalı."))) { try add(-30 * h, -5 * h) }
        // Üst üste binen reddedilir; uç uca gelen kabul edilir.
        try add(-5 * h, -3 * h)
        #expect(throws: MarkaError.validation(L("Bu aralık başka bir süre kaydıyla çakışıyor."))) { try add(-4 * h, -2 * h) }
        try add(-3 * h, -2 * h)
        // Düzenleme de aynı kurallara bağlı; kendisiyle çakışma sayılmaz.
        let entries = try store.timeEntries(taskId: t.id, brandId: b.id)
        #expect(entries.count == 2)
        let last = entries[0]
        #expect(throws: MarkaError.validation(L("Bu aralık başka bir süre kaydıyla çakışıyor."))) {
            try store.updateTimeEntry(last.id, brandId: b.id, startedAt: now.addingTimeInterval(-4 * h),
                                      endedAt: last.endedAt!, note: "", now: now)
        }
        try store.updateTimeEntry(last.id, brandId: b.id, startedAt: last.startedAt.addingTimeInterval(600),
                                  endedAt: last.endedAt!, note: "", now: now)
        #expect(try store.task(t.id).timeSpentSeconds == 2 * 3600 + 3000)
    }

    @Test func sureKaydiBaskaMarkaninKimligiyleOkunamazVeDegistirilemez() throws {
        let store = try makeStore()
        let a = try store.createBrand(name: "Deneme Yangın")
        let other = try store.createBrand(name: "Kuzey Lojistik")
        let t = try store.saveTask(WorkTask(brandId: a.id, title: "Bakım"))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let e = try store.addTimeEntry(taskId: t.id, brandId: a.id, startedAt: now.addingTimeInterval(-3600), endedAt: now, now: now)
        #expect(throws: MarkaError.brandScope) { try store.timeEntries(taskId: t.id, brandId: other.id) }
        #expect(throws: MarkaError.brandScope) { try store.taskTimeSummary(taskId: t.id, brandId: other.id) }
        #expect(throws: MarkaError.brandScope) {
            try store.addTimeEntry(taskId: t.id, brandId: other.id, startedAt: now.addingTimeInterval(-7200),
                                   endedAt: now.addingTimeInterval(-3600), now: now)
        }
        #expect(throws: MarkaError.brandScope) {
            try store.updateTimeEntry(e.id, brandId: other.id, startedAt: e.startedAt, endedAt: now, note: "x", now: now)
        }
        #expect(throws: MarkaError.brandScope) { try store.deleteTimeEntry(e.id, brandId: other.id) }
        // Başka markanın kaydı çakışma denetimine de girmez (yalıtım): aynı aralık diğer markada serbest.
        let ot = try store.saveTask(WorkTask(brandId: other.id, title: "Rota"))
        try store.addTimeEntry(taskId: ot.id, brandId: other.id, startedAt: e.startedAt, endedAt: now, now: now)
        #expect(try store.timeEntries(taskId: t.id, brandId: a.id).map(\.id) == [e.id])
    }

    @Test func sekizSaattenUzunAcikSayacIcinUyariKarariCekirdekteVerilir() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Deneme Yangın")
        let t = try store.saveTask(WorkTask(brandId: b.id, title: "Teklif"))
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let running = try store.startTimer(taskId: t.id, at: start)
        #expect(!running.isLongRunning(now: start.addingTimeInterval(8 * 3600)))
        #expect(try store.longRunningTimer(now: start.addingTimeInterval(8 * 3600)) == nil)
        #expect(running.isLongRunning(now: start.addingTimeInterval(8 * 3600 + 1)))
        #expect(try store.longRunningTimer(now: start.addingTimeInterval(14 * 3600))?.id == running.id)
        // Durmuş kayıt ne kadar uzun olursa olsun uyarı değildir.
        let stopped = try store.stopTimer(at: start.addingTimeInterval(14 * 3600))
        #expect(stopped?.isLongRunning(now: start.addingTimeInterval(20 * 3600)) == false)
        #expect(try store.longRunningTimer(now: start.addingTimeInterval(20 * 3600)) == nil)
    }
}
