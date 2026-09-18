import Foundation
import Testing
@testable import MarkaCore

/// 0.2.1 U5: Rapor ekranının önizlemesi — canlı içerik mi kayıtlı sürüm mü, sürümden sonra değişen iş kayıtları,
/// dönem aralıkları ve boş bölümlerin sunumdan atılması. Salt okunur sorgular; yazma çekirdeğin rapor yollarıyla.
@Suite struct RaporOnizlemeTests {
    /// Kaynağa bağlı iş kaydı; `verify` ise doğrulanır.
    @discardableResult
    func isKaydi(_ store: Store, _ brandId: String, _ title: String, verify: Bool, at: Date = Date()) throws -> WorkLog {
        let src = try store.addTextSource(brandId: brandId, kind: .note, title: "Dayanak " + title, body: "Not", capturedAt: at)
        let log = try store.saveWorkLog(WorkLog(brandId: brandId, title: title, performed: "Yapıldı", occurredAt: at),
                                        inputSourceIds: [src.id], outputSourceIds: [])
        if verify { try store.verifyWorkLog(log.id, verifiedBy: "Danışman") }
        return log
    }

    @Test func donemAraliklariBuVeGecenHaftaAyi() throws {
        let cal = StatusService.turkishCalendar
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 10))!  // Cuma
        let thisWeek = ReportRange.thisWeek.interval(now: now)
        #expect(cal.component(.day, from: thisWeek.start) == 14)
        #expect(ReportRange.lastWeek.interval(now: now).end == thisWeek.start)
        #expect(cal.component(.day, from: ReportRange.lastWeek.interval(now: now).start) == 7)
        let lastMonth = ReportRange.lastMonth.interval(now: now)
        #expect(cal.component(.month, from: lastMonth.start) == 8)
        #expect(lastMonth.end == ReportRange.thisMonth.interval(now: now).start)
        #expect(ReportRange.lastMonth.period == .monthly && ReportRange.lastWeek.period == .weekly)
    }

    @Test func kayitlardanOlusanSurumCanliOnizlemeyiDegistirmezVeYenidenKullanilir() throws {
        let store = try makeStore()
        let a = try store.createBrand(name: "A")
        let b = try store.createBrand(name: "B")
        let now = Date()
        let interval = ReportRange.thisWeek.interval(now: now)
        try isKaydi(store, a.id, "İlk iş", verify: true, at: now)
        try isKaydi(store, a.id, "Taslak iş", verify: false, at: now)
        try isKaydi(store, b.id, "Başka marka", verify: false, at: now)

        var p = try store.reportPreview(brandId: a.id, period: .weekly, interval: interval)
        #expect(p.report == nil && !p.showsSaved && !p.isEmpty)
        #expect(p.unverifiedWorkLogs == 1)
        #expect(p.content.section(.completedWork)?.items.map(\.text) == ["İlk iş: Yapıldı"])

        // İlk PDF anı: kayıtlardan taslak. Önizleme canlı kalır, aynı içerik için sürüm yeniden kullanılır.
        let (_, v1) = try store.createReportDraft(brandId: a.id, period: .weekly, interval: interval, content: p.live)
        p = try store.reportPreview(brandId: a.id, period: .weekly, interval: interval)
        #expect(!p.showsSaved)
        #expect(p.reusableVersion?.id == v1.id)

        // Yeni doğrulanan iş kaydı canlı önizlemeye girer; eski sürüm artık yeniden kullanılmaz.
        try isKaydi(store, a.id, "İkinci iş", verify: true, at: now)
        p = try store.reportPreview(brandId: a.id, period: .weekly, interval: interval)
        #expect(!p.showsSaved)
        #expect(p.content.section(.completedWork)?.items.count == 2)
        #expect(p.reusableVersion == nil)
    }

    @Test func duzenlenenVeOnaylananSurumGosterilirSonradanDegisenIsKaydiSayilir() throws {
        let store = try makeStore()
        let a = try store.createBrand(name: "A")
        let now = Date()
        let interval = ReportRange.thisWeek.interval(now: now)
        let ilk = try isKaydi(store, a.id, "İlk iş", verify: true, at: now)
        var p = try store.reportPreview(brandId: a.id, period: .weekly, interval: interval)
        let (report, _) = try store.createReportDraft(brandId: a.id, period: .weekly, interval: interval, content: p.live)
        var edited = p.live
        edited.intro = "Merhaba"
        edited.sections[0].items[0].text = "Düzeltilmiş madde"
        edited.sections[0].items[0].edited = true
        let v2 = try store.saveReportVersion(reportId: report.id, content: edited, note: "Düzenlendi")

        p = try store.reportPreview(brandId: a.id, period: .weekly, interval: interval)
        #expect(p.showsSaved && !p.isApproved)
        #expect(p.content.intro == "Merhaba")
        #expect(p.reusableVersion?.id == v2.id)
        #expect(p.changedWorkLogs == 0)

        try store.approveReport(reportId: report.id, versionId: v2.id)
        p = try store.reportPreview(brandId: a.id, period: .weekly, interval: interval)
        #expect(p.isApproved)

        // Sürümden sonra: yeni doğrulanan bir iş kaydı + sürümdeki kaydın geri çekilmesi = 2 değişiklik.
        try isKaydi(store, a.id, "Sonra gelen", verify: true, at: now)
        try store.retractWorkLog(ilk.id)
        p = try store.reportPreview(brandId: a.id, period: .weekly, interval: interval)
        #expect(p.showsSaved)
        #expect(p.changedWorkLogs == 2)
    }

    @Test func dogrulanmisIsKaydiYoksaDonemBosVeBosBolumlerSunumdanAtilir() throws {
        let store = try makeStore()
        let a = try store.createBrand(name: "A")
        let now = Date()
        let interval = ReportRange.thisWeek.interval(now: now)
        try store.saveTask(WorkTask(brandId: a.id, title: "Sıradaki", priority: 2))
        var p = try store.reportPreview(brandId: a.id, period: .weekly, interval: interval)
        #expect(p.isEmpty)

        try isKaydi(store, a.id, "İş", verify: true, at: now)
        p = try store.reportPreview(brandId: a.id, period: .weekly, interval: interval)
        #expect(!p.isEmpty)
        let shown = p.content.withoutEmptySections
        #expect(shown.sections.map(\.kind) == [.completedWork, .nextSteps])
        #expect(shown.section(.completedWork)?.items == p.content.section(.completedWork)?.items)
    }
}
