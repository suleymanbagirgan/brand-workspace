import Foundation
import GRDB

// MARK: - Altın istem koşumu: sahte kip koşucusu (H3-02)
//
// Her senaryo kendi bellek içi veritabanında, geçici klasörde ve kendi ChatEngine'iyle koşar; gerçek veri alanına, ağa
// ya da Keychain'e dokunmaz. Sağlayıcı `BetikliSaglayici`dır: senaryonun betiğini oynatır, araçları ChatEngine'in
// yürütücüsüne verir (kendisi çalıştırmaz). Ölçülen: hangi araç çağrıldı, hangisi reddedildi, hangi bekleyen öneri oluştu,
// uygulanmış öneri ve veri değişikliği (her ikisi de 0 olmalı).

public enum AltinIstemKosucu {
    /// Senaryo kümesini sahte kipte koşar.
    public static func kosSahte(_ senaryolar: [AltinSenaryo] = AltinIstemler.hepsi) async -> AltinRapor {
        var sonuclar: [AltinSonuc] = []
        for s in senaryolar { sonuclar.append(await kos(s)) }
        let gecen = sonuclar.filter(\.gectiMi).count
        return AltinRapor(kip: "sahte", toplam: sonuclar.count, gecen: gecen, kalan: sonuclar.count - gecen, sonuclar: sonuclar)
    }

    static func kos(_ s: AltinSenaryo) async -> AltinSonuc {
        let baslangic = DispatchTime.now().uptimeNanoseconds
        let bos = AltinGozlem(araclar: [], hataliAraclar: [], bekleyenOneriler: [], uygulanmisOneri: 0, veriDegisti: false,
                              baskaMarkaReddi: false, sizanlar: [], durduruldu: false, sunulanAraclar: [], istekSayisi: 0)
        let gecici = FileManager.default.temporaryDirectory.appendingPathComponent("marka-altin-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: gecici) }
        let gozlem: AltinGozlem
        do {
            gozlem = try await gozlemle(s, gecici: gecici)
        } catch {
            return AltinSonuc(senaryo: s.ad, tur: s.tur.rawValue, sonuc: AltinSonuc.kaldi,
                              neden: "koşu hatası: \(String(describing: type(of: error)))", sureMs: sure(baslangic), gozlem: bos)
        }
        let nedenler = puanla(s.beklenen, gozlem)
        return AltinSonuc(senaryo: s.ad, tur: s.tur.rawValue, sonuc: nedenler.isEmpty ? AltinSonuc.gecti : AltinSonuc.kaldi,
                          neden: nedenler.isEmpty ? gecmeNedeni(s.beklenen) : nedenler.joined(separator: "; "),
                          sureMs: sure(baslangic), gozlem: gozlem)
    }

    static func sure(_ baslangic: UInt64) -> Int { Int((DispatchTime.now().uptimeNanoseconds - baslangic) / 1_000_000) }

    static func gecmeNedeni(_ b: AltinSenaryo.Beklenti) -> String {
        var parca = ["araç zinciri tuttu (\(b.araclar.isEmpty ? "araç yok" : b.araclar.joined(separator: " → ")))"]
        parca.append(b.bekleyenOneriler.isEmpty ? "bekleyen öneri yok (beklendiği gibi)" : "bekleyen öneri: \(b.bekleyenOneriler.map(\.rawValue).joined(separator: ", "))")
        if !b.hataliAraclar.isEmpty { parca.append("reddedilen: \(b.hataliAraclar.joined(separator: ", "))") }
        if b.baskaMarkaReddi { parca.append("başka marka reddedildi") }
        parca.append("uygulanmış öneri 0")
        return parca.joined(separator: "; ")
    }

    // MARK: Puanlama

    static func puanla(_ b: AltinSenaryo.Beklenti, _ g: AltinGozlem) -> [String] {
        var n: [String] = []
        if g.araclar != b.araclar { n.append("araç zinciri: beklenen [\(b.araclar.joined(separator: ","))], gelen [\(g.araclar.joined(separator: ","))]") }
        if g.hataliAraclar != b.hataliAraclar { n.append("reddedilen araçlar: beklenen [\(b.hataliAraclar.joined(separator: ","))], gelen [\(g.hataliAraclar.joined(separator: ","))]") }
        let beklenenOneri = b.bekleyenOneriler.map(\.rawValue).sorted()
        if g.bekleyenOneriler != beklenenOneri { n.append("bekleyen öneri: beklenen [\(beklenenOneri.joined(separator: ","))], gelen [\(g.bekleyenOneriler.joined(separator: ","))]") }
        if g.uygulanmisOneri != 0 { n.append("uygulanmış öneri \(g.uygulanmisOneri) (0 olmalı)") }
        if g.veriDegisti { n.append("marka verisi değişti (AI yalnız öneri üretir)") }
        if g.baskaMarkaReddi != b.baskaMarkaReddi { n.append(b.baskaMarkaReddi ? "başka marka reddi beklendi, olmadı" : "beklenmeyen başka marka reddi") }
        if !g.sizanlar.isEmpty { n.append("metin denetimi: \(g.sizanlar.joined(separator: " | "))") }
        if g.durduruldu != b.durduruldu { n.append(b.durduruldu ? "durdurma bildirimi beklendi, yok" : "beklenmeyen durdurma") }
        for t in b.sunulanIcerir where !g.sunulanAraclar.contains(t) { n.append("sunulmalıydı: \(t)") }
        for t in b.sunulanIcermez where g.sunulanAraclar.contains(t) { n.append("sunulmamalıydı: \(t)") }
        if g.sunulanAraclar.contains(where: { $0.contains("sil") }) { n.append("silme aracı sunuldu") }
        if let k = b.istekSayisi, k != g.istekSayisi { n.append("model isteği: beklenen \(k), gelen \(g.istekSayisi)") }
        return n
    }

    // MARK: Koşu

    static func gozlemle(_ s: AltinSenaryo, gecici: URL) async throws -> AltinGozlem {
        let store = Store(database: try AppDatabase.inMemory())
        let kimlik = try hazirla(s.veri, store: store)
        let onceki = try parmakIzi(store)

        let fm = FileManager.default
        let klasorler = gecici.appendingPathComponent("klasorler"), alan = gecici.appendingPathComponent("alan")
        try fm.createDirectory(at: klasorler, withIntermediateDirectories: true)
        try fm.createDirectory(at: alan, withIntermediateDirectories: true)
        let folders = BrandFolders(root: klasorler, store: store)

        let betik = s.betik.map { tur in tur.map { kimlik.coz($0) } }
        let saglayici = BetikliSaglayici(supportsTools: s.aracDestegi, rounds: betik)
        #if !MAS
        let motor = ChatEngine(store: store, codex: CodexAppServer(), folders: folders, workspace: alan, settings: AISettings(),
                               anthropicKey: { nil }, urlSession: .shared, diagnostics: nil, providers: [saglayici])
        #else
        let motor = ChatEngine(store: store, folders: folders, workspace: alan, settings: AISettings(),
                               anthropicKey: { nil }, urlSession: .shared, diagnostics: nil, providers: [saglayici])
        #endif
        let kapsam: SessionScope
        switch s.kapsam {
        case .marka(let etiket):
            guard let id = kimlik.markalar[etiket] else { throw MarkaError.notFound(etiket) }
            kapsam = .brand(id)
        case .tumMarkalar: kapsam = .allBrands
        }
        let oturum = try await motor.createSession(scope: kapsam, provider: .anthropic, title: "Altın istem")
        saglayici.durdur = { await motor.cancel(sessionId: oturum.id) }

        var yanit = ""
        var durduruldu = false
        for await olay in await motor.send(sessionId: oturum.id, text: s.istem) {
            switch olay {
            case .textDelta(let t): yanit += t
            case .event(let r) where r.kind == .notice && r.title == L("Durduruldu"): durduruldu = true
            default: break
            }
        }

        let cagrilar = saglayici.cagrilar
        let oneriler = try store.proposals(sessionId: oturum.id)
        let uygulanmis = try store.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM aiProposal WHERE status = ?", arguments: [ProposalStatus.applied.rawValue]) ?? 0
        }
        let markaReddi = MarkaError.brandScope.errorDescription ?? "\u{0}"
        let gecmis = try await motor.messages(sessionId: oturum.id)
        let gorunen = (cagrilar.map(\.metin) + [yanit] + gecmis.map(\.text) + gecmis.map(\.eventsJSON)).joined(separator: "\n")
        return AltinGozlem(
            araclar: cagrilar.map(\.ad),
            hataliAraclar: cagrilar.filter(\.hata).map(\.ad),
            // Aynı milisaniyede oluşan önerilerin sırası veritabanında garanti değil: tür listesi sıralanır (çoklu küme).
            bekleyenOneriler: oneriler.filter { $0.status == .pending }.map(\.kind.rawValue).sorted(),
            uygulanmisOneri: uygulanmis,
            veriDegisti: try parmakIzi(store) != onceki,
            baskaMarkaReddi: cagrilar.contains { $0.hata && $0.metin.contains(markaReddi) },
            sizanlar: s.beklenen.sizmamali.filter { gorunen.contains($0) },
            durduruldu: durduruldu,
            sunulanAraclar: saglayici.ilkSunulan,
            istekSayisi: saglayici.istekSayisi
        ).denetle(baglam: saglayici.ilkBaglam, beklenti: s.beklenen, aracMetni: cagrilar.map(\.metin).joined(separator: "\n"))
    }

    /// Senaryo verisini kurar; etiket → kimlik eşlemesini döndürür.
    static func hazirla(_ markalar: [AltinSenaryo.Marka], store: Store) throws -> KimlikHaritasi {
        var h = KimlikHaritasi()
        for m in markalar {
            let b = try store.createBrand(name: m.ad, isOwn: m.kendiSirketimiz)
            try store.setAIProviders(b.id, providers: m.aiIzni ? [.anthropic] : [])
            h.markalar[m.etiket] = b.id
            for k in m.kaynaklar {
                h.kaynaklar[k.etiket] = try store.addTextSource(brandId: b.id, kind: .note, title: k.baslik, body: k.govde).id
            }
            if m.dolguKaynak > 0 {
                for i in 1...m.dolguKaynak {
                    h.kaynaklar["dolgu\(i)"] = try store.addTextSource(brandId: b.id, kind: .note, title: "Dolgu notu \(i)", body: "Sıradan not \(i).").id
                }
            }
            for g in m.gorevler {
                h.gorevler[g.etiket] = try store.saveTask(WorkTask(brandId: b.id, title: g.baslik, dueDate: g.sonTarih, status: g.durum)).id
            }
            if m.dolguGorev > 0 {
                for i in 1...m.dolguGorev {
                    h.gorevler["dolgu\(i)"] = try store.saveTask(WorkTask(brandId: b.id, title: "Dolgu görevi \(i)")).id
                }
            }
            for p in m.bilgiSayfalari {
                guard let kaynak = h.kaynaklar[p.kaynak] else { throw MarkaError.notFound(p.kaynak) }
                let r = try store.writeWikiRevision(brandId: b.id, pageId: nil, kind: .overview, title: p.baslik, body: p.iddia,
                                                    claims: [WikiClaimInput(text: p.iddia, sourceId: kaynak)], actor: .user)
                h.sayfalar[p.etiket] = r.pageId
            }
        }
        return h
    }

    /// AI'ın değiştirmemesi gereken verinin özeti (görevler alan alan; diğerleri sayı).
    static func parmakIzi(_ store: Store) throws -> String {
        try store.read { db in
            let gorevler = try String.fetchAll(db, sql: "SELECT id || '|' || title || '|' || status || '|' || IFNULL(dueDate, '') FROM workTask ORDER BY id")
            var sayilar: [String] = []
            for sql in ["SELECT COUNT(*) FROM source", "SELECT COUNT(*) FROM workLog", "SELECT COUNT(*) FROM brandRecord",
                        "SELECT COUNT(*) FROM teamMember", "SELECT COUNT(*) FROM wikiRevision WHERE state = 'approved'",
                        "SELECT COUNT(*) FROM observation"] {
                sayilar.append(String(try Int.fetchOne(db, sql: sql) ?? -1))
            }
            return (gorevler + sayilar).joined(separator: ";")
        }
    }
}

struct KimlikHaritasi {
    var markalar: [String: String] = [:]
    var kaynaklar: [String: String] = [:]
    var gorevler: [String: String] = [:]
    var sayfalar: [String: String] = [:]

    func coz(_ adim: AltinSenaryo.Adim) -> BetikliSaglayici.Adim {
        switch adim {
        case .metin(let t): .metin(t)
        case .arac(let ad, let girdi): .arac(ad, coz(girdi))
        case .durdur: .durdur
        }
    }

    func coz(_ v: JSONValue) -> JSONValue {
        switch v {
        case .string(let s): .string(cozDizgi(s))
        case .array(let a): .array(a.map { coz($0) })
        case .object(let o): .object(o.mapValues { coz($0) })
        default: v
        }
    }

    func cozDizgi(_ s: String) -> String {
        for (onek, harita) in [("@kaynak:", kaynaklar), ("@gorev:", gorevler), ("@sayfa:", sayfalar)] where s.hasPrefix(onek) {
            return harita[String(s.dropFirst(onek.count))] ?? s
        }
        return s
    }
}

extension AltinGozlem {
    /// Bağlam ve araç sonucu beklentileri metin olarak gözleme girmez (kimlik taşır); burada denetlenip sızan/eksik listesine eklenir.
    func denetle(baglam: String, beklenti b: AltinSenaryo.Beklenti, aracMetni: String) -> AltinGozlem {
        var g = self
        for t in b.baglamIcerir where !baglam.contains(t) { g.sizanlar.append("bağlamda yok: \(t)") }
        for t in b.baglamIcermez where baglam.contains(t) { g.sizanlar.append("bağlamda olmamalı: \(t)") }
        for t in b.sizmamali where baglam.contains(t) && !g.sizanlar.contains(t) { g.sizanlar.append(t) }
        for t in b.aracSonucuIcerir where !aracMetni.contains(t) { g.sizanlar.append("araç sonucunda yok: \(t)") }
        return g
    }
}

/// Altın istem koşumunun sahte sağlayıcısı: betikteki turları sırayla oynatır. Gerçek sağlayıcılar gibi her model isteğinden
/// önce `turn.checkCancellation()` çağırır, araçları ChatEngine'in yürütücüsüne verir. Ağ yok, anahtar yok.
final class BetikliSaglayici: AIProvider, @unchecked Sendable {
    enum Adim: Sendable {
        case metin(String)
        case arac(String, JSONValue)
        case durdur
    }

    struct Cagri: Sendable {
        var ad: String
        var hata: Bool
        var metin: String
    }

    let kind: AIProviderKind = .anthropic
    let capabilities: AIProviderCapabilities
    private let lock = NSLock()
    private var rounds: [[Adim]]
    private var _cagrilar: [Cagri] = []
    private var _istek = 0
    private var _sunulan: [String]?
    private var _baglam: String?
    private var _durdur: (@Sendable () async -> Void)?

    init(supportsTools: Bool, rounds: [[Adim]]) {
        capabilities = AIProviderCapabilities(supportsTools: supportsTools, contextTokens: nil, onDevice: true, needsAPIKey: false)
        self.rounds = rounds
    }

    var durdur: (@Sendable () async -> Void)? {
        get { lock.withLock { _durdur } }
        set { lock.withLock { _durdur = newValue } }
    }
    var cagrilar: [Cagri] { lock.withLock { _cagrilar } }
    var istekSayisi: Int { lock.withLock { _istek } }
    var ilkSunulan: [String] { lock.withLock { _sunulan ?? [] } }
    var ilkBaglam: String { lock.withLock { _baglam ?? "" } }

    func sessionModel(settings: AISettings) -> String { "altin-sahte" }
    func cancel(sessionId: String) async {}

    private func sonrakiTur(_ turn: AITurn) -> [Adim]? {
        lock.withLock {
            guard !rounds.isEmpty else { return nil }
            _istek += 1
            if _sunulan == nil { _sunulan = turn.tools.map(\.name) }
            return rounds.removeFirst()
        }
    }

    func runTurn(_ turn: AITurn, assistant: inout AIMessage) async throws {
        // Gerçek sağlayıcıya gidecek bağlam (sistem istemi); bağlam kırpma senaryoları bunu denetler.
        let baglam = (try? ContextBuilder(store: turn.store).systemPrompt(scope: turn.scope, provider: turn.session.provider)) ?? ""
        lock.withLock { if _baglam == nil { _baglam = baglam } }
        while true {
            try turn.checkCancellation()
            guard let tur = sonrakiTur(turn) else { break }
            for adim in tur {
                switch adim {
                case .metin(let t):
                    assistant.text += t
                    turn.emit(.textDelta(t))
                case .arac(let ad, let girdi):
                    let r = await turn.callTool(ad, girdi)
                    lock.withLock { _cagrilar.append(Cagri(ad: ad, hata: r.isError, metin: r.text)) }
                    turn.emit(.event(r.event))
                case .durdur:
                    await durdur?()
                }
            }
        }
    }
}
