import Foundation
import GRDB
import Testing
@testable import MarkaCore

/// İ7: terminal/CLI öneri köprüsü. Marka klasöründeki `oneriler/*.json` → bekleyen öneri → kullanıcı onayı → kayıt; geri alınabilir.
@Suite struct TerminalOneriTests {
    struct Ortam {
        let store: Store
        let folders: BrandFolders
        let a: Brand
        let b: Brand
        let dirA: URL
        let dirB: URL
        var inbox: SuggestionInbox { SuggestionInbox(folders: folders) }
        var kutuA: URL { dirA.appendingPathComponent("oneriler", isDirectory: true) }
        var kutuB: URL { dirB.appendingPathComponent("oneriler", isDirectory: true) }
    }

    /// Diskte çalışma alanı + iki markanın klasörü (öneri kutuları BAGLAM.md yazılınca oluşur).
    func ortam() throws -> Ortam {
        let base = try tempDir("oneri")
        let store = Store(database: try AppDatabase.open(at: base.appendingPathComponent("veri", isDirectory: true)))
        let a = try store.createBrand(name: "Kuzey Lojistik")
        let b = try store.createBrand(name: "Gizli Şirket")
        let folders = BrandFolders(root: base.appendingPathComponent("Marka Çalışma Alanı", isDirectory: true), store: store)
        let dirA = try folders.writeContextFile(brandId: a.id).deletingLastPathComponent()
        let dirB = try folders.writeContextFile(brandId: b.id).deletingLastPathComponent()
        return Ortam(store: store, folders: folders, a: a, b: b, dirA: dirA, dirB: dirB)
    }

    func yaz(_ json: String, _ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try json.write(to: url, atomically: true, encoding: .utf8)
    }

    func kabul(_ proposals: [AIProposal]) -> [SuggestionDecision] {
        proposals.map { SuggestionDecision(proposalId: $0.id, accept: true) }
    }

    func dosyaVar(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    // MARK: Geçerli dosya

    @Test func gecerliDosyaOnerilerOlusturOnaylaGorevlerDogruMarkadaOlusurGeriAlinir() throws {
        let o = try ortam()
        // Dosyadaki marka adı/kimliği yok sayılır: marka dosyanın bulunduğu klasörden gelir.
        try yaz("""
        {"surum": 1, "tur": "gorevler", "marka": "Gizli Şirket", "markaId": "\(o.b.id)",
         "gorevler": [
           {"baslik": "Web sitesi", "aciklama": "Ana sayfa", "sonTarih": "2026-09-30", "oncelik": "yuksek"},
           {"baslik": "Katalog metinleri", "oncelik": "düşük", "durum": "Sürüyor", "sorumlu": "Danışman"}
         ]}
        """, o.kutuA.appendingPathComponent("gorevler.json"))

        let r = o.inbox.scan(brandId: o.a.id)
        #expect(r.failures.isEmpty)
        #expect(r.created.count == 2)
        #expect(r.created.allSatisfy { $0.brandId == o.a.id && $0.origin == .terminal && $0.status == .pending && $0.originRef == "gorevler.json" })
        #expect(try o.store.pendingSuggestions(brandId: o.a.id).map(\.summary) == ["Yeni görev: Web sitesi", "Yeni görev: Katalog metinleri"])
        #expect(try o.store.pendingSuggestions(brandId: o.b.id).isEmpty)
        // AI veri değiştirmez: onaydan önce görev yok.
        #expect(try o.store.tasks(brandId: o.a.id).isEmpty)
        // İşlenen dosya `islenmis/` altına taşınır; ingest denetim olayı bırakır.
        #expect(!dosyaVar(o.kutuA.appendingPathComponent("gorevler.json")))
        #expect(dosyaVar(o.kutuA.appendingPathComponent("islenmis/gorevler.json")))
        #expect(try o.store.read { db in try AuditEvent.filter(Column("entity") == "suggestionFile" && Column("action") == "ingest").fetchCount(db) } == 1)

        // İnceleme: ilkinin başlığı ve son tarihi düzeltilir.
        let pending = try o.store.pendingSuggestions(brandId: o.a.id)
        let applied = try o.store.decideSuggestions(brandId: o.a.id, decisions: [
            SuggestionDecision(proposalId: pending[0].id, accept: true, title: "Web sitesi v1", changeDueDate: true, dueDate: "2026-10-01"),
            SuggestionDecision(proposalId: pending[1].id, accept: true),
        ])
        #expect(applied.count == 2 && applied.allSatisfy { $0.status == .applied })
        let tasks = try o.store.tasks(brandId: o.a.id).sorted { $0.title < $1.title }
        #expect(tasks.map(\.title) == ["Katalog metinleri", "Web sitesi v1"])
        #expect(tasks[1].dueDate == "2026-10-01" && tasks[1].priority == 3 && tasks[1].notes == "Ana sayfa")
        #expect(tasks[0].priority == 1 && tasks[0].status == .inProgress && tasks[0].assignee == "Danışman")
        #expect(tasks.allSatisfy { $0.actor == .ai })
        #expect(try o.store.tasks(brandId: o.b.id).isEmpty)
        #expect(try o.store.auditTrail(entity: "aiProposal", entityId: pending[0].id).map(\.action) == ["edit"])
        #expect(try o.store.pendingSuggestions(brandId: o.a.id).isEmpty)

        // Geri alma: görevler silinir, öneriler "geri alındı".
        try o.store.revertSuggestions(brandId: o.a.id, proposalIds: applied.map(\.id))
        #expect(try o.store.tasks(brandId: o.a.id).isEmpty)
        #expect(try o.store.proposals(brandId: o.a.id).allSatisfy { $0.status == .reverted })
    }

    @Test func ayniDosyaIkinciKezOnerilmez() throws {
        let o = try ortam()
        let json = #"{"surum": 1, "gorevler": [{"baslik": "reklam kampanyası başlangıç"}]}"#
        try yaz(json, o.kutuA.appendingPathComponent("a.json"))
        #expect(o.inbox.scan(brandId: o.a.id).created.count == 1)
        // Aynı içerik başka adla ya da aynı adla yeniden yazılsa da (sha256) ikinci kez önerilmez.
        try yaz(json, o.kutuA.appendingPathComponent("a.json"))
        try yaz(json, o.kutuA.appendingPathComponent("kopya.json"))
        let r = o.inbox.scan(brandId: o.a.id)
        #expect(r.created.isEmpty && r.failures.isEmpty)
        #expect(try o.store.pendingSuggestions(brandId: o.a.id).count == 1)
        // Kopyalar da işlenmiş klasörüne taşınır (ad çakışınca sha önekiyle).
        let processed = try FileManager.default.contentsOfDirectory(atPath: o.kutuA.appendingPathComponent("islenmis").path)
        #expect(processed.count == 3)
        // Taşıma başarısız olsa bile (dosya yerinde kalsa) sha kaydı yeniden öneriyi engeller.
        try yaz(json, o.kutuA.appendingPathComponent("yine.json"))
        try FileManager.default.removeItem(at: o.kutuA.appendingPathComponent("islenmis"))
        try "engel".write(to: o.kutuA.appendingPathComponent("islenmis"), atomically: true, encoding: .utf8)
        #expect(o.inbox.scan(brandId: o.a.id).created.isEmpty)
        #expect(dosyaVar(o.kutuA.appendingPathComponent("yine.json")))
        #expect(o.inbox.scan(brandId: o.a.id).created.isEmpty)
        #expect(try o.store.pendingSuggestions(brandId: o.a.id).count == 1)
        // Aynı içerik başka markanın kutusunda o markaya ayrıca önerilir (kayıt marka başınadır).
        try yaz(json, o.kutuB.appendingPathComponent("b.json"))
        #expect(o.inbox.scan(brandId: o.b.id).created.count == 1)
    }

    // MARK: Reddedilen dosyalar

    @Test func bozukSemaDisiVeCokBuyukDosyaReddedilirGorevOlusmaz() throws {
        let o = try ortam()
        let big = "{\"surum\": 1, \"gorevler\": [{\"baslik\": \"x\", \"aciklama\": \"" + String(repeating: "a", count: 300_000) + "\"}]}"
        let many = "{\"surum\": 1, \"gorevler\": [" + (1...51).map { "{\"baslik\": \"g\($0)\"}" }.joined(separator: ",") + "]}"
        let cases: [(String, String)] = [
            ("bozuk.json", #"{"surum": 1, "gorevler": [ {"baslik": "Yarım"#),
            ("dizi.json", #"[{"baslik": "Kök dizi"}]"#),
            ("surumyok.json", #"{"gorevler": [{"baslik": "Sürümsüz"}]}"#),
            ("surum2.json", #"{"surum": 2, "gorevler": [{"baslik": "Gelecek"}]}"#),
            ("surumbool.json", #"{"surum": true, "gorevler": [{"baslik": "Mantıksal"}]}"#),
            ("bos.json", #"{"surum": 1, "gorev": [{"baslik": "Yanlış anahtar"}]}"#),
            ("basliksiz.json", #"{"surum": 1, "gorevler": [{"baslik": "İyi"}, {"aciklama": "başlık yok"}]}"#),
            ("tarih.json", #"{"surum": 1, "gorevler": [{"baslik": "Tarih", "sonTarih": "30.09.2026"}]}"#),
            ("oncelik.json", #"{"surum": 1, "gorevler": [{"baslik": "Öncelik", "oncelik": 7}]}"#),
            ("durum.json", #"{"surum": 1, "gorevler": [{"baslik": "Durum", "durum": "belki"}]}"#),
            ("uzun.json", "{\"surum\": 1, \"gorevler\": [{\"baslik\": \"" + String(repeating: "u", count: 201) + "\"}]}"),
            ("tur.json", #"{"surum": 1, "kayitlar": [{"tur": "fatura", "baslik": "Bilinmeyen tür"}]}"#),
            ("kayitsiz.json", #"{"surum": 1, "calismaKayitlari": [{"baslik": "Ne yapıldı yok"}]}"#),
            ("buyuk.json", big),
            ("cok.json", many),
        ]
        for (name, json) in cases { try yaz(json, o.kutuA.appendingPathComponent(name)) }
        let r = o.inbox.scan(brandId: o.a.id)
        #expect(r.created.isEmpty)
        #expect(Set(r.failures.map(\.fileName)) == Set(cases.map { "oneriler/" + $0.0 }))
        #expect(r.failures.allSatisfy { !$0.message.isEmpty })
        #expect(r.failures.first { $0.fileName == "oneriler/basliksiz.json" }?.message.contains("2. görev") == true)
        #expect(r.failures.first { $0.fileName == "oneriler/buyuk.json" }?.message.contains("256 KB") == true)
        #expect(try o.store.pendingSuggestions(brandId: o.a.id).isEmpty)
        #expect(try o.store.tasks(brandId: o.a.id).isEmpty)
        #expect(try o.store.read { db in try SuggestionFile.fetchCount(db) } == 0)
        // Hatalı dosyalar taşınmaz: kullanıcı/araç düzeltip yeniden yazabilir.
        for (name, _) in cases { #expect(dosyaVar(o.kutuA.appendingPathComponent(name))) }
        // Aynı dosya durumu için parmak izi değişmez (arayüz hatayı bir kez gösterir).
        let again = o.inbox.scan(brandId: o.a.id)
        #expect(Set(again.failures.map(\.fingerprint)) == Set(r.failures.map(\.fingerprint)))
    }

    @Test func sembolikBagVeMarkaKlasoruDisiReddedilir() throws {
        let o = try ortam()
        let fm = FileManager.default
        // B'nin kutusundaki dosya.
        try yaz(#"{"surum": 1, "gorevler": [{"baslik": "B'nin gizli görevi"}]}"#, o.kutuB.appendingPathComponent("gizli.json"))
        try "GIZLI-B".write(to: o.dirB.appendingPathComponent("gizli.txt"), atomically: true, encoding: .utf8)
        // 1) A'nın kutusunda B'nin dosyasına giden sembolik bağ.
        try fm.createSymbolicLink(at: o.kutuA.appendingPathComponent("bag.json"), withDestinationURL: o.kutuB.appendingPathComponent("gizli.json"))
        // 2) Çalışma kaydı dosya yolu marka klasörünün dışına çıkıyor ("..").
        try yaz(#"{"surum": 1, "calismaKayitlari": [{"baslik": "Kaçış", "neYapildi": "x", "girdiDosyalari": ["../Gizli Şirket/gizli.txt"]}]}"#,
                o.kutuA.appendingPathComponent("kacis.json"))
        // 3) Mutlak yol.
        try yaz("{\"surum\": 1, \"calismaKayitlari\": [{\"baslik\": \"Mutlak\", \"neYapildi\": \"x\", \"ciktiDosyalari\": [\"\(o.dirB.appendingPathComponent("gizli.txt").path)\"]}]}",
                o.kutuA.appendingPathComponent("mutlak.json"))
        // 4) Marka klasörü içinde ama başka markaya giden bağ üzerinden dosya.
        try fm.createSymbolicLink(at: o.dirA.appendingPathComponent("ciktilar/kopru"), withDestinationURL: o.dirB)
        try yaz(#"{"surum": 1, "calismaKayitlari": [{"baslik": "Köprü", "neYapildi": "x", "ciktiDosyalari": ["ciktilar/kopru/gizli.txt"]}]}"#,
                o.kutuA.appendingPathComponent("kopru.json"))
        // 5) Başka markanın kimliğiyle görev tamamlama / kaynak bağlama.
        let bTask = try o.store.saveTask(WorkTask(brandId: o.b.id, title: "B görevi"))
        let bSource = try o.store.addTextSource(brandId: o.b.id, kind: .note, title: "B notu", body: "gizli")
        try yaz("{\"surum\": 1, \"gorevler\": [{\"baslik\": \"B görevi\", \"durum\": \"bitti\", \"gorevId\": \"\(bTask.id)\"}]}",
                o.kutuA.appendingPathComponent("bgorev.json"))
        try yaz("{\"surum\": 1, \"calismaKayitlari\": [{\"baslik\": \"B kaynağı\", \"neYapildi\": \"x\", \"girdiKaynaklari\": [\"\(bSource.id)\"]}]}",
                o.kutuA.appendingPathComponent("bkaynak.json"))

        let r = o.inbox.scan(brandId: o.a.id)
        #expect(r.created.isEmpty)
        #expect(Set(r.failures.map(\.fileName)) == ["oneriler/bag.json", "oneriler/kacis.json", "oneriler/mutlak.json",
                                                    "oneriler/kopru.json", "oneriler/bgorev.json", "oneriler/bkaynak.json"])
        #expect(try o.store.pendingSuggestions(brandId: o.a.id).isEmpty)
        #expect(try o.store.sources(brandId: o.a.id, includeArchived: true).isEmpty)
        #expect(try o.store.task(bTask.id).status == .todo)
        // B'nin dosyası yerinde; A'nın taraması onu taşımadı.
        #expect(dosyaVar(o.kutuB.appendingPathComponent("gizli.json")))

        // 6) `oneriler` klasörünün kendisi B'nin kutusuna giden bağ: hiç okunmaz.
        try fm.removeItem(at: o.kutuA)
        try fm.createSymbolicLink(at: o.kutuA, withDestinationURL: o.kutuB)
        let r2 = o.inbox.scan(brandId: o.a.id)
        #expect(r2.created.isEmpty && r2.failures.map(\.fileName) == ["oneriler"])
        #expect(try o.store.pendingSuggestions(brandId: o.a.id).isEmpty)
        #expect(dosyaVar(o.kutuB.appendingPathComponent("gizli.json")))
        // B kendi kutusunu tarayınca yalnızca B'ye öneri olur.
        #expect(o.inbox.scan(brandId: o.b.id).created.map(\.brandId) == [o.b.id])
    }

    @Test func hataTaniKaydiIcerikVeDosyaAdiTasimaz() throws {
        let o = try ortam()
        try yaz(#"{"surum": 1, "gorevler": [{"baslik": "ABC gizli proje adı", "sonTarih": "yarın"}]}"#, o.kutuA.appendingPathComponent("abc-ozel.json"))
        let failure = try #require(o.inbox.scan(brandId: o.a.id).failures.first)
        #expect(failure.message.contains("sonTarih"))
        let entry = DiagnosticEntry(error: failure.error, context: "terminal.oneri")
        #expect(entry.context == "terminal.oneri")
        for secret in ["ABC", "abc-ozel", "yarın", "sonTarih", "oneriler"] { #expect(!entry.line.contains(secret)) }
    }

    // MARK: Gün sonu dökümü

    @Test func gunSonuDokumuGorevCalismaKaydiKayitVeNotuOnaylaGeriAl() throws {
        let o = try ortam()
        let open = try o.store.saveTask(WorkTask(brandId: o.a.id, title: "Katalog metinleri"))
        let project = Project(brandId: o.a.id, name: "Klinik Lansmanı")
        try o.store.saveProject(project)
        try "# Marka tanımı\nKonumlandırma".write(to: o.dirA.appendingPathComponent("ciktilar/marka-tanimi.md"), atomically: true, encoding: .utf8)
        try "brief".write(to: o.dirA.appendingPathComponent("brief.txt"), atomically: true, encoding: .utf8)
        try yaz("""
        {"surum": 1,
         "gorevler": [
           {"baslik": "Web sitesi", "durum": "bitti", "proje": "klinik lansmanı"},
           {"baslik": "katalog METİNLERİ", "durum": "bitti"}
         ],
         "calismaKayitlari": [
           {"baslik": "Marka tanımı yazıldı", "neIstendi": "Klinik için marka tanımı", "neYapildi": "Konumlandırma metni",
            "karar": "Ton: sıcak", "kimOnayladi": "Müşteri", "musteriyeBildirilen": "Taslak gönderildi", "tarih": "2026-09-18",
            "gorev": "Web sitesi", "girdiDosyalari": ["brief.txt"], "ciktiDosyalari": ["ciktilar/marka-tanimi.md"]}
         ],
         "kayitlar": [{"tur": "Söz", "baslik": "Cuma'ya kadar site taslağı", "sonTarih": "2026-09-26"}],
         "not": {"tur": "gorusme", "baslik": "Ön görüşme", "metin": "Öncelik web sitesi.", "tarih": "2026-09-18"}
        }
        """, o.kutuA.appendingPathComponent("2026-09-18-gun-sonu.json"))

        let r = o.inbox.scan(brandId: o.a.id)
        #expect(r.failures.isEmpty)
        #expect(r.created.map(\.kind) == [.createTask, .completeTask, .createBrandRecord, .createNote, .createWorkLog])
        // Dosya taranırken kaynak oluşmaz (yalnızca içerik adresli depoya alınır).
        #expect(try o.store.sources(brandId: o.a.id, includeArchived: true).isEmpty)

        let applied = try o.store.decideSuggestions(brandId: o.a.id, decisions: kabul(r.created))
        #expect(applied.count == 5)
        let tasks = try o.store.tasks(brandId: o.a.id)
        let web = try #require(tasks.first { $0.title == "Web sitesi" })
        #expect(web.status == .done && web.completedAt != nil && web.projectId == project.id)
        #expect(try o.store.task(open.id).status == .done, "açık görev yeniden açılmadı, tamamlandı")
        #expect(tasks.count == 2)
        let log = try #require(try o.store.workLogs(brandId: o.a.id).first)
        #expect(log.status == .draft && log.taskId == web.id && log.approvedBy == "Müşteri" && log.decision == "Ton: sıcak")
        #expect(DayString.from(log.occurredAt) == "2026-09-18")
        let detail = try o.store.workLogDetail(log.id)
        #expect(detail.inputs.map(\.fileName) == ["brief.txt"] && detail.inputs.first?.kind == .file)
        #expect(detail.outputs.map(\.fileName) == ["marka-tanimi.md"] && detail.outputs.first?.kind == .workOutput)
        #expect(detail.outputs.first?.body.contains("Konumlandırma") == true)
        let record = try #require(try o.store.records(brandId: o.a.id).first)
        #expect(record.kind == .promise && record.dueDate == "2026-09-26")
        let note = try #require(try o.store.sources(brandId: o.a.id, kinds: [.meeting]).first)
        #expect(note.body == "Öncelik web sitesi." && note.actor == .ai)
        #expect(try o.store.tasks(brandId: o.b.id).isEmpty && o.store.workLogs(brandId: o.b.id).isEmpty)

        // Hepsi geri alınır: kayıt silinir, oluşturulan kaynaklar arşivlenir, açık görev yeniden açılır.
        try o.store.revertSuggestions(brandId: o.a.id, proposalIds: applied.map(\.id))
        #expect(try o.store.workLogs(brandId: o.a.id).isEmpty)
        #expect(try o.store.tasks(brandId: o.a.id).map(\.id) == [open.id])
        #expect(try o.store.task(open.id).status == .todo)
        #expect(try o.store.records(brandId: o.a.id).isEmpty)
        #expect(try o.store.sources(brandId: o.a.id).isEmpty, "oluşan kaynaklar arşivde")
        #expect(try o.store.sources(brandId: o.a.id, includeArchived: true).count == 3)
    }

    @Test func secilmeyenlerReddedilirKullaniciDuzeltmesiSonrasiGeriAlmaEngellenir() throws {
        let o = try ortam()
        try yaz(#"{"surum": 1, "gorevler": [{"baslik": "Bir"}, {"baslik": "İki"}]}"#, o.kutuA.appendingPathComponent("x.json"))
        let created = o.inbox.scan(brandId: o.a.id).created
        let applied = try o.store.decideSuggestions(brandId: o.a.id, decisions: [
            SuggestionDecision(proposalId: created[0].id, accept: true),
            SuggestionDecision(proposalId: created[1].id, accept: false),
        ])
        #expect(applied.map(\.id) == [created[0].id])
        #expect(try o.store.proposals(brandId: o.a.id, status: .rejected).map(\.id) == [created[1].id])
        #expect(try o.store.auditTrail(entity: "aiProposal", entityId: created[1].id).map(\.action) == ["reject"])
        #expect(try o.store.tasks(brandId: o.a.id).map(\.title) == ["Bir"])
        // Sonuçlanmış öneri yeniden karara sokulamaz; başka markanın önerisi bu markadan kararlaştırılamaz.
        #expect(throws: MarkaError.self) { try o.store.decideSuggestions(brandId: o.a.id, decisions: kabul([created[1]])) }
        try yaz(#"{"surum": 1, "gorevler": [{"baslik": "B işi"}]}"#, o.kutuB.appendingPathComponent("b.json"))
        let bp = o.inbox.scan(brandId: o.b.id).created
        #expect(throws: MarkaError.brandScope) { try o.store.decideSuggestions(brandId: o.a.id, decisions: kabul(bp)) }
        // Kullanıcı görevi sonradan düzenlediyse mevcut kural geçerli: geri alma reddedilir.
        var t = try #require(try o.store.tasks(brandId: o.a.id).first)
        t.notes = "elle"
        try o.store.saveTask(t)
        #expect(throws: MarkaError.self) { try o.store.revertSuggestions(brandId: o.a.id, proposalIds: applied.map(\.id)) }
        #expect(try o.store.tasks(brandId: o.a.id).count == 1)
    }

    /// 0.2.1 U9: onay sayfası yalnız seçilenleri karara sokar; seçilmeyenler bekler. Dosya ilk taramada bütünüyle öneriye
    /// dönüşüp `islenmis/`'e taşındığı ve sha'sı kaydedildiği için yeniden önerilmez; bekleyenler veri tabanında kalır.
    @Test func kismenOnaylananDosyaninBekleyenleriKalirDosyaYenidenOnerilmez() throws {
        let o = try ortam()
        let json = #"{"surum": 1, "gorevler": [{"baslik": "Bir"}, {"baslik": "İki"}, {"baslik": "Üç"}]}"#
        try yaz(json, o.kutuA.appendingPathComponent("gun.json"))
        let created = o.inbox.scan(brandId: o.a.id).created
        #expect(created.count == 3)
        #expect(!dosyaVar(o.kutuA.appendingPathComponent("gun.json")))
        #expect(dosyaVar(o.kutuA.appendingPathComponent("islenmis/gun.json")))

        // Yalnız seçilen karara girer (seçilmeyenler için karar gönderilmez).
        let applied = try o.store.decideSuggestions(brandId: o.a.id, decisions: kabul([created[0]]))
        #expect(applied.map(\.id) == [created[0].id])
        #expect(try o.store.pendingSuggestions(brandId: o.a.id).map(\.id) == [created[1].id, created[2].id])
        #expect(try o.store.pendingApprovals(brandId: o.a.id).count == 2)
        #expect(try o.store.pendingApprovalCounts()[o.a.id] == 2)
        #expect(try o.store.proposals(brandId: o.a.id, status: .rejected).isEmpty, "hiçbiri reddedilmedi")

        // Aynı dosya yeniden yazılsa da önerilmez; bekleyenler kaybolmaz ve sonradan onaylanabilir.
        try yaz(json, o.kutuA.appendingPathComponent("gun.json"))
        #expect(o.inbox.scan(brandId: o.a.id).created.isEmpty)
        #expect(try o.store.pendingSuggestions(brandId: o.a.id).count == 2)
        try o.store.decideSuggestions(brandId: o.a.id, decisions: kabul([created[2]]))
        #expect(Set(try o.store.tasks(brandId: o.a.id).map(\.title)) == ["Bir", "Üç"])
        #expect(try o.store.pendingSuggestions(brandId: o.a.id).map(\.id) == [created[1].id])
    }

    // MARK: Klasör ve BAGLAM.md

    @Test func oneriDosyalariIsCiktisiAdayiOlarakListelenmez() throws {
        let o = try ortam()
        try "çıktı".write(to: o.dirA.appendingPathComponent("ciktilar/rapor.md"), atomically: true, encoding: .utf8)
        try yaz(#"{"surum": 1, "gorevler": [{"baslik": "x"}]}"#, o.kutuA.appendingPathComponent("a.json"))
        try yaz("{}", o.kutuA.appendingPathComponent("islenmis/eski.json"))
        let names = try o.folders.importableFiles(brandId: o.a.id).map(\.lastPathComponent)
        #expect(names == ["rapor.md"])
    }

    @Test func yazilmasiSurenDosyaAtlanirSonraOkunur() throws {
        let o = try ortam()
        // Yarım yazılmış dosya (terminal hâlâ yazıyor): periyodik tarama yeni değişmiş dosyayı atlar, hata göstermez.
        try yaz(#"{"surum": 1, "gorevler": [{"baslik": "Yar"#, o.kutuA.appendingPathComponent("yarim.json"))
        let early = o.inbox.scan(brandId: o.a.id, settle: 60)
        #expect(early.created.isEmpty && early.failures.isEmpty)
        try yaz(#"{"surum": 1, "gorevler": [{"baslik": "Yarım kalmadı"}]}"#, o.kutuA.appendingPathComponent("yarim.json"))
        #expect(o.inbox.scan(brandId: o.a.id, settle: 60, now: Date().addingTimeInterval(120)).created.count == 1)
    }

    @Test func klasoruOlmayanMarkaTaranirkenKlasorOlusturulmaz() throws {
        let o = try ortam()
        let c = try o.store.createBrand(name: "Yeni Marka")
        #expect(o.inbox.scan(brandId: c.id).created.isEmpty)
        #expect(try o.store.setting("folder.\(c.id)") == nil)
        #expect(!dosyaVar(o.folders.root.appendingPathComponent("Yeni Marka")))
    }

    @Test func baglamDosyasiOneriTalimatiniVeGecerliOrnegiTasir() throws {
        let o = try ortam()
        let text = try String(contentsOf: o.dirA.appendingPathComponent("BAGLAM.md"), encoding: .utf8)
        #expect(text.contains("uygulamanın veri tabanına yazamaz"))
        #expect(text.contains("oneriler/<tarih>-<konu>.json"))
        #expect(text.contains("markdown olarak yazma"))
        #expect(dosyaVar(o.kutuA))
        // Talimattaki örnek şemaya uyar ve bu markada öneriye dönüşür (örnekteki çıktı dosyası varsa).
        let example = try #require(text.components(separatedBy: "```json\n").dropFirst().first?.components(separatedBy: "```").first)
        let doc = try SuggestionDocument.parse(Data(example.utf8))
        #expect(doc.tasks.count == 2 && doc.workLogs.count == 1 && doc.records.count == 1 && doc.notes.count == 1)
        try "tanım".write(to: o.dirA.appendingPathComponent("ciktilar/marka-tanimi.md"), atomically: true, encoding: .utf8)
        try yaz(example, o.kutuA.appendingPathComponent("ornek.json"))
        let r = o.inbox.scan(brandId: o.a.id)
        #expect(r.failures.isEmpty && r.created.count == 5)
    }

    @Test func claudeVeAgentsDosyasiBaglamaYonlendirirKullanicininkineDokunulmaz() throws {
        let o = try ortam()
        let claude = try String(contentsOf: o.dirA.appendingPathComponent("CLAUDE.md"), encoding: .utf8)
        #expect(claude.hasPrefix(BrandFolders.agentPointerMarker) && claude.contains("@BAGLAM.md") && claude.contains("oneriler/"))
        let agents = try String(contentsOf: o.dirA.appendingPathComponent("AGENTS.md"), encoding: .utf8)
        #expect(agents.contains("BAGLAM.md") && agents.contains("oneriler/"))
        // Kullanıcının kendi CLAUDE.md'si (işaretsiz) yeniden yazımda korunur; bağ izlenmez.
        try "# Benim kurallarım\n".write(to: o.dirB.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: o.dirB.appendingPathComponent("AGENTS.md"))
        try FileManager.default.createSymbolicLink(at: o.dirB.appendingPathComponent("AGENTS.md"), withDestinationURL: o.dirA.appendingPathComponent("AGENTS.md"))
        try o.folders.writeContextFile(brandId: o.b.id)
        #expect(try String(contentsOf: o.dirB.appendingPathComponent("CLAUDE.md"), encoding: .utf8) == "# Benim kurallarım\n")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: o.dirB.appendingPathComponent("AGENTS.md").path) == o.dirA.appendingPathComponent("AGENTS.md").path)
        // İş çıktısı adayı sayılmazlar.
        #expect(try o.folders.importableFiles(brandId: o.a.id).isEmpty)
    }

    // MARK: Uçtan uca: yalıtımlı terminal → dosya → tarama → onay

    /// Gerçek `sandbox-exec` + terminal profili: yalıtımlı kabuk kendi `oneriler/` kutusuna yazabilir, başka markanınkine yazamaz;
    /// uygulama (çekirdek) dosyayı tarar, onayla görevler doğru markada oluşur.
    @Test func yalitimliTerminaldenYazilanOneriOnaylaGoreveDonusur() throws {
        let o = try ortam()
        let ws = o.store.database.filesRoot.deletingLastPathComponent()
        let profile = try BrandIsolation(workspace: ws, folders: o.folders).terminalProfile(brandId: o.a.id).render()
        func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let json = #"{"surum":1,"gorevler":[{"baslik":"Web sitesi","sonTarih":"2026-09-30","oncelik":"yuksek"},{"baslik":"reklam kampanyası başlangıç"}]}"#
        let own = try SandboxRunner.run(profile: profile, ["/bin/sh", "-c",
            "cd \(q(o.dirA.path)) && mkdir -p oneriler && printf '%s' \(q(json)) > oneriler/2026-09-18-gorevler.json && echo yazildi"])
        #expect(own.status == 0 && own.stdout.contains("yazildi"))
        let other = try SandboxRunner.run(profile: profile, ["/bin/sh", "-c", "printf '%s' \(q(json)) > \(q(o.kutuB.appendingPathComponent("sizma.json").path))"])
        #expect(other.status != 0 && other.stderr.contains("Operation not permitted"))
        #expect(!dosyaVar(o.kutuB.appendingPathComponent("sizma.json")))
        // Uygulama verisi (veri tabanı) terminalden okunamaz: köprü yalnızca dosyadır.
        #expect(try SandboxRunner.run(profile: profile, ["/bin/ls", ws.path]).status != 0)

        let r = o.inbox.scan(brandId: o.a.id)
        #expect(r.failures.isEmpty && r.created.count == 2)
        #expect(o.inbox.scan(brandId: o.b.id).created.isEmpty)
        try o.store.decideSuggestions(brandId: o.a.id, decisions: kabul(r.created))
        #expect(Set(try o.store.tasks(brandId: o.a.id).map(\.title)) == ["Web sitesi", "reklam kampanyası başlangıç"])
        #expect(try o.store.tasks(brandId: o.b.id).isEmpty)
        #expect(dosyaVar(o.kutuA.appendingPathComponent("islenmis/2026-09-18-gorevler.json")))
    }
}
