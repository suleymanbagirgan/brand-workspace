import Foundation
import GRDB
import Testing
@testable import MarkaCore

/// H2-06 (G-01): marka yalıtımının ve denetim izinin SİSTEMATİK kanıtı (kural 1 ve 5).
///
/// 1. `Store.swift` + `Store+*.swift` içindeki her `public func` kaynak taramasıyla çıkarılır. Zorunlu `brandId: String`
///    almayan her yüzey gerekçesiyle `docs/yalitim-izin-listesi.md` §1'de olmalıdır; listede olmayan yeni yüzey testi kırar.
/// 2. Tohumlu (belirlenimli) rastgele iki marka çifti; A ile çağrılan her okuma yüzeyinin sonucunda B'nin hiçbir kimliği ya da
///    işareti geçmez. Başarısızlıkta tohum yazılır: `tohum` değeriyle aynı dünya yeniden kurulur.
/// 3. Her yazma yüzeyi en az bir `auditEvent` bırakır; istisnalar `docs/yalitim-izin-listesi.md` §2'de gerekçelidir.
///
/// Tüm adlar uydurmadır; gerçek veri, ağ ya da kullanıcı veri alanı kullanılmaz (bellek içi veritabanı).
@Suite struct YalitimOzellikTests {

    // MARK: - Kaynak taraması

    struct Yuzey: Hashable {
        /// `ad(etiket1:etiket2:)` biçimi (Swift seçici yazımı); izin listesindeki anahtar budur.
        let imza: String
        let ad: String
        let dosya: String
        let satir: Int
        /// Zorunlu `brandId: String` parametresi var (dış ya da iç ad). `String?` kapsam sayılmaz: `nil` tüm markalar demektir.
        let kapsamli: Bool
        var yazma: Bool { YalitimOzellikTests.yazmaMi(ad) }
    }

    /// Yazma yüzeyi adlandırma kuralı: ad bu öneklerden biriyle başlar ve önekten sonra büyük harf gelir (ya da ad önekin
    /// kendisidir). `archivedBrands`, `assignments`, `setting` bu yüzden okuma sayılır.
    static let yazmaOnekleri = ["save", "set", "create", "add", "delete", "update", "assign", "unassign", "archive", "restore",
                                "apply", "reject", "revert", "start", "stop", "verify", "retract", "ingest", "decide", "import",
                                "install", "write", "invalidate"]

    static func yazmaMi(_ ad: String) -> Bool {
        yazmaOnekleri.contains { onek in
            guard ad.hasPrefix(onek) else { return false }
            guard let sonraki = ad.dropFirst(onek.count).first else { return true }
            return sonraki.isUppercase
        }
    }

    static let kok = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Depodaki Store dosyalarını tarar.
    static func tara() throws -> [Yuzey] {
        let klasor = kok.appendingPathComponent("Sources/MarkaCore/Store")
        let adlar = try FileManager.default.contentsOfDirectory(atPath: klasor.path)
            .filter { $0 == "Store.swift" || ($0.hasPrefix("Store+") && $0.hasSuffix(".swift")) }.sorted()
        return try adlar.flatMap { ad in
            try tara(dosya: ad, metin: String(contentsOf: klasor.appendingPathComponent(ad), encoding: .utf8))
        }
    }

    /// Bir Swift kaynağındaki `Store` gövdelerinde (sınıf ya da uzantı, iç içe tür değil) duran `public func`'ları çıkarır.
    /// Ayraç sayımı dizge, çok satırlı dizge ve `//` yorumunu atlar; dosya sonunda derinlik sıfır değilse hata verir.
    static func tara(dosya: String, metin: String) throws -> [Yuzey] {
        let satirlar = metin.components(separatedBy: "\n")
        var out: [Yuzey] = []
        var derinlik = 0, storeIcinde = false
        var durum = 0 // 0 kod, 1 dizge, 2 çok satırlı dizge
        func bas(_ c: [Character], _ k: Int, _ s: String) -> Bool {
            let p = Array(s)
            return k + p.count <= c.count && Array(c[k..<(k + p.count)]) == p
        }
        for (i, satir) in satirlar.enumerated() {
            let t = satir.trimmingCharacters(in: .whitespaces)
            if derinlik == 0, durum == 0,
               t.range(of: #"^(public )?(final )?(class|extension) Store( |:|\{|$)"#, options: .regularExpression) != nil {
                storeIcinde = true
            }
            if storeIcinde, derinlik == 1, durum == 0, t.hasPrefix("public func ") || t.hasPrefix("public static func ") {
                var imza = t, j = i
                func kapandi(_ s: String) -> Bool {
                    let ac = s.filter { $0 == "(" }.count
                    return ac > 0 && ac == s.filter { $0 == ")" }.count
                }
                while !kapandi(imza), j + 1 < satirlar.count {
                    j += 1
                    imza += " " + satirlar[j].trimmingCharacters(in: .whitespaces)
                }
                out.append(try cozumle(imza, dosya: dosya, satir: i + 1))
            }
            let c = Array(satir)
            var k = 0
            while k < c.count {
                switch durum {
                case 0:
                    if bas(c, k, "\"\"\"") { durum = 2; k += 3; continue }
                    if bas(c, k, "//") { k = c.count; continue }
                    if c[k] == "\"" { durum = 1 } else if c[k] == "{" { derinlik += 1 } else if c[k] == "}" { derinlik -= 1 }
                case 1:
                    if c[k] == "\\" { k += 2; continue }
                    if c[k] == "\"" { durum = 0 }
                default:
                    if bas(c, k, "\"\"\"") { durum = 0; k += 3; continue }
                }
                k += 1
            }
            if durum == 1 { durum = 0 }
            if derinlik == 0 { storeIcinde = false }
        }
        guard derinlik == 0, durum == 0 else {
            throw MarkaError.validation("\(dosya): ayraç sayımı dengesiz (derinlik \(derinlik)); tarayıcı dosyayı okuyamadı")
        }
        return out
    }

    /// `public func ad<G>(dış iç: Tür = varsayılan, …)` imzasından seçici yazımını ve kapsamı çıkarır.
    static func cozumle(_ imza: String, dosya: String, satir: Int) throws -> Yuzey {
        let c = Array(imza)
        guard let funcAralik = imza.range(of: "func ") else { throw MarkaError.validation("\(dosya):\(satir) imza okunamadı") }
        var k = imza.distance(from: imza.startIndex, to: funcAralik.upperBound)
        var ad = ""
        while k < c.count, c[k].isLetter || c[k].isNumber || c[k] == "_" { ad.append(c[k]); k += 1 }
        while k < c.count, c[k] == " " { k += 1 }
        if k < c.count, c[k] == "<" {
            var d = 0
            repeat {
                if c[k] == "<" { d += 1 } else if c[k] == ">" { d -= 1 }
                k += 1
            } while d > 0 && k < c.count
        }
        guard !ad.isEmpty, k < c.count, c[k] == "(" else { throw MarkaError.validation("\(dosya):\(satir) imza okunamadı: \(imza)") }
        k += 1
        var d = 1, parametreler: [String] = [], gecerli = ""
        while k < c.count {
            let ch = c[k]
            if ch == "(" || ch == "[" || ch == "<" { d += 1 }
            if ch == ")" || ch == "]" || ch == ">" { d -= 1 }
            if d == 0 { break }
            if ch == ",", d == 1 { parametreler.append(gecerli); gecerli = "" } else { gecerli.append(ch) }
            k += 1
        }
        if !gecerli.trimmingCharacters(in: .whitespaces).isEmpty { parametreler.append(gecerli) }
        var etiketler: [String] = [], kapsamli = false
        for p in parametreler {
            guard let iki = p.firstIndex(of: ":") else { throw MarkaError.validation("\(dosya):\(satir) parametre okunamadı: \(p)") }
            let adlar = p[..<iki].split(separator: " ").map(String.init)
            let tur = p[p.index(after: iki)...].split(separator: "=", maxSplits: 1).first.map {
                $0.trimmingCharacters(in: .whitespaces)
            } ?? ""
            etiketler.append(adlar.first ?? "_")
            if adlar.contains("brandId"), tur == "String" { kapsamli = true }
        }
        return Yuzey(imza: "\(ad)(\(etiketler.map { $0 + ":" }.joined()))", ad: ad, dosya: dosya, satir: satir, kapsamli: kapsamli)
    }

    struct IzinListesi {
        /// §1: kapsamsız yüzey → gerekçe.
        var kapsamsiz: [String: String] = [:]
        /// §2: denetim olayı bırakmayan yazma yüzeyi → gerekçe.
        var denetimsiz: [String: String] = [:]
        var yinelenen: [String] = []
    }

    /// `docs/yalitim-izin-listesi.md`: `## 1.` ve `## 2.` bölümlerindeki "| `imza` | … | gerekçe |" satırları.
    static func izinListesi() throws -> IzinListesi {
        let metin = try String(contentsOf: kok.appendingPathComponent("docs/yalitim-izin-listesi.md"), encoding: .utf8)
        var liste = IzinListesi(), bolum = 0
        for satir in metin.components(separatedBy: "\n") {
            if satir.hasPrefix("## ") { bolum = satir.hasPrefix("## 1.") ? 1 : satir.hasPrefix("## 2.") ? 2 : 0; continue }
            guard bolum > 0, satir.hasPrefix("| `") else { continue }
            let hucreler = satir.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard hucreler.count >= 4 else { continue }
            let imza = hucreler[1].trimmingCharacters(in: CharacterSet(charactersIn: "`"))
            let gerekce = hucreler[hucreler.count - 2]
            if bolum == 1 {
                if liste.kapsamsiz[imza] != nil { liste.yinelenen.append(imza) }
                liste.kapsamsiz[imza] = gerekce
            } else {
                if liste.denetimsiz[imza] != nil { liste.yinelenen.append(imza) }
                liste.denetimsiz[imza] = gerekce
            }
        }
        return liste
    }

    // MARK: - (1) Yüzey taraması

    @Test func storeGenelYuzeyiTaranirKapsamsizlarIzinListesinde() throws {
        let yuzeyler = try Self.tara()
        // Tarayıcı sessizce boş dönerse test anlamsız kalır: bugünkü yüzeyin altına düşmemeli.
        #expect(yuzeyler.count >= 100, "Taranan yüzey sayısı beklenmedik derecede az: \(yuzeyler.count)")
        let imzalar = yuzeyler.map(\.imza)
        #expect(Set(imzalar).count == imzalar.count, "Aynı seçicili iki yüzey: \(Dictionary(grouping: imzalar) { $0 }.filter { $1.count > 1 }.keys.sorted())")

        let izin = try Self.izinListesi()
        #expect(izin.yinelenen.isEmpty, "İzin listesinde yinelenen satır: \(izin.yinelenen)")
        let kapsamsiz = yuzeyler.filter { !$0.kapsamli }
        let eksik = kapsamsiz.filter { izin.kapsamsiz[$0.imza] == nil }
        #expect(eksik.isEmpty, """
            İzin listesinde olmayan kapsamsız Store yüzeyi. Yeni yüzey `brandId: String` almalı ya da \
            docs/yalitim-izin-listesi.md §1'e gerekçesiyle yazılmalı: \(eksik.map { "\($0.imza) [\($0.dosya):\($0.satir)]" })
            """)
        let bayat = Set(izin.kapsamsiz.keys).subtracting(kapsamsiz.map(\.imza))
        #expect(bayat.isEmpty, "İzin listesinde artık var olmayan ya da kapsamlı hâle gelmiş satır (listeden çıkar): \(bayat.sorted())")
        for (imza, gerekce) in izin.kapsamsiz {
            #expect(gerekce.count >= 20, "\(imza): gerekçe yok ya da çok kısa")
        }
        let yazma = Set(yuzeyler.filter(\.yazma).map(\.imza))
        #expect(Set(izin.denetimsiz.keys).subtracting(yazma).isEmpty,
                "§2 denetim istisnası yazma yüzeyi değil ya da yok: \(Set(izin.denetimsiz.keys).subtracting(yazma).sorted())")
        for (imza, gerekce) in izin.denetimsiz {
            #expect(gerekce.count >= 20, "\(imza): denetim istisnasının gerekçesi yok ya da çok kısa")
        }
    }

    /// Mekanizmanın kendisi: yeni eklenen kapsamsız yüzey yakalanır; iç içe türün yöntemi, `String?` marka ve çok satırlı
    /// imza doğru okunur. (Testin kırmızıya dönebildiğinin kanıtı; depoya dokunmaz.)
    @Test func taramaYeniKapsamsizYuzeyiYakalarIcIceTuruAtlar() throws {
        let kaynak = #"""
            import Foundation
            extension Store {
                /// Örnek { yorumdaki ayraç sayılmaz
                public func gizliOku(_ id: String) throws -> [WorkTask] { let s = "}" ; _ = s; return [] }
                public func kapsamliOku(brandId: String, limit: Int = 3) throws -> Int { 0 }
                public func istegeBagli(brandId: String?) -> Int {
                    let sql = """
                        SELECT { FROM x
                        """
                    return sql.count
                }
                @discardableResult
                public func cokSatirli(taskId: String,
                                       to brandId: String, at: Date = Date()) throws -> Bool { true }
                public struct Ic { public func icYontem() {} }
                func icKapsamsiz() {}
            }
            extension WorkTask { public func baskaTur() {} }
            """#
        let y = try Self.tara(dosya: "Store+Deneme.swift", metin: kaynak)
        #expect(y.map(\.imza) == ["gizliOku(_:)", "kapsamliOku(brandId:limit:)", "istegeBagli(brandId:)", "cokSatirli(taskId:to:at:)"])
        #expect(y.map(\.kapsamli) == [false, true, false, true])
        let izin = try Self.izinListesi()
        let yakalanan = y.filter { !$0.kapsamli && izin.kapsamsiz[$0.imza] == nil }.map(\.imza)
        #expect(yakalanan == ["gizliOku(_:)", "istegeBagli(brandId:)"], "Yeni kapsamsız yüzey izin listesi dışında kalmalı (test kırmızı olur)")
        #expect(throws: MarkaError.self) { try Self.tara(dosya: "Bozuk.swift", metin: "extension Store {\n public func a() {\n") }
        #expect(Self.yazmaMi("saveTask") && Self.yazmaMi("write") && !Self.yazmaMi("setting") && !Self.yazmaMi("assignments")
                && !Self.yazmaMi("archivedBrands"))
    }

    // MARK: - (2) Rastgele iki marka

    /// Bir markaya yazılan her şey: kimlikler ve markanın benzersiz işareti (her başlık/metin bunu taşır).
    struct Marka: Sendable {
        var id: String
        var isaret: String
        var gorevler: [WorkTask] = []
        var kaynaklar: [Source] = []
        var kayitlar: [BrandRecord] = []
        var isKayitlari: [WorkLog] = []
        var finans: [FinanceEntry] = []
        var kisiler: [Contact] = []
        var projeler: [Project] = []
        var oneriler: [AIProposal] = []
        var sureler: [TimeEntry] = []
        var ekKimlikler: [String] = []
        var uyeId = ""
        var oturumId = ""
        var dosyaSha = ""

        var kimlikler: [String] {
            [id, uyeId, oturumId, dosyaSha] + gorevler.map(\.id) + kaynaklar.map(\.id) + kayitlar.map(\.id) + isKayitlari.map(\.id)
                + finans.map(\.id) + kisiler.map(\.id) + projeler.map(\.id) + oneriler.map(\.id) + sureler.map(\.id) + ekKimlikler
        }
    }

    typealias Zar = YogunVeri.Zar

    static func gun(_ z: inout Zar) -> String { String(format: "2026-%02d-%02d", 1 + z.int(9), 1 + z.int(28)) }

    /// Markayı rastgele doldurur: proje, kişi, görev, kaynak, kayıt, iş kaydı, finans, profil, ekip ataması, oturum, öneri
    /// (bekleyen / uygulanmış / reddedilmiş), terminal önerisi ve süre kaydı. Saat tabanı geçmiştedir (gelecek süre yok).
    static func doldur(_ store: Store, _ z: inout Zar, isOwn: Bool) throws -> Marka {
        let isaret = String(format: "mk%016llx", z.next())
        let brand = try store.createBrand(name: "Deneme \(isaret)", summary: "Özet \(isaret)", sector: "Sentetik", isOwn: isOwn)
        var m = Marka(id: brand.id, isaret: isaret)
        func metin(_ n: Int) -> String { YogunVeri.cumle(&z, n) + " " + isaret }

        for _ in 0..<z.int(3) { let p = Project(brandId: m.id, name: "Proje " + metin(2)); try store.saveProject(p); m.projeler.append(p) }
        for _ in 0..<z.int(3) { let c = Contact(brandId: m.id, name: "Kişi " + metin(1), notes: metin(3)); try store.saveContact(c); m.kisiler.append(c) }
        for _ in 0..<(1 + z.int(6)) {
            let t = WorkTask(brandId: m.id, projectId: m.projeler.isEmpty || z.chance(0.5) ? nil : z.pick(m.projeler).id,
                             title: "Görev " + metin(3), notes: metin(5), priority: z.int(4), dueDate: z.chance(0.6) ? gun(&z) : nil,
                             status: z.pick(TaskStatus.allCases))
            m.gorevler.append(try store.saveTask(t))
        }
        for _ in 0..<(1 + z.int(4)) {
            let kind = z.pick([SourceKind.note, .meeting, .clientRequest])
            m.kaynaklar.append(try store.addTextSource(brandId: m.id, kind: kind, title: "Not " + metin(2), body: metin(8),
                                                       openRequest: kind == .clientRequest && z.chance(0.5)))
        }
        for _ in 0..<(1 + z.int(4)) {
            let r = BrandRecord(brandId: m.id, kind: z.pick(BrandRecordKind.allCases), title: "Kayıt " + metin(2), detail: metin(4),
                                status: z.pick(RecordStatus.allCases), dueDate: z.chance(0.5) ? gun(&z) : nil,
                                sourceId: z.chance(0.4) ? z.pick(m.kaynaklar).id : nil)
            m.kayitlar.append(try store.saveRecord(r))
        }
        for _ in 0..<(1 + z.int(3)) {
            let girdiler = m.kaynaklar.filter { _ in z.chance(0.4) }.map(\.id)
            var l = try store.saveWorkLog(WorkLog(brandId: m.id, taskId: z.chance(0.7) ? z.pick(m.gorevler).id : nil,
                                                  title: "İş " + metin(3), requested: metin(3), performed: metin(5),
                                                  occurredAt: Date(timeIntervalSince1970: 1_767_225_600 + Double(z.int(200)) * 86_400)),
                                          inputSourceIds: girdiler, outputSourceIds: [])
            if z.chance(0.5), (try? store.verifyWorkLog(l.id, verifiedBy: "Deneme Kişi")) != nil { l = try store.workLogDetail(l.id).log }
            if z.chance(0.15) { try store.retractWorkLog(l.id) }
            m.isKayitlari.append(l)
        }
        for _ in 0..<z.int(4) {
            let kind = z.pick(FinanceKind.allCases)
            m.finans.append(try store.saveFinanceEntry(FinanceEntry(brandId: m.id, kind: kind, title: "Finans " + metin(2),
                                                                    amountMinor: Int64(z.int(1_000_000)), date: z.chance(0.7) ? gun(&z) : nil,
                                                                    note: metin(2))))
        }
        for section in ProfileSection.allCases where z.chance(0.4) {
            try store.setProfileSection(brandId: m.id, section, body: metin(6))
        }
        let uye = try store.saveTeamMember(TeamMember(kind: z.chance(0.5) ? .human : .ai, name: "Üye " + metin(1), title: "Danışman " + isaret))
        m.uyeId = uye.id
        if !isOwn { try store.assignMember(uye.id, to: m.id, role: z.chance(0.5) ? .lead : .member) }
        let oturum = AISession(brandId: m.id, scope: .brand, provider: .anthropic, model: "deneme", title: "Oturum " + isaret, memberId: uye.id)
        try store.write { db in try oturum.insert(db) }
        m.oturumId = oturum.id

        // Uygulama içi öneriler: görev, marka kaydı, görev tamamlama, görev güncelleme; bir kısmı uygulanır ya da reddedilir.
        for _ in 0..<(1 + z.int(3)) {
            let p: AIProposal
            switch z.int(4) {
            case 0:
                p = try store.createProposal(sessionId: oturum.id, brandId: m.id, kind: .createTask, summary: "Öneri " + metin(2),
                                             payload: ProposalPayload.CreateTask(title: "Önerilen görev " + metin(2), dueDate: z.chance(0.5) ? gun(&z) : nil))
            case 1:
                p = try store.createProposal(sessionId: nil, brandId: m.id, kind: .createBrandRecord, summary: "Öneri " + metin(2),
                                             payload: ProposalPayload.CreateBrandRecord(kind: z.pick(BrandRecordKind.allCases), title: "Önerilen kayıt " + metin(2)))
            case 2:
                p = try store.createProposal(sessionId: oturum.id, brandId: m.id, kind: .completeTask, summary: "Tamamla " + isaret,
                                             payload: ProposalPayload.CompleteTask(taskId: z.pick(m.gorevler).id))
            default:
                p = try store.createProposal(sessionId: oturum.id, brandId: m.id, kind: .updateTask, summary: "Güncelle " + isaret,
                                             payload: ProposalPayload.UpdateTask(taskId: z.pick(m.gorevler).id, title: "Yeni ad " + metin(2)))
            }
            m.oneriler.append(p)
            switch z.int(3) {
            case 0: if let a = try? store.applyProposal(p.id), let r = a.resultEntityId { m.ekKimlikler.append(r) }
            case 1: try store.rejectProposal(p.id)
            default: break
            }
        }
        // Terminal öneri kutusu: dosya kaydı + bekleyen öneri; bazen onaylanır.
        m.dosyaSha = (0..<4).map { _ in String(format: "%016llx", z.next()) }.joined()
        let gelen = try store.ingestSuggestionFile(brandId: m.id, fileName: "oneri-\(isaret).json", sha256: m.dosyaSha, drafts: [
            SuggestionDraft(kind: .createTask, summary: "Terminal " + isaret, payload: ProposalPayload.CreateTask(title: "Terminal görevi " + metin(2))),
        ])
        m.oneriler += gelen
        if z.chance(0.5) {
            for a in try store.decideSuggestions(brandId: m.id, decisions: gelen.map { SuggestionDecision(proposalId: $0.id, accept: true) }) {
                if let r = a.resultEntityId { m.ekKimlikler.append(r) }
            }
        }
        // Süre kayıtları: geçmişte, üst üste binmeyen saat dilimleri.
        let taban = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01
        for i in 0..<z.int(4) {
            let t = z.pick(m.gorevler)
            let bas = taban.addingTimeInterval(Double(i) * 7_200 + Double(z.int(3_000)))
            m.sureler.append(try store.addTimeEntry(taskId: t.id, brandId: m.id, startedAt: bas, endedAt: bas.addingTimeInterval(600 + Double(z.int(3_000))),
                                                    note: "Süre " + isaret))
        }
        // Kanıt sayılı gözlem (E-01): biri bazen yeni kanıtla kapatılır; ikisi de A'nın okumasında görünmemeli.
        let gozlem = try store.addObservation(brandId: m.id, statement: "Gözlem " + metin(3), evidenceSourceIds: [z.pick(m.kaynaklar).id])
        m.ekKimlikler.append(gozlem.id)
        if z.chance(0.5) {
            m.ekKimlikler.append(try store.addSupersedingObservation(replacing: gozlem.id, brandId: m.id, statement: "Yeni gözlem " + metin(3),
                                                                     evidenceSourceIds: m.kaynaklar.map(\.id)).id)
        }
        // Marka radarı (E-21): bağlantılı ya da yalnız notlu madde; bazen arşivlenir. A'nın okumasında görünmemeli.
        let radar = try store.addRadarItem(brandId: m.id, title: "Radar " + metin(2), address: z.chance(0.5) ? "ornek-rakip.com" : "",
                                           note: metin(4), tag: "rakip")
        m.ekKimlikler.append(radar.id)
        if z.chance(0.3) { try store.setRadarItemArchived(radar.id, brandId: m.id, archived: true) }
        m.gorevler = try store.tasks(brandId: m.id)
        return m
    }

    /// A ile çağrılan okuma yüzeyleri. Anahtar = taranan seçici; kapsamlı her okuma yüzeyi burada olmalı
    /// (`okumaVeYazmaTablolariTaramayiKapsar`). İsteğe bağlı `brandId` alanlar ve kimlikle okuyanlar da A'nın değeriyle çağrılır.
    typealias Okuma = @Sendable (Store, Marka, Marka) throws -> Any
    static let okumalar: [String: Okuma] = [
        "pendingApprovals(brandId:)": { s, a, _ in try s.pendingApprovals(brandId: a.id) },
        "recentlyAppliedProposals(brandId:limit:)": { s, a, _ in try s.recentlyAppliedProposals(brandId: a.id) },
        "contacts(brandId:)": { s, a, _ in try s.contacts(brandId: a.id) },
        "projects(brandId:)": { s, a, _ in try s.projects(brandId: a.id) },
        "records(brandId:kinds:)": { s, a, _ in try s.records(brandId: a.id) },
        "financeEntries(brandId:kind:)": { s, a, _ in try s.financeEntries(brandId: a.id) },
        "flow(brandId:limit:)": { s, a, _ in try s.flow(brandId: a.id) },
        "todo(brandId:)": { s, a, _ in try s.todo(brandId: a.id) },
        "referenceRecords(brandId:)": { s, a, _ in try s.referenceRecords(brandId: a.id) },
        "brandTeam(brandId:)": { s, a, _ in try s.brandTeam(brandId: a.id) },
        "profile(brandId:)": { s, a, _ in try s.profile(brandId: a.id) },
        "profileUpdatedAt(brandId:)": { s, a, _ in try s.profileUpdatedAt(brandId: a.id) },
        "proposals(brandId:status:)": { s, a, _ in try s.proposals(brandId: a.id) },
        "sources(brandId:kinds:includeArchived:)": { s, a, _ in try s.sources(brandId: a.id, includeArchived: true) },
        "pendingSuggestions(brandId:)": { s, a, _ in try s.pendingSuggestions(brandId: a.id) },
        "observations(brandId:includeInvalidated:)": { s, a, _ in try s.observations(brandId: a.id, includeInvalidated: true) },
        "radarItems(brandId:includeArchived:)": { s, a, _ in try s.radarItems(brandId: a.id, includeArchived: true) },
        // B'nin dosyası A'da "işlenmiş" görünmemeli; B'nin görev başlığı A'da eşleşmemeli.
        "isSuggestionFileProcessed(brandId:sha256:)": { s, a, b in
            let bDosyasi = try s.isSuggestionFileProcessed(brandId: a.id, sha256: b.dosyaSha)
            guard !bDosyasi, try s.isSuggestionFileProcessed(brandId: a.id, sha256: a.dosyaSha) else {
                throw MarkaError.validation("öneri dosyası kapsamı yanlış")
            }
            return bDosyasi
        },
        "taskMatching(title:brandId:openOnly:)": { s, a, b in
            try b.gorevler.map { try s.taskMatching(title: $0.title, brandId: a.id) as Any }
                + a.gorevler.map { try s.taskMatching(title: $0.title, brandId: a.id) as Any }
        },
        "completedTaskCount(brandId:since:)": { s, a, _ in
            let n = try s.completedTaskCount(brandId: a.id, since: .distantPast)
            let beklenen = try s.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM workTask WHERE brandId = ? AND status = 'done' AND completedAt IS NOT NULL",
                                 arguments: [a.id]) ?? -1
            }
            guard n == beklenen else { throw MarkaError.validation("biten görev sayısı \(n), A'nın kendi sayısı \(beklenen)") }
            return n
        },
        "completedTaskCount(brandId:week:)": { s, a, _ in
            let n = try s.completedTaskCount(brandId: a.id, week: DateInterval(start: .distantPast, end: .distantFuture))
            let beklenen = try s.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM workTask WHERE brandId = ? AND status = 'done' AND completedAt IS NOT NULL",
                                 arguments: [a.id]) ?? -1
            }
            guard n == beklenen else { throw MarkaError.validation("haftalık biten görev sayısı \(n), A'nın kendi sayısı \(beklenen)") }
            return n
        },
        "timeEntries(taskId:brandId:)": { s, a, b in
            for t in b.gorevler {
                guard (try? s.timeEntries(taskId: t.id, brandId: a.id)) == nil else { throw MarkaError.validation("B'nin görevinin süreleri A ile okundu") }
            }
            return try a.gorevler.map { try s.timeEntries(taskId: $0.id, brandId: a.id) }
        },
        "taskTimeSummary(taskId:brandId:now:)": { s, a, b in
            for t in b.gorevler {
                guard (try? s.taskTimeSummary(taskId: t.id, brandId: a.id)) == nil else { throw MarkaError.validation("B'nin görev süresi A ile okundu") }
            }
            return try a.gorevler.map { t in
                let ozet = try s.taskTimeSummary(taskId: t.id, brandId: a.id)
                let beklenen = try s.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM timeEntry WHERE taskId = ? AND brandId = ?", arguments: [t.id, a.id]) ?? -1 }
                guard ozet.count == beklenen else { throw MarkaError.validation("görev süre sayısı \(ozet.count), A'nın kendi sayısı \(beklenen)") }
                return ozet
            }
        },
        // `brandId: String?` olan okumalar A ile.
        "tasks(brandId:statuses:limit:)": { s, a, _ in try s.tasks(brandId: a.id) },
        "timeEntries(brandId:from:to:)": { s, a, _ in try s.timeEntries(brandId: a.id, from: .distantPast, to: .distantFuture) },
        "workLogs(brandId:statuses:)": { s, a, _ in try s.workLogs(brandId: a.id) },
        // Kimlikle okuyanlar A'nın kimlikleriyle.
        "brand(_:)": { s, a, _ in try s.brand(a.id) },
        "task(_:)": { s, a, _ in try a.gorevler.map { try s.task($0.id) } },
        "source(_:)": { s, a, _ in try a.kaynaklar.map { try s.source($0.id) } },
        "workLogDetail(_:)": { s, a, _ in try a.isKayitlari.map { try s.workLogDetail($0.id) } },
        "needsWorkLog(taskId:)": { s, a, _ in try a.gorevler.map { try s.needsWorkLog(taskId: $0.id) } },
        "knowledgeUndo(proposalId:)": { s, a, _ in try a.oneriler.map { try s.knowledgeUndo(proposalId: $0.id) as Any } },
        "proposalPreview(_:)": { s, a, _ in try s.proposals(brandId: a.id).map { s.proposalPreview($0) as Any } },
        "proposer(of:)": { s, a, _ in try s.proposals(brandId: a.id).map { try s.proposer(of: $0) as Any } },
        "proposals(sessionId:)": { s, a, _ in try s.proposals(sessionId: a.oturumId) },
        "auditTrail(entity:entityId:)": { s, a, _ in
            try a.gorevler.map { try s.auditTrail(entity: "task", entityId: $0.id) } + [try s.auditTrail(entity: "brand", entityId: a.id)]
        },
    ]

    /// A'nın sonucunda kendi işareti görünmesi gereken okumalar (testin boşa geçmediğinin kanıtı).
    static let aIsaretiGorunmeli: Set<String> = [
        "records(brandId:kinds:)", "flow(brandId:limit:)", "brandTeam(brandId:)",
        "proposals(brandId:status:)", "sources(brandId:kinds:includeArchived:)", "tasks(brandId:statuses:limit:)", "workLogs(brandId:statuses:)",
        "observations(brandId:includeInvalidated:)", "radarItems(brandId:includeArchived:)", "brand(_:)", "task(_:)", "source(_:)", "workLogDetail(_:)", "auditTrail(entity:entityId:)",
    ]

    static let tohumTabani: UInt64 = 0x4832_3036_0000 // "H206"

    /// ≥ 200 tohumlu çift. Her tohum bağımsız bir bellek içi çalışma alanıdır; başarısızlık mesajı tohumu verir.
    @Test(arguments: 0..<200)
    func rastgeleIkiMarkaHerYuzeydeSizintiYok(_ sira: Int) throws {
        let tohum = Self.tohumTabani + UInt64(sira)
        var z = Zar(state: tohum)
        let store = try makeStore()
        // Sıra da rastgele: B önce ya da sonra yazılır; B bazen kendi şirket (Stüdyo) markasıdır.
        let bOnce = z.chance(0.5), bStudyo = z.chance(0.25)
        let a: Marka, b: Marka
        if bOnce {
            b = try Self.doldur(store, &z, isOwn: bStudyo); a = try Self.doldur(store, &z, isOwn: false)
        } else {
            a = try Self.doldur(store, &z, isOwn: false); b = try Self.doldur(store, &z, isOwn: bStudyo)
        }
        #expect(!a.isaret.contains(b.isaret) && !b.isaret.contains(a.isaret), "tohum \(tohum): işaretler ayırt edilemiyor")

        // Kimlik çakışmasıyla yazma: B'nin kaydı A'nın kimliğiyle kaydedilip A'ya taşınamaz (bağlı kimlikler temizlenmiş kopya).
        var tasima: [String] = []
        func dene(_ ad: String, _ blok: () throws -> Void) { if (try? blok()) != nil { tasima.append(ad) } }
        if var t = b.gorevler.first { t.brandId = a.id; t.projectId = nil; dene("saveTask") { try store.saveTask(t) } }
        if var r = b.kayitlar.first { r.brandId = a.id; r.sourceId = nil; dene("saveRecord") { try store.saveRecord(r) } }
        if var c = b.kisiler.first { c.brandId = a.id; dene("saveContact") { try store.saveContact(c) } }
        if var p = b.projeler.first { p.brandId = a.id; dene("saveProject") { try store.saveProject(p) } }
        if var l = b.isKayitlari.first { l.brandId = a.id; l.taskId = nil; dene("saveWorkLog") { try store.saveWorkLog(l, inputSourceIds: [], outputSourceIds: []) } }
        if var f = b.finans.first { f.brandId = a.id; dene("saveFinanceEntry") { try store.saveFinanceEntry(f) } }
        #expect(tasima.isEmpty, "tohum \(tohum): B'nin kaydı kimlik çakışmasıyla A'ya yazılabildi: \(tasima)")

        let bIzleri = [b.isaret] + b.kimlikler.filter { !$0.isEmpty }
        var aGoruldu: Set<String> = []
        for (imza, oku) in Self.okumalar.sorted(by: { $0.key < $1.key }) {
            let sonuc: Any
            do { sonuc = try oku(store, a, b) } catch {
                Issue.record("tohum \(tohum): \(imza) A ile çağrılınca hata: \(error)")
                continue
            }
            let duz = String(describing: sonuc)
            let sizan = bIzleri.filter { duz.contains($0) }
            #expect(sizan.isEmpty, "tohum \(tohum): \(imza) A'nın sonucunda B'nin izi: \(sizan.prefix(3))")
            if duz.contains(a.isaret) { aGoruldu.insert(imza) }
        }
        let gorunmeyen = Self.aIsaretiGorunmeli.subtracting(aGoruldu)
        #expect(gorunmeyen.isEmpty, "tohum \(tohum): A'nın kendi verisi görünmedi (test boşa geçiyor olabilir): \(gorunmeyen.sorted())")
    }

    // MARK: - (3) Yazma → denetim olayı

    /// Yazma testinin hazır dünyası: tek müşteri markası (Stüdyo yok) ve her yazma yüzeyinin ihtiyaç duyduğu kayıtlar.
    struct Dunya: Sendable {
        var marka = "", gorev = "", bosGorev = "", kaynak = "", kayit = "", kisi = "", finans = "", isKaydi = ""
        var sure = "", uye = "", bosUye = "", hizmet = "", yetenek = "", bekleyenOneri = "", reddedilecekOneri = ""
        var uygulanmisOneri = "", bekleyenTerminal = "", uygulanmisTerminal = "", gozlem = "", radar = "", dosya: URL!
    }

    static func dunya(_ s: Store) throws -> Dunya {
        var d = Dunya()
        d.marka = try s.createBrand(name: "Kuzey Lojistik").id
        d.gorev = try s.saveTask(WorkTask(brandId: d.marka, title: "Teklif hazırla")).id
        d.bosGorev = try s.saveTask(WorkTask(brandId: d.marka, title: "Silinecek görev")).id
        d.kaynak = try s.addTextSource(brandId: d.marka, kind: .note, title: "Toplantı notu", body: "Sentetik not").id
        d.kayit = try s.saveRecord(BrandRecord(brandId: d.marka, kind: .promise, title: "Cuma teslim")).id
        let kisi = Contact(brandId: d.marka, name: "Deneme Kişi"); try s.saveContact(kisi); d.kisi = kisi.id
        d.finans = try s.saveFinanceEntry(FinanceEntry(brandId: d.marka, kind: .payment, title: "Ödeme")).id
        d.isKaydi = try s.saveWorkLog(WorkLog(brandId: d.marka, taskId: d.gorev, title: "Teklif yazıldı", performed: "Taslak çıktı"),
                                      inputSourceIds: [d.kaynak], outputSourceIds: []).id
        let bas = Date(timeIntervalSince1970: 1_767_225_600)
        d.sure = try s.addTimeEntry(taskId: d.gorev, brandId: d.marka, startedAt: bas, endedAt: bas.addingTimeInterval(1_800)).id
        d.uye = try s.saveTeamMember(TeamMember(kind: .human, name: "Ayşe Deneme", title: "Danışman")).id
        d.bosUye = try s.saveTeamMember(TeamMember(kind: .ai, name: "Yardımcı", title: "Araştırmacı")).id
        try s.assignMember(d.uye, to: d.marka)
        d.hizmet = try s.saveService(ServiceOffering(name: "Sosyal medya")).id
        d.yetenek = try s.saveSkill(Skill(name: "deneme-yetenek", description: "Sentetik yetenek")).id
        d.gozlem = try s.addObservation(brandId: d.marka, statement: "Teklifler cuma günü beklenir", evidenceSourceIds: [d.kaynak]).id
        d.radar = try s.addRadarItem(brandId: d.marka, title: "Rakip kampanyası", address: "ornek-rakip.com", tag: "rakip").id
        d.bekleyenOneri = try s.createProposal(sessionId: nil, brandId: d.marka, kind: .createTask, summary: "Yeni görev",
                                               payload: ProposalPayload.CreateTask(title: "Önerilen görev")).id
        d.reddedilecekOneri = try s.createProposal(sessionId: nil, brandId: d.marka, kind: .createTask, summary: "Başka görev",
                                                   payload: ProposalPayload.CreateTask(title: "Reddedilecek görev")).id
        let uygulanan = try s.createProposal(sessionId: nil, brandId: d.marka, kind: .createBrandRecord, summary: "Söz",
                                             payload: ProposalPayload.CreateBrandRecord(kind: .promise, title: "Önerilen söz"))
        d.uygulanmisOneri = try s.applyProposal(uygulanan.id).id
        func terminal(_ ad: String, _ sha: Character) throws -> String {
            try s.ingestSuggestionFile(brandId: d.marka, fileName: "\(ad).json", sha256: String(repeating: sha, count: 64), drafts: [
                SuggestionDraft(kind: .createTask, summary: ad, payload: ProposalPayload.CreateTask(title: "Terminal \(ad)")),
            ])[0].id
        }
        d.bekleyenTerminal = try terminal("bekleyen", "a")
        let uygulanacak = try terminal("uygulanan", "b")
        d.uygulanmisTerminal = try s.decideSuggestions(brandId: d.marka, decisions: [SuggestionDecision(proposalId: uygulanacak, accept: true)])[0].id
        let klasor = try tempDir("yalitim-yazma")
        d.dosya = klasor.appendingPathComponent("logo.png")
        try Data("sentetik dosya".utf8).write(to: d.dosya)
        return d
    }

    struct Yazma: Sendable {
        var hazirlik: (@Sendable (Store, Dunya) throws -> Void)? = nil
        var yaz: @Sendable (Store, Dunya) throws -> Void
    }

    /// Her yazma yüzeyi için bir çağrı. Anahtar = taranan seçici; §2 istisnaları dışındaki her yazma yüzeyi burada olmalı.
    static let yazmalar: [String: Yazma] = [
        "createBrand(name:summary:sector:isOwn:actor:)": .init { s, _ in try s.createBrand(name: "Örnek Kafe Zinciri") },
        "createStudio(name:actor:)": .init { s, _ in try s.createStudio(name: "Deneme Stüdyo") },
        "updateBrand(_:actor:)": .init { s, d in var b = try s.brand(d.marka); b.summary = "Yeni özet"; try s.updateBrand(b) },
        "setBrandArchived(_:archived:)": .init { s, d in try s.setBrandArchived(d.marka, archived: true) },
        "setBrandLogo(_:fileURL:)": .init { s, d in try s.setBrandLogo(d.marka, fileURL: d.dosya) },
        "setAIProviders(_:providers:)": .init { s, d in try s.setAIProviders(d.marka, providers: [.anthropic]) },
        "saveContact(_:)": .init { s, d in try s.saveContact(Contact(brandId: d.marka, name: "Yeni Kişi")) },
        "deleteContact(_:)": .init { s, d in try s.deleteContact(d.kisi) },
        "saveProject(_:)": .init { s, d in try s.saveProject(Project(brandId: d.marka, name: "Lansman")) },
        "saveRecord(_:actor:)": .init { s, d in try s.saveRecord(BrandRecord(brandId: d.marka, kind: .decision, title: "Karar")) },
        "deleteRecord(_:)": .init { s, d in try s.deleteRecord(d.kayit) },
        "saveFinanceEntry(_:actor:)": .init { s, d in try s.saveFinanceEntry(FinanceEntry(brandId: d.marka, kind: .budget, title: "Bütçe")) },
        "deleteFinanceEntry(_:actor:)": .init { s, d in try s.deleteFinanceEntry(d.finans) },
        "saveCompanyProfile(_:actor:)": .init { s, _ in try s.saveCompanyProfile(CompanyProfile(name: "Deneme Şirket")) },
        "saveService(_:actor:)": .init { s, _ in try s.saveService(ServiceOffering(name: "Bülten")) },
        "deleteService(_:actor:)": .init { s, d in try s.deleteService(d.hizmet) },
        "saveTeamMember(_:actor:)": .init { s, _ in try s.saveTeamMember(TeamMember(kind: .human, name: "Yeni Üye", title: "Tasarımcı")) },
        "archiveTeamMember(_:actor:)": .init { s, d in try s.archiveTeamMember(d.uye) },
        "restoreTeamMember(_:actor:)": .init(hazirlik: { s, d in try s.archiveTeamMember(d.uye) }) { s, d in try s.restoreTeamMember(d.uye) },
        "assignMember(_:to:role:actor:)": .init { s, d in try s.assignMember(d.bosUye, to: d.marka) },
        "unassignMember(_:from:actor:)": .init { s, d in try s.unassignMember(d.uye, from: d.marka) },
        "setProfileSection(brandId:_:body:actor:)": .init { s, d in try s.setProfileSection(brandId: d.marka, .audience, body: "Esnaf") },
        "applyProposal(_:)": .init { s, d in try s.applyProposal(d.bekleyenOneri) },
        "rejectProposal(_:)": .init { s, d in try s.rejectProposal(d.reddedilecekOneri) },
        "revertProposal(_:)": .init { s, d in try s.revertProposal(d.uygulanmisOneri) },
        "saveSkill(_:actor:)": .init { s, _ in try s.saveSkill(Skill(name: "yeni-yetenek", description: "Sentetik")) },
        "deleteSkill(_:actor:)": .init { s, d in try s.deleteSkill(d.yetenek) },
        "importSkill(markdown:fileName:actor:)": .init { s, _ in
            try s.importSkill(markdown: "---\nname: ice-aktarilan\ndescription: Sentetik yetenek\n---\nYönerge", fileName: "SKILL.md")
        },
        "importSkillBundle(_:folderName:actor:)": .init { s, _ in
            let p = SkillBundlePreview(action: .add, existingId: nil, name: "paket-yetenek", title: "", description: "Sentetik paket",
                                       referencePaths: [], skipped: [], digest: "", totalBytes: 0, combinedBody: "Yönerge",
                                       exceedsLibraryLimit: false)
            try s.importSkillBundle(p, folderName: "paket-yetenek")
        },
        "installSkillPack(_:actor:)": .init { s, _ in _ = try s.installSkillPack(SkillPacks.method) },
        "addTextSource(brandId:kind:title:body:url:capturedAt:openRequest:actor:)": .init { s, d in
            try s.addTextSource(brandId: d.marka, kind: .meeting, title: "Görüşme", body: "Sentetik görüşme")
        },
        "addFileSource(brandId:fileURL:kind:title:capturedAt:confineTo:actor:)": .init { s, d in try s.addFileSource(brandId: d.marka, fileURL: d.dosya) },
        "addGeneratedOutput(brandId:fileName:content:title:capturedAt:actor:)": .init { s, d in
            try s.addGeneratedOutput(brandId: d.marka, fileName: "cikti.md", content: "# Çıktı", title: "Çıktı", actor: .user)
        },
        "setSourceArchived(_:brandId:archived:actor:)": .init { s, d in try s.setSourceArchived(d.kaynak, brandId: d.marka, archived: true) },
        "ingestSuggestionFile(brandId:fileName:sha256:drafts:)": .init { s, d in
            try s.ingestSuggestionFile(brandId: d.marka, fileName: "yeni.json", sha256: String(repeating: "c", count: 64), drafts: [])
        },
        "decideSuggestions(brandId:decisions:)": .init { s, d in
            try s.decideSuggestions(brandId: d.marka, decisions: [SuggestionDecision(proposalId: d.bekleyenTerminal, accept: true)])
        },
        "revertSuggestions(brandId:proposalIds:)": .init { s, d in try s.revertSuggestions(brandId: d.marka, proposalIds: [d.uygulanmisTerminal]) },
        "saveTask(_:actor:)": .init { s, d in try s.saveTask(WorkTask(brandId: d.marka, title: "Yeni görev")) },
        "setTaskStatus(_:_:actor:)": .init { s, d in try s.setTaskStatus(d.gorev, .waiting) },
        "deleteTask(_:)": .init { s, d in try s.deleteTask(d.bosGorev) },
        "startTimer(taskId:at:)": .init { s, d in try s.startTimer(taskId: d.gorev) },
        "stopTimer(at:)": .init(hazirlik: { s, d in try s.startTimer(taskId: d.gorev) }) { s, _ in try s.stopTimer() },
        "addManualTime(taskId:seconds:endingAt:note:)": .init { s, d in try s.addManualTime(taskId: d.gorev, seconds: 600) },
        "addTimeEntry(taskId:brandId:startedAt:endedAt:note:now:)": .init { s, d in
            let bas = Date(timeIntervalSince1970: 1_767_400_000)
            try s.addTimeEntry(taskId: d.gorev, brandId: d.marka, startedAt: bas, endedAt: bas.addingTimeInterval(900))
        },
        "updateTimeEntry(_:brandId:startedAt:endedAt:note:now:)": .init { s, d in
            let bas = Date(timeIntervalSince1970: 1_767_225_600)
            try s.updateTimeEntry(d.sure, brandId: d.marka, startedAt: bas, endedAt: bas.addingTimeInterval(2_400), note: "düzeltildi")
        },
        "deleteTimeEntry(_:brandId:)": .init { s, d in try s.deleteTimeEntry(d.sure, brandId: d.marka) },
        "startTimerReportingHandoff(taskId:at:)": .init { s, d in try s.startTimerReportingHandoff(taskId: d.gorev) },
        "saveWorkLog(_:inputSourceIds:outputSourceIds:actor:)": .init { s, d in
            try s.saveWorkLog(WorkLog(brandId: d.marka, title: "Yeni iş"), inputSourceIds: [], outputSourceIds: [])
        },
        "verifyWorkLog(_:verifiedBy:)": .init { s, d in try s.verifyWorkLog(d.isKaydi, verifiedBy: "Deneme Kişi") },
        "saveUserWorkLog(_:inputSourceIds:outputSourceIds:verifiedBy:)": .init { s, d in
            try s.saveUserWorkLog(WorkLog(brandId: d.marka, taskId: d.gorev, title: "Elle iş", performed: "Yapıldı"),
                                  inputSourceIds: [], outputSourceIds: [], verifiedBy: "Deneme Kişi")
        },
        "retractWorkLog(_:)": .init { s, d in try s.retractWorkLog(d.isKaydi) },
        "addObservation(brandId:statement:evidenceSourceIds:actor:)": .init { s, d in
            try s.addObservation(brandId: d.marka, statement: "Müşteri kısa rapor ister", evidenceSourceIds: [d.kaynak])
        },
        "addSupersedingObservation(replacing:brandId:statement:evidenceSourceIds:actor:)": .init { s, d in
            try s.addSupersedingObservation(replacing: d.gozlem, brandId: d.marka, statement: "Teklifler perşembe beklenir",
                                            evidenceSourceIds: [d.kaynak])
        },
        "invalidateObservation(_:brandId:actor:)": .init { s, d in try s.invalidateObservation(d.gozlem, brandId: d.marka) },
        "addRadarItem(brandId:title:address:note:tag:actor:)": .init { s, d in
            try s.addRadarItem(brandId: d.marka, title: "Sektör notu", note: "Fuar tarihi açıklandı")
        },
        "setRadarItemArchived(_:brandId:archived:actor:)": .init { s, d in try s.setRadarItemArchived(d.radar, brandId: d.marka, archived: true) },
    ]

    @Test func herYazmaYuzeyiDenetimOlayiBirakir() throws {
        for (imza, yazma) in Self.yazmalar.sorted(by: { $0.key < $1.key }) {
            let s = try makeStore()
            let d = try Self.dunya(s)
            try yazma.hazirlik?(s, d)
            let once = try s.read { db in try AuditEvent.fetchCount(db) }
            do { try yazma.yaz(s, d) } catch {
                Issue.record("\(imza) yazılamadı: \(error)")
                continue
            }
            let sonra = try s.read { db in try AuditEvent.fetchCount(db) }
            #expect(sonra - once >= 1, "\(imza) denetim olayı bırakmadı")
        }
    }

    /// Tabloların taramayla eşleşmesi: kapsamlı her okuma yüzeyi okuma tablosunda, §2 dışındaki her yazma yüzeyi yazma
    /// tablosunda. Yeni yüzey eklenip tabloya girmezse kırmızı (bilinçli karar zorunlu).
    @Test func okumaVeYazmaTablolariTaramayiKapsar() throws {
        let yuzeyler = try Self.tara()
        let izin = try Self.izinListesi()
        let hepsi = Set(yuzeyler.map(\.imza))
        let kapsamliOkuma = Set(yuzeyler.filter { $0.kapsamli && !$0.yazma }.map(\.imza))
        #expect(kapsamliOkuma.subtracting(Self.okumalar.keys).isEmpty,
                "Okuma tablosunda olmayan kapsamlı okuma yüzeyi: \(kapsamliOkuma.subtracting(Self.okumalar.keys).sorted())")
        #expect(Set(Self.okumalar.keys).subtracting(hepsi).isEmpty, "Okuma tablosunda var olmayan yüzey: \(Set(Self.okumalar.keys).subtracting(hepsi).sorted())")
        let okumaAdlari = Self.okumalar.keys.map { imza in String(imza.prefix { ch in ch != "(" }) }
        #expect(okumaAdlari.allSatisfy { ad in !Self.yazmaMi(ad) }, "Okuma tablosunda yazma yüzeyi var")

        let yazma = Set(yuzeyler.filter(\.yazma).map(\.imza))
        let kapsanan = Set(Self.yazmalar.keys).union(izin.denetimsiz.keys)
        #expect(yazma.subtracting(kapsanan).isEmpty,
                "Denetim testi ya da §2 istisnası olmayan yazma yüzeyi: \(yazma.subtracting(kapsanan).sorted())")
        #expect(Set(Self.yazmalar.keys).subtracting(yazma).isEmpty, "Yazma tablosunda var olmayan yüzey: \(Set(Self.yazmalar.keys).subtracting(yazma).sorted())")
        #expect(Set(Self.yazmalar.keys).isDisjoint(with: izin.denetimsiz.keys), "Hem test edilen hem istisna olan yazma yüzeyi")
    }
}
