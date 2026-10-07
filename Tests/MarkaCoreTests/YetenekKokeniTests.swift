import Foundation
import GRDB
import Testing
@testable import MarkaCore

/// E-07 (docs/entegrasyon-plani-30.md): yeteneğin kökeni, gövde özeti ve içe aktarma tarihi (migration v11_yetenek_kokeni).
/// Tüm adlar uydurmadır; bellek içi ya da geçici klasördeki veritabanı kullanılır.
@Suite struct YetenekKokeniTests {
    static let skillMd = "---\nname: Kampanya Kontrolü\ndescription: Kampanya metnini denetler.\n---\nAdım 1: hedefi oku."

    func paket(_ ad: String = "kampanya-kontrolu", refs: [String: String] = [:]) throws -> URL {
        let dir = try tempDir("yetenek-koken").appendingPathComponent(ad)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(Self.skillMd.utf8).write(to: dir.appendingPathComponent("SKILL.md"))
        for (rel, text) in refs {
            let url = dir.appendingPathComponent("references").appendingPathComponent(rel)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        return dir
    }

    func olaylar(_ store: Store, _ id: String) throws -> [String] {
        try store.auditTrail(entity: "skill", entityId: id).map(\.action).sorted()
    }

    @Test func v11MigrationEskiSatirlariPaketVeElleOlarakDoldurur() throws {
        let dir = try tempDir("v11")
        let store = Store(database: try AppDatabase.open(at: dir))
        // v11'den sonra yalnız v12 marka radarı (E-21) gelir; o `skill`'e dokunmaz.
        #expect(AppDatabase.migrationIdentifiers.suffix(2) == ["v11_yetenek_kokeni", "v12_marka_radari"])
        let elle = try store.saveSkill(Skill(name: "elle-yazilan", description: "Elle."))
        _ = try store.installSkillPack(SkillPacks.method)
        let paketSayisi = SkillPacks.method.skills.count
        // v11 öncesi şemayı taklit et: sütunlar ve migration kaydı yok, satırlar yerinde.
        if let pool = store.database.writer as? DatabasePool { try pool.close() }
        let q = try DatabaseQueue(path: dir.appendingPathComponent("workspace.sqlite").path)
        try q.write { db in
            for c in ["origin", "contentHash", "importedAt"] { try db.execute(sql: "ALTER TABLE skill DROP COLUMN \(c)") }
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'v11_yetenek_kokeni'")
        }
        #expect(try q.read { db in try db.columns(in: "skill").map(\.name) }.contains("origin") == false)
        try q.close()

        let again = Store(database: try AppDatabase.open(at: dir))
        let hepsi = try again.skills()
        #expect(hepsi.count == paketSayisi + 1)
        #expect(hepsi.first { $0.id == elle.id }?.originKind == .manual)
        #expect(hepsi.filter { !$0.pack.isEmpty }.allSatisfy { $0.originKind == .pack })
        #expect(hepsi.filter { $0.originKind == .pack }.count == paketSayisi)
        // Eski satırın özeti bilinmiyor: boş ve "yerel değişiklik" yok; içe aktarma tarihi yok.
        #expect(hepsi.allSatisfy { $0.contentHash.isEmpty && $0.importedAt == nil && !$0.hasLocalChanges && !$0.isImported })
    }

    @Test func dosyadanIceAktarilanYetenekteKokenOzetVeTarihDolu() throws {
        let store = try makeStore()
        let once = Date().addingTimeInterval(-1)
        let s = try store.importSkill(markdown: Self.skillMd, fileName: "/geçici/klasör/SKILL.md")
        let kayit = try #require(try store.skills().first { $0.id == s.id })
        #expect(kayit.originKind == .file("SKILL.md"))   // tam yol saklanmaz, yalnız dosya adı
        #expect(kayit.origin == "file:SKILL.md" && kayit.isImported)
        #expect(kayit.contentHash == Skill.digest(body: "Adım 1: hedefi oku.") && kayit.contentHash.count == 64)
        #expect(try #require(kayit.importedAt) >= once)
        #expect(!kayit.hasLocalChanges)
        #expect(try olaylar(store, s.id) == ["create"])
    }

    @Test func klasorPaketiIceAktarilincaKokenKlasorAdiVeOzetBirlesikGovdeden() throws {
        let store = try makeStore()
        let klasor = try paket(refs: ["ton.md": "Sade yaz."])
        let p = SkillBundleReader.preview(try SkillBundleReader.read(folder: klasor), existing: try store.skills())
        let olayOnce = try store.read { db in try AuditEvent.fetchCount(db) }
        let s = try store.importSkillBundle(p, folderName: klasor.lastPathComponent)
        let kayit = try #require(try store.skills().first { $0.id == s.id })
        #expect(kayit.originKind == .folder("kampanya-kontrolu") && kayit.isImported)
        #expect(kayit.body == p.combinedBody.trimmed)
        #expect(kayit.contentHash == Skill.digest(body: kayit.body))
        #expect(kayit.importedAt != nil && !kayit.hasLocalChanges)
        #expect(try store.read { db in try AuditEvent.fetchCount(db) } == olayOnce + 1)
        #expect(try olaylar(store, s.id) == ["create"])
    }

    @Test func govdeDuzenleninceYerelDegisiklikDogruVeKokenKorunur() throws {
        let store = try makeStore()
        let ilk = try store.importSkill(markdown: Self.skillMd, fileName: "SKILL.md")
        let s = try #require(try store.skills().first { $0.id == ilk.id })   // veritabanındaki (milisaniye) tarih
        // Başlık değişikliği gövdeyi değiştirmez: yerel değişiklik yok.
        var d = s; d.title = "Kampanya denetimi"
        let baslik = try store.saveSkill(d)
        #expect(!baslik.hasLocalChanges)
        // Gövde değişince var; köken, özet ve tarih korunur.
        var g = baslik; g.body = "Adım 1: hedefi oku.\nAdım 2: tonu denetle."
        let duzenli = try store.saveSkill(g)
        #expect(duzenli.hasLocalChanges)
        #expect(duzenli.origin == s.origin && duzenli.contentHash == s.contentHash && duzenli.importedAt == s.importedAt)
        #expect(try store.skills().first { $0.id == s.id }?.hasLocalChanges == true)
        // Gövde geri dönünce yok.
        var geri = duzenli; geri.body = "Adım 1: hedefi oku."
        #expect(try !store.saveSkill(geri).hasLocalChanges)
        #expect(try olaylar(store, s.id) == ["create", "update", "update", "update"])
    }

    @Test func disaAktarilanSkillMdyeKokenAlaniYazilmaz() throws {
        let store = try makeStore()
        let klasor = try paket("ozel-klasor-adi")
        let p = SkillBundleReader.preview(try SkillBundleReader.read(folder: klasor), existing: [])
        let s = try store.importSkillBundle(p, folderName: klasor.lastPathComponent)
        let metin = SkillMarkdown.export(s)
        for iz in ["origin", "folder:", "ozel-klasor-adi", "contentHash", s.contentHash, "importedAt", "manual"] {
            #expect(!metin.contains(iz), "Dışa aktarımda köken izi: \(iz)")
        }
        // Geri okunan metin aynı yetenektir.
        let geri = try #require(SkillMarkdown.parse(metin))
        #expect(geri.name == s.name && geri.description == s.description && geri.body == s.body)
    }

    @Test func elleVePaketKokeniSaveSkillYolundanUydurulamaz() throws {
        let store = try makeStore()
        // Yeni kayıtta çağıranın verdiği köken yok sayılır.
        let sahte = try store.saveSkill(Skill(name: "sahte-koken", description: "x", body: "b",
                                              origin: "folder:baska", contentHash: "abc", importedAt: Date()))
        #expect(sahte.originKind == .manual && sahte.contentHash.isEmpty && sahte.importedAt == nil)
        // Elle yazılanın gövdesi değişse de "yerel değişiklik" gösterilmez (karşılaştırılacak özet yok).
        var g = sahte; g.body = "yeni"; g.origin = "file:x"
        let guncel = try store.saveSkill(g)
        #expect(guncel.originKind == .manual && !guncel.hasLocalChanges)
        // Hazır paket: köken 'pack', özet dolu, içe aktarma tarihi yok.
        _ = try store.installSkillPack(SkillPacks.method)
        let paket = try store.skills().filter { $0.pack == SkillPacks.method.key }
        #expect(!paket.isEmpty && paket.allSatisfy { $0.originKind == .pack && !$0.contentHash.isEmpty && $0.importedAt == nil })
        #expect(paket.allSatisfy { !$0.hasLocalChanges && !$0.isImported })
    }

    @Test func paketGuncellemesiKimligiKorurBayatOnizlemeyiReddeder() throws {
        let store = try makeStore()
        _ = try store.saveSkill(Skill(name: "kampanya-kontrolu", description: "Eski.", body: "eski", pack: "pazarlama"))
        let eski = try #require(try store.skills().first)   // veritabanındaki (milisaniye) tarih
        let p = SkillBundleReader.preview(try SkillBundleReader.read(folder: try paket()), existing: try store.skills())
        #expect(p.action == .update)
        let s = try store.importSkillBundle(p, folderName: "kampanya-kontrolu")
        #expect(s.id == eski.id && s.createdAt == eski.createdAt && s.pack == "pazarlama")
        #expect(s.originKind == .folder("kampanya-kontrolu") && s.importedAt != nil && !s.hasLocalChanges)
        #expect(try store.skills().count == 1)
        #expect(try olaylar(store, s.id) == ["create", "update"])

        // Önizlemeden sonra kayıt silindi: bayat önizleme yazılmaz, kütüphane sayısı değişmez.
        try store.deleteSkill(eski.id)
        #expect(throws: MarkaError.self) { try store.importSkillBundle(p) }
        #expect(try store.skills().isEmpty)
        // "Ekleme" önizlemesinden sonra aynı ad eklendi: ad tekilliği reddeder.
        let ekle = SkillBundleReader.preview(try SkillBundleReader.read(folder: try paket()), existing: [])
        _ = try store.saveSkill(Skill(name: "kampanya-kontrolu", description: "Araya giren."))
        #expect(throws: MarkaError.self) { try store.importSkillBundle(ekle) }
        #expect(try store.skills().count == 1)
    }

    @Test func kokenHamDegeriGidipGelirVeAdSadelesir() {
        for o in [SkillOrigin.manual, .pack, .file("SKILL.md"), .folder("seo-denetimi")] {
            #expect(SkillOrigin(rawValue: o.rawValue) == o)
        }
        #expect(SkillOrigin(rawValue: "bilinmeyen") == .manual)
        #expect(SkillOrigin.cleanName("/a/b/paket\nadı") == "paket adı")
        #expect(SkillOrigin.cleanName(String(repeating: "k", count: 300)).count == 128)
        #expect(SkillOrigin.folder("x").sourceName == "x" && SkillOrigin.pack.sourceName.isEmpty)
    }
}
