import Foundation
import Testing
@testable import MarkaCore

@Suite struct SirketVeEkipTests {
    @Test func sirketProfiliYazilirVeDenetimBirakir() throws {
        let store = try makeStore()
        #expect(try store.companyProfile().isEmpty)
        let p = try store.saveCompanyProfile(CompanyProfile(name: "  Örnek Ajans  ", tagline: "Sakin iş", foundedOn: "2024-03-01"))
        #expect(p.name == "Örnek Ajans")
        #expect(try store.companyProfile().foundedOn == "2024-03-01")
        #expect(try store.auditTrail(entity: "company", entityId: "self").count == 1)
        #expect(throws: MarkaError.self) { try store.saveCompanyProfile(CompanyProfile(name: "A", foundedOn: "yarın")) }
    }

    @Test func hizmetSiralanirVeDogrulanir() throws {
        let store = try makeStore()
        _ = try store.saveService(ServiceOffering(name: "Sosyal medya", status: .paused, startedOn: "2024-01-01"))
        _ = try store.saveService(ServiceOffering(name: "Marka stratejisi", startedOn: "2024-05-01"))
        _ = try store.saveService(ServiceOffering(name: "Web sitesi", startedOn: "2024-02-01"))
        _ = try store.saveService(ServiceOffering(name: "Podcast", status: .planned))
        #expect(try store.services().map(\.name) == ["Web sitesi", "Marka stratejisi", "Podcast", "Sosyal medya"])
        #expect(throws: MarkaError.self) { try store.saveService(ServiceOffering(name: "  ")) }
    }

    @Test func yapayZekaCalisanAlanlariniTasirInsandaTemizlenir() throws {
        let store = try makeStore()
        var ai = TeamMember(kind: .ai, name: "Claude Code", title: "Kıdemli Yazılımcı", level: .senior,
                            provider: "anthropic", model: "claude-opus-5-5", charter: "Kodu inceler.", skills: [" test ", "", "refactor"])
        ai = try store.saveTeamMember(ai)
        #expect(ai.skills == ["test", "refactor"])
        #expect(ai.provider == "anthropic")
        let human = try store.saveTeamMember(TeamMember(kind: .human, name: "Deniz", title: "Tasarımcı", provider: "x", charter: "y", skills: ["z"]))
        #expect(human.provider.isEmpty && human.charter.isEmpty && human.skills.isEmpty)
    }

    @Test func yoneticiDongusuVeKendineBaglanmaReddedilir() throws {
        let store = try makeStore()
        let a = try store.saveTeamMember(TeamMember(kind: .human, name: "Aylin", title: "Kurucu", level: .director))
        var b = try store.saveTeamMember(TeamMember(kind: .ai, name: "B", title: "Lider", level: .lead, reportsToId: a.id))
        let c = try store.saveTeamMember(TeamMember(kind: .ai, name: "C", title: "Junior", level: .junior, reportsToId: b.id))
        var a2 = a; a2.reportsToId = c.id
        #expect(throws: MarkaError.self) { try store.saveTeamMember(a2) }
        b.reportsToId = b.id
        #expect(throws: MarkaError.self) { try store.saveTeamMember(b) }
    }

    @Test func organizasyonSemasiKidemSirasiylaAgacKurar() throws {
        let store = try makeStore()
        let boss = try store.saveTeamMember(TeamMember(kind: .human, name: "Aylin", title: "Kurucu", level: .director))
        let lead = try store.saveTeamMember(TeamMember(kind: .ai, name: "Lider", title: "Teknik lider", level: .lead, reportsToId: boss.id))
        _ = try store.saveTeamMember(TeamMember(kind: .ai, name: "Çaylak", title: "Junior", level: .junior, reportsToId: lead.id))
        _ = try store.saveTeamMember(TeamMember(kind: .ai, name: "Usta", title: "Senior", level: .senior, reportsToId: lead.id))
        let chart = try store.orgChart()
        #expect(chart.count == 1 && chart[0].member.id == boss.id)
        #expect(chart[0].children[0].children.map(\.member.name) == ["Usta", "Çaylak"])
    }

    @Test func arsivlemeAstlariUstuneDevreder() throws {
        let store = try makeStore()
        let boss = try store.saveTeamMember(TeamMember(kind: .human, name: "Aylin", title: "Kurucu", level: .director))
        let mid = try store.saveTeamMember(TeamMember(kind: .human, name: "Orta", title: "Yönetici", level: .lead, reportsToId: boss.id))
        let low = try store.saveTeamMember(TeamMember(kind: .ai, name: "Alt", title: "Junior", level: .junior, reportsToId: mid.id))
        try store.archiveTeamMember(mid.id)
        #expect(try store.teamMembers().map(\.id).contains(mid.id) == false)
        #expect(try store.teamMembers(includeArchived: true).count == 3)
        #expect(try store.orgChart()[0].children.map(\.member.id) == [low.id])
        try store.restoreTeamMember(mid.id)
        #expect(try store.teamMembers().count == 3)
    }

    @Test func atamaMarkayaBaglidirYalitilirVeTekLiderVardir() throws {
        let store = try makeStore()
        let b1 = try store.createBrand(name: "Deneme Yangın")
        let b2 = try store.createBrand(name: "Kuzey Lojistik")
        let a = try store.saveTeamMember(TeamMember(kind: .human, name: "Aylin", title: "Danışman", level: .senior))
        let c = try store.saveTeamMember(TeamMember(kind: .ai, name: "Claude Code", title: "Yazılımcı", level: .senior))
        try store.assignMember(a.id, to: b1.id, role: .lead)
        try store.assignMember(c.id, to: b1.id)
        try store.assignMember(c.id, to: b2.id)
        #expect(try store.brandTeam(brandId: b1.id).map(\.member.name) == ["Aylin", "Claude Code"])
        #expect(try store.brandTeam(brandId: b2.id).map(\.member.name) == ["Claude Code"])
        try store.assignMember(c.id, to: b1.id, role: .lead)
        let team = try store.brandTeam(brandId: b1.id)
        #expect(team.first?.member.name == "Claude Code" && team.first?.role == .lead)
        #expect(team.filter { $0.role == .lead }.count == 1)
        try store.unassignMember(c.id, from: b1.id)
        #expect(try store.brandTeam(brandId: b1.id).count == 1)
        #expect(try store.assignments(memberId: c.id).map(\.brandId) == [b2.id])
    }

    @Test func arsivdekiAtanmazVeBilinmeyenMarkaReddedilir() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Deneme Yangın")
        let m = try store.saveTeamMember(TeamMember(kind: .ai, name: "Eski", title: "Junior", level: .junior))
        try store.archiveTeamMember(m.id)
        #expect(throws: MarkaError.self) { try store.assignMember(m.id, to: b.id) }
        try store.restoreTeamMember(m.id)
        #expect(throws: MarkaError.self) { try store.assignMember(m.id, to: "yok") }
    }

    @Test func markaArsivlenseDeAtamaVeUyeKalir() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Deneme Yangın")
        let m = try store.saveTeamMember(TeamMember(kind: .human, name: "Aylin", title: "Danışman"))
        try store.assignMember(m.id, to: b.id)
        #expect(try store.assignments(memberId: m.id).count == 1)
        try store.setBrandArchived(b.id, archived: true)
        #expect(try store.teamMembers().count == 1)
        #expect(try store.assignments(memberId: m.id).count == 1)
    }

    @Test func uyeTuruDegistirilemez() throws {
        let store = try makeStore()
        var m = try store.saveTeamMember(TeamMember(kind: .human, name: "Aylin", title: "Danışman"))
        m.kind = .ai
        #expect(throws: MarkaError.self) { try store.saveTeamMember(m) }
    }

    @Test func yapayZekaBaglamiYalnizBuMarkanin_EkibiniVeSirketiTasir() throws {
        let store = try makeStore()
        let b1 = try store.createBrand(name: "Deneme Yangın")
        let b2 = try store.createBrand(name: "Kuzey Lojistik")
        _ = try store.saveCompanyProfile(CompanyProfile(name: "Örnek Ajans", mission: "Sakin iş"))
        let ai = try store.saveTeamMember(TeamMember(kind: .ai, name: "Claude Code", title: "Yazılımcı", level: .senior, charter: "Kodu inceler."))
        let other = try store.saveTeamMember(TeamMember(kind: .human, name: "Gizli Kişi", title: "Danışman", email: "gizli@ornek.test"))
        try store.assignMember(ai.id, to: b1.id, role: .lead)
        try store.assignMember(other.id, to: b2.id)
        // Şirket verisi yalnız Stüdyo oturumun sağlayıcısına izin verdiyse girer (B1/O1).
        let own = try store.createBrand(name: "Nova Stüdyo", isOwn: true)
        try store.setAIProviders(own.id, providers: [.anthropic])
        let ctx = try ContextBuilder(store: store).brandContext(brandId: b1.id, provider: .anthropic)
        #expect(ctx.contains("Örnek Ajans") && ctx.contains("Claude Code") && ctx.contains("Kodu inceler."))
        #expect(ctx.contains("ekip lideri"))
        #expect(!ctx.contains("Gizli Kişi") && !ctx.contains("gizli@ornek.test"))
    }

    @Test func oneriCalisanRoluylaAcilanSohbettenGeldiyseSahibiBilinir() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Deneme Yangın")
        let ai = try store.saveTeamMember(TeamMember(kind: .ai, name: "Claude Code", title: "Yazılımcı"))
        let withRole = AISession(brandId: b.id, scope: .brand, provider: .anthropic, model: "m", title: "", memberId: ai.id)
        let plain = AISession(brandId: b.id, scope: .brand, provider: .anthropic, model: "m", title: "")
        try store.write { db in try withRole.insert(db); try plain.insert(db) }
        let p1 = AIProposal(sessionId: withRole.id, brandId: b.id, kind: .createNote, summary: "a", payloadJSON: "{}")
        let p2 = AIProposal(sessionId: plain.id, brandId: b.id, kind: .createNote, summary: "b", payloadJSON: "{}")
        let p3 = AIProposal(sessionId: nil, brandId: b.id, kind: .createNote, summary: "c", payloadJSON: "{}")
        #expect(try store.proposer(of: p1)?.name == "Claude Code")
        #expect(try store.proposer(of: p2) == nil && store.proposer(of: p3) == nil)
        try store.archiveTeamMember(ai.id)
        #expect(try store.proposer(of: p1)?.name == "Claude Code")
    }

    @Test func kendiSirketTekdirEkibiHerkestirAtamaGerekmez() throws {
        let store = try makeStore()
        #expect(try store.ownBrand() == nil)
        let own = try store.createBrand(name: "Nova Stüdyo", isOwn: true)
        #expect(try store.ownBrand()?.id == own.id)
        #expect(throws: MarkaError.self) { try store.createBrand(name: "İkinci", isOwn: true) }
        let a = try store.saveTeamMember(TeamMember(kind: .human, name: "Aylin", title: "Kurucu", level: .director))
        let ai = try store.saveTeamMember(TeamMember(kind: .ai, name: "Claude Code", title: "Yazılımcı", level: .senior))
        let old = try store.saveTeamMember(TeamMember(kind: .ai, name: "Eski", title: "Junior"))
        try store.archiveTeamMember(old.id)
        #expect(try store.brandTeam(brandId: own.id).map(\.member.name) == ["Aylin", "Claude Code"])
        #expect(throws: MarkaError.self) { try store.assignMember(a.id, to: own.id) }
        let customer = try store.createBrand(name: "Deneme Yangın")
        #expect(try store.brandTeam(brandId: customer.id).isEmpty)
        // Rol: şirket sohbetinde etkin her yapay zekâ çalışan seçilebilir; müşteri sohbetinde atama gerekir.
        _ = try ContextBuilder(store: store).persona(memberId: ai.id, brandId: own.id)
        #expect(throws: MarkaError.self) { _ = try ContextBuilder(store: store).persona(memberId: ai.id, brandId: customer.id) }
        try store.setAIProviders(own.id, providers: [.anthropic])
        let ctx = try ContextBuilder(store: store).brandContext(brandId: own.id, provider: .anthropic)
        #expect(ctx.contains("kendi şirketimiz") && ctx.contains("Claude Code"))
    }

    @Test func sirketAdiKendiMarkaAdiniGuncellerCakismaVarsaDokunmaz() throws {
        let store = try makeStore()
        let own = try store.createBrand(name: "Eski Ad", isOwn: true)
        _ = try store.createBrand(name: "Kuzey Lojistik")
        _ = try store.saveCompanyProfile(CompanyProfile(name: "Nova Stüdyo"))
        #expect(try store.brand(own.id).name == "Nova Stüdyo")
        _ = try store.saveCompanyProfile(CompanyProfile(name: "kuzey lojistik"))
        #expect(try store.brand(own.id).name == "Nova Stüdyo")
    }

    @Test func iseAlimOnerisiYalnizSirketSohbetindeOnayliEkibeGirerGeriAlinincaArsivlenir() throws {
        let store = try makeStore()
        let own = try store.createBrand(name: "Nova Stüdyo", isOwn: true)
        let customer = try store.createBrand(name: "Deneme Yangın")
        let boss = try store.saveTeamMember(TeamMember(kind: .human, name: "Aylin", title: "Kurucu", level: .director))
        #expect(ToolCatalog.tools(for: .brand(own.id), store: store).contains { $0.name == "calisan_oner" })
        #expect(!ToolCatalog.tools(for: .brand(customer.id), store: store).contains { $0.name == "calisan_oner" })
        #expect(!ToolCatalog.tools(for: .allBrands, store: store).contains { $0.name == "calisan_oner" })
        let payload = ProposalPayload.CreateTeamMember(name: "Claude Haiku", title: "Araştırma asistanı", level: "junior", department: "İçerik",
                                                       reportsToId: boss.id, provider: "anthropic", model: "claude-haiku-4-5-20251001",
                                                       charter: "Kaynak tarar.", skills: ["kaynakli-arastirma"])
        // Müşteri markasında öneri açılamaz.
        #expect(throws: MarkaError.self) { try store.createProposal(sessionId: nil, brandId: customer.id, kind: .createTeamMember, summary: "x", payload: payload) }
        // Geçersiz yük (bilinmeyen kıdem, olmayan yönetici) reddedilir.
        #expect(throws: MarkaError.self) { try store.createProposal(sessionId: nil, brandId: own.id, kind: .createTeamMember, summary: "x",
                                                                      payload: ProposalPayload.CreateTeamMember(name: "A", title: "B", level: "efsane")) }
        #expect(throws: MarkaError.self) { try store.createProposal(sessionId: nil, brandId: own.id, kind: .createTeamMember, summary: "x",
                                                                      payload: ProposalPayload.CreateTeamMember(name: "A", title: "B", reportsToId: "yok")) }
        let p = try store.createProposal(sessionId: nil, brandId: own.id, kind: .createTeamMember, summary: "Yeni çalışan: Claude Haiku", payload: payload)
        // Onaydan önce ekipte yok.
        #expect(try store.teamMembers().count == 1)
        let applied = try store.applyProposal(p.id)
        let member = try #require(try store.teamMembers(kind: .ai).first)
        #expect(applied.resultEntityId == member.id && member.kind == .ai && member.level == .junior && member.reportsToId == boss.id)
        #expect(member.skills == ["kaynakli-arastirma"])
        #expect(try store.auditTrail(entity: "teamMember", entityId: member.id).first?.actor == .ai)
        try store.revertProposal(p.id)
        #expect(try store.teamMembers(kind: .ai).isEmpty)
        #expect(try store.teamMembers(includeArchived: true).count == 2)   // silinmedi, arşivlendi
    }

    @Test func calisanEtkinligiOnerileriDurumunaGoreSayar() throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Deneme Yangın")
        let ai = try store.saveTeamMember(TeamMember(kind: .ai, name: "Claude Code", title: "Yazılımcı"))
        let other = try store.saveTeamMember(TeamMember(kind: .ai, name: "Sessiz", title: "Junior"))
        try store.assignMember(ai.id, to: b.id)
        let s = AISession(brandId: b.id, scope: .brand, provider: .anthropic, model: "m", title: "", memberId: ai.id)
        let plain = AISession(brandId: b.id, scope: .brand, provider: .anthropic, model: "m", title: "")
        try store.write { db in try s.insert(db); try plain.insert(db) }
        for _ in 0..<2 { _ = try store.createProposal(sessionId: s.id, brandId: b.id, kind: .createTask, summary: "g", payload: ProposalPayload.CreateTask(title: "Görev")) }
        let done = try store.createProposal(sessionId: s.id, brandId: b.id, kind: .createTask, summary: "g", payload: ProposalPayload.CreateTask(title: "Biten"))
        _ = try store.applyProposal(done.id)
        _ = try store.createProposal(sessionId: plain.id, brandId: b.id, kind: .createTask, summary: "g", payload: ProposalPayload.CreateTask(title: "Asistan"))
        let a = try store.memberActivity()
        #expect(a[ai.id]?.pending == 2 && a[ai.id]?.applied == 1 && a[ai.id]?.lastActiveAt != nil)
        #expect(a[other.id] == nil)
    }
}
