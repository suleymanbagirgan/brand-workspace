import Foundation
import Testing
@testable import MarkaCore

/// H3-05 Onay ritüeli: seçim durumu, yıkıcı ayrımı, toplu uygulama sonucu ve geri alma kapsamı (çekirdekte, saf).
/// Kural 3: AI öneri üretir, kullanıcı onaylar; varsayılan seçim boş, geri alma uygulama öncesi duruma döner.
@Suite struct OnayRituelTests {
    struct Hata: Error {}

    static let ornek: [ApprovalItem] = [
        ApprovalItem(id: "g1", kind: .proposal(.createTask)),
        ApprovalItem(id: "g2", kind: .proposal(.completeTask)),
        ApprovalItem(id: "k1", kind: .knowledge),
        ApprovalItem(id: "d1", kind: .folderFile),
    ]

    func gorevOnerisi(_ title: String) -> SuggestionDraft {
        SuggestionDraft(kind: .createTask, summary: "Yeni görev: " + title, payload: ProposalPayload.CreateTask(title: title))
    }

    // MARK: Seçim durumu

    @Test func varsayilanSecimBosVeImlecIlkSatirda() {
        let s = ProposalSelection(items: Self.ornek)
        #expect(s.selected.isEmpty)
        #expect(s.selectedItems.isEmpty)
        #expect(!s.allSelected)
        #expect(s.cursor == "g1")
        #expect(ProposalSelection(items: []).cursor == nil)
    }

    @Test func komutATumunuSecerVeSecimiKaldirTemizler() {
        var s = ProposalSelection(items: Self.ornek)
        s.selectAll()
        #expect(s.allSelected)
        #expect(s.selectedItems.map(\.id) == ["g1", "g2", "k1", "d1"])
        s.clearSelection()
        #expect(s.selected.isEmpty)
    }

    @Test func boslukImlectekiSatiriSecipBirakir() {
        var s = ProposalSelection(items: Self.ornek)
        s.moveCursor(by: 1)
        s.toggleAtCursor()
        #expect(s.selectedItems.map(\.id) == ["g2"])
        s.toggleAtCursor()
        #expect(s.selected.isEmpty)
        s.toggle("yok") // bilinmeyen kimlik seçime girmez
        #expect(s.selected.isEmpty)
    }

    @Test func okTuslariImleciTasirUclardaDururVeSecimiDegistirmez() {
        var s = ProposalSelection(items: Self.ornek)
        s.moveCursor(by: -1)
        #expect(s.cursor == "g1")
        for _ in 0..<10 { s.moveCursor(by: 1) }
        #expect(s.cursor == "d1")
        #expect(s.selected.isEmpty)
    }

    @Test func sonuclananSatirlarDuserImlecSonrakineGecerYeniSatirSeciliGelmez() {
        var s = ProposalSelection(items: Self.ornek)
        s.toggle("g1"); s.toggle("k1")
        s.remove(["g1"])
        #expect(s.cursor == "g2")
        #expect(s.selectedItems.map(\.id) == ["k1"])
        s.replaceItems(Self.ornek.dropFirst() + [ApprovalItem(id: "yeni", kind: .proposal(.createNote))])
        #expect(s.selectedItems.map(\.id) == ["k1"])
        #expect(!s.isSelected("yeni"))
    }

    // MARK: Yıkıcı ayrımı

    @Test func yikiciOneriEkOnayIsterOnaysizUygulanmaz() {
        #expect(ApprovalPolicy.isDestructive(.proposal(.completeTask)))
        #expect(ApprovalPolicy.isDestructive(.proposal(.updateTask)))
        #expect(!ApprovalPolicy.isDestructive(.proposal(.createTask)))
        #expect(!ApprovalPolicy.isDestructive(.folderFile))

        var s = ProposalSelection(items: Self.ornek)
        s.selectAll()
        #expect(s.destructiveSelected.map(\.id) == ["g2"])
        var denenen: [String] = []
        let onaysiz = ApprovalBatch.run(s.selectedItems, destructiveConfirmed: false) { denenen.append($0.id) }
        #expect(denenen == ["g1", "k1", "d1"])
        #expect(onaysiz.awaitingConfirmation.map(\.id) == ["g2"])
        denenen = []
        let onayli = ApprovalBatch.run(s.selectedItems, destructiveConfirmed: true) { denenen.append($0.id) }
        #expect(denenen == ["g1", "g2", "k1", "d1"])
        #expect(onayli.awaitingConfirmation.isEmpty)
    }

    @Test func retYalnizReddedilebilenleriDenerDosyaKlasordeKalir() {
        var denenen: [String] = []
        let r = ApprovalBatch.reject(Self.ornek) { denenen.append($0.id) }
        #expect(denenen == ["g1", "g2", "k1"])
        #expect(r.succeeded.count == 3)
    }

    // MARK: Toplu uygulama (gerçek çekirdek, bellek içi)

    @Test func topluUygulamaYalnizSecilileriUygularSecilmeyenBekler() throws {
        let store = try makeStore()
        let a = try store.createBrand(name: "Deneme Yangın")
        let p = try store.ingestSuggestionFile(brandId: a.id, fileName: "g.json", sha256: "s1",
                                               drafts: [gorevOnerisi("Bir"), gorevOnerisi("İki"), gorevOnerisi("Üç")])
        var s = ProposalSelection(items: p.map { ApprovalItem(id: $0.id, kind: .proposal($0.kind)) })
        #expect(ApprovalBatch.run(s.selectedItems, destructiveConfirmed: false) { _ in Issue.record("boş seçim uygulandı") }.succeeded.isEmpty)
        s.toggle(p[0].id); s.toggle(p[2].id)
        let r = ApprovalBatch.run(s.selectedItems, destructiveConfirmed: false) { item in
            _ = try store.decideSuggestions(brandId: a.id, decisions: [SuggestionDecision(proposalId: item.id, accept: true)])
        }
        #expect(r.succeeded.map(\.id) == [p[0].id, p[2].id])
        #expect(try store.pendingApprovals(brandId: a.id).suggestions.map(\.id) == [p[1].id])
        #expect(Set(try store.tasks(brandId: a.id).map(\.title)) == ["Bir", "Üç"])
    }

    @Test func kismiHataDigerleriniEngellemez() throws {
        let store = try makeStore()
        let a = try store.createBrand(name: "Kuzey Lojistik")
        let silinecek = try store.saveTask(WorkTask(brandId: a.id, title: "Silinecek"))
        let bir = try store.createProposal(sessionId: nil, brandId: a.id, kind: .createTask, summary: "Bir", payload: ProposalPayload.CreateTask(title: "Bir"))
        let bozuk = try store.createProposal(sessionId: nil, brandId: a.id, kind: .completeTask, summary: "Bitir",
                                             payload: ProposalPayload.CompleteTask(taskId: silinecek.id))
        let iki = try store.createProposal(sessionId: nil, brandId: a.id, kind: .createTask, summary: "İki", payload: ProposalPayload.CreateTask(title: "İki"))
        try store.deleteTask(silinecek.id)

        let items = [bir, bozuk, iki].map { ApprovalItem(id: $0.id, kind: .proposal($0.kind)) }
        let r = ApprovalBatch.run(items, destructiveConfirmed: true) { _ = try store.applyProposal($0.id) }
        #expect(r.succeeded.map(\.id) == [bir.id, iki.id])
        #expect(r.failures.map(\.item.id) == [bozuk.id])
        #expect(!(r.failures.first?.message.isEmpty ?? true))
        #expect(Set(try store.tasks(brandId: a.id).map(\.title)) == ["Bir", "İki"])
        #expect(try store.proposals(brandId: a.id, status: .pending).map(\.id) == [bozuk.id])
    }

    // MARK: Geri alma kapsamı

    @Test func geriAlKapsamiYalnizGercektenGeriAlinabilenTurleriIcerir() {
        let kapsam = ApprovalUndoScope(applied: Self.ornek)
        #expect(kapsam.appliedCount == 4)
        #expect(kapsam.undoableIds == ["g1", "g2"])
        #expect(kapsam.notUndoableCount == 2)
        #expect(kapsam.showsUndo)
        // Geri alınamayanlar tek başınaysa düğme hiç gösterilmez (yalan söylemez).
        let yalnizDosya = ApprovalUndoScope(applied: [ApprovalItem(id: "d1", kind: .folderFile), ApprovalItem(id: "k1", kind: .knowledge),
                                                      ApprovalItem(id: "w1", kind: .proposal(.wikiRevision))])
        #expect(!yalnizDosya.showsUndo)
        #expect(yalnizDosya.notUndoableCount == 3)
        for kind in ProposalKind.allCases where kind != .wikiRevision { #expect(ApprovalPolicy.isUndoable(.proposal(kind))) }
        // Geri alma ters sırayla yürür; kısmi hata diğerlerini engellemez.
        var sira: [String] = []
        let sonuc = kapsam.revert { id in sira.append(id); if id == "g2" { throw Hata() } }
        #expect(sira == ["g2", "g1"])
        #expect(sonuc.reverted == ["g1"])
        #expect(sonuc.failures.keys.sorted() == ["g2"])
    }

    @Test func geriAlUygulamaOncesiDurumaDonerVeDenetimOlayiBirakir() throws {
        let store = try makeStore()
        let a = try store.createBrand(name: "Örnek Kafe Zinciri")
        let suren = try store.saveTask(WorkTask(brandId: a.id, title: "Menü baskısı", status: .inProgress))
        let ekle = try store.createProposal(sessionId: nil, brandId: a.id, kind: .createTask, summary: "Yeni",
                                            payload: ProposalPayload.CreateTask(title: "Yeni görev"))
        let bitir = try store.createProposal(sessionId: nil, brandId: a.id, kind: .completeTask, summary: "Bitir",
                                             payload: ProposalPayload.CompleteTask(taskId: suren.id))
        let items = [ekle, bitir].map { ApprovalItem(id: $0.id, kind: .proposal($0.kind)) }
        let denetimOnce = try store.auditTrail(entity: "task", entityId: suren.id).count

        let r = ApprovalBatch.run(items, destructiveConfirmed: true) { _ = try store.applyProposal($0.id) }
        #expect(r.failures.isEmpty)
        #expect(try store.task(suren.id).status == .done)
        // Her uygulama denetim olayı bırakır.
        #expect(try store.auditTrail(entity: "task", entityId: suren.id).count == denetimOnce + 1)
        let yeniId = try #require(try store.proposals(brandId: a.id).first { $0.id == ekle.id }?.resultEntityId)
        #expect(try store.auditTrail(entity: "task", entityId: yeniId).count >= 1)

        let sonuc = r.undo.revert { id in try store.revertSuggestions(brandId: a.id, proposalIds: [id]) }
        #expect(sonuc.failures.isEmpty)
        // "Yapılacak"a değil, uygulama öncesi "Sürüyor" durumuna döner; eklenen görev kalkar.
        let geri = try store.task(suren.id)
        #expect(geri.status == .inProgress)
        #expect(geri.completedAt == nil)
        #expect(try store.tasks(brandId: a.id).map(\.id) == [suren.id])
        #expect(try store.auditTrail(entity: "task", entityId: suren.id).count == denetimOnce + 2)
        #expect(try store.auditTrail(entity: "task", entityId: suren.id).map(\.action).contains("revertAI"))
        #expect(try store.proposals(brandId: a.id).allSatisfy { $0.status == .reverted })
    }

    @Test func geriAlBaskaMarkaninOnerisiniReddeder() throws {
        let store = try makeStore()
        let a = try store.createBrand(name: "Deneme Yangın")
        let b = try store.createBrand(name: "Kuzey Lojistik")
        let p = try store.createProposal(sessionId: nil, brandId: b.id, kind: .createTask, summary: "B", payload: ProposalPayload.CreateTask(title: "B görevi"))
        try store.applyProposal(p.id)
        let kapsam = ApprovalUndoScope(applied: [ApprovalItem(id: p.id, kind: .proposal(.createTask))])
        let sonuc = kapsam.revert { id in try store.revertSuggestions(brandId: a.id, proposalIds: [id]) }
        #expect(sonuc.reverted.isEmpty)
        #expect(try store.tasks(brandId: b.id).map(\.title) == ["B görevi"])
    }
}
