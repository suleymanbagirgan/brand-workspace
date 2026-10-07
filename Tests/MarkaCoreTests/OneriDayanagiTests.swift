import Foundation
import GRDB
import Testing
@testable import MarkaCore

/// E-22 · Onay kartında dayanak ("neden bu öneri"). Dayanak çipleri yalnız önerinin markasından gelir, yalnız başlık taşır;
/// dayanaksız öneri "dayanak yok" diye işaretlenir; dış ajan önerisinde gerekçe denetim kaydından okunur.
/// Adlar uydurmadır; bellek içi ya da geçici veri tabanı (gerçek veri, ağ, Keychain yok).
@Suite struct OneriDayanagiTests {
    struct Kurulum {
        let store: Store
        let a: String, b: String
        let aKaynak1: String, aKaynak2: String, bKaynak: String
        let aGozlem: String, bGozlem: String
    }

    static func kur(_ store: Store? = nil) throws -> Kurulum {
        let s = try store ?? makeStore()
        let a = try s.createBrand(name: "Deneme Yangın").id
        let b = try s.createBrand(name: "Kuzey Lojistik").id
        let k1 = try s.addTextSource(brandId: a, kind: .meeting, title: "Haftalık görüşme", body: "ICERIK-A-GORUSME").id
        let k2 = try s.addTextSource(brandId: a, kind: .note, title: "E-posta notu", body: "ICERIK-A-NOT").id
        let kb = try s.addTextSource(brandId: b, kind: .note, title: "Bütçe notu", body: "GIZLI-BUTCE-KUZEY").id
        let ga = try s.addObservation(brandId: a, statement: "Teslimler ay sonuna kayıyor", evidenceSourceIds: [k1]).id
        let gb = try s.addObservation(brandId: b, statement: "GIZLI-GOZLEM-KUZEY", evidenceSourceIds: [kb]).id
        return Kurulum(store: s, a: a, b: b, aKaynak1: k1, aKaynak2: k2, bKaynak: kb, aGozlem: ga, bGozlem: gb)
    }

    static func json<T: Encodable>(_ v: T) -> String { String(data: try! JSONEncoder().encode(v), encoding: .utf8)! }

    /// Doğrulamayı atlayarak öneri yazar (eski ya da bozuk kayıt benzetimi): çözüm yine marka dışını göstermemeli.
    static func hamOneri(_ s: Store, brandId: String, kind: ProposalKind, payload: String) throws -> AIProposal {
        let p = AIProposal(sessionId: nil, brandId: brandId, kind: kind, summary: "Deneme", payloadJSON: payload)
        try s.writer.write { db in try p.insert(db) }
        return p
    }

    // MARK: Çıkarım (saf)

    @Test func herOneriTuruIcinDayanakKimlikleriYuktenCikarilir() {
        typealias R = ProposalEvidence.Reference
        let wl = Self.json(ProposalPayload.CreateWorkLog(title: "t", requested: "r", performed: "p",
                                                         inputSourceIds: ["k1"], outputSourceIds: ["k2"]))
        #expect(ProposalEvidence.references(kind: .createWorkLog, payloadJSON: wl) == [R(.source, "k1"), R(.source, "k2")])
        let out = Self.json(ProposalPayload.CreateOutput(fileName: "a.md", title: "t", content: "c", inputSourceIds: ["k3"]))
        #expect(ProposalEvidence.references(kind: .createOutput, payloadJSON: out) == [R(.source, "k3")])
        let rec = Self.json(ProposalPayload.CreateBrandRecord(kind: .promise, title: "t", sourceId: "k4"))
        #expect(ProposalEvidence.references(kind: .createBrandRecord, payloadJSON: rec) == [R(.source, "k4")])
        let recYok = Self.json(ProposalPayload.CreateBrandRecord(kind: .promise, title: "t"))
        #expect(ProposalEvidence.references(kind: .createBrandRecord, payloadJSON: recYok).isEmpty)
        let obs = Self.json(ProposalPayload.CreateObservation(statement: "s", evidenceSourceIds: ["k5", "k6"], supersedesId: "g1"))
        #expect(ProposalEvidence.references(kind: .createObservation, payloadJSON: obs)
                == [R(.source, "k5"), R(.source, "k6"), R(.observation, "g1")])
        // Kimlik taşımayan türler boş döner; bozuk yük de çökmeden boş döner.
        let bos: [(ProposalKind, String)] = [
            (.createTask, Self.json(ProposalPayload.CreateTask(title: "t"))),
            (.completeTask, Self.json(ProposalPayload.CompleteTask(taskId: "g"))),
            (.updateTask, Self.json(ProposalPayload.UpdateTask(taskId: "g", title: "x"))),
            (.createNote, Self.json(ProposalPayload.CreateNote(kind: .note, title: "t", body: "b"))),
            (.createTeamMember, Self.json(ProposalPayload.CreateTeamMember(name: "n", title: "t"))),
            (.wikiRevision, "{}"),
        ]
        for (k, j) in bos { #expect(ProposalEvidence.references(kind: k, payloadJSON: j).isEmpty, "\(k)") }
        for k in ProposalKind.allCases { #expect(ProposalEvidence.references(kind: k, payloadJSON: "bozuk").isEmpty, "\(k)") }
    }

    @Test func cozumdeHaritadaOlmayanKimlikAtilirSiraKorunurTekrarDuser() {
        typealias R = ProposalEvidence.Reference
        let refs = [R(.source, "k2"), R(.source, "yabanci"), R(nil, "g1"), R(.source, "k2"), R(nil, "k1"), R(.observation, "k1")]
        let e = ProposalEvidence.resolve(refs, sources: ["k1": "Bir", "k2": "İki"], observations: ["g1": "Gözlem"])
        #expect(e.chips.map(\.id) == ["k2", "g1", "k1"])
        #expect(e.chips.map(\.kind) == [.source, .observation, .source])
        #expect(!e.chips.contains { $0.id == "yabanci" })
        // Türü belli kimlik yanlış tabloda aranmaz: kaynak diye verilen gözlem kimliği çip olmaz.
        #expect(ProposalEvidence.resolve([R(.source, "g1")], sources: [:], observations: ["g1": "Gözlem"]).chips.isEmpty)
    }

    // MARK: Marka yalıtımı ve içerik

    @Test func baskaMarkaninKaynakVeGozlemKimligiCipOlarakSifirKezDoner() throws {
        let k = try Self.kur()
        let wl = Self.json(ProposalPayload.CreateWorkLog(title: "t", requested: "r", performed: "p",
                                                         inputSourceIds: [k.aKaynak1, k.bKaynak], outputSourceIds: [k.bKaynak]))
        let p = try Self.hamOneri(k.store, brandId: k.a, kind: .createWorkLog, payload: wl)
        let e = try k.store.proposalEvidence(p)
        #expect(e.chips.map(\.id) == [k.aKaynak1])
        let obs = Self.json(ProposalPayload.CreateObservation(statement: "s", evidenceSourceIds: [k.bKaynak], supersedesId: k.bGozlem))
        let p2 = try Self.hamOneri(k.store, brandId: k.a, kind: .createObservation, payload: obs)
        let e2 = try k.store.proposalEvidence(p2)
        #expect(e2.chips.isEmpty && !e2.hasEvidence)
        let hepsi = (e.chips + e2.chips)
        #expect(hepsi.filter { $0.id == k.bKaynak || $0.id == k.bGozlem }.count == 0)
        #expect(!hepsi.contains { $0.title.contains("KUZEY") || $0.title == "Bütçe notu" })
    }

    @Test func cipYalnizBaslikTasirIcerikOnizlemesiTasimazVeKirpilir() throws {
        let k = try Self.kur()
        let uzun = try k.store.addTextSource(brandId: k.a, kind: .note, title: String(repeating: "Uzun başlık ", count: 10),
                                             body: "ICERIK-UZUN").id
        let obs = Self.json(ProposalPayload.CreateObservation(statement: "Yeni", evidenceSourceIds: [k.aKaynak1, k.aKaynak2, uzun],
                                                              supersedesId: k.aGozlem))
        let p = try Self.hamOneri(k.store, brandId: k.a, kind: .createObservation, payload: obs)
        let e = try k.store.proposalEvidence(p)
        #expect(e.chips.map(\.id) == [k.aKaynak1, k.aKaynak2, uzun, k.aGozlem])
        #expect(e.chips.prefix(2).map(\.title) == ["Haftalık görüşme", "E-posta notu"])
        #expect(e.chips.last?.kind == .observation && e.chips.last?.title == "Teslimler ay sonuna kayıyor")
        #expect(e.chips.allSatisfy { $0.title.count <= ProposalEvidence.maxTitle && !$0.title.contains("ICERIK") })
    }

    @Test func dayanaksizOneriDayanakYokDiyeIsaretlenir() throws {
        let k = try Self.kur()
        let gorev = try k.store.createProposal(sessionId: nil, brandId: k.a, kind: .createTask, summary: "Görev",
                                               payload: ProposalPayload.CreateTask(title: "Katalog metinleri"))
        let e = try k.store.proposalEvidence(gorev)
        #expect(!e.hasEvidence && e.chips.isEmpty && e.rationale == nil)
        let wl = try k.store.createProposal(sessionId: nil, brandId: k.a, kind: .createWorkLog, summary: "İş",
                                            payload: ProposalPayload.CreateWorkLog(title: "t", requested: "r", performed: "p",
                                                                                   inputSourceIds: [k.aKaynak2]))
        #expect(try k.store.proposalEvidence(wl).hasEvidence)
    }

    // MARK: Dış ajan zarfı (E-17): gerekçe ve dayanak

    @Test func disAjanOnerisindeGerekceVeZarfDayanagiGosterilirSonrakiZarfaKarismaz() throws {
        let base = try tempDir("dayanak")
        let store = Store(database: try AppDatabase.open(at: base.appendingPathComponent("veri", isDirectory: true)))
        let k = try Self.kur(store)
        let folders = BrandFolders(root: base.appendingPathComponent("Marka Çalışma Alanı", isDirectory: true), store: store)
        let inbox = SuggestionInbox(folders: folders)
        let zarf = """
        {"surum": 2, "uretici": "Codex", "gerekce": "Görüşmede iki teslim tarihi çelişiyor",
         "dayanak": ["\(k.aKaynak1)", "\(k.aGozlem)"], "gorevler": [{"baslik": "Tarihi netleştir"}, {"baslik": "Müşteriye yaz"}]}
        """
        let birinci = try inbox.importEnvelope(Data(zarf.utf8), brandId: k.a, sourceName: "zarf.json")
        #expect(birinci.count == 2)
        for p in birinci {
            let e = try store.proposalEvidence(p)
            #expect(e.rationale == "Görüşmede iki teslim tarihi çelişiyor")
            #expect(e.chips.map(\.id) == [k.aKaynak1, k.aGozlem])
            #expect(e.chips.map(\.kind) == [.source, .observation])
        }
        // Gerekçesiz ikinci zarf (şema 1, pano): kendi önerisi gerekçe göstermez; birincinin gerekçesi ona geçmez.
        let ikinci = try inbox.importEnvelope(Data(#"{"surum": 1, "gorevler": [{"baslik": "Ayrı iş"}]}"#.utf8), brandId: k.a, sourceName: "")
        #expect(ikinci.count == 1)
        let e2 = try store.proposalEvidence(try #require(ikinci.first))
        #expect(e2.rationale == nil && !e2.hasEvidence)
        #expect(try store.proposalEvidence(try #require(birinci.first)).rationale == "Görüşmede iki teslim tarihi çelişiyor")
        // Başka markanın önerisi bu zarfın gerekçesini görmez.
        let bOneri = try store.createProposal(sessionId: nil, brandId: k.b, kind: .createTask, summary: "B",
                                              payload: ProposalPayload.CreateTask(title: "B işi"))
        #expect(try store.proposalEvidence(bOneri).rationale == nil)
    }

    @Test func terminalOnerisiZarfGerekcesiGostermez() throws {
        let k = try Self.kur()
        // Terminal kökenli öneri: zarf denetim kaydı aranmaz (yalnız `.external`).
        var p = AIProposal(sessionId: nil, brandId: k.a, kind: .createTask, summary: "T",
                           payloadJSON: Self.json(ProposalPayload.CreateTask(title: "T")), origin: .terminal, originRef: "gorevler.json")
        try k.store.writer.write { db in try p.insert(db) }
        #expect(try k.store.proposalEvidence(p).rationale == nil)
        p.origin = nil
        #expect(try !k.store.proposalEvidence(p).hasEvidence)
    }
}
