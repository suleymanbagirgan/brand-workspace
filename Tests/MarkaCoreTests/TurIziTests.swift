import Foundation
import Testing
@testable import MarkaCore

/// Belirteç kullanımı bildiren ya da hata fırlatan küçük kayıtlı sahte sağlayıcı (ağ yok, anahtar yok).
private final class KullanimliSaglayici: AIProvider, @unchecked Sendable {
    let kind: AIProviderKind
    let capabilities = AIProviderCapabilities(supportsTools: true, contextTokens: 4096, onDevice: true, needsAPIKey: false)
    let kullanimlar: [(Int, Int)]
    let hata: Error?

    init(kind: AIProviderKind = .anthropic, kullanimlar: [(Int, Int)] = [], hata: Error? = nil) {
        self.kind = kind; self.kullanimlar = kullanimlar; self.hata = hata
    }

    func sessionModel(settings: AISettings) -> String { "sahte-model" }
    func cancel(sessionId: String) async {}

    func runTurn(_ turn: AITurn, assistant: inout AIMessage) async throws {
        try turn.checkCancellation()
        assistant.text += "Yanıt."
        turn.emit(.textDelta("Yanıt."))
        for (giris, cikis) in kullanimlar {
            turn.emit(.usage(UsageEntry(provider: kind, model: "sahte-model", sessionId: turn.session.id, brandId: turn.session.brandId,
                                        purpose: "chat", inputTokens: giris, outputTokens: cikis, costMicros: nil)))
        }
        if let hata { throw hata }
    }
}

/// E-30: yerel yapay zekâ tur izi. İz içeriksizdir (sağlayıcı türü, süre, araç ADI sayacı, öneri/belirteç sayısı, sonuç türü),
/// yalnız bellekte 20'lik halkada durur ve Tanı raporunda "son_turlar" olarak görünür.
@Suite struct TurIziTests {
    static let marka = "GizliMarkaXYZ"
    static let govde = "sirMetin123"
    static let girdi = "araçGirdisiQWE"

    func engine(store: Store, providers: [any AIProvider], iz: TurnTraces) async throws -> ChatEngine {
        let e = ChatEngine(store: store, codex: CodexAppServer(), folders: BrandFolders(root: try tempDir("folders"), store: store),
                           workspace: try tempDir("ws"), settings: AISettings(), anthropicKey: { nil }, urlSession: .shared,
                           diagnostics: nil, providers: providers)
        await e.useTurnTraces(iz)
        return e
    }

    func kur(_ store: Store, provider: AIProviderKind = .anthropic) throws -> Brand {
        let b = try store.createBrand(name: Self.marka)
        try store.setAIProviders(b.id, providers: [provider])
        return b
    }

    func gonder(_ e: ChatEngine, _ sessionId: String, _ text: String) async {
        for await _ in await e.send(sessionId: sessionId, text: text) {}
    }

    func bosAnlik() -> DiagnosticSnapshot {
        DiagnosticSnapshot.collect(store: nil, log: DiagnosticsLog(url: nil), anthropicKeyPresent: false, codex: .bilinmiyor)
    }

    @Test func sahteSaglayiciTurundaIzAlanlariDogru() async throws {
        let store = try makeStore()
        let b = try kur(store)
        _ = try store.addTextSource(brandId: b.id, kind: .note, title: "Not", body: "Teklif \(Self.govde) burada.")
        let fake = FakeProvider(rounds: [
            [.tool("kaynak_ara", ["sorgu": "teklif"]), .tool("kaynak_ara", ["sorgu": "dolap"]), .tool("gorev_oner", ["baslik": "Teklifi kontrol et"])],
            [.text("Görev önerdim.")],
        ])
        let iz = TurnTraces()
        let e = try await engine(store: store, providers: [fake], iz: iz)
        let s = try await e.createSession(scope: .brand(b.id), provider: .anthropic, title: "Yeni oturum")
        await gonder(e, s.id, "Teklifi tamamla")

        let kayitlar = iz.entries()
        #expect(kayitlar.count == 1)
        let t = try #require(kayitlar.first)
        #expect(t.provider == .anthropic)
        #expect(t.outcome == .tamam)
        #expect(t.toolCalls == ["kaynak_ara": 2, "gorev_oner": 1])
        #expect(t.proposalCount == 1)
        #expect(t.durationMs >= 0)
        // FakeProvider kullanım bildirmez: belirteç alanı yazılmaz.
        #expect(t.inputTokens == nil && t.outputTokens == nil)
        #expect(!t.line.contains("giris=") && t.line.contains("sonuc=tamam araclar=gorev_oner:1,kaynak_ara:2 oneri=1"))

        // Kullanım bildiren sağlayıcıda belirteçler toplanır.
        let store2 = try makeStore()
        let b2 = try kur(store2)
        let iz2 = TurnTraces()
        let e2 = try await engine(store: store2, providers: [KullanimliSaglayici(kullanimlar: [(1200, 300), (50, 20)])], iz: iz2)
        let s2 = try await e2.createSession(scope: .brand(b2.id), provider: .anthropic, title: "Yeni oturum")
        await gonder(e2, s2.id, "Merhaba")
        let t2 = try #require(iz2.entries().first)
        #expect(t2.inputTokens == 1250 && t2.outputTokens == 320)
        #expect(t2.toolCalls.isEmpty && t2.line.contains("araclar=— oneri=0 giris=1250 cikis=320"))
    }

    @Test func aracGirdisiVeCiktisiIzdeSifirKezGecer() async throws {
        let store = try makeStore()
        let b = try kur(store)
        let src = try store.addTextSource(brandId: b.id, kind: .note, title: "Not", body: "Çıktı \(Self.govde) metni.")
        // Model uydurma bir araç adı da üretebilir (ad içerik taşıyabilir): izde yalnız "bilinmeyen" yazılır.
        let fake = FakeProvider(rounds: [
            [.tool("kaynak_oku", ["kaynak_id": .string(src.id)]), .tool("kaynak_ara", ["sorgu": .string(Self.girdi)]),
             .tool("\(Self.marka)_\(Self.govde)", ["x": .string(Self.girdi)])],
            [.text("Tamam.")],
        ])
        let iz = TurnTraces()
        let e = try await engine(store: store, providers: [fake], iz: iz)
        let s = try await e.createSession(scope: .brand(b.id), provider: .anthropic, title: "Yeni oturum")
        await gonder(e, s.id, "Oku")
        #expect(fake.toolResults.first?.text.contains(Self.govde) == true)   // araç çıktısı içeriği gerçekten taşıdı

        let t = try #require(iz.entries().first)
        #expect(t.toolCalls == ["kaynak_oku": 1, "kaynak_ara": 1, TurnTrace.unknownTool: 1])
        for gizli in [Self.govde, Self.girdi, Self.marka, src.id, "sorgu", "kaynak_id"] {
            #expect(t.line.components(separatedBy: gizli).count - 1 == 0, "İzde araç girdisi/çıktısı var: \(gizli)")
        }
    }

    /// Kanıt (`GizlilikTests` deseni): ayırt edici marka adı, içerik ve kimlikler raporda 0 kez geçer.
    @Test func taniRaporundaMarkaAdiVeIcerikSifirKezGecer() async throws {
        let store = try makeStore()
        let b = try kur(store)
        let fake = FakeProvider(rounds: [
            [.text("\(Self.marka) için \(Self.govde)."), .tool("gorev_oner", ["baslik": .string("\(Self.marka) \(Self.govde)")])],
            [.text("Bitti.")],
        ])
        let iz = TurnTraces()
        let e = try await engine(store: store, providers: [fake], iz: iz)
        let s = try await e.createSession(scope: .brand(b.id), provider: .anthropic, title: "Yeni oturum")
        await gonder(e, s.id, "\(Self.marka) \(Self.govde) özetle")

        let metin = DiagnosticReport.render(bosAnlik(), now: Date(), turns: iz.entries())
        #expect(metin.contains("son_turlar (1, yeniden eskiye):"))
        #expect(metin.contains("saglayici=anthropic") && metin.contains("araclar=gorev_oner:1 oneri=1"))
        let oneriId = try #require(try store.proposals(sessionId: s.id).first?.id)
        for gizli in [Self.marka, Self.govde, b.id, s.id, oneriId, "Bitti", "özetle", NSUserName()] {
            #expect(metin.components(separatedBy: gizli).count - 1 == 0, "Tanı raporunda içerik/kimlik var: \(gizli)")
        }
    }

    @Test func iptalEdilenTurDurdurulduTuruyleKaydedilir() async throws {
        let store = try makeStore()
        let b = try kur(store)
        let ref = EngineRef()
        let fake = FakeProvider(rounds: [
            [.tool("kaynak_ara", ["sorgu": "x"]), .hook({ await ref.engine?.cancel(sessionId: ref.sessionId) })],
            [.text("olmamalı")],
        ])
        let iz = TurnTraces()
        let e = try await engine(store: store, providers: [fake], iz: iz)
        ref.engine = e
        let s = try await e.createSession(scope: .brand(b.id), provider: .anthropic, title: "Yeni oturum")
        ref.sessionId = s.id
        await gonder(e, s.id, "Başla")
        let t = try #require(iz.entries().first)
        #expect(t.outcome == .durduruldu)
        #expect(t.toolCalls == ["kaynak_ara": 1])
        #expect(t.line.contains("sonuc=durduruldu"))
    }

    /// Hata yalnız TÜRÜYLE yazılır (H3-04 `AIErrorKind`); hata mesajı izde ve raporda yoktur.
    @Test func hataTuruYazilirMesajYazilmaz() async throws {
        let store = try makeStore()
        let b = try kur(store)
        let hata = MarkaError.ai("\(Self.marka) \(Self.govde) sağlayıcı ham gövdesi")
        let beklenen = AIFailure(error: hata, provider: .anthropic).kind
        let iz = TurnTraces()
        let e = try await engine(store: store, providers: [KullanimliSaglayici(hata: hata)], iz: iz)
        let s = try await e.createSession(scope: .brand(b.id), provider: .anthropic, title: "Yeni oturum")
        await gonder(e, s.id, "Merhaba")
        let t = try #require(iz.entries().first)
        #expect(t.outcome == .hata(beklenen))
        #expect(t.line.contains("sonuc=hata.\(beklenen.rawValue)"))
        let metin = DiagnosticReport.render(bosAnlik(), now: Date(), turns: iz.entries())
        for gizli in [Self.marka, Self.govde, "ham gövdesi"] {
            #expect(metin.components(separatedBy: gizli).count - 1 == 0, "Hata mesajı rapora girdi: \(gizli)")
        }
    }

    @Test func tamponYirmideSinirliRaporYenidenEskiyeYazar() {
        let iz = TurnTraces()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        for i in 0..<35 { iz.record(TurnTrace(at: t0.addingTimeInterval(Double(i)), provider: .codex, durationMs: 1000 + i, outcome: .tamam)) }
        let kayitlar = iz.entries()
        #expect(TurnTraces.capacity == 20)
        #expect(kayitlar.count == 20)
        #expect(kayitlar.first?.durationMs == 1015 && kayitlar.last?.durationMs == 1034)

        // Daha uzun liste verilse de rapor en çok 20 yazar, yeniden eskiye.
        let liste = (0..<30).map { TurnTrace(at: t0.addingTimeInterval(Double($0)), provider: .anthropic, durationMs: 500 + $0, outcome: .tamam) }
        let metin = DiagnosticReport.render(bosAnlik(), now: t0, turns: liste)
        #expect(metin.contains("son_turlar (20, yeniden eskiye):"))
        #expect(metin.contains("sure_ms=529 ") && metin.contains("sure_ms=510 ") && !metin.contains("sure_ms=509 "))
        #expect(metin.range(of: "sure_ms=529 ")!.lowerBound < metin.range(of: "sure_ms=510 ")!.lowerBound)
        // İz verilmeyen çağrı (mevcut çağrı noktaları) bölümü boş gösterir.
        #expect(DiagnosticReport.render(bosAnlik(), now: t0).contains("son_turlar (0, yeniden eskiye):\n  —"))
    }

    /// Uygulama yeniden açılınca tampon boş başlar: izin kalıcı deposu yoktur, kaynakta disk/tercih/ağ yazma çağrısı bulunmaz.
    @Test func yeniTamponBosBaslarVeDiskeYazilmaz() throws {
        let onceki = TurnTraces()
        onceki.record(TurnTrace(provider: .anthropic, durationMs: 5, outcome: .tamam))
        #expect(onceki.entries().count == 1)
        #expect(TurnTraces().entries().isEmpty)

        let kaynak = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/MarkaCore/AI/TurnTrace.swift")
        let kod = try String(contentsOf: kaynak, encoding: .utf8)
        for yasak in ["FileManager", "write(to", "contentsOf", "UserDefaults", "URLSession", "URLRequest", "Process(", "fopen", "Keychain", "SecItem", "os_log", "Logger(", "print(", "NSLog", "store.write", "insert("] {
            #expect(!kod.contains(yasak), "Tur izi kaynağında kalıcı/ağ çağrısı var: \(yasak)")
        }
    }
}
