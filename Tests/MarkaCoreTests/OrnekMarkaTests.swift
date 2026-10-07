import Foundation
import GRDB
import Testing
@testable import MarkaCore

/// Örnek marka (`Store.createSampleBrand`): ilk 5 dakikada yapay zekâsız değer. Tek, idempotent, yalıtımlı, izinsiz, denetimli.
@Suite struct OrnekMarkaTests {
    let calendar = StatusService.turkishCalendar

    @Test func ornekMarkaTekVeIdempotent() throws {
        let store = try makeStore()
        let first = try store.createSampleBrand()
        let second = try store.createSampleBrand()
        #expect(first.id == second.id)
        #expect(try store.brands().filter { $0.name == SampleWorkspace.brandName }.count == 1)
        #expect(try store.tasks(brandId: first.id).count == 8)
        #expect(try store.workLogs(brandId: first.id).count == 3)
    }

    @Test func ornekMarkaSampleBrandIdAyariylaIsaretlenir() throws {
        let store = try makeStore()
        #expect(try store.sampleBrandId() == nil)
        let sample = try store.createSampleBrand()
        #expect(try store.setting(SampleWorkspace.settingKey) == sample.id)
        #expect(try store.sampleBrandId() == sample.id)
        #expect(store.isSampleBrand(sample.id))
        let other = try store.createBrand(name: "Kuzey Lojistik")
        #expect(!store.isSampleBrand(other.id))
    }

    @Test func ornekMarkaBaskaMarkayaVeriSizdirmaz() throws {
        let store = try makeStore()
        let other = try store.createBrand(name: "Deneme Yangın")
        let sample = try store.createSampleBrand()
        #expect(try store.tasks(brandId: other.id).isEmpty)
        #expect(try store.workLogs(brandId: other.id).isEmpty)
        #expect(try store.sources(brandId: other.id).isEmpty)
        #expect(try store.records(brandId: other.id).isEmpty)
        #expect(try store.financeEntries(brandId: other.id).isEmpty)
        #expect(try store.projects(brandId: other.id).isEmpty)
        #expect(try store.profile(brandId: other.id).isEmpty)
        // Örnek markanın tüm kayıtları kendi kimliğini taşır; çapraz bağ yok.
        let ids = try store.read { db -> [String] in
            try String.fetchAll(db, sql: """
                SELECT brandId FROM workTask UNION ALL SELECT brandId FROM workLog UNION ALL SELECT brandId FROM source
                UNION ALL SELECT brandId FROM brandRecord UNION ALL SELECT brandId FROM financeEntry UNION ALL SELECT brandId FROM project
                """)
        }
        #expect(!ids.isEmpty && ids.allSatisfy { $0 == sample.id })
        for log in try store.workLogs(brandId: sample.id) {
            let d = try store.workLogDetail(log.id)
            #expect(d.task?.brandId == sample.id)
            #expect((d.inputs + d.outputs).allSatisfy { $0.brandId == sample.id })
        }
    }

    @Test func ornekMarkaninYapayZekaIzniYok() throws {
        let store = try makeStore()
        let sample = try store.createSampleBrand()
        let b = try store.brand(sample.id)
        #expect(b.allowedProviders.isEmpty)
        #expect(!b.allows(.anthropic) && !b.allows(.codex))
        #expect(!b.isOwn)
    }

    @Test func ucDogrulanmisKayitGoreveBagliVeDogrulamaKuralinaUyar() throws {
        let store = try makeStore()
        let sample = try store.createSampleBrand()
        let verified = try store.workLogs(brandId: sample.id, statuses: [.verified])
        #expect(verified.count >= 3)
        for log in verified {
            let d = try store.workLogDetail(log.id)
            #expect(d.verificationProblem == nil)
            #expect(d.task?.status == .done)
            #expect(log.verifiedBy == SampleWorkspace.verifier)
            #expect(log.verifiedAt != nil)
        }
    }

    @Test func raporOnizlemesiYapayZekasizEnAzUcMaddeUretir() throws {
        let store = try makeStore()
        let now = Date()
        let sample = try store.createSampleBrand(now: now)
        let interval = ReportRange.thisWeek.interval(now: now)
        let preview = try store.reportPreview(brandId: sample.id, period: .weekly, interval: interval, now: now)
        #expect(!preview.isEmpty)
        let completed = preview.content.section(.completedWork)?.items ?? []
        #expect(completed.count >= 3)
        // Her madde doğrulanmış iş kaydına dayanır; AI özeti yok, uyarı yok (biten görevlerin hepsinin kaydı var).
        #expect(completed.allSatisfy { item in item.refs.contains { $0.kind == .workLog } })
        #expect(preview.content.summary.isEmpty)
        #expect(preview.content.warnings.isEmpty)
        #expect(preview.unverifiedWorkLogs == 0)
        // Karar bekleyen kayıt "Müşteriden beklenen"de.
        #expect((preview.content.section(.awaitingClient)?.items.count ?? 0) == 1)
        // PDF de AI'sız üretilir.
        let pdf = ReportPDFRenderer(content: preview.content.withoutEmptySections, isDraft: true, versionNumber: 1,
                                    describe: { try? store.describe($0) }).render()
        #expect(pdf.count > 1000)
    }

    @Test func gecikmisVeBuHaftaBitenGorevVar() throws {
        let store = try makeStore()
        let now = Date()
        let sample = try store.createSampleBrand(now: now)
        let today = DayString.from(now, calendar: calendar)
        let week = calendar.dateInterval(of: .weekOfYear, for: now)!
        let lastDay = DayString.from(week.end.addingTimeInterval(-1), calendar: calendar)
        let tasks = try store.tasks(brandId: sample.id)
        #expect(tasks.contains { $0.isOverdue(today: today) })
        #expect(tasks.contains { t in t.status.isOpen && (t.dueDate.map { $0 >= today && $0 <= lastDay } ?? false) })
        #expect(Set(tasks.map(\.status)).isSuperset(of: [.todo, .inProgress, .waiting, .done]))
        #expect(try store.today(now: now).overdue.contains { $0.brandId == sample.id })
    }

    @Test func profilProjeHedefKararVeNotlarYazilir() throws {
        let store = try makeStore()
        let sample = try store.createSampleBrand()
        #expect(try store.profile(brandId: sample.id).count >= 5)
        #expect(try store.projects(brandId: sample.id).count == 2)
        #expect(try store.records(brandId: sample.id, kinds: [.goal]).count == 2)
        let decisions = try store.records(brandId: sample.id, kinds: [.decision])
        #expect(decisions.count == 1 && decisions[0].isOpen)
        let notes = try store.sources(brandId: sample.id, kinds: [.note, .meeting])
        #expect(notes.count == 2)
    }

    @Test func finansSatirlariIkiOdemeBirButce() throws {
        let store = try makeStore()
        let sample = try store.createSampleBrand()
        let payments = try store.financeEntries(brandId: sample.id, kind: .payment)
        let budgets = try store.financeEntries(brandId: sample.id, kind: .budget)
        #expect(payments.count == 2 && budgets.count == 1)
        #expect(payments.allSatisfy { $0.status != nil && ($0.amountMinor ?? 0) > 0 })
        #expect(budgets.allSatisfy { $0.status == nil })
    }

    @Test func herYazmaSistemAktoruyleDenetimIziBirakir() throws {
        let store = try makeStore()
        let sample = try store.createSampleBrand()
        let events = try store.read { db in try AuditEvent.filter(Column("brandId") == sample.id).fetchAll(db) }
        #expect(events.allSatisfy { $0.actor == .system })
        func count(_ entity: String, _ action: String? = nil) -> Int {
            events.filter { $0.entity == entity && (action == nil || $0.action == action) }.count
        }
        #expect(count("brand", "create") == 1)
        #expect(count("brandProfile") == 5)
        #expect(count("project") == 2)
        #expect(count("task") == 8)
        #expect(count("source") == 2)
        #expect(count("workLog", "create") == 3)
        #expect(count("workLog", "verify") == 3)
        #expect(count("brandRecord") == 3)
        #expect(count("financeEntry") == 3)
        // İdempotent çağrı yeni olay yazmaz.
        try store.createSampleBrand()
        let after = try store.read { db in try AuditEvent.filter(Column("brandId") == sample.id).fetchCount(db) }
        #expect(after == events.count)
    }

    @Test func arsivlenenOrnekMarkaBugundenCikarVeTekrarCagrilincaGeriGelir() throws {
        let store = try makeStore()
        let now = Date()
        let sample = try store.createSampleBrand(now: now)
        #expect(try store.today(now: now).overdue.contains { $0.brandId == sample.id })
        try store.setBrandArchived(sample.id, archived: true)
        let today = try store.today(now: now)
        #expect(!today.overdue.contains { $0.brandId == sample.id })
        #expect(!today.awaiting.contains { $0.brandId == sample.id })
        #expect(!today.week.contains { $0.brandId == sample.id })
        #expect(!(try store.brands()).contains { $0.id == sample.id })
        // İkinci örnek açılmaz; var olan arşivden çıkar.
        let again = try store.createSampleBrand(now: now)
        #expect(again.id == sample.id && again.status == .active)
        #expect(try store.brands(includeArchived: true).filter { $0.id == sample.id || $0.name.hasPrefix(SampleWorkspace.brandName) }.count == 1)
    }

    @Test func ayniAdliMarkaVarsaNumaraliAdlaAcilir() throws {
        let store = try makeStore()
        _ = try store.createBrand(name: "örnek marka")
        let sample = try store.createSampleBrand()
        #expect(sample.name == "Örnek Marka 2")
        #expect(try store.sampleBrandId() == sample.id)
    }

    @Test func yapayZekaCalismaKaydiniIslemIcindeDogrulayamaz() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Kuzey Lojistik")
        let t = try store.saveTask(WorkTask(brandId: b.id, title: "Görev"))
        let log = try store.saveWorkLog(WorkLog(brandId: b.id, taskId: t.id, title: "İş", performed: "Yapıldı"), inputSourceIds: [], outputSourceIds: [])
        #expect(throws: MarkaError.self) {
            try store.write { db in try store.verifyWorkLog(db, log.id, verifiedBy: "X", actor: .ai) }
        }
        #expect(try store.workLogDetail(log.id).log.status == .draft)
    }
}

@Suite struct BitenGorevSayisiTests {
    @Test func buHaftaBitenGorevIsKaydiBagliOlsunOlmasinSayilirBaskaMarkaSayilmaz() throws {
        let store = try makeStore()
        let a = try store.createBrand(name: "Deneme Yangın")
        let b = try store.createBrand(name: "Kuzey Lojistik")
        let now = Date()
        for (title, brand, done, at) in [("Yeni bitti", a.id, true, now), ("Eski bitti", a.id, true, now.addingTimeInterval(-40 * 86_400)),
                                          ("Açık", a.id, false, now), ("Başka marka", b.id, true, now)] {
            var t = WorkTask(brandId: brand, title: title)
            if done { t.status = .done; t.completedAt = at }
            try store.saveTask(t)
        }
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        #expect(try store.completedTaskCount(brandId: a.id, since: weekAgo) == 1)
        #expect(try store.completedTaskCount(brandId: b.id, since: weekAgo) == 1)
        #expect(try store.completedTaskCount(brandId: a.id, since: now.addingTimeInterval(-60 * 86_400)) == 2)
    }

    @Test func ornekMarkadaBuHaftaBitenGorevSayisiSifirDegildir() throws {
        let store = try makeStore()
        let sample = try store.createSampleBrand()
        let weekStart = StatusService.turkishCalendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        #expect(try store.completedTaskCount(brandId: sample.id, since: weekStart) >= 1)
    }
}

/// H3-12 (U-52 + T-18): örnek veride ASCII-only ad yok, kaynak saatleri çeşitli.
@Suite struct OrnekVeriAdVeSaatTests {
    @Test func ornekMarkaKaynakBasliklarindaYalnizAsciiOlanSayisiSifir() throws {
        let store = try makeStore()
        let sample = try store.createSampleBrand()
        let titles = try store.sources(brandId: sample.id).map(\.title)
        #expect(titles.count >= 2)
        let yalnizAscii = titles.filter { $0.unicodeScalars.allSatisfy(\.isASCII) }
        #expect(yalnizAscii.isEmpty, "Türkçe karakter beklenen başlıklar: \(yalnizAscii)")
    }

    @Test func ornekMarkaKaynakVeIsKayitlariEnAzUcFarkliSaattedir() throws {
        let store = try makeStore()
        let sample = try store.createSampleBrand()
        let cal = StatusService.turkishCalendar
        let units: Set<DateComponents> = Set(
            try store.sources(brandId: sample.id).map { $0.capturedAt }.map { cal.dateComponents([.year, .month, .day, .hour, .minute], from: $0) }
            + store.workLogs(brandId: sample.id).map { $0.occurredAt }.map { cal.dateComponents([.year, .month, .day, .hour, .minute], from: $0) })
        #expect(units.count >= 3)
        let sources = Set(try store.sources(brandId: sample.id).map { $0.capturedAt })
        #expect(sources.count == 2, "iki kaynak da farklı anda")
    }
}
