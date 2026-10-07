import Foundation
import GRDB
import Testing
@testable import MarkaCore

/// E-25: Apple Foundation Models sağlayıcısı (araçsız ilk dilim). Hiçbir test modeli çağırmaz: durum sabit verilir ve
/// "kullanılabilir" durumda yalnız oturum açılır (tur gönderilmez). Canlı yanıt kurucunun makinesinde elle denenir.
@Suite(.serialized) struct AppleSaglayiciTests {
    /// Sabit durumlu Apple sağlayıcısı (gerçek sistem durumu okunmaz).
    func apple(_ durum: AppleModelAvailability) -> AppleFoundationModelsProvider {
        var p = AppleFoundationModelsProvider()
        p.availability = { durum }
        return p
    }

    #if !MAS
    func motor(_ store: Store, providers: [any AIProvider]?) throws -> ChatEngine {
        ChatEngine(store: store, codex: CodexAppServer(), folders: BrandFolders(root: try tempDir("folders"), store: store),
                   workspace: try tempDir("ws"), settings: AISettings(), anthropicKey: { nil }, urlSession: .shared,
                   diagnostics: nil, providers: providers)
    }
    #endif

    func sabitTakvim() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return c
    }

    /// Denemenin günü: 2026-10-04 Pazar, öğleden sonra.
    func denemeGunu() -> Date {
        sabitTakvim().date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 15))!
    }

    @Test func appleSaglayicisiCihazUstuAracsizVeAnahtarsiz() async throws {
        let p = AppleFoundationModelsProvider()
        #expect(p.kind == .apple)
        #expect(p.capabilities.onDevice)
        #expect(!p.capabilities.supportsTools)
        #expect(!p.capabilities.needsAPIKey)
        #expect(p.capabilities.contextTokens == 4096)
        #expect(p.sessionModel(settings: AISettings()) == AppleFoundationModelsProvider.modelName)
        #expect(AIProviderKind(rawValue: "apple") == .apple)
        #expect(AIProviderKind.apple.displayName == L("Apple Intelligence (cihaz üstü)"))
        #if !MAS
        // Varsayılan kayıtta (providers: nil) Apple sağlayıcısı var.
        let e = try motor(try makeStore(), providers: nil)
        let kayitli = try await e.registry.provider(for: .apple)
        #expect(kayitli.kind == .apple && !kayitli.capabilities.supportsTools)
        #endif
    }

    @Test func masKipindeAppleSecilebilirVeAnthropicIleBirlikte() {
        #expect(AIProviderKind.selectable(mas: true) == [.anthropic, .apple])
        #expect(!AIProviderKind.selectable(mas: true).contains(.codex))
        #expect(!AIProviderKind.selectable(mas: true).contains(.local))
        #expect(AIProviderKind.selectable(mas: false) == AIProviderKind.allCases)
        #expect(AIProviderKind.apple.isSelectable)
    }

    @Test func kullanilamazkenAnlasilirTurkceHataVerirVeModelCagrilmaz() async throws {
        // Her durumun metni boş değil ve kullanılamaz durumlar hata verir.
        for d in AppleModelAvailability.allCases {
            #expect(!d.statusText.isEmpty)
            if d == .available { #expect(throws: Never.self) { try apple(d).requireAvailable() } }
            else { #expect(throws: MarkaError.self) { try apple(d).requireAvailable() } }
        }
        #expect(AppleModelAvailability.appleIntelligenceNotEnabled.statusText.hasPrefix(L("Apple Intelligence açık değil.")))
        #expect(AppleModelAvailability.unsupportedSystem.statusText.contains("macOS 26"))
        // Kullanıcının gördüğü metin, doğrulama hatası olarak olduğu gibi gösterilir (ham sağlayıcı metni değil).
        do { try apple(.appleIntelligenceNotEnabled).requireAvailable() } catch {
            #expect(AIFailure(error: error, provider: .apple).message == AppleModelAvailability.appleIntelligenceNotEnabled.statusText)
        }
        #if !MAS
        let store = try makeStore()
        let b = try store.createBrand(name: "Deneme Yangın")
        try store.setAIProviders(b.id, providers: [.apple])
        // Apple Intelligence kapalı: izin olsa da oturum açılmaz.
        let kapali = try motor(store, providers: [apple(.appleIntelligenceNotEnabled)])
        await #expect(throws: MarkaError.self) { try await kapali.createSession(scope: .brand(b.id), provider: .apple, title: "x") }
        // Açıkken açılmış bir oturuma, sonradan kapanan Apple Intelligence ile tur gönderilirse model çağrılmadan hata döner.
        let acik = try motor(store, providers: [apple(.available)])
        let s = try await acik.createSession(scope: .brand(b.id), provider: .apple, title: "x")
        var hatalar: [String] = [], metin = ""
        for await ev in await kapali.send(sessionId: s.id, text: "Kuzey Lojistik için kısa bir özet yaz") {
            switch ev {
            case .failed(let m): hatalar.append(m)
            case .textDelta(let t): metin += t
            default: break
            }
        }
        #expect(metin.isEmpty)
        #expect(hatalar == [AppleModelAvailability.appleIntelligenceNotEnabled.statusText])
        #endif
    }

    @Test func istemdeUygulamaninHesapladigiTarihTablosuVar() {
        let tablo = AppleDateTable.table(now: denemeGunu(), calendar: sabitTakvim())
        // Deneme §4b'deki beklenen değerler (bugün 2026-10-04 Pazar).
        #expect(tablo.contains("bugün=2026-10-04 pazar"))
        #expect(tablo.contains("yarın=2026-10-05"))
        #expect(tablo.contains("cuma=2026-10-09"))
        #expect(tablo.contains("pazartesi=2026-10-05"))
        #expect(tablo.contains("pazar=2026-10-11"))   // bugün pazar: "pazar" gelecek haftanınki
        #expect(tablo.contains("haftaya bugün=2026-10-11"))
        let talimat = AppleFoundationModelsProvider.instructions(system: "Sen bir asistansın.", now: denemeGunu(), calendar: sabitTakvim())
        #expect(talimat.hasPrefix("# Tarih tablosu"))
        #expect(talimat.contains("cuma=2026-10-09"))
        #expect(talimat.contains("aracın yok"))
        #expect(talimat.hasSuffix("Sen bir asistansın."))
    }

    @Test func kisaBaglamButcesiTalimatiVeGecmisiKirpar() {
        // Uzun genel istem kırpılır; tarih tablosu ve kurallar korunur.
        let uzun = String(repeating: "Örnek Kafe Zinciri kampanya notu, tutar 1.250 TL, 2026-09-30. ", count: 400)
        let talimat = AppleFoundationModelsProvider.instructions(system: uzun, now: denemeGunu(), calendar: sabitTakvim())
        #expect(talimat.count <= AppleContextBudget.instructionChars)
        #expect(talimat.contains("cuma=2026-10-09") && talimat.hasSuffix(AppleContextBudget.clippedMark))
        // Geçmiş: en yeniler kalır, son mesaj (şimdiki soru) her zaman var, toplam bütçeyi aşmaz.
        var mesajlar: [AIMessage] = []
        for i in 0..<40 {
            mesajlar.append(AIMessage(sessionId: "s", role: i % 2 == 0 ? .user : .assistant,
                                      text: "mesaj-\(i) " + String(repeating: "Deneme Yangın görev notu. ", count: 8)))
        }
        mesajlar.append(AIMessage(sessionId: "s", role: .user, text: "SIMDIKI-SORU: en acil iş hangisi?"))
        let istem = AppleContextBudget.prompt(messages: mesajlar)
        #expect(istem.count <= AppleContextBudget.promptChars)
        #expect(istem.hasSuffix("SIMDIKI-SORU: en acil iş hangisi?"))
        #expect(istem.contains("mesaj-39") && !istem.contains("mesaj-0 "))
        // Çok uzun tek soru da sığdırılır.
        let tek = AppleContextBudget.prompt(messages: [AIMessage(sessionId: "s", role: .user, text: uzun)])
        #expect(tek.count <= AppleContextBudget.promptChars)
        #expect(AppleContextBudget.prompt(messages: []).isEmpty)
    }

    #if !MAS
    @Test func appleIzniMarkaBasinaAyriVeVarsayilanKapali() async throws {
        let store = try makeStore()
        let b = try store.createBrand(name: "Kuzey Lojistik")
        let diger = try store.createBrand(name: "Örnek Kafe Zinciri")
        #expect(!(try store.brand(b.id)).allows(.apple))   // varsayılan: izin yok
        let e = try motor(store, providers: [apple(.available)])
        await #expect(throws: MarkaError.self) { try await e.createSession(scope: .brand(b.id), provider: .apple, title: "x") }
        // Başka sağlayıcıya izin Apple iznini açmaz.
        try store.setAIProviders(b.id, providers: [.anthropic, .local])
        await #expect(throws: MarkaError.self) { try await e.createSession(scope: .brand(b.id), provider: .apple, title: "x") }
        try store.setAIProviders(b.id, providers: [.apple])
        let s = try await e.createSession(scope: .brand(b.id), provider: .apple, title: "x")
        #expect(s.provider == .apple && s.model == AppleFoundationModelsProvider.modelName && s.brandId == b.id)
        // Tüm markalar kapsamında izinsiz marka kapsama girmez.
        #expect(try await e.allowedBrandIds(scope: .allBrands, provider: .apple) == [b.id])
        #expect(!(try store.brand(diger.id)).allows(.apple))
    }
    #endif

    @Test func cltIleDerlenirVeMakroKullanmaz() throws {
        // Bu SDK'da (CLT 26.x) çerçeve var: sağlayıcı gerçek yolla derlendi. Çerçevesiz SDK'da `#if canImport` dalı derlenir.
        #expect(AppleModelAvailability.frameworkCompiledIn)
        // Durum okuma modeli çağırmaz; hangi makinede olursa olsun tanımlı bir değer döner.
        #expect(AppleModelAvailability.allCases.contains(AppleModelAvailability.current()))
        // `@Generable`/`@Guide` makroları yalnız Xcode ile derlenir (deneme §1): kaynakta kullanılmaz.
        let kaynak = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/MarkaCore/AI/FoundationModelsProvider.swift")
        let metin = try String(contentsOf: kaynak, encoding: .utf8)
        #expect(!metin.contains("@" + "Generable") && !metin.contains("@" + "Guide"))
        #expect(metin.contains("#if canImport(FoundationModels)") && metin.contains("@available(macOS 26, *)"))
    }
}
