import Foundation
import Testing
@testable import MarkaCore

/// 0.2.1 U6: Bugün özeti ve arama — salt okunur, marka yalıtımlı, arşivlenmiş markalar hariç.
@Suite struct BugunTests {
    func gorevOnerisi(_ title: String) -> SuggestionDraft {
        SuggestionDraft(kind: .createTask, summary: "Yeni görev: " + title, payload: ProposalPayload.CreateTask(title: title))
    }

    /// Kaynağa bağlı iş kaydı; `verify` ise doğrulanır.
    @discardableResult
    func isKaydi(_ store: Store, _ brandId: String, _ title: String, verify: Bool, at: Date = Date()) throws -> WorkLog {
        let src = try store.addTextSource(brandId: brandId, kind: .note, title: "Dayanak " + title, body: "Not", capturedAt: at)
        let log = try store.saveWorkLog(WorkLog(brandId: brandId, title: title, performed: "Yapıldı", occurredAt: at),
                                        inputSourceIds: [src.id], outputSourceIds: [])
        if verify { try store.verifyWorkLog(log.id, verifiedBy: "Danışman") }
        return log
    }

    func dun() -> String { DayString.from(Date().addingTimeInterval(-86400 * 2)) }

    @Test func bugunOzetiMarkaBasinaSayarYalitirVeArsivliMarkayiAtlar() throws {
        let store = try makeStore()
        let a = try store.createBrand(name: "Beta")
        let b = try store.createBrand(name: "Alfa")
        let c = try store.createBrand(name: "Arşivli")

        // A: 2 terminal önerisi + 1 uygulama içi öneri; 1 biten görev, 1 geciken; 2 iş kaydı (1 doğrulanmadı) + 1 geri çekilen;
        // 1 dosya + (iş kayıtlarının 3 dayanak notu) ; 1 açık, 1 kapalı "Karar bekleniyor".
        try store.ingestSuggestionFile(brandId: a.id, fileName: "g.json", sha256: "s1", drafts: [gorevOnerisi("Bir"), gorevOnerisi("İki")])
        try store.createProposal(sessionId: nil, brandId: a.id, kind: .createTask, summary: "Sohbetten",
                                 payload: ProposalPayload.CreateTask(title: "Sohbetten görev"))
        let bitti = try store.saveTask(WorkTask(brandId: a.id, title: "Bitti"))
        try store.setTaskStatus(bitti.id, .done)
        try store.saveTask(WorkTask(brandId: a.id, title: "Geciken A", dueDate: dun()))
        try isKaydi(store, a.id, "Doğrulanan", verify: true)
        try isKaydi(store, a.id, "Bekleyen", verify: false)
        let geri = try isKaydi(store, a.id, "Geri çekilen", verify: false)
        try store.retractWorkLog(geri.id)
        try store.addTextSource(brandId: a.id, kind: .file, title: "Sunum.pdf", body: "Sunum metni")
        try store.saveRecord(BrandRecord(brandId: a.id, kind: .decision, title: "Bütçe onayı"))
        try store.saveRecord(BrandRecord(brandId: a.id, kind: .decision, title: "Kapanan karar", status: .done))
        try store.saveRecord(BrandRecord(brandId: a.id, kind: .promise, title: "Söz karar değildir"))

        // B: yalnız bir geciken görev ve bir bilgi güncellemesi.
        try store.saveTask(WorkTask(brandId: b.id, title: "Geciken B", dueDate: dun()))
        try store.writeWikiRevision(brandId: b.id, pageId: nil, kind: .person, title: "Ayşe", body: "Müdür", claims: [], actor: .ai)

        // C (arşivli): her şeyden biraz; hiçbir bölümde görünmemeli.
        try store.ingestSuggestionFile(brandId: c.id, fileName: "c.json", sha256: "s3", drafts: [gorevOnerisi("Arşiv")])
        try store.saveTask(WorkTask(brandId: c.id, title: "Geciken C", dueDate: dun()))
        try isKaydi(store, c.id, "Arşivli iş", verify: true)
        try store.saveRecord(BrandRecord(brandId: c.id, kind: .decision, title: "Arşivli karar"))
        try store.setBrandArchived(c.id, archived: true)

        let t = try store.today()
        #expect(t.pending == [TodaySummary.Pending(brandId: b.id, terminal: 0, other: 1),
                              TodaySummary.Pending(brandId: a.id, terminal: 2, other: 1)])
        #expect(Set(t.overdue.map(\.text)) == ["Geciken A", "Geciken B"])
        #expect(t.overdue.first { $0.text == "Geciken A" }?.brandId == a.id)
        let weekA = try #require(t.week.first { $0.brandId == a.id })
        #expect(weekA.tasksDone == 1)
        #expect(weekA.workLogs == 2)
        #expect(weekA.unverified == 1)
        #expect(weekA.files == 1)
        #expect(weekA.notes == 3)
        #expect(!t.week.contains { $0.brandId == b.id })
        #expect(t.awaiting.map(\.brandId) == [a.id])
        #expect(t.awaiting.first?.titles == ["Bütçe onayı"])
        for id in t.pending.map(\.brandId) + t.overdue.compactMap(\.brandId) + t.week.map(\.brandId) + t.awaiting.map(\.brandId) {
            #expect(id != c.id)
        }
    }

    @Test func bugunAramasiGorevIsKaydiKayitVeDosyadaBulurArsivliMarkayiAtlar() throws {
        let store = try makeStore()
        let a = try store.createBrand(name: "A")
        let c = try store.createBrand(name: "C")
        try store.saveTask(WorkTask(brandId: a.id, title: "Teklif hazırla"))
        try isKaydi(store, a.id, "Teklif gönderildi", verify: false)
        try store.saveRecord(BrandRecord(brandId: a.id, kind: .decision, title: "Teklif onayı"))
        try store.addTextSource(brandId: a.id, kind: .meeting, title: "Görüşme", body: "Müşteri TEKLİF istedi")
        try store.saveTask(WorkTask(brandId: c.id, title: "Teklif arşivde"))
        try store.setBrandArchived(c.id, archived: true)

        let hits = try store.searchToday("teklıf")
        #expect(Set(hits.map(\.ref.kind)) == [.task, .workLog, .brandRecord, .source])
        #expect(hits.allSatisfy { $0.brandId == a.id })
        #expect(!hits.contains { $0.title == "Teklif arşivde" })
        #expect(try store.searchToday("  ").isEmpty)
    }
}
