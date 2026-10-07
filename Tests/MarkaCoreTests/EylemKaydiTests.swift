import Foundation
import Testing
@testable import MarkaCore

/// Eylem kaydı (F1 ilk dilim): `task.reschedule`, `task.rename`, `task.setStatus` ve `updateTask` önerisi.
@Suite struct EylemKaydiTests {
    let tr = Locale(identifier: "tr_TR")

    func kur() throws -> (store: Store, a: Brand, b: Brand, gorev: WorkTask, yabanci: WorkTask) {
        let store = try makeStore()
        let a = try store.createBrand(name: "Deneme Yangın")
        let b = try store.createBrand(name: "Kuzey Lojistik")
        let gorev = try store.saveTask(WorkTask(brandId: a.id, title: "Teklif gönder", dueDate: "2026-10-12"))
        let yabanci = try store.saveTask(WorkTask(brandId: b.id, title: "Depo sayımı", dueDate: "2026-10-20"))
        return (store, a, b, gorev, yabanci)
    }

    @Test func kayitDefteriUcGorevEyleminiOnayGerektirenKademedeTutar() {
        #expect(ActionRegistry.all.map(\.id) == ["task.reschedule", "task.rename", "task.setStatus"])
        #expect(ActionRegistry.all.allSatisfy { $0.risk == .needsApproval })
        #expect(ActionRegistry.descriptor(id: "task.delete") == nil)
    }

    @Test func ertelemeOnizlemesiSonTarihiOnceSonraVerirVeYazmaz() throws {
        let o = try kur()
        let params = try TaskReschedule.postpone(o.gorev, days: 3)
        #expect(params.dueDate == "2026-10-15")
        let p = try o.store.preview(TaskReschedule.self, brandId: o.a.id, params)
        #expect(p.changes == [FieldChange(field: .dueDate, before: "2026-10-12", after: "2026-10-15")])
        #expect(p.lines(locale: tr) == ["Son tarih: 12 Eki → 15 Eki"])
        #expect(try o.store.task(o.gorev.id).dueDate == "2026-10-12")
    }

    @Test func tarihsizGorevBugundenErtelenirVeEksiGunIleriAlir() throws {
        let t = WorkTask(brandId: "x", title: "t")
        #expect(try TaskReschedule.postpone(t, days: 2, today: "2026-12-30").dueDate == "2027-01-01")
        #expect(TaskReschedule.shifted("2026-10-12", by: -5) == "2026-10-07")
        #expect(TaskReschedule.shifted("2026-02-30", by: 1) == nil)
    }

    @Test func yenidenAdlandirmaVeDurumOnizlemesiDogruAlanlariVerir() throws {
        let o = try kur()
        let ad = try o.store.preview(TaskRename.self, brandId: o.a.id, .init(taskId: o.gorev.id, title: "  Teklifi gönder  "))
        #expect(ad.changes == [FieldChange(field: .title, before: "Teklif gönder", after: "Teklifi gönder")])
        let durum = try o.store.preview(TaskSetStatus.self, brandId: o.a.id, .init(taskId: o.gorev.id, status: .done))
        #expect(durum.changes == [FieldChange(field: .status, before: "todo", after: "done")])
        #expect(durum.lines(locale: tr) == ["Durum: Yapılacak → Bitti"])
    }

    @Test func baskaMarkaninGoreviOnizlemedeVeUygulamadaReddedilir() throws {
        let o = try kur()
        #expect(throws: MarkaError.brandScope) {
            try o.store.preview(TaskRename.self, brandId: o.a.id, .init(taskId: o.yabanci.id, title: "Ele geçir"))
        }
        #expect(throws: MarkaError.brandScope) {
            try o.store.apply(TaskReschedule.self, brandId: o.a.id, .init(taskId: o.yabanci.id, dueDate: "2026-11-01"))
        }
        #expect(try o.store.task(o.yabanci.id).dueDate == "2026-10-20")
    }

    @Test func uygulamaDenetimIziBirakirVeGeriAlmaOncekiDegerleriYukler() throws {
        let o = try kur()
        let kayit = try o.store.apply(TaskReschedule.self, brandId: o.a.id, .init(taskId: o.gorev.id, dueDate: "2026-10-15"))
        #expect(try o.store.task(o.gorev.id).dueDate == "2026-10-15")
        let iz = try o.store.auditTrail(entity: "task", entityId: o.gorev.id)
        #expect(iz.first?.action == "task.reschedule")
        #expect(iz.first?.brandId == o.a.id)
        try o.store.undo(kayit, brandId: o.a.id)
        #expect(try o.store.task(o.gorev.id).dueDate == "2026-10-12")
        #expect(try o.store.auditTrail(entity: "task", entityId: o.gorev.id).first?.action == "undo")
    }

    @Test func geriAlmaBaskaMarkaAdinaVeSonradanDegisenGorevdeReddedilir() throws {
        let o = try kur()
        let kayit = try o.store.apply(TaskSetStatus.self, brandId: o.a.id, .init(taskId: o.gorev.id, status: .inProgress))
        #expect(throws: MarkaError.brandScope) { try o.store.undo(kayit, brandId: o.b.id) }
        try o.store.setTaskStatus(o.gorev.id, .waiting)
        #expect(throws: MarkaError.self) { try o.store.undo(kayit, brandId: o.a.id) }
        #expect(try o.store.task(o.gorev.id).status == .waiting)
    }

    @Test func onayGerektirenEylemYapayZekaAdinaDogrudanUygulanamaz() throws {
        let o = try kur()
        #expect(throws: MarkaError.self) {
            try o.store.apply(TaskRename.self, brandId: o.a.id, .init(taskId: o.gorev.id, title: "AI yazdı"), actor: .ai)
        }
        #expect(try o.store.task(o.gorev.id).title == "Teklif gönder")
    }

    @Test func gecersizTarihBosBaslikVeDegisiklikYokReddedilir() throws {
        let o = try kur()
        #expect(throws: MarkaError.self) { try o.store.preview(TaskReschedule.self, brandId: o.a.id, .init(taskId: o.gorev.id, dueDate: "2026-13-01")) }
        #expect(throws: MarkaError.self) { try o.store.preview(TaskRename.self, brandId: o.a.id, .init(taskId: o.gorev.id, title: "   ")) }
        // Aynı değer: değişecek alan yok.
        #expect(throws: MarkaError.self) { try o.store.apply(TaskReschedule.self, brandId: o.a.id, .init(taskId: o.gorev.id, dueDate: "2026-10-12")) }
    }

    @Test func gorevGuncelleOnerisiBosBilinmeyenVeGecersizDegisikligiReddeder() throws {
        let o = try kur()
        let gecersiz: [String] = [
            #"{"taskId":"\#(o.gorev.id)"}"#,                                    // boş değişiklik
            #"{"taskId":"\#(o.gorev.id)","priority":3}"#,                       // bilinmeyen alan
            #"{"taskId":"\#(o.gorev.id)","dueDate":"2026-02-30"}"#,             // geçersiz tarih
            #"{"taskId":"\#(o.gorev.id)","status":"archived"}"#,                // geçersiz durum
            #"{"taskId":"\#(o.yabanci.id)","title":"Yabancı"}"#,                // başka markanın görevi
        ]
        for json in gecersiz {
            #expect(throws: MarkaError.self) {
                try o.store.write { db in try o.store.validateProposal(db, brandId: o.a.id, kind: .updateTask, json: json) }
            }
        }
        #expect(throws: MarkaError.self) {
            try o.store.createProposal(sessionId: nil, brandId: o.a.id, kind: .updateTask, summary: "x",
                                       payload: ProposalPayload.UpdateTask(taskId: o.gorev.id))
        }
    }

    @Test func oneriOnaydanOnceGorevDegistirmezOnaylaUygulanir() throws {
        let o = try kur()
        let p = try o.store.createProposal(sessionId: nil, brandId: o.a.id, kind: .updateTask, summary: "Görevi güncelle",
                                           payload: ProposalPayload.UpdateTask(taskId: o.gorev.id, title: "Teklifi gönder", dueDate: "2026-10-15", status: .inProgress))
        let once = try o.store.task(o.gorev.id)
        #expect(once.title == "Teklif gönder" && once.dueDate == "2026-10-12" && once.status == .todo)
        let uygulanan = try o.store.applyProposal(p.id)
        #expect(uygulanan.resultEntityId == o.gorev.id)
        let sonra = try o.store.task(o.gorev.id)
        #expect(sonra.title == "Teklifi gönder" && sonra.dueDate == "2026-10-15" && sonra.status == .inProgress)
        let onceki = try #require(uygulanan.payload(ProposalPayload.UpdateTask.self)?.previous)
        #expect(Set(onceki.actionIds) == ["task.rename", "task.reschedule", "task.setStatus"])
        #expect(onceki.changes.first { $0.field == .dueDate }?.before == "2026-10-12")
        #expect(try o.store.auditTrail(entity: "task", entityId: o.gorev.id).first?.actor == .ai)
    }

    @Test func onaylananGorevGuncellemesiGeriAlinir() throws {
        let o = try kur()
        let p = try o.store.createProposal(sessionId: nil, brandId: o.a.id, kind: .updateTask, summary: "x",
                                           payload: ProposalPayload.UpdateTask(taskId: o.gorev.id, dueDate: "2026-10-15", status: .done))
        try o.store.applyProposal(p.id)
        try o.store.revertProposal(p.id)
        let t = try o.store.task(o.gorev.id)
        #expect(t.dueDate == "2026-10-12" && t.status == .todo && t.completedAt == nil)
        #expect(try o.store.proposals(brandId: o.a.id).first?.status == .reverted)
        #expect(try o.store.auditTrail(entity: "task", entityId: o.gorev.id).first?.action == "revertAI")
    }

    @Test func kullaniciSonradanDuzenlediyseGeriAlmaReddedilir() throws {
        let o = try kur()
        let p = try o.store.createProposal(sessionId: nil, brandId: o.a.id, kind: .updateTask, summary: "x",
                                           payload: ProposalPayload.UpdateTask(taskId: o.gorev.id, dueDate: "2026-10-15"))
        try o.store.applyProposal(p.id)
        var t = try o.store.task(o.gorev.id)
        t.notes = "Kullanıcı not ekledi"
        try o.store.saveTask(t)
        #expect(throws: MarkaError.self) { try o.store.revertProposal(p.id) }
        #expect(try o.store.task(o.gorev.id).dueDate == "2026-10-15")
    }

    @Test func disaridanGelenGeriAlmaKaydiIcerenOneriReddedilir() throws {
        let o = try kur()
        var x = ProposalPayload.UpdateTask(taskId: o.gorev.id, title: "Yeni")
        x.previous = UndoRecord(actionIds: ["task.rename"], brandId: o.a.id, entity: "task", entityId: o.gorev.id,
                                changes: [FieldChange(field: .title, before: "Sahte", after: "Yeni")], appliedAt: Date())
        #expect(throws: MarkaError.self) { try o.store.createProposal(sessionId: nil, brandId: o.a.id, kind: .updateTask, summary: "x", payload: x) }
    }

    @Test func aracYalnizOneriUretirGorevDegismez() throws {
        let o = try kur()
        let exec = ToolExecutor(store: o.store, scope: .brand(o.a.id), sessionId: nil)
        let r = exec.run(name: "gorev_guncelle_oner", input: ["gorev_id": .string(o.gorev.id), "son_tarih": "2026-10-15", "durum": "inProgress"])
        #expect(!r.isError)
        #expect(r.event.kind == .proposal)
        let t = try o.store.task(o.gorev.id)
        #expect(t.dueDate == "2026-10-12" && t.status == .todo)
        let p = try #require(try o.store.proposals(brandId: o.a.id, status: .pending).first)
        #expect(p.kind == .updateTask)
        #expect(o.store.proposalPreview(p)?.lines(locale: tr) == ["Son tarih: 12 Eki → 15 Eki", "Durum: Yapılacak → Sürüyor"])
    }

    @Test func aracBaskaMarkaninGoreviniVeBilinmeyenAlaniReddeder() throws {
        let o = try kur()
        let exec = ToolExecutor(store: o.store, scope: .brand(o.a.id), sessionId: nil)
        let yabanci = exec.run(name: "gorev_guncelle_oner", input: ["gorev_id": .string(o.yabanci.id), "baslik": "Ele geçir"])
        #expect(yabanci.isError)
        let bilinmeyen = exec.run(name: "gorev_guncelle_oner", input: ["gorev_id": .string(o.gorev.id), "oncelik": 3])
        #expect(bilinmeyen.isError)
        let durum = exec.run(name: "gorev_guncelle_oner", input: ["gorev_id": .string(o.gorev.id), "durum": "silindi"])
        #expect(durum.isError)
        #expect(try o.store.proposals(brandId: o.a.id).isEmpty)
        #expect(try o.store.proposals(brandId: o.b.id).isEmpty)
        #expect(try o.store.task(o.yabanci.id).title == "Depo sayımı")
        // Tüm markalar kapsamında araç yok.
        let all = ToolExecutor(store: o.store, scope: .allBrands, sessionId: nil)
        #expect(all.run(name: "gorev_guncelle_oner", input: ["gorev_id": .string(o.gorev.id), "baslik": "x"]).isError)
    }

    @Test func onaySayfasiOnizlemesiOnceSonraVerirUygulanmistaOncekiKayittanGelir() throws {
        let o = try kur()
        let p = try o.store.createProposal(sessionId: nil, brandId: o.a.id, kind: .updateTask, summary: "x",
                                           payload: ProposalPayload.UpdateTask(taskId: o.gorev.id, title: "Teklifi gönder", dueDate: "2026-10-15"))
        let bekleyen = try #require(o.store.proposalPreview(p))
        #expect(bekleyen.entityTitle == "Teklif gönder")
        #expect(bekleyen.lines(locale: tr) == ["Başlık: “Teklif gönder” → “Teklifi gönder”", "Son tarih: 12 Eki → 15 Eki"])
        let uygulanan = try o.store.applyProposal(p.id)
        #expect(o.store.proposalPreview(uygulanan)?.lines(locale: tr) == bekleyen.lines(locale: tr))
        // Başka türde önizleme yok.
        let diger = try o.store.createProposal(sessionId: nil, brandId: o.a.id, kind: .completeTask, summary: "x",
                                               payload: ProposalPayload.CompleteTask(taskId: o.gorev.id))
        #expect(o.store.proposalPreview(diger) == nil)
    }

    @Test func sistemIstemiVeAracListesiGorevGuncelleAraciniIcerir() throws {
        #expect(ContextBuilder.baseInstructions.contains("gorev_guncelle_oner"))
        let spec = try #require(ToolCatalog.brandTools.first { $0.name == "gorev_guncelle_oner" })
        #expect(spec.isProposal)
        #expect(!ToolCatalog.allBrandTools.contains { $0.name == "gorev_guncelle_oner" })
    }
}
