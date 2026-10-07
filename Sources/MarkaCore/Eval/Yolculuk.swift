import Foundation
import GRDB

// MARK: - Yolculuk betikleri (E-09)
//
// Gerçek bir kullanıcı yolculuğu ("marka aç → kaynak ekle → asistan görev önersin → onayla → geri al → rapor") çekirdek
// düzeyinde ve sahte sağlayıcıyla, bir KAYIT dosyasından (JSON) oynatılır. Model yok, ağ yok, Keychain yok: yalnız bellek içi
// veritabanı, geçici klasör ve `BetikliSaglayici` (altın istem koşumunun sahte sağlayıcısı) kullanılır.
// Her adım bir eylem + beklenti taşır; bir değişiklik yolculuğu bozarsa raporda BOZULAN ADIMIN ADI yazılır.
//
// SINIR: Bu bir arayüz testi DEĞİLDİR. Hiçbir tıklama, ekran ya da SwiftUI görünümü sınanmaz; yalnız çekirdeğin
// (Store, ChatEngine araç yürütücüsü, öneri kutusu, rapor oluşturucu) adım adım davranışı sınanır.
// Kayıt biçimi ve örnekler: Tests/Fixtures/yolculuk/*.json.

public struct Yolculuk: Codable, Sendable, Equatable {
    public var ad: String
    public var aciklama: String
    public var adimlar: [Adim]

    public enum Eylem: String, Codable, Sendable {
        case markaAc, kaynakEkle, gorevEkle, asistan, onayla, reddet, geriAl, isKaydiYaz, raporOlustur
    }

    /// Sahte sağlayıcının bir adımı: düz metin, araç çağrısı ya da "Durdur".
    public struct BetikAdimi: Codable, Sendable, Equatable {
        public var metin: String?
        public var arac: String?
        public var girdi: JSONValue?
        public var durdur: Bool?
    }

    /// Bir adımın sonunda aranan koşullar. Boş bırakılan alan denetlenmez.
    public struct Beklenti: Codable, Sendable, Equatable {
        /// Adımın markasındaki (marka yoksa tüm markalardaki) bekleyen / uygulanmış öneri sayısı.
        public var bekleyenOneri: Int?
        public var uygulanmisOneri: Int?
        public var reddedilenOneri: Int?
        public var geriAlinanOneri: Int?
        public var gorevSayisi: Int?
        public var gorevBasliklari: [String]?
        public var kaynakSayisi: Int?
        public var isKaydiSayisi: Int?
        /// Rapor adımında "yapılan iş" bölümündeki en az madde sayısı.
        public var raporMaddeEnAz: Int?
        /// Rapor adımında "yapılan iş" bölümündeki tam madde sayısı (dayanaksız madde olmadığının denetimi için 0 da yazılır).
        public var raporMadde: Int?
        /// Asistan adımında çağrılan araçlar (sırayla) ve reddedilenler (sırayla).
        public var araclar: [String]?
        public var hataliAraclar: [String]?
        public var baskaMarkaReddi: Bool?
        /// Araç sonuçlarında, yanıtta ve oturum geçmişinde GÖRÜNMEMESİ gereken metinler.
        public var sizmamali: [String]?
        /// `true`: adımın bir hatayla (ör. marka kapsamı) reddedilmesi beklenir.
        public var hata: Bool?
    }

    public struct Adim: Codable, Sendable, Equatable {
        public var ad: String
        public var eylem: Eylem
        /// Marka etiketi (`markaAc` adımında `etiket` ile tanımlanır).
        public var marka: String?
        public var etiket: String?
        public var baslik: String?
        public var metin: String?
        public var sonTarih: String?
        public var kendiSirketimiz: Bool?
        /// `asistan`: kullanıcı istemi, sahte sağlayıcı betiği (turlar) ve kapsam (`tumMarkalar` ise tüm markalar).
        public var istem: String?
        public var betik: [[BetikAdimi]]?
        public var tumMarkalar: Bool?
        /// `onayla` / `reddet` / `geriAl`: öneri türü (`ProposalKind`) ve aynı türdeki kaçıncı öneri (varsayılan 0).
        public var tur: String?
        public var sira: Int?
        /// `isKaydiYaz`: girdi kaynak etiketleri ve görev etiketi.
        public var kaynaklar: [String]?
        public var gorev: String?
        public var bekle: Beklenti?
    }
}

/// Kasıtlı bozulma: yolculuk kırmızıya dönerse adım adı yazılır (testte "yakalama kanıtı").
public enum YolculukBozulma: Sendable {
    /// Onay adımı öneriyi uygulamaz ama başarılı görünür.
    case onayUygulanmaz
    /// Geri alma adımı hiçbir şey yapmaz.
    case geriAlmaYapilmaz
}

public struct YolculukAdimSonucu: Codable, Sendable, Equatable {
    public var sira: Int
    public var ad: String
    public var eylem: String
    public var gecti: Bool
    /// Adım çıktısı: kimlik ya da zaman taşımaz; aynı kayıtla her koşuda bire bir aynıdır.
    public var cikti: String
    public var neden: String
}

public struct YolculukSonucu: Codable, Sendable, Equatable {
    public var yolculuk: String
    public var gecti: Bool
    public var adimlar: [YolculukAdimSonucu]
    /// İlk kırılan adımın adı (geçtiyse nil); sonraki adımlar koşulmaz.
    public var bozulanAdim: String?
    public var neden: String

    /// Tek satırlık okunur özet; rapora ya da test mesajına kopyalanır.
    public var ozet: String {
        if gecti { return "\(yolculuk): GEÇTİ (\(adimlar.count) adım)" }
        let s = adimlar.last?.sira ?? 0
        return "\(yolculuk): KALDI, adım \(s) «\(bozulanAdim ?? "?")»: \(neden)"
    }
}

public enum YolculukKosucu {
    /// Klasördeki `*.json` kayıtlarını ada göre sıralı yükler.
    public static func yukleKlasor(_ klasor: URL) throws -> [Yolculuk] {
        let dosyalar = try FileManager.default.contentsOfDirectory(at: klasor, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try dosyalar.map { try yukle($0) }
    }

    public static func yukle(_ url: URL) throws -> Yolculuk {
        try JSONDecoder().decode(Yolculuk.self, from: Data(contentsOf: url))
    }

    public static func kos(_ y: Yolculuk, bozulma: YolculukBozulma? = nil) async -> YolculukSonucu {
        let gecici = FileManager.default.temporaryDirectory.appendingPathComponent("marka-yolculuk-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: gecici) }
        var durum: Durum
        do {
            durum = try Durum(gecici: gecici)
        } catch {
            return YolculukSonucu(yolculuk: y.ad, gecti: false, adimlar: [], bozulanAdim: "hazırlık",
                                  neden: "koşu hazırlanamadı: \(String(describing: type(of: error)))")
        }
        var sonuclar: [YolculukAdimSonucu] = []
        for (i, adim) in y.adimlar.enumerated() {
            let sira = i + 1
            var cikti = ""
            var beklenenHata = false
            var neden: [String] = []
            do {
                cikti = try await durum.uygula(adim, bozulma: bozulma)
            } catch {
                let aciklama = (error as? LocalizedError)?.errorDescription ?? String(describing: type(of: error))
                if adim.bekle?.hata == true {
                    beklenenHata = true
                    cikti = "reddedildi: \(aciklama)"
                } else {
                    cikti = "hata: \(aciklama)"
                    neden.append("adım hata verdi (\(aciklama))")
                }
            }
            if adim.bekle?.hata == true, !beklenenHata, neden.isEmpty { neden.append("hata beklendi, adım başarılı oldu") }
            if neden.isEmpty, let b = adim.bekle {
                do { neden += try await durum.denetle(adim, b) } catch { neden.append("denetim hatası: \(String(describing: type(of: error)))") }
            }
            let gecti = neden.isEmpty
            sonuclar.append(YolculukAdimSonucu(sira: sira, ad: adim.ad, eylem: adim.eylem.rawValue, gecti: gecti, cikti: cikti,
                                               neden: gecti ? "tuttu" : neden.joined(separator: "; ")))
            if !gecti {
                return YolculukSonucu(yolculuk: y.ad, gecti: false, adimlar: sonuclar, bozulanAdim: adim.ad, neden: neden.joined(separator: "; "))
            }
        }
        return YolculukSonucu(yolculuk: y.ad, gecti: true, adimlar: sonuclar, bozulanAdim: nil, neden: "tüm adımlar tuttu")
    }

    // MARK: Durum

    struct Eksik: LocalizedError {
        var errorDescription: String?
        init(_ m: String) { errorDescription = m }
    }

    /// Bir yolculuğun kendi dünyası: bellek içi veritabanı + etiket → kimlik haritası.
    struct Durum {
        let store: Store
        let klasorler: BrandFolders
        let alan: URL
        var kimlik = KimlikHaritasi()
        var asistanCagrilari: [BetikliSaglayici.Cagri] = []
        var asistanYaniti = ""
        var asistanGecmisi = ""

        init(gecici: URL) throws {
            store = Store(database: try AppDatabase.inMemory())
            let fm = FileManager.default
            let k = gecici.appendingPathComponent("klasorler")
            alan = gecici.appendingPathComponent("alan")
            try fm.createDirectory(at: k, withIntermediateDirectories: true)
            try fm.createDirectory(at: alan, withIntermediateDirectories: true)
            klasorler = BrandFolders(root: k, store: store)
        }

        func markaKimligi(_ etiket: String?) throws -> String {
            guard let etiket, let id = kimlik.markalar[etiket] else { throw Eksik("bilinmeyen marka etiketi: \(etiket ?? "yok")") }
            return id
        }

        func gerekli(_ v: String?, _ alan: String) throws -> String {
            guard let v, !v.isEmpty else { throw Eksik("kayıtta \(alan) eksik") }
            return v
        }

        // MARK: Eylemler

        mutating func uygula(_ a: Yolculuk.Adim, bozulma: YolculukBozulma?) async throws -> String {
            switch a.eylem {
            case .markaAc:
                let etiket = try gerekli(a.etiket, "etiket")
                let b = try store.createBrand(name: try gerekli(a.baslik, "baslik"), isOwn: a.kendiSirketimiz ?? false)
                try store.setAIProviders(b.id, providers: [.anthropic])
                kimlik.markalar[etiket] = b.id
                return "marka açıldı: \(b.name)"

            case .kaynakEkle:
                let b = try markaKimligi(a.marka)
                let s = try store.addTextSource(brandId: b, kind: .note, title: try gerekli(a.baslik, "baslik"), body: a.metin ?? "")
                kimlik.kaynaklar[try gerekli(a.etiket, "etiket")] = s.id
                return "kaynak eklendi: \(s.title)"

            case .gorevEkle:
                let b = try markaKimligi(a.marka)
                let t = try store.saveTask(WorkTask(brandId: b, title: try gerekli(a.baslik, "baslik"), dueDate: a.sonTarih))
                kimlik.gorevler[try gerekli(a.etiket, "etiket")] = t.id
                return "görev eklendi: \(t.title)"

            case .asistan:
                return try await asistanKos(a)

            case .onayla:
                let p = try oneriBul(a, durum: .pending)
                if bozulma == .onayUygulanmaz { return "onaylandı: \(p.kind.rawValue)" }
                _ = try store.applyProposal(p.id)
                return "onaylandı: \(p.kind.rawValue)"

            case .reddet:
                let p = try oneriBul(a, durum: .pending)
                try store.rejectProposal(p.id)
                return "reddedildi: \(p.kind.rawValue)"

            case .geriAl:
                let p = try oneriBul(a, durum: .applied)
                if bozulma == .geriAlmaYapilmaz { return "geri alındı: \(p.kind.rawValue)" }
                try store.revertProposal(p.id)
                return "geri alındı: \(p.kind.rawValue)"

            case .isKaydiYaz:
                let b = try markaKimligi(a.marka)
                let girdiler = try (a.kaynaklar ?? []).map { e -> String in
                    guard let id = kimlik.kaynaklar[e] else { throw Eksik("bilinmeyen kaynak etiketi: \(e)") }
                    return id
                }
                let gorevId = try a.gorev.map { e -> String in
                    guard let id = kimlik.gorevler[e] else { throw Eksik("bilinmeyen görev etiketi: \(e)") }
                    return id
                }
                let l = try store.saveUserWorkLog(WorkLog(brandId: b, taskId: gorevId, title: try gerekli(a.baslik, "baslik"),
                                                          requested: "Yolculuk betiği", performed: a.metin ?? ""),
                                                  inputSourceIds: girdiler, outputSourceIds: [], verifiedBy: "Deneme Danışman")
                return "iş kaydı yazıldı ve doğrulandı: \(l.title)"

            case .raporOlustur:
                let b = try markaKimligi(a.marka)
                let olusturucu = ReportBuilder(store: store)
                let donem = olusturucu.period(.weekly, containing: Date())
                let icerik = try olusturucu.build(brandId: b, period: donem)
                let sayilar = icerik.sections.map { "\($0.kind.rawValue)=\($0.items.count)" }.joined(separator: ", ")
                return "rapor taslağı: \(sayilar); uyarı=\(icerik.warnings.count)"
            }
        }

        func oneriBul(_ a: Yolculuk.Adim, durum: ProposalStatus) throws -> AIProposal {
            let b = try markaKimligi(a.marka)
            let turAdi = try gerekli(a.tur, "tur")
            guard let tur = ProposalKind(rawValue: turAdi) else { throw Eksik("bilinmeyen öneri türü: \(turAdi)") }
            // Aynı milisaniyedeki önerilerin veritabanı sırası garanti değil: özet metne göre sıralanır (deterministik).
            let adaylar = try store.proposals(brandId: b, status: durum).filter { $0.kind == tur }.sorted { $0.summary < $1.summary }
            let sira = a.sira ?? 0
            guard sira < adaylar.count else { throw Eksik("\(durum.rawValue) \(turAdi) önerisi yok (sıra \(sira), bulunan \(adaylar.count))") }
            return adaylar[sira]
        }

        mutating func asistanKos(_ a: Yolculuk.Adim) async throws -> String {
            let rounds: [[BetikliSaglayici.Adim]] = (a.betik ?? []).map { tur in
                tur.map { x -> BetikliSaglayici.Adim in
                    if x.durdur == true { return .durdur }
                    if let ad = x.arac { return .arac(ad, kimlik.coz(x.girdi ?? [:])) }
                    return .metin(x.metin ?? "")
                }
            }
            let saglayici = BetikliSaglayici(supportsTools: true, rounds: rounds)
            #if !MAS
            let motor = ChatEngine(store: store, codex: CodexAppServer(), folders: klasorler, workspace: alan, settings: AISettings(),
                                   anthropicKey: { nil }, urlSession: .shared, diagnostics: nil, providers: [saglayici])
            #else
            let motor = ChatEngine(store: store, folders: klasorler, workspace: alan, settings: AISettings(),
                                   anthropicKey: { nil }, urlSession: .shared, diagnostics: nil, providers: [saglayici])
            #endif
            let kapsam: SessionScope = a.tumMarkalar == true ? .allBrands : .brand(try markaKimligi(a.marka))
            let oturum = try await motor.createSession(scope: kapsam, provider: .anthropic, title: "Yolculuk")
            saglayici.durdur = { await motor.cancel(sessionId: oturum.id) }
            var yanit = ""
            for await olay in await motor.send(sessionId: oturum.id, text: try gerekli(a.istem, "istem")) {
                if case .textDelta(let t) = olay { yanit += t }
            }
            let gecmis = try await motor.messages(sessionId: oturum.id)
            asistanCagrilari = saglayici.cagrilar
            asistanYaniti = yanit
            asistanGecmisi = (gecmis.map(\.text) + gecmis.map(\.eventsJSON)).joined(separator: "\n")
            let araclar = asistanCagrilari.map(\.ad).joined(separator: " → ")
            let hatali = asistanCagrilari.filter(\.hata).map(\.ad).joined(separator: ", ")
            let bekleyen = try bekleyenSayisi(a.tumMarkalar == true ? nil : a.marka)
            return "araçlar: \(araclar.isEmpty ? "yok" : araclar); reddedilen: \(hatali.isEmpty ? "yok" : hatali); bekleyen öneri: \(bekleyen)"
        }

        // MARK: Sayımlar ve denetim

        func oneriSayisi(_ durum: ProposalStatus, marka: String?) throws -> Int {
            let idler = try marka.map { [try markaKimligi($0)] } ?? kimlik.markalar.values.sorted()
            return try idler.reduce(0) { $0 + (try store.proposals(brandId: $1, status: durum).count) }
        }

        func bekleyenSayisi(_ marka: String?) throws -> Int { try oneriSayisi(.pending, marka: marka) }

        func denetle(_ a: Yolculuk.Adim, _ b: Yolculuk.Beklenti) async throws -> [String] {
            var n: [String] = []
            func say<T: Equatable>(_ ad: String, _ beklenen: T?, _ gelen: @autoclosure () throws -> T) rethrows {
                guard let beklenen else { return }
                let g = try gelen()
                if g != beklenen { n.append("\(ad): beklenen \(beklenen), gelen \(g)") }
            }
            let marka = a.marka
            try say("bekleyen öneri", b.bekleyenOneri, try oneriSayisi(.pending, marka: marka))
            try say("uygulanmış öneri", b.uygulanmisOneri, try oneriSayisi(.applied, marka: marka))
            try say("reddedilen öneri", b.reddedilenOneri, try oneriSayisi(.rejected, marka: marka))
            try say("geri alınan öneri", b.geriAlinanOneri, try oneriSayisi(.reverted, marka: marka))
            if b.gorevSayisi != nil || b.gorevBasliklari != nil {
                let id = try markaKimligi(marka)
                let gorevler = try store.tasks(brandId: id)
                try say("görev sayısı", b.gorevSayisi, gorevler.count)
                try say("görev başlıkları", b.gorevBasliklari.map { $0.sorted() }, gorevler.map(\.title).sorted())
            }
            if b.kaynakSayisi != nil { try say("kaynak sayısı", b.kaynakSayisi, try store.sources(brandId: try markaKimligi(marka)).count) }
            if b.isKaydiSayisi != nil {
                let id = try markaKimligi(marka)
                try say("iş kaydı sayısı", b.isKaydiSayisi, try store.read { db in
                    try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM workLog WHERE brandId = ?", arguments: [id]) ?? 0 })
            }
            if b.raporMaddeEnAz != nil || b.raporMadde != nil {
                let id = try markaKimligi(marka)
                let o = ReportBuilder(store: store)
                let madde = try o.build(brandId: id, period: o.period(.weekly, containing: Date())).section(.completedWork)?.items.count ?? 0
                if let en = b.raporMaddeEnAz, madde < en { n.append("rapor maddesi: en az \(en) beklendi, gelen \(madde)") }
                try say("rapor maddesi", b.raporMadde, madde)
            }
            if a.eylem == .asistan {
                try say("araç zinciri", b.araclar, asistanCagrilari.map(\.ad))
                try say("reddedilen araçlar", b.hataliAraclar, asistanCagrilari.filter(\.hata).map(\.ad))
                let reddi = MarkaError.brandScope.errorDescription ?? "\u{0}"
                try say("başka marka reddi", b.baskaMarkaReddi, asistanCagrilari.contains { $0.hata && $0.metin.contains(reddi) })
            }
            if let yasak = b.sizmamali {
                let gorunen = (asistanCagrilari.map(\.metin) + [asistanYaniti, asistanGecmisi]).joined(separator: "\n")
                for t in yasak where gorunen.contains(t) { n.append("sızıntı: «\(t)» görünür") }
            }
            return n
        }
    }
}
