import Foundation
import Testing
@testable import MarkaCore

/// 0.2.1: tek onay bandı ve kenar çubuğu sayıları. Terminal + uygulama içi öneriler + bilgi güncellemeleri tek sayımda,
/// marka kapsamlı; karar verilince sayıdan düşer.
@Suite struct OnayBandiTests {
    func gorevOnerisi(_ title: String) -> SuggestionDraft {
        SuggestionDraft(kind: .createTask, summary: "Yeni görev: " + title, payload: ProposalPayload.CreateTask(title: title))
    }

    @Test func bekleyenlerTerminalUygulamaIciVeBilgiOnerileriniMarkayaGoreAyirir() throws {
        let store = try makeStore()
        let a = try store.createBrand(name: "A")
        let b = try store.createBrand(name: "B")
        try store.ingestSuggestionFile(brandId: a.id, fileName: "g.json", sha256: "s1", drafts: [gorevOnerisi("Bir"), gorevOnerisi("İki")])
        try store.createProposal(sessionId: nil, brandId: a.id, kind: .createTask, summary: "Sohbetten",
                                 payload: ProposalPayload.CreateTask(title: "Sohbetten görev"))
        try store.writeWikiRevision(brandId: a.id, pageId: nil, kind: .person, title: "Ayşe", body: "Müdür", claims: [], actor: .ai)
        try store.ingestSuggestionFile(brandId: b.id, fileName: "b.json", sha256: "s2", drafts: [gorevOnerisi("Başka marka")])

        let p = try store.pendingApprovals(brandId: a.id)
        #expect(p.suggestions.map(\.summary) == ["Yeni görev: Bir", "Yeni görev: İki"])
        #expect(p.proposals.map(\.summary) == ["Sohbetten"])
        #expect(p.revisions.count == 1)
        #expect(p.count == 4)
        #expect(try store.pendingApprovalCounts() == [a.id: 4, b.id: 1])
    }

    @Test func kullanicininYazdigiBilgiSurumuOnayBeklemez() throws {
        let store = try makeStore()
        let a = try store.createBrand(name: "A")
        try store.writeWikiRevision(brandId: a.id, pageId: nil, kind: .person, title: "Ayşe", body: "Müdür", claims: [], actor: .user)
        #expect(try store.pendingApprovals(brandId: a.id).isEmpty)
        #expect(try store.pendingApprovalCounts().isEmpty)
    }

    @Test func kararVerilinceSayidanDuserVeSonOnaylananlardaGorunur() throws {
        let store = try makeStore()
        let a = try store.createBrand(name: "A")
        let created = try store.ingestSuggestionFile(brandId: a.id, fileName: "g.json", sha256: "s1", drafts: [gorevOnerisi("Bir"), gorevOnerisi("İki")])
        let app = try store.createProposal(sessionId: nil, brandId: a.id, kind: .createTask, summary: "Sohbetten",
                                           payload: ProposalPayload.CreateTask(title: "Sohbetten görev"))
        let rev = try store.writeWikiRevision(brandId: a.id, pageId: nil, kind: .person, title: "Ayşe", body: "Müdür", claims: [], actor: .ai)

        try store.decideSuggestions(brandId: a.id, decisions: [SuggestionDecision(proposalId: created[0].id, accept: true),
                                                                SuggestionDecision(proposalId: created[1].id, accept: false)])
        try store.applyProposal(app.id)
        try store.approveRevision(rev.id)
        #expect(try store.pendingApprovals(brandId: a.id).isEmpty)
        #expect(try store.pendingApprovalCounts().isEmpty)

        let recent = try store.recentlyAppliedProposals(brandId: a.id)
        #expect(Set(recent.map(\.id)) == [created[0].id, app.id])
        // Geri alınan öneri "son onaylananlar"dan çıkar.
        try store.revertProposal(app.id)
        #expect(try store.recentlyAppliedProposals(brandId: a.id).map(\.id) == [created[0].id])
    }

    @Test func bolumlerKisayolVeKayitEslemesiSabittir() {
        #expect(BrandSection.allCases == [.flow, .todo, .report])
        #expect(BrandSection.allCases.map(\.shortcutDigit) == [1, 2, 3])
        #expect(BrandSection.section(for: .workLog) == .flow)
        #expect(BrandSection.section(for: .source) == .flow)
        #expect(BrandSection.section(for: .task) == .todo)
        #expect(BrandSection.section(for: .brandRecord) == .todo)
        #expect(BrandSection.section(for: .report) == .report)
        #expect(BrandSection.section(for: .wikiPage) == nil)
    }
}
