import Testing
import Foundation
@testable import MarkaCore

@Suite struct EkipSablonuTests {
    @Test func enAzUcSablonVarVeHerRolunTarifiDolu() {
        #expect(TeamTemplates.all.count >= 3)
        #expect(Set(TeamTemplates.all.map(\.key)).count == TeamTemplates.all.count)
        for t in TeamTemplates.all {
            #expect(!t.roles.isEmpty)
            #expect(Set(t.roles.map(\.name)).count == t.roles.count)
            for r in t.roles { #expect(!r.name.isEmpty && !r.title.isEmpty && !r.charter.isEmpty && !r.skills.isEmpty) }
        }
    }

    @Test func sablonKurulumuOnayBekleyenOneriAcarUygulanmisSifirdir() throws {
        let store = try makeStore()
        let own = try store.createBrand(name: "Nova Stüdyo", isOwn: true)
        let r = try store.proposeTeamTemplate(TeamTemplates.agency)
        let n = TeamTemplates.agency.roles.count
        #expect(r.proposals.count == n && r.skipped.isEmpty)
        #expect(try store.proposals(brandId: own.id, status: .pending).count == n)
        #expect(try store.proposals(brandId: own.id, status: .applied).isEmpty)
        #expect(try store.teamMembers().isEmpty)   // onaydan önce ekip oluşmaz
    }

    @Test func sablonYalnizStudyoMarkasindaCalisirMusteriMarkasindaYokSayilir() throws {
        let store = try makeStore()
        // Stüdyo kurulmamış: ret.
        _ = try store.createBrand(name: "Deneme Yangın")
        #expect(throws: MarkaError.self) { try store.proposeTeamTemplate(TeamTemplates.soloConsultant) }
        #expect(try store.proposals(brandId: try #require(try store.brands().first).id).isEmpty)
        // Müşteri markasına doğrudan çalışan önerisi de reddedilir (şablonun dayandığı yol).
        let customer = try #require(try store.brands().first)
        #expect(throws: MarkaError.self) {
            try store.createProposal(sessionId: nil, brandId: customer.id, kind: .createTeamMember, summary: "x",
                                     payload: ProposalPayload.CreateTeamMember(name: "A", title: "B"))
        }
    }

    @Test func ayniSablonIkinciKezKuruluncaVarOlanRolAtlanir() throws {
        let store = try makeStore()
        let own = try store.createBrand(name: "Nova Stüdyo", isOwn: true)
        let t = TeamTemplates.agency
        // Bir rolü elle ekibe al; ikinci kurulumda o rol atlanmalı.
        _ = try store.saveTeamMember(TeamMember(kind: .ai, name: "metin yazarı", title: "Metin yazarı"))
        let first = try store.proposeTeamTemplate(t)
        #expect(first.skipped == ["Metin Yazarı"] && first.proposals.count == t.roles.count - 1)
        // Bekleyen öneriler varken tekrar kurmak çift öneri açmaz.
        let second = try store.proposeTeamTemplate(t)
        #expect(second.proposals.isEmpty && second.skipped.count == t.roles.count)
        #expect(try store.proposals(brandId: own.id, status: .pending).count == t.roles.count - 1)
        // Onaylanınca da atlanır.
        for p in first.proposals { _ = try store.applyProposal(p.id) }
        #expect(try store.proposeTeamTemplate(t).proposals.isEmpty)
    }

    @Test func sablonRolleriOnayliysaYoneticiAgaciDonguSuzOlur() throws {
        let store = try makeStore()
        _ = try store.createBrand(name: "Nova Stüdyo", isOwn: true)
        let boss = try store.saveTeamMember(TeamMember(kind: .human, name: "Aylin", title: "Kurucu", level: .director))
        let r = try store.proposeTeamTemplate(TeamTemplates.contentDesk, reportsToId: boss.id)
        for p in r.proposals { _ = try store.applyProposal(p.id) }
        let all = try store.teamMembers()
        #expect(all.count == 1 + TeamTemplates.contentDesk.roles.count)
        let byId = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        for m in all {
            var cursor = m.reportsToId, hops = 0
            while let c = cursor { cursor = byId[c]?.reportsToId; hops += 1; #expect(hops <= all.count) ; if hops > all.count { break } }
        }
        #expect(try store.orgChart().count == 1)
        #expect(try store.orgChart().first?.children.count == TeamTemplates.contentDesk.roles.count)
        // Olmayan yönetici kimliği reddedilir, öneri açılmaz.
        #expect(throws: MarkaError.self) { try store.proposeTeamTemplate(TeamTemplates.agency, reportsToId: "yok") }
    }

    @Test func kutuphanedeOlmayanYetenekAdiSerbestMetinOlarakKalir() throws {
        let store = try makeStore()
        _ = try store.createBrand(name: "Nova Stüdyo", isOwn: true)
        let librarySkills = Set(try store.skills().map(\.name))
        #expect(!librarySkills.contains("rapor-hazirlama"))   // kütüphane boş: ad serbest metin
        let r = try store.proposeTeamTemplate(TeamTemplates.agency)
        for p in r.proposals { _ = try store.applyProposal(p.id) }
        let reporter = try #require(try store.teamMembers(kind: .ai).first { $0.name == "Rapor Hazırlayıcı" })
        #expect(reporter.skills == ["rapor-hazirlama"])
        #expect(try store.skills().isEmpty)   // şablon kütüphaneye yetenek eklemez
    }

    @Test func vazgecilenSablondaBekleyenOneriSayisiSifirKalir() throws {
        let store = try makeStore()
        let own = try store.createBrand(name: "Nova Stüdyo", isOwn: true)
        let r = try store.proposeTeamTemplate(TeamTemplates.soloConsultant)
        #expect(try store.proposals(brandId: own.id, status: .pending).count == r.proposals.count)
        for p in r.proposals { try store.rejectProposal(p.id) }
        #expect(try store.proposals(brandId: own.id, status: .pending).count == 0)
        #expect(try store.teamMembers().isEmpty)
    }
}
