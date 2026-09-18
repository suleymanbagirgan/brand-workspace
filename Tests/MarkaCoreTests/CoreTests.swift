import Foundation
import GRDB
import Testing
@testable import MarkaCore

func makeStore() throws -> Store { Store(database: try AppDatabase.inMemory()) }

func tempDir(_ name: String = "t") throws -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("marka-\(name)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

@Suite struct MarkaTests {
    @Test func markaAdiTekilVeTurkceBuyukKucukHarfDuyarsiz() throws {
        let store = try makeStore()
        try store.createBrand(name: "İzmir Yangın")
        #expect(throws: MarkaError.self) { try store.createBrand(name: "izmir yangın") }
        #expect(throws: MarkaError.self) { try store.createBrand(name: "   ") }
        #expect(try store.brands().count == 1)
        // Her markaya varsayılan bilgi kuralları yazılır.
        #expect(try store.wikiRules(brandId: store.brands()[0].id).contains("Bilgi kuralları"))
    }

    @Test func arsivlenenMarkaListedenCikarAmaSilinmez() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "A")
        try store.setBrandArchived(b.id, archived: true)
        #expect(try store.brands().isEmpty)
        #expect(try store.brands(includeArchived: true).count == 1)
    }

    @Test func arsivdenCikarilanMarkaListeyeDonerVeDenetimBirakir() throws {
        let store = try makeStore()
        let a = try store.createBrand(name: "A")
        try store.createBrand(name: "B")
        try store.setBrandArchived(a.id, archived: true)
        #expect(try store.archivedBrands().map(\.id) == [a.id])
        #expect(try store.brands().map(\.name) == ["B"])
        try store.setBrandArchived(a.id, archived: false)
        #expect(try store.archivedBrands().isEmpty)
        #expect(try store.brands().map(\.name) == ["A", "B"])
        let trail = try store.auditTrail(entity: "brand", entityId: a.id)
        #expect(trail.count == 3)
        #expect(trail.filter { $0.action == "update" }.count == 2)
        #expect(trail.contains { $0.action == "update" && ($0.afterJSON ?? "").contains("\"active\"") && ($0.beforeJSON ?? "").contains("\"archived\"") })
    }
}

@Suite struct KaynakTests {
    @Test func hamKaynakDegistirilemezYalnizcaArsivlenir() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Örnek Yangın")
        let s = try store.addTextSource(brandId: b.id, kind: .meeting, title: "Görüşme", body: "Fiyat teklifi istendi.")
        #expect(throws: (any Error).self) {
            try store.writer.write { db in try db.execute(sql: "UPDATE source SET body = 'değişti' WHERE id = ?", arguments: [s.id]) }
        }
        try store.setSourceArchived(s.id, archived: true)
        #expect(try store.source(s.id).archivedAt != nil)
        #expect(try store.source(s.id).body == "Fiyat teklifi istendi.")
    }

    @Test func dosyaIcerikAdresliSaklanirVeMetniAranir() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Marka")
        let dir = try tempDir()
        let f = dir.appendingPathComponent("teklif.md")
        try "Yangın dolabı teklifi: 42 adet".write(to: f, atomically: true, encoding: .utf8)
        let s1 = try store.addFileSource(brandId: b.id, fileURL: f)
        let s2 = try store.addFileSource(brandId: b.id, fileURL: f, title: "Aynı dosya")
        #expect(s1.filePath == s2.filePath)
        #expect(s1.sha256 == s2.sha256)
        let url = try #require(store.fileURL(for: s1))
        #expect(try String(contentsOf: url, encoding: .utf8) == "Yangın dolabı teklifi: 42 adet")
        // Aksan duyarsız arama: "yangin" → "Yangın"
        let hits = try store.search("yangin dolabi", brandId: b.id)
        #expect(hits.contains { $0.id == s1.id })
    }

    @Test func aramaMarkaSinirinaUyar() throws {
        let store = try makeStore()
        let a = try store.createBrand(name: "A")
        let b = try store.createBrand(name: "B")
        try store.addTextSource(brandId: a.id, kind: .note, title: "Gizli strateji", body: "A markasının bütçesi 1 milyon")
        #expect(try store.search("bütçe", brandId: b.id).isEmpty)
        #expect(try store.search("bütçe", brandId: a.id).count == 1)
    }

    @Test func gecersizBaglantiReddedilir() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "B")
        #expect(throws: MarkaError.self) { try store.addTextSource(brandId: b.id, kind: .link, title: "x", body: "", url: "javascript:alert(1)") }
    }
}

@Suite struct GorevTests {
    @Test func tekSayacCalisirVeSureToplanir() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "B")
        let t1 = try store.saveTask(WorkTask(brandId: b.id, title: "Bir"))
        let t2 = try store.saveTask(WorkTask(brandId: b.id, title: "İki"))
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        try store.startTimer(taskId: t1.id, at: start)
        try store.startTimer(taskId: t2.id, at: start.addingTimeInterval(600))
        let running = try #require(try store.runningTimer())
        #expect(running.taskId == t2.id)
        #expect(try store.task(t1.id).timeSpentSeconds == 600)
        #expect(try store.task(t2.id).status == .inProgress)
        // Görev bitince sayaç kapanır.
        var done = try store.task(t2.id)
        done.status = .done
        try store.saveTask(done)
        #expect(try store.runningTimer() == nil)
        #expect(try store.task(t2.id).completedAt != nil)
    }

    @Test func dogrudanIkinciAcikSureKaydiEklenemez() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "B")
        let t = try store.saveTask(WorkTask(brandId: b.id, title: "Bir"))
        try store.startTimer(taskId: t.id)
        #expect(throws: (any Error).self) {
            try store.writer.write { db in try TimeEntry(taskId: t.id, brandId: b.id, startedAt: Date()).insert(db) }
        }
    }

    @Test func gecersizTarihVeOncelikReddedilir() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "B")
        #expect(throws: MarkaError.self) { try store.saveTask(WorkTask(brandId: b.id, title: "x", dueDate: "2026-13-40")) }
        #expect(throws: MarkaError.self) { try store.saveTask(WorkTask(brandId: b.id, title: "x", priority: 7)) }
    }
}

@Suite struct CalismaKaydiTests {
    @Test func dogrulamaKosullariVeDuzenlemeTaslagaDusurur() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "B")
        let src = try store.addTextSource(brandId: b.id, kind: .clientRequest, title: "Talep", body: "Teklif istendi")
        var log = try store.saveWorkLog(WorkLog(brandId: b.id, title: "Teklif"), inputSourceIds: [], outputSourceIds: [])
        #expect(throws: MarkaError.self) { try store.verifyWorkLog(log.id, verifiedBy: "Danışman") } // ne yapıldı boş
        log.performed = "Teklif hazırlandı"
        log = try store.saveWorkLog(log, inputSourceIds: [], outputSourceIds: [])
        #expect(throws: MarkaError.self) { try store.verifyWorkLog(log.id, verifiedBy: "Danışman") } // bağlantı yok
        log = try store.saveWorkLog(log, inputSourceIds: [src.id], outputSourceIds: [])
        try store.verifyWorkLog(log.id, verifiedBy: "Danışman")
        #expect(try store.workLogDetail(log.id).log.status == .verified)
        var edited = try store.workLogDetail(log.id).log
        edited.performed = "Teklif hazırlandı ve gönderildi"
        try store.saveWorkLog(edited, inputSourceIds: [src.id], outputSourceIds: [])
        let after = try store.workLogDetail(log.id).log
        #expect(after.status == .draft)
        #expect(after.verifiedBy == nil)
    }

    @Test func baskaMarkaninKaynagiBaglanamaz() throws {
        let store = try makeStore()
        let a = try store.createBrand(name: "A")
        let b = try store.createBrand(name: "B")
        let srcA = try store.addTextSource(brandId: a.id, kind: .note, title: "n", body: "x")
        #expect(throws: MarkaError.brandScope) {
            try store.saveWorkLog(WorkLog(brandId: b.id, title: "t"), inputSourceIds: [srcA.id], outputSourceIds: [])
        }
    }
}

@Suite struct BilgiTests {
    @Test func aiIddiasiKaynaksizVeyaBaskaMarkadanOlamaz() throws {
        let store = try makeStore()
        let a = try store.createBrand(name: "A")
        let b = try store.createBrand(name: "B")
        let srcB = try store.addTextSource(brandId: b.id, kind: .note, title: "n", body: "x")
        #expect(throws: MarkaError.self) {
            try store.writeWikiRevision(brandId: a.id, pageId: nil, kind: .overview, title: "Genel", body: "b",
                                        claims: [WikiClaimInput(text: "Kaynaksız iddia")], actor: .ai)
        }
        #expect(throws: MarkaError.brandScope) {
            try store.writeWikiRevision(brandId: a.id, pageId: nil, kind: .overview, title: "Genel", body: "b",
                                        claims: [WikiClaimInput(text: "İddia", sourceId: srcB.id)], actor: .ai)
        }
    }

    @Test func aiOnerisiOnaylanmadanGuncelSayilmazVeGeriDonulebilir() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "B")
        let src = try store.addTextSource(brandId: b.id, kind: .meeting, title: "Toplantı", body: "Karar verici Ayşe Hanım")
        let v1 = try store.writeWikiRevision(brandId: b.id, pageId: nil, kind: .person, title: "Ayşe Hanım", body: "Satın alma",
                                             claims: [WikiClaimInput(text: "Karar verici", sourceId: src.id)], actor: .user)
        let pageId = v1.pageId
        #expect(try store.wikiPageDetail(pageId).current?.id == v1.id)
        let v2 = try store.writeWikiRevision(brandId: b.id, pageId: pageId, kind: .person, title: "Ayşe Hanım", body: "Genel müdür",
                                             claims: [WikiClaimInput(text: "Genel müdür oldu", sourceId: src.id)], actor: .ai)
        #expect(v2.state == .proposed)
        #expect(try store.wikiPageDetail(pageId).current?.id == v1.id)
        try store.approveRevision(v2.id)
        #expect(try store.wikiPageDetail(pageId).current?.id == v2.id)
        let v3 = try store.revertPage(pageId, to: v1.id)
        let detail = try store.wikiPageDetail(pageId)
        #expect(detail.current?.id == v3.id)
        #expect(detail.current?.body == "Satın alma")
        #expect(detail.revisions.count == 3)
        #expect(detail.claims.first?.sourceDate == (try store.source(src.id)).capturedAt)
        // Onaylı içerik aranabilir; reddedilmiş öneri aranmaz.
        #expect(try store.search("satın", brandId: b.id).contains { $0.kind == .wiki })
    }

    @Test func celiskiIsaretiSayfaDurumunuDegistirirVeDenetimdeGorunur() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "B")
        let src = try store.addTextSource(brandId: b.id, kind: .note, title: "n", body: "bütçe 100")
        let r = try store.writeWikiRevision(brandId: b.id, pageId: nil, kind: .goal, title: "Bütçe", body: "",
                                            claims: [WikiClaimInput(text: "Bütçe 100 TL", sourceId: src.id)], actor: .user)
        let claim = try #require(try store.claims(revisionId: r.id).first)
        try store.flagClaim(claim.id, status: .conflict, note: "Yeni görüşmede 150 dendi")
        #expect(try store.wikiPageDetail(r.pageId).page.status == .conflict)
        #expect(try store.wikiLint(brandId: b.id).contains { $0.kind == .conflict })
    }

    @Test func slugTurkceKarakterleriSadelestirir() {
        #expect(Store.slug("Örnek Yangın Işık") == "ornek-yangin-isik")
    }
}

@Suite struct OneriTests {
    @Test func uygulaGeriAlVeKullaniciDuzenlemesiSonrasiEngel() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "B")
        let p = try store.createProposal(sessionId: nil, brandId: b.id, kind: .createTask, summary: "Görev",
                                         payload: ProposalPayload.CreateTask(title: "Teklifi kontrol et", dueDate: "2026-09-19"))
        let applied = try store.applyProposal(p.id)
        let taskId = try #require(applied.resultEntityId)
        #expect(try store.task(taskId).actor == .ai)
        try store.revertProposal(p.id)
        #expect(throws: MarkaError.self) { try store.task(taskId) }

        let p2 = try store.createProposal(sessionId: nil, brandId: b.id, kind: .createTask, summary: "Görev",
                                          payload: ProposalPayload.CreateTask(title: "İkinci"))
        let id2 = try #require(try store.applyProposal(p2.id).resultEntityId)
        var t = try store.task(id2)
        t.title = "Kullanıcı düzeltti"
        try store.saveTask(t)
        #expect(throws: MarkaError.self) { try store.revertProposal(p2.id) }
    }

    @Test func sureBaglanmisAIGoreviGeriAlinamaz() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "B")
        let p = try store.createProposal(sessionId: nil, brandId: b.id, kind: .createTask, summary: "x", payload: ProposalPayload.CreateTask(title: "AI görevi"))
        let id = try #require(try store.applyProposal(p.id).resultEntityId)
        try store.addManualTime(taskId: id, seconds: 7200)
        #expect(throws: MarkaError.self) { try store.revertProposal(p.id) }
        #expect(try store.task(id).timeSpentSeconds == 7200)
    }

    @Test func markaYenidenAdlandirilirkenAdTekildir() throws {
        let store = try makeStore()
        try store.createBrand(name: "A")
        var b = try store.createBrand(name: "B")
        b.name = "a"
        #expect(throws: MarkaError.self) { try store.updateBrand(b) }
    }

    @Test func baskaMarkayaAitKimlikIcerenOneriReddedilir() throws {
        let store = try makeStore()
        let a = try store.createBrand(name: "A")
        let b = try store.createBrand(name: "B")
        let tA = try store.saveTask(WorkTask(brandId: a.id, title: "A görevi"))
        #expect(throws: MarkaError.brandScope) {
            try store.createProposal(sessionId: nil, brandId: b.id, kind: .completeTask, summary: "x",
                                     payload: ProposalPayload.CompleteTask(taskId: tA.id))
        }
    }

    @Test func ciktiOnerisiGeriAlininkaSilinmezArsivlenir() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "B")
        let p = try store.createProposal(sessionId: nil, brandId: b.id, kind: .createOutput, summary: "Teklif",
                                         payload: ProposalPayload.CreateOutput(fileName: "teklif.md", title: "Teklif", content: "# Teklif"))
        let sid = try #require(try store.applyProposal(p.id).resultEntityId)
        try store.revertProposal(p.id)
        #expect(try store.source(sid).archivedAt != nil)
    }

    @Test func oturumunMarkasiSonradanDegistirilemez() throws {
        let store = try makeStore()
        let a = try store.createBrand(name: "A")
        let b = try store.createBrand(name: "B")
        let s = AISession(brandId: a.id, scope: .brand, provider: .anthropic, model: "m", title: "t")
        try store.writer.write { db in try s.insert(db) }
        #expect(throws: (any Error).self) {
            try store.writer.write { db in try db.execute(sql: "UPDATE aiSession SET brandId = ? WHERE id = ?", arguments: [b.id, s.id]) }
        }
        #expect(throws: (any Error).self) {
            try store.writer.write { db in try AISession(brandId: nil, scope: .brand, provider: .codex, model: "m", title: "t").insert(db) }
        }
    }
}

@Suite struct DurumTests {
    @Test func sonrakiAdimKurallariVeSonTemas() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Örnek Yangın")
        let service = StatusService(store: store)
        let now = DayString.date("2026-09-16")!.addingTimeInterval(10 * 3600)
        #expect(try service.brandStatus(brandId: b.id, now: now).isEmpty)
        #expect(try service.brandStatus(brandId: b.id, now: now).nextStep.reason == .addFirstSource)

        try store.addTextSource(brandId: b.id, kind: .meeting, title: "Son görüşme", body: "Fiyat teklifi istendi",
                                capturedAt: now.addingTimeInterval(-86400))
        try store.saveRecord(BrandRecord(brandId: b.id, kind: .promise, title: "Teklif gönderilecek", dueDate: "2026-09-18"))
        try store.saveRecord(BrandRecord(brandId: b.id, kind: .proposal, title: "Yangın dolabı teklifi"))
        var s = try service.brandStatus(brandId: b.id, now: now)
        #expect(s.lastContact?.text == "Son görüşme")
        #expect(s.nextStep.reason == .promiseDueSoon)
        #expect(s.drafts.count == 1)

        try store.saveTask(WorkTask(brandId: b.id, title: "Geciken iş", dueDate: "2026-09-10"))
        s = try service.brandStatus(brandId: b.id, now: now)
        #expect(s.nextStep.reason == .overdueTask)
        #expect(s.nextStep.ref != nil)
    }

    @Test func genelBakisSayilariKayitlardanGelir() throws {
        let store = try makeStore()
        let a = try store.createBrand(name: "A")
        let b = try store.createBrand(name: "B")
        let now = DayString.date("2026-09-16")!.addingTimeInterval(10 * 3600)
        try store.saveTask(WorkTask(brandId: a.id, title: "Geciken", dueDate: "2026-09-01"))
        try store.saveTask(WorkTask(brandId: b.id, title: "Yakında", dueDate: "2026-09-20"))
        try store.saveRecord(BrandRecord(brandId: b.id, kind: .decision, title: "Bütçe onayı"))
        let src = try store.addTextSource(brandId: a.id, kind: .note, title: "n", body: "x")
        var log = try store.saveWorkLog(WorkLog(brandId: a.id, title: "İş", performed: "yapıldı", occurredAt: now), inputSourceIds: [src.id], outputSourceIds: [])
        try store.verifyWorkLog(log.id, verifiedBy: "S")
        log = try store.workLogDetail(log.id).log
        let o = try StatusService(store: store).overview(now: now)
        #expect(o.overdueTasks.map(\.text) == ["Geciken"])
        #expect(o.dueThisWeek.map(\.text) == ["Yakında"])
        #expect(o.awaiting.map(\.text) == ["Bütçe onayı"])
        #expect(o.verifiedThisWeek.map(\.ref.id) == [log.id])
    }
}
