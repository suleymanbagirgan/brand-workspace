import Foundation
import Testing
@testable import MarkaCore

@Suite struct YetenekTests {
    @Test func adTurkceKarakterlerdenSadelesir() {
        #expect(SkillMarkdown.slug("SEO Denetimi") == "seo-denetimi")
        #expect(SkillMarkdown.slug("Dönüşüm İyileştirme!") == "donusum-iyilestirme")
        #expect(SkillMarkdown.slug("  --Çok   boşluk-- ") == "cok-bosluk")
        #expect(SkillMarkdown.slug(String(repeating: "a", count: 100)).count == 64)
    }

    @Test func skillMdCozulurVeGeriYazilir() throws {
        let md = "---\nname: kod-incelemesi\ndescription: \"Kodu inceler. Birleştirmeden önce kullan.\"\nlicense: MIT\n---\n\n# Adımlar\n1. Oku\n2. Öner\n"
        let p = try #require(SkillMarkdown.parse(md))
        #expect(p.name == "kod-incelemesi" && p.description == "Kodu inceler. Birleştirmeden önce kullan.")
        #expect(p.body.hasPrefix("# Adımlar") && p.body.contains("2. Öner"))
        let again = try #require(SkillMarkdown.parse(SkillMarkdown.export(Skill(name: p.name, description: p.description, body: p.body))))
        #expect(again.name == p.name && again.body == p.body)
        #expect(SkillMarkdown.parse("başlık yok") == nil)
        #expect(SkillMarkdown.parse("---\nname: x\n---\ngövde") == nil)   // tanım zorunlu
    }

    @Test func kayitDogrulanirAdTekildir() throws {
        let store = try makeStore()
        _ = try store.saveSkill(Skill(name: "test-plani", description: "Test planı çıkarır."))
        #expect(throws: MarkaError.self) { try store.saveSkill(Skill(name: "test-plani", description: "ikinci")) }
        #expect(throws: MarkaError.self) { try store.saveSkill(Skill(name: "Büyük Harf", description: "x")) }
        #expect(throws: MarkaError.self) { try store.saveSkill(Skill(name: "bos-tanim", description: "  ")) }
        #expect(throws: MarkaError.self) { try store.saveSkill(Skill(name: "uzun", description: String(repeating: "a", count: 1025))) }
        let i = try store.importSkill(markdown: "---\nname: Müşteri Görüşmesi\ndescription: Hazırlık yapar.\n---\ngövde")
        #expect(i.name == "musteri-gorusmesi" && i.title == "Müşteri Görüşmesi")
        #expect(throws: MarkaError.self) { try store.importSkill(markdown: "bozuk") }
    }

    @Test func hazirPaketlerGecerliVeYenidenYuklenmesiDuzenlemeyiEzmez() throws {
        for pack in SkillPacks.all {
            for s in pack.skills {
                #expect(s.name == SkillMarkdown.slug(s.name) && s.description.count <= 1024 && !s.body.isEmpty, "\(s.name)")
            }
        }
        let store = try makeStore()
        let pack = SkillPacks.marketing
        #expect(try store.installSkillPack(pack) == pack.skills.count)
        var seo = try #require(try store.skills().first { $0.name == "seo-denetimi" })
        seo.body = "Benim düzenlemem"
        try store.saveSkill(seo)
        #expect(try store.installSkillPack(pack) == 0)
        #expect(try store.skills().first { $0.name == "seo-denetimi" }?.body == "Benim düzenlemem")
        #expect(SkillPacks.all.flatMap(\.skills).map(\.name).count == Set(SkillPacks.all.flatMap(\.skills).map(\.name)).count)
    }

    @Test func yetenekCalisaninBaglaminaGirerSerbestMetinDeKalir() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Deneme Yangın")
        _ = try store.saveSkill(Skill(name: "seo-denetimi", title: "SEO denetimi", description: "Arama görünürlüğünü denetler.", body: "ADIM-GOVDESI"))
        _ = try store.saveSkill(Skill(name: "baska-yetenek", description: "Bu üyede yok.", body: "BASKA-GOVDE"))
        let own = try store.createBrand(name: "Stüdyo", isOwn: true)
        try store.setAIProviders(own.id, providers: [.anthropic])
        let ai = try store.saveTeamMember(TeamMember(kind: .ai, name: "Claude Sonnet", title: "Yazar", skills: ["seo-denetimi", "serbest metin yetenek"]))
        try store.assignMember(ai.id, to: b.id)
        let session = AISession(brandId: b.id, scope: .brand, provider: .anthropic, model: "m", title: "", memberId: ai.id)
        let p = ContextBuilder(store: store).personaPrompt(session: session)
        #expect(p.contains("ADIM-GOVDESI") && p.contains("Arama görünürlüğünü denetler.") && p.contains("serbest metin yetenek"))
        #expect(!p.contains("BASKA-GOVDE"))
    }
}
