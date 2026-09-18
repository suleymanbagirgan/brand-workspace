import Foundation
import Testing
@testable import MarkaCore

/// 0.2.1 U3/U4: Akış (ne yapıldı) ve Yapılacaklar (ne bekliyor) birleşik sorguları. Salt okunur, marka kapsamlı.
@Suite struct AkisYapilacaklarTests {
    let now = Date()
    func ago(hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }
    func day(_ offset: Int) -> String { DayString.from(now.addingTimeInterval(Double(offset) * 86_400)) }

    // MARK: Akış

    @Test func akisEnYeniUstteVeTurleriDogruEsler() throws {
        let store = try makeStore()
        let a = try store.createBrand(name: "A")
        let note = try store.addTextSource(brandId: a.id, kind: .meeting, title: "Görüşme", body: "…", capturedAt: ago(hours: 72))
        let file = try store.addGeneratedOutput(brandId: a.id, fileName: "t.md", content: "# t", title: "Tablo", actor: .user)
        let log = try store.saveWorkLog(WorkLog(brandId: a.id, title: "Araştırma", performed: "Yapıldı", occurredAt: ago(hours: 5)),
                                        inputSourceIds: [note.id], outputSourceIds: [])
        var task = try store.saveTask(WorkTask(brandId: a.id, title: "Bitti görev"))
        task.status = .done
        task = try store.saveTask(task)
        try store.saveTask(WorkTask(brandId: a.id, title: "Açık görev"))
        var promise = try store.saveRecord(BrandRecord(brandId: a.id, kind: .promise, title: "Söz"))
        promise.status = .done
        promise = try store.saveRecord(promise)
        let decision = try store.saveRecord(BrandRecord(brandId: a.id, kind: .decision, title: "Karar"))
        let goal = try store.saveRecord(BrandRecord(brandId: a.id, kind: .goal, title: "Hedef"))
        let p = try store.createProposal(sessionId: nil, brandId: a.id, kind: .createBrandRecord, summary: "Talep önerisi",
                                         payload: ProposalPayload.CreateBrandRecord(kind: .request, title: "Önerilen talep"))
        try store.applyProposal(p.id)

        let items = try store.flow(brandId: a.id)
        #expect(zip(items, items.dropFirst()).allSatisfy { $0.date >= $1.date })
        func kinds(_ id: String) -> [FlowItem.Kind] { items.filter { $0.entityId == id }.map(\.kind) }
        #expect(kinds(log.id) == [.workLog(.draft)])
        #expect(kinds(task.id) == [.taskDone])
        #expect(kinds(note.id) == [.note])
        #expect(kinds(file.id) == [.file])
        #expect(kinds(promise.id) == [.recordClosed(.promise, .done)], "söz yalnız kapanınca Akış'ta (açılışı Yapılacaklar'da)")
        #expect(kinds(decision.id).isEmpty, "açık karar bekleniyor Akış'ta değil, Yapılacaklar'da")
        #expect(kinds(goal.id).isEmpty, "hedef Akış'ta görünmez")
        #expect(kinds(p.id) == [.proposalApplied(.createBrandRecord)])
        #expect(items.first { $0.entityId == p.id }?.title == "Önerilen talep")
        #expect(!items.contains { $0.title == "Açık görev" }, "açık görev Akış'ta değil")
        // Kimlikler tekil (aynı kaydın açılış ve kapanış satırı ayrı).
        #expect(Set(items.map(\.id)).count == items.count)
        // En eski öğe (3 gün önceki görüşme notu) en altta.
        #expect(items.last?.entityId == note.id)
    }

    /// 0.2.1 U9: iş kaydı bağlı biten görev Akış'ta tek satır (iş kaydı); iş kaydı olmayan biten görev "Görev bitti" satırıdır.
    @Test func isKaydiBagliBitenGorevAkistaTekSatirdir() throws {
        let store = try makeStore()
        let a = try store.createBrand(name: "A")
        let b = try store.createBrand(name: "B")
        let bagli = try store.saveTask(WorkTask(brandId: a.id, title: "Bağlı görev", status: .done))
        let yalniz = try store.saveTask(WorkTask(brandId: a.id, title: "Yalnız görev", status: .done))
        let log = try store.saveWorkLog(WorkLog(brandId: a.id, taskId: bagli.id, title: "Bağlı iş", performed: "x"),
                                        inputSourceIds: [], outputSourceIds: [])
        // Başka markanın iş kaydı bu markanın görevini gizlemez.
        let bTask = try store.saveTask(WorkTask(brandId: b.id, title: "B görevi", status: .done))
        try store.saveWorkLog(WorkLog(brandId: b.id, title: "B işi", performed: "x"), inputSourceIds: [], outputSourceIds: [])

        let items = try store.flow(brandId: a.id)
        #expect(!items.contains { $0.entityId == bagli.id }, "görev bitti satırı gizlenir")
        #expect(items.contains { $0.entityId == log.id && $0.kind == .workLog(.draft) })
        #expect(items.contains { $0.entityId == yalniz.id && $0.kind == .taskDone })
        #expect(try store.flow(brandId: b.id).contains { $0.entityId == bTask.id && $0.kind == .taskDone })
    }

    @Test func akisGunlereGoreGruplanirEnYeniGunUstte() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        let base = cal.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 12))!
        func at(_ dayOffset: Int, _ hour: Int) -> Date {
            cal.date(byAdding: .hour, value: hour - 12, to: cal.date(byAdding: .day, value: dayOffset, to: base)!)!
        }
        let items = [FlowItem(kind: .note, entityId: "1", title: "a", date: at(0, 23)),
                     FlowItem(kind: .file, entityId: "2", title: "b", date: at(0, 0)),
                     FlowItem(kind: .taskDone, entityId: "3", title: "c", date: at(-1, 23)),
                     FlowItem(kind: .workLog(.verified), entityId: "4", title: "d", date: at(-3, 9))]
            .sorted(by: FlowItem.newestFirst)
        let days = FlowItem.days(items, calendar: cal)
        #expect(days.map { $0.items.map(\.entityId) } == [["1", "2"], ["3"], ["4"]])
        #expect(days.map { cal.component(.day, from: $0.day) } == [18, 17, 15])
    }

    @Test func akisBaskaMarkaninOgesiniGetirmez() throws {
        let store = try makeStore()
        let a = try store.createBrand(name: "A")
        let b = try store.createBrand(name: "B")
        try store.addTextSource(brandId: a.id, kind: .note, title: "A notu", body: "x")
        let bNote = try store.addTextSource(brandId: b.id, kind: .note, title: "B notu", body: "x")
        let bLog = try store.saveWorkLog(WorkLog(brandId: b.id, title: "B işi"), inputSourceIds: [], outputSourceIds: [])
        var bTask = try store.saveTask(WorkTask(brandId: b.id, title: "B görevi"))
        bTask.status = .done
        try store.saveTask(bTask)
        let bRecord = try store.saveRecord(BrandRecord(brandId: b.id, kind: .promise, title: "B sözü"))
        let bp = try store.createProposal(sessionId: nil, brandId: b.id, kind: .createTask, summary: "B",
                                          payload: ProposalPayload.CreateTask(title: "B önerisi"))
        try store.applyProposal(bp.id)

        let items = try store.flow(brandId: a.id)
        #expect(items.map(\.title) == ["A notu"])
        let bIds: Set<String> = [bNote.id, bLog.id, bTask.id, bRecord.id, bp.id]
        #expect(items.allSatisfy { !bIds.contains($0.entityId) })
        #expect(try store.flow(brandId: b.id).count == 4, "açık söz Akış'ta değil")
    }

    @Test func akisSiniriEnYenileriVerirArsivVeGeriAlinanGorunmez() throws {
        let store = try makeStore()
        let a = try store.createBrand(name: "A")
        for i in 0..<5 {
            try store.addTextSource(brandId: a.id, kind: .note, title: "Not \(i)", body: "x", capturedAt: ago(hours: Double(10 - i)))
        }
        #expect(try store.flow(brandId: a.id, limit: 3).map(\.title) == ["Not 4", "Not 3", "Not 2"])
        #expect(try store.flow(brandId: a.id, limit: 0).isEmpty)

        let archived = try store.addTextSource(brandId: a.id, kind: .note, title: "Arşivli", body: "x")
        try store.setSourceArchived(archived.id, archived: true)
        let p = try store.createProposal(sessionId: nil, brandId: a.id, kind: .createTask, summary: "G",
                                         payload: ProposalPayload.CreateTask(title: "Geri alınacak"))
        try store.applyProposal(p.id)
        #expect(try store.flow(brandId: a.id).contains { $0.entityId == p.id })
        try store.revertProposal(p.id)
        let items = try store.flow(brandId: a.id)
        #expect(!items.contains { $0.entityId == p.id || $0.entityId == archived.id })
    }

    // MARK: Doğrulama kuralı

    @Test func dogrulamaKuraliEksikOlaniSoylerVeCekirdekleAyni() throws {
        let store = try makeStore()
        let a = try store.createBrand(name: "A")
        var log = try store.saveWorkLog(WorkLog(brandId: a.id, title: "İş"), inputSourceIds: [], outputSourceIds: [])
        let empty = try store.workLogDetail(log.id).verificationProblem
        #expect(empty == "Doğrulamak için “Ne yapıldı?” alanı dolu olmalı.")
        #expect(throws: MarkaError.validation(empty!)) { try store.verifyWorkLog(log.id, verifiedBy: "Ben") }

        log.performed = "Yapıldı"
        log = try store.saveWorkLog(log, inputSourceIds: [], outputSourceIds: [])
        let noLink = try store.workLogDetail(log.id).verificationProblem
        #expect(noLink == "Doğrulamak için en az bir dosya ya da görev bağlanmalı.")
        #expect(throws: MarkaError.validation(noLink!)) { try store.verifyWorkLog(log.id, verifiedBy: "Ben") }

        let note = try store.addTextSource(brandId: a.id, kind: .note, title: "Dayanak", body: "x")
        try store.saveWorkLog(log, inputSourceIds: [note.id], outputSourceIds: [])
        #expect(try store.workLogDetail(log.id).verificationProblem == nil)
        try store.verifyWorkLog(log.id, verifiedBy: "Ben")
        #expect(try store.flow(brandId: a.id).first { $0.entityId == log.id }?.kind == .workLog(.verified))
    }

    // MARK: Yapılacaklar

    @Test func yapilacaklarYalnizAciklariGecikenVeTarihSirasiylaVerir() throws {
        let store = try makeStore()
        let a = try store.createBrand(name: "A")
        try store.saveTask(WorkTask(brandId: a.id, title: "Tarihsiz görev"))
        try store.saveTask(WorkTask(brandId: a.id, title: "Geciken görev", dueDate: day(-2)))
        try store.saveTask(WorkTask(brandId: a.id, title: "Sürüyor", dueDate: day(3), status: .inProgress))
        try store.saveTask(WorkTask(brandId: a.id, title: "Biten", dueDate: day(-5), status: .done))
        try store.saveTask(WorkTask(brandId: a.id, title: "İptal", status: .cancelled))
        try store.saveRecord(BrandRecord(brandId: a.id, kind: .promise, title: "Söz", dueDate: day(1)))
        try store.saveRecord(BrandRecord(brandId: a.id, kind: .decision, title: "Karar"))
        try store.saveRecord(BrandRecord(brandId: a.id, kind: .request, title: "Kapanmış talep", status: .done))
        try store.saveRecord(BrandRecord(brandId: a.id, kind: .goal, title: "Hedef", dueDate: day(-10)))
        try store.saveRecord(BrandRecord(brandId: a.id, kind: .contract, title: "Yürürlükteki sözleşme"))
        try store.saveRecord(BrandRecord(brandId: a.id, kind: .proposal, title: "Teklif taslağı"))

        let items = try store.todo(brandId: a.id)
        #expect(items.map(\.title) == ["Geciken görev", "Söz", "Sürüyor", "Tarihsiz görev", "Karar"])
        #expect(items.first?.isOverdue(today: day(0)) == true)
        #expect(items.first { $0.title == "Sürüyor" }?.kind == .task(.inProgress))
        #expect(items.first { $0.title == "Söz" }?.kind == .record(.promise, .open))
        #expect(items.allSatisfy { $0.isPrimary }, "hedef/teklif/sözleşme/önemli tarih Yapılacaklar'da değil (U9)")
    }

    /// 0.2.1 U9: hedef, teklif, sözleşme ve önemli tarih Bilgiler'de salt okunur liste; iptal edilen görünmez, marka kapsamlı.
    @Test func bilgilerListesiHedefTeklifSozlesmeVeOnemliTarihiVerir() throws {
        let store = try makeStore()
        let a = try store.createBrand(name: "A")
        let b = try store.createBrand(name: "B")
        let eski = try store.saveRecord(BrandRecord(brandId: a.id, kind: .contract, title: "Sözleşme", createdAt: ago(hours: 48)))
        let yeni = try store.saveRecord(BrandRecord(brandId: a.id, kind: .proposal, title: "Teklif", createdAt: ago(hours: 1)))
        let tarihli = try store.saveRecord(BrandRecord(brandId: a.id, kind: .milestone, title: "Lansman", dueDate: day(10)))
        let hedef = try store.saveRecord(BrandRecord(brandId: a.id, kind: .goal, title: "Hedef", status: .done, dueDate: day(-3)))
        try store.saveRecord(BrandRecord(brandId: a.id, kind: .goal, title: "İptal hedef", status: .cancelled))
        try store.saveRecord(BrandRecord(brandId: a.id, kind: .promise, title: "Söz"))
        try store.saveRecord(BrandRecord(brandId: b.id, kind: .goal, title: "B hedefi"))

        #expect(try store.referenceRecords(brandId: a.id).map(\.id) == [hedef.id, tarihli.id, yeni.id, eski.id])
        #expect(try store.referenceRecords(brandId: b.id).map(\.title) == ["B hedefi"])
    }

    @Test func yapilacaklarBaskaMarkaninKaydiniGetirmezVeKapaninciCikar() throws {
        let store = try makeStore()
        let a = try store.createBrand(name: "A")
        let b = try store.createBrand(name: "B")
        let t = try store.saveTask(WorkTask(brandId: a.id, title: "A görevi"))
        var r = try store.saveRecord(BrandRecord(brandId: a.id, kind: .request, title: "A talebi"))
        try store.saveTask(WorkTask(brandId: b.id, title: "B görevi"))
        try store.saveRecord(BrandRecord(brandId: b.id, kind: .promise, title: "B sözü"))

        #expect(Set(try store.todo(brandId: a.id).map(\.title)) == ["A görevi", "A talebi"])
        try store.setTaskStatus(t.id, .done)
        r.status = .done
        r = try store.saveRecord(r)
        #expect(try store.todo(brandId: a.id).isEmpty)
        #expect(Set(try store.todo(brandId: b.id).map(\.title)) == ["B görevi", "B sözü"])
        // Kapananlar Akış'a düşer.
        let flow = try store.flow(brandId: a.id)
        #expect(flow.contains { $0.entityId == t.id && $0.kind == .taskDone })
        #expect(flow.contains { $0.entityId == r.id && $0.kind == .recordClosed(.request, .done) })
    }

    /// 0.2.1 U8: Bilgi ekranı kalktı; onaylanmış bilgi güncellemesi Akış'ta "Öneri onaylandı" satırı olur ve mevcut
    /// `revertPage` yoluyla önceki sürüme döner. Yeni sayfa açan güncellemenin dönülecek sürümü yoktur.
    @Test func onaylanmisBilgiGuncellemesiAkistaGorunurVeOncekiSurumeDoner() throws {
        let store = try makeStore()
        let a = try store.createBrand(name: "A")
        let b = try store.createBrand(name: "B")
        let v1 = try store.writeWikiRevision(brandId: a.id, pageId: nil, kind: .person, title: "Ayşe", body: "Satın alma", claims: [], actor: .user)
        let v2 = try store.writeWikiRevision(brandId: a.id, pageId: v1.pageId, kind: .person, title: "Ayşe", body: "Genel müdür", claims: [], actor: .ai)
        let p = AIProposal(sessionId: nil, brandId: a.id, kind: .wikiRevision, summary: "Bilgi sayfası: Ayşe", payloadJSON: "{}", resultEntityId: v2.id)
        try store.write { db in try p.insert(db) }
        #expect(try store.knowledgeUndo(proposalId: p.id) == nil, "onaylanmadan geri alınacak bir şey yok")
        try store.approveRevision(v2.id)

        #expect(try store.flow(brandId: a.id).contains { $0.entityId == p.id && $0.kind == .proposalApplied(.wikiRevision) })
        #expect(try store.flow(brandId: b.id).isEmpty, "başka markanın Akış'ında görünmez")
        let undo = try #require(try store.knowledgeUndo(proposalId: p.id))
        #expect(undo == KnowledgeUndo(pageId: v1.pageId, revisionId: v1.id))

        try store.revertPage(undo.pageId, to: undo.revisionId)
        #expect(try store.wikiPageDetail(v1.pageId).current?.body == "Satın alma")
        #expect(try store.wikiPageDetail(v1.pageId).revisions.count == 3, "geçmiş silinmez; yeni onaylı sürüm")
        #expect(try store.knowledgeUndo(proposalId: p.id) == nil, "ikinci kez geri alınmaz")

        // Yeni sayfa açan güncelleme: önceki sürüm yok.
        let yeni = try store.writeWikiRevision(brandId: a.id, pageId: nil, kind: .process, title: "Süreç", body: "Adımlar", claims: [], actor: .ai)
        let q = AIProposal(sessionId: nil, brandId: a.id, kind: .wikiRevision, summary: "Bilgi sayfası: Süreç", payloadJSON: "{}", resultEntityId: yeni.id)
        try store.write { db in try q.insert(db) }
        try store.approveRevision(yeni.id)
        #expect(try store.knowledgeUndo(proposalId: q.id) == nil)
    }
}
