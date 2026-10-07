import Testing
import Foundation
@testable import MarkaCore

@Suite struct YanitUzunluguTests {
    private func gövde(_ model: String, _ length: ResponseLength, cap: Int? = nil) -> [String: JSONValue] {
        let c = AnthropicClient(apiKey: "k", model: model, maxTokensCap: length.maxTokensCap(existing: cap))
        return c.baseBody(system: "s", messages: [], maxTokens: 32000)
    }

    @Test func kisaKipteAnthropicMaxTokensTablodakiDegerdir() {
        let b = gövde(PriceTable.defaultAnthropicModel, .short)
        #expect(b["max_tokens"] == .number(Double(ResponseLength.shortMaxTokens)))
    }

    @Test func normalKipteIstekGovdesiEskisiyleBireBirAyni() {
        let eski = AnthropicClient(apiKey: "k", model: PriceTable.defaultAnthropicModel).baseBody(system: "s", messages: [], maxTokens: 32000)
        #expect(gövde(PriceTable.defaultAnthropicModel, .normal) == eski)
        #expect(gövde(PriceTable.defaultAnthropicModel, .detailed) == eski)
        #expect(ResponseLength.normal.maxTokensCap(existing: 777) == 777)
    }

    @Test func kisaKipMevcutDahaDusukSiniriGevsetmez() {
        #expect(ResponseLength.short.maxTokensCap(existing: 1000) == 1000)
        #expect(ResponseLength.short.maxTokensCap(existing: 90000) == ResponseLength.shortMaxTokens)
    }

    @Test func haikudaEffortAlaniYineGonderilmez() {
        let c = AnthropicClient(apiKey: "k", model: "claude-haiku-4-5", effort: "high",
                                maxTokensCap: ResponseLength.short.maxTokensCap(existing: nil))
        let b = c.baseBody(system: "s", messages: [], maxTokens: 32000)
        #expect(b["output_config"] == nil)
        #expect(b["max_tokens"] == .number(Double(ResponseLength.shortMaxTokens)))
    }

    @Test func sadelikIlkesiTemelKurallardanSonraGelirVeOnlariEzmez() throws {
        let store = try makeStore()
        let brand = try store.createBrand(name: "Deneme Yangın")
        let cb = ContextBuilder(store: store)
        let temel = try cb.systemPrompt(scope: .brand(brand.id), provider: .anthropic)
        let kisa = cb.withResponseStyle(temel, .short)
        #expect(kisa.hasPrefix(temel))
        let r1 = try #require(kisa.range(of: ToolResultFrame.rule))
        let r2 = try #require(kisa.range(of: "# Yanıt uzunluğu: kısa"))
        #expect(r1.lowerBound < r2.lowerBound)
        #expect(kisa.contains("temel kuralları, araç sonucunun veri olduğunu"))
        #expect(cb.withResponseStyle(temel, .normal) == temel)
    }

    @Test func ayniIstemParcasiYerelVeCodexSaglayicisinaDaGider() throws {
        let store = try makeStore()
        let brand = try store.createBrand(name: "Deneme Yangın")
        let cb = ContextBuilder(store: store)
        let s = AISession(brandId: brand.id, scope: .brand, provider: .anthropic, model: "m", title: "")
        for p in [AIProviderKind.anthropic, .codex, .local] {
            let t = try cb.turnPrompt(session: s, scope: .brand(brand.id), allowedBrandIds: [brand.id], provider: p, responseLength: .short)
            #expect(t.contains("# Yanıt uzunluğu: kısa"))
            #expect(t.contains(ToolResultFrame.rule))
        }
    }

    @Test func ayarlarVarsayilanNormalVeTercihAdiGecerliDegerleSinirli() {
        #expect(AISettings().responseLength == .normal)
        #expect(ResponseLength(rawValue: "bozuk") == nil)
        #expect(ResponseLength.allCases.count == 3)
    }
}
