import Foundation
import Testing
@testable import MarkaCore

/// H3-10 (U-18 + U-51 + K-22): ekrandaki sayıların tek tanımı (`CountDefinitions`). Bant sayısı süzgeç sonucuna eşit,
/// "bu hafta biten görev" iş kaydı bağlı görevleri de sayar, haftalık kutucuk birim karıştırmaz.
@Suite struct SayiTutarliligiTests {
    private let takvim = StatusService.turkishCalendar

    private func gorev(_ durum: TaskStatus, _ ad: String = "Görev") -> TodoItem {
        TodoItem(kind: .task(durum), entityId: newID(), title: ad, dueDate: nil, createdAt: Date())
    }

    private func kayit(_ tur: BrandRecordKind, _ durum: RecordStatus = .open) -> TodoItem {
        TodoItem(kind: .record(tur, durum), entityId: newID(), title: "Kayıt", dueDate: nil, createdAt: Date())
    }

    // MARK: Bant = süzgeç

    @Test func bekleyenBantSayisiBekliyorSuzgecininSonucSayisinaEsittir() {
        let liste = [gorev(.todo), gorev(.waiting), gorev(.waiting), gorev(.inProgress), kayit(.decision), kayit(.promise)]
        let sonuc = TodoStageFilter.waiting.apply(liste)
        #expect(CountDefinitions.waitingBandCount(liste) == sonuc.count)
        // Eski hata (U-18): bant yalnız kararları sayıyordu (1), süzgeç 3 satır gösteriyordu.
        #expect(sonuc.count == 3)
    }

    @Test func bekleyenTanimiBekliyorGorevleriVeAcikKararlariKapsar() {
        #expect(gorev(.waiting).stage == .waiting)
        #expect(kayit(.decision).stage == .waiting)
        #expect(kayit(.decision, .done).stage == .waiting)
        #expect(gorev(.todo).stage == .todo)
        #expect(gorev(.inProgress).stage == .doing)
        #expect(kayit(.promise).stage == .todo)
        #expect(kayit(.promise, .done).stage == .done)
    }

    @Test func azOnceTamamlananSatirDurumSuzgecindeGorunmezYalnizTumdeGorunur() {
        let biten = gorev(.waiting)
        let liste = [biten, gorev(.waiting)]
        #expect(TodoStageFilter.waiting.apply(liste, doneIds: [biten.id]).count == 1)
        #expect(TodoStageFilter.all.apply(liste, doneIds: [biten.id]).count == 2)
    }

    @Test func herSuzgecinSonucuKendiAsamasindakiSatirSayisidir() {
        let liste = [gorev(.todo), gorev(.todo), gorev(.inProgress), gorev(.waiting), kayit(.decision), kayit(.request)]
        #expect(TodoStageFilter.todo.apply(liste).count == 3)
        #expect(TodoStageFilter.doing.apply(liste).count == 1)
        #expect(TodoStageFilter.waiting.apply(liste).count == 2)
        #expect(TodoStageFilter.all.apply(liste).count == liste.count)
    }

    @Test func gercekMarkadaBantSayisiStoreTodoUzerindeSuzgecleAyniSonucuVerir() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Kuzey Lojistik")
        _ = try store.saveTask(WorkTask(brandId: b.id, title: "Sözleşme yanıtı", status: .waiting))
        _ = try store.saveTask(WorkTask(brandId: b.id, title: "Logo onayı", status: .waiting))
        _ = try store.saveTask(WorkTask(brandId: b.id, title: "Sunum", status: .inProgress))
        _ = try store.saveTask(WorkTask(brandId: b.id, title: "Bülten"))
        try store.saveRecord(BrandRecord(brandId: b.id, kind: .decision, title: "Bütçe onayı"))
        let acik = try store.todo(brandId: b.id)
        let bant = CountDefinitions.waitingBandCount(acik)
        #expect(bant == TodoStageFilter.waiting.apply(acik).count)
        #expect(bant == 3)
    }

    // MARK: Bu hafta biten görev

    @Test func haftaBitenTanimiHaftaBasiDahilSonuHaricBitenGorevdir() {
        let simdi = Date()
        let hafta = CountDefinitions.week(containing: simdi, calendar: takvim)
        let bas = WorkTask(brandId: "b", title: "a", status: .done, completedAt: hafta.start)
        let son = WorkTask(brandId: "b", title: "b", status: .done, completedAt: hafta.end)
        let onceki = WorkTask(brandId: "b", title: "c", status: .done, completedAt: hafta.start.addingTimeInterval(-1))
        let acik = WorkTask(brandId: "b", title: "d", status: .waiting, completedAt: simdi)
        let tarihsiz = WorkTask(brandId: "b", title: "e", status: .done)
        #expect(CountDefinitions.isDoneInWeek(bas, week: hafta))
        #expect(!CountDefinitions.isDoneInWeek(son, week: hafta))
        #expect(!CountDefinitions.isDoneInWeek(onceki, week: hafta))
        #expect(!CountDefinitions.isDoneInWeek(acik, week: hafta))
        #expect(!CountDefinitions.isDoneInWeek(tarihsiz, week: hafta))
        #expect(CountDefinitions.doneInWeekCount([bas, son, onceki, acik, tarihsiz], week: hafta) == 1)
    }

    @Test func haftaBitenGorevIsKaydiBagliGoreviDeSayarOzetVeBugunAyniSayiyiVerir() throws {
        let store = try makeStore()
        let now = Date()
        let b = try store.createBrand(name: "Deneme Yangın")
        var kayitli = try store.saveTask(WorkTask(brandId: b.id, title: "Bayi listesi"))
        try store.setTaskStatus(kayitli.id, .done)
        kayitli = try #require(try store.tasks(brandId: b.id).first { $0.id == kayitli.id })
        var taslak = WorkLog.draft(for: kayitli, now: now)
        taslak.performed = "Liste güncellendi."
        try store.saveUserWorkLog(taslak, inputSourceIds: [], outputSourceIds: [], verifiedBy: "Danışman")
        let kayitsiz = try store.saveTask(WorkTask(brandId: b.id, title: "Afiş"))
        try store.setTaskStatus(kayitsiz.id, .done)

        let hafta = CountDefinitions.week(containing: now, calendar: takvim)
        let saf = CountDefinitions.doneInWeekCount(try store.tasks(brandId: b.id), week: hafta)
        let ozet = try store.completedTaskCount(brandId: b.id, week: hafta)
        let bugun = CountDefinitions.weekDoneTaskTotal(try store.today(now: now, calendar: takvim).week.filter { $0.brandId == b.id })
        #expect(saf == 2)
        #expect(ozet == saf)
        #expect(bugun == saf)
    }

    // MARK: Birim

    @Test func haftalikKutucukYalnizBitenGorevleriToplarBirimKaristirmaz() {
        let haftalar = [TodaySummary.Week(brandId: "a", tasksDone: 2, workLogs: 8, unverified: 1, files: 15, notes: 3),
                        TodaySummary.Week(brandId: "b", tasksDone: 1, workLogs: 6, unverified: 0, files: 11, notes: 2)]
        // Eski "68" benzeri toplam (2+8+15+3+1+6+11+2 = 48) değil, yalnız görev: 3.
        #expect(CountDefinitions.weekDoneTaskTotal(haftalar) == 3)
    }

    @Test func haftalikDokumHerParcayiKendiBirimiyleVerirSifirlariAtlar() {
        let w = TodaySummary.Week(brandId: "a", tasksDone: 0, workLogs: 4, unverified: 0, files: 0, notes: 2)
        let parcalar = CountDefinitions.weekParts(w)
        #expect(parcalar == [CountDefinitions.WeekPart(unit: .workLog, count: 4), CountDefinitions.WeekPart(unit: .note, count: 2)])
        #expect(Set(parcalar.map(\.unit)).count == parcalar.count)
    }
}
