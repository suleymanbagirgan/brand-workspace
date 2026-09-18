import Foundation
import GRDB

/// Oturumun kapsamı. Marka kapsamında yalnızca o markanın verisi okunur.
public enum SessionScope: Sendable, Hashable {
    case brand(String)
    case allBrands

    public init(session: AISession) {
        if session.scope == .brand, let b = session.brandId { self = .brand(b) } else { self = .allBrands }
    }
}

public struct ContextBuilder: Sendable {
    public let store: Store
    public init(store: Store) { self.store = store }

    static let baseInstructions = """
    Sen "Marka Çalışma Alanı" uygulamasında çalışan bir danışmanlık asistanısın. Kullanıcı birden fazla markaya danışmanlık veriyor.
    Kurallar:
    - Yalnızca sana verilen kapsamdaki markanın verisini kullan. Başka bir markayı tahmin etme, anma veya bilgi uydurma.
    - Kaynaklara dayan. Bir bilgiyi kullandığında hangi kaynaktan geldiğini (kaynak adı) belirt. Emin olmadığın şeyi söyleme; "kayıtlarda yok" de.
    - Veri değiştiremezsin. Görev, çalışma kaydı, çıktı dosyası, marka kaydı veya bilgi sayfası değişikliği için ilgili *_oner aracını kullan; kullanıcı onaylar.
    - Sohbette kullanıcının söylediği şey otomatik olarak gerçek kabul edilmez; kalıcı bilgi için kullanıcıya not kaynağı eklemesini öner.
    - Müşteriye bir şey gönderemezsin ve gönderilmiş gibi yazmazsın.
    - Kısa, net, Türkçe yaz (kullanıcı başka dilde yazarsa o dilde).
    """

    public func systemPrompt(scope: SessionScope, now: Date = Date()) throws -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "tr_TR")
        fmt.dateFormat = "d MMMM yyyy EEEE"
        var out = Self.baseInstructions + "\n\nBugün: \(fmt.string(from: now)) (\(DayString.from(now)))\n"
        switch scope {
        case .brand(let id):
            out += try brandContext(brandId: id, now: now)
        case .allBrands:
            out += try allBrandsContext(now: now)
        }
        return out
    }

    public func brandContext(brandId: String, now: Date = Date()) throws -> String {
        let brand = try store.brand(brandId)
        var s = "\n# Kapsam: yalnızca “\(brand.name)” markası\n"
        if !brand.sector.isEmpty { s += "Sektör: \(brand.sector)\n" }
        if !brand.summary.isEmpty { s += "Tanım: \(brand.summary)\n" }
        let contacts = try store.contacts(brandId: brandId)
        if !contacts.isEmpty {
            s += "\n## Kişiler (iletişim bilgileri paylaşılmaz)\n"
            for c in contacts { s += "- \(c.name)\(c.role.isEmpty ? "" : " — \(c.role)")\n" }
        }
        let records = try store.records(brandId: brandId).filter(\.isOpen)
        if !records.isEmpty {
            s += "\n## Açık marka kayıtları\n"
            for r in records.prefix(40) {
                s += "- [\(r.kind.rawValue)] \(r.title)\(r.dueDate.map { " (tarih: \($0))" } ?? "") id=\(r.id)\n"
            }
        }
        let tasks = try store.tasks(brandId: brandId).filter(\.status.isOpen)
        if !tasks.isEmpty {
            s += "\n## Açık görevler\n"
            for t in tasks.prefix(40) {
                s += "- \(t.title) [durum: \(t.status.rawValue), öncelik: \(t.priority)\(t.dueDate.map { ", son tarih: \($0)" } ?? "")] id=\(t.id)\n"
            }
        }
        let sources = try store.sources(brandId: brandId)
        if !sources.isEmpty {
            s += "\n## Son kaynaklar (içerik için kaynak_oku aracını kullan)\n"
            let df = ISO8601DateFormatter()
            for src in sources.prefix(40) {
                s += "- \(src.title) [tür: \(src.kind.rawValue), tarih: \(df.string(from: src.capturedAt))] id=\(src.id)\n"
            }
        }
        let pages = try store.wikiPages(brandId: brandId).filter { $0.currentRevisionId != nil }
        if !pages.isEmpty {
            s += "\n## Bilgi sayfaları\n"
            for p in pages { s += "- \(p.title) [\(p.kind.rawValue)\(p.status == .current ? "" : ", durum: \(p.status.rawValue)")] id=\(p.id)\n" }
        }
        s += "\n## Bu markanın bilgi kuralları\n" + (try store.wikiRules(brandId: brandId)) + "\n"
        return s
    }

    public func allBrandsContext(now: Date = Date()) throws -> String {
        var s = "\n# Kapsam: TÜM MARKALAR (kullanıcı açıkça seçti)\nBu kapsamda öneri araçları yoktur; yalnızca okuma ve karşılaştırma yapılır. Markaların bilgilerini birbirine karıştırma; her cümlede hangi markadan söz ettiğini belirt.\n"
        let overview = try StatusService(store: store).overview(now: now)
        for b in try store.brands() {
            s += "\n## \(b.name) id=\(b.id)\n"
            let open = try store.tasks(brandId: b.id).filter(\.status.isOpen)
            s += "Açık görev: \(open.count)\n"
            if let lc = overview.lastContacts.first(where: { $0.brand.id == b.id })?.line {
                s += "Son temas: \(lc.text)\n"
            }
        }
        return s
    }
}

// MARK: - Araçlar

public struct ToolSpec: Sendable, Hashable {
    public var name: String
    public var description: String
    public var schema: JSONValue
    public var isProposal: Bool
}

public enum ToolCatalog {
    static func obj(_ props: [String: JSONValue], required: [String]) -> JSONValue {
        .object(["type": "object", "properties": .object(props), "required": .array(required.map { .string($0) }), "additionalProperties": false])
    }
    static let str: JSONValue = ["type": "string"]
    static func str(_ d: String) -> JSONValue { ["type": "string", "description": .string(d)] }
    static let strArray: JSONValue = ["type": "array", "items": ["type": "string"]]

    public static func tools(for scope: SessionScope) -> [ToolSpec] {
        switch scope {
        case .brand: brandTools
        case .allBrands: allBrandTools
        }
    }

    public static let brandTools: [ToolSpec] = [
        ToolSpec(name: "kaynak_ara", description: "Bu markanın kaynaklarında ve onaylı bilgi sayfalarında tam metin arama yapar.",
                 schema: obj(["sorgu": str("Aranacak sözcükler")], required: ["sorgu"]), isProposal: false),
        ToolSpec(name: "kaynak_oku", description: "Bu markanın bir kaynağının tam metnini ve bilgilerini döndürür.",
                 schema: obj(["kaynak_id": str], required: ["kaynak_id"]), isProposal: false),
        ToolSpec(name: "bilgi_sayfasi_oku", description: "Bir bilgi sayfasının güncel sürümünü ve kaynaklı iddialarını döndürür.",
                 schema: obj(["sayfa_id": str], required: ["sayfa_id"]), isProposal: false),
        ToolSpec(name: "calisma_kayitlari", description: "Bu markanın son çalışma kayıtlarını (durumlarıyla) listeler.",
                 schema: obj([:], required: []), isProposal: false),
        ToolSpec(name: "gorev_oner", description: "Yeni görev önerir. Kullanıcı onaylarsa oluşturulur.",
                 schema: obj(["baslik": str, "notlar": str, "oncelik": ["type": "integer", "minimum": 0, "maximum": 3],
                              "son_tarih": str("yyyy-MM-dd")], required: ["baslik"]), isProposal: true),
        ToolSpec(name: "gorevi_tamamla_oner", description: "Bir görevin tamamlandı olarak işaretlenmesini önerir.",
                 schema: obj(["gorev_id": str], required: ["gorev_id"]), isProposal: true),
        ToolSpec(name: "cikti_dosyasi_oner", description: "Bir iş çıktısı dosyası (Markdown) önerir: teklif metni, e-posta taslağı, özet vb. Onaylanırsa markanın kaynaklarına iş çıktısı olarak eklenir.",
                 schema: obj(["dosya_adi": str("ör. teklif-taslagi.md"), "baslik": str, "icerik": str("Markdown içerik"),
                              "kullanilan_kaynaklar": strArray], required: ["dosya_adi", "baslik", "icerik", "kullanilan_kaynaklar"]), isProposal: true),
        ToolSpec(name: "calisma_kaydi_oner", description: "Yapılan iş için taslak çalışma kaydı önerir. Kullanıcı sonradan doğrular. Henüz onaylanmamış çıktı önerisini 'oneri:<id>' biçiminde çıktı olarak verebilirsin.",
                 schema: obj(["baslik": str, "ne_istendi": str, "ne_yapildi": str, "karar": str, "musteriye_bildirilen": str,
                              "gorev_id": str, "girdi_kaynaklari": strArray, "ciktilar": strArray],
                             required: ["baslik", "ne_istendi", "ne_yapildi", "girdi_kaynaklari"]), isProposal: true),
        ToolSpec(name: "marka_kaydi_oner", description: "Marka kaydı önerir: hedef, talep, söz, bekleyen karar, teklif, sözleşme veya önemli tarih.",
                 schema: obj(["tur": ["type": "string", "enum": ["goal", "request", "promise", "decision", "proposal", "contract", "milestone"]],
                              "baslik": str, "detay": str, "tarih": str("yyyy-MM-dd"), "kaynak_id": str], required: ["tur", "baslik"]), isProposal: true),
        ToolSpec(name: "bilgi_guncelle_oner", description: "Bilgi sayfası oluşturma veya güncelleme önerir. Her iddia bu markanın bir kaynak kimliğine dayanmalı. Çelişen veya eskimiş bilgiyi durum alanıyla işaretle.",
                 schema: obj(["sayfa_id": str("Güncellenecek sayfa; yeni sayfa için boş bırak"),
                              "tur": ["type": "string", "enum": ["overview", "person", "goal", "project", "decision", "preference", "process"]],
                              "baslik": str, "govde": str("Kısa Markdown özet"),
                              "iddialar": ["type": "array", "items": obj(["metin": str, "kaynak_id": str,
                                                                          "durum": ["type": "string", "enum": ["current", "conflict", "stale"]],
                                                                          "not": str], required: ["metin", "kaynak_id"])],
                              "baglantilar": strArray], required: ["tur", "baslik", "govde", "iddialar"]), isProposal: true),
    ]

    public static let allBrandTools: [ToolSpec] = [
        ToolSpec(name: "kaynak_ara", description: "Tüm markalarda arama yapar; sonuçlar marka adıyla döner.",
                 schema: obj(["sorgu": str], required: ["sorgu"]), isProposal: false),
        ToolSpec(name: "genel_bakis", description: "Tüm markalar için geciken görevler, yaklaşan teslimler, bekleyen konular ve bu hafta doğrulanan işler.",
                 schema: obj([:], required: []), isProposal: false),
    ]
}

public struct ToolResult: Sendable {
    public var text: String
    public var isError: Bool
    public var event: ChatEventRecord
}

/// Araçları oturum kapsamına bağlı olarak yürütür. Başka markanın kimliği istenirse hata döner.
public struct ToolExecutor: Sendable {
    public let store: Store
    public let scope: SessionScope
    public let sessionId: String?
    /// Tüm markalar kapsamında yalnızca bu sağlayıcıya izin veren markalar okunur.
    public let allowedBrandIds: Set<String>?

    public init(store: Store, scope: SessionScope, sessionId: String?, allowedBrandIds: Set<String>? = nil) {
        self.store = store; self.scope = scope; self.sessionId = sessionId; self.allowedBrandIds = allowedBrandIds
    }

    func permitted(_ brandId: String) -> Bool { allowedBrandIds?.contains(brandId) ?? true }

    var brandId: String? { if case .brand(let b) = scope { return b }; return nil }

    public func run(name: String, input: JSONValue) -> ToolResult {
        do {
            guard ToolCatalog.tools(for: scope).contains(where: { $0.name == name }) else {
                throw MarkaError.validation(LF("Bu kapsamda “%@” aracı yok.", name))
            }
            return try execute(name: name, input: input)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return ToolResult(text: "HATA: \(message)", isError: true,
                              event: ChatEventRecord(kind: .error, title: LF("Araç reddedildi: %@", name), detail: message, status: "error"))
        }
    }

    func req(_ input: JSONValue, _ key: String) throws -> String {
        guard let v = input[key]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else {
            throw MarkaError.validation(LF("Eksik alan: %@", key))
        }
        return v
    }

    func opt(_ input: JSONValue, _ key: String) -> String? {
        guard let v = input[key]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
        return v
    }

    func strings(_ input: JSONValue, _ key: String) -> [String] {
        input[key]?.array?.compactMap(\.string).filter { !$0.isEmpty } ?? []
    }

    func requireBrand() throws -> String {
        guard let brandId else { throw MarkaError.validation(L("Tüm markalar kapsamında öneri yapılamaz.")) }
        return brandId
    }

    func ownSource(_ id: String) throws -> Source {
        let s = try store.source(id)
        if let brandId, s.brandId != brandId { throw MarkaError.brandScope }
        if !permitted(s.brandId) { throw MarkaError.brandScope }
        return s
    }

    private func execute(name: String, input: JSONValue) throws -> ToolResult {
        let names = Dictionary(uniqueKeysWithValues: try store.brands(includeArchived: true).map { ($0.id, $0.name) })
        switch name {
        case "kaynak_ara":
            let q = try req(input, "sorgu")
            let hits = try store.search(q, brandId: brandId, limit: 12).filter { permitted($0.brandId) }
            let text = hits.isEmpty ? "Sonuç yok." : hits.map {
                "- [\($0.kind == .source ? "kaynak" : "bilgi")] \($0.title)\(brandId == nil ? " (marka: \(names[$0.brandId] ?? "?"))" : "") id=\($0.id)\n  \($0.snippet)"
            }.joined(separator: "\n")
            return ToolResult(text: text, isError: false,
                              event: ChatEventRecord(kind: .toolRead, title: LF("Arandı: “%@”", q), detail: LF("%d sonuç", hits.count), status: "done"))
        case "kaynak_oku":
            let s = try ownSource(try req(input, "kaynak_id"))
            let body = s.body.count > 30_000 ? String(s.body.prefix(30_000)) + "\n…(kısaltıldı)" : s.body
            let text = "Başlık: \(s.title)\nTür: \(s.kind.rawValue)\nTarih: \(ISO8601DateFormatter().string(from: s.capturedAt))\n\(s.fileName.map { "Dosya: \($0)\n" } ?? "")\(s.url.map { "Bağlantı: \($0)\n" } ?? "")\n\(body.isEmpty ? "(metin çıkarılamadı)" : body)"
            return ToolResult(text: text, isError: false,
                              event: ChatEventRecord(kind: .toolRead, title: LF("Kaynak okundu: %@", s.title), detail: s.fileName ?? "", status: "done", refId: s.id))
        case "bilgi_sayfasi_oku":
            let d = try store.wikiPageDetail(try req(input, "sayfa_id"))
            if let brandId, d.page.brandId != brandId { throw MarkaError.brandScope }
            var text = "Sayfa: \(d.page.title) [\(d.page.kind.rawValue)] durum: \(d.page.status.rawValue)\n\(d.current?.body ?? "")\nİddialar:\n"
            for c in d.claims { text += "- \(c.text) (kaynak: \(c.sourceId ?? "yok"), durum: \(c.status.rawValue)\(c.flagNote.isEmpty ? "" : ", not: \(c.flagNote)"))\n" }
            return ToolResult(text: text, isError: false,
                              event: ChatEventRecord(kind: .toolRead, title: LF("Bilgi sayfası okundu: %@", d.page.title), status: "done", refId: d.page.id))
        case "calisma_kayitlari":
            let logs = try store.workLogs(brandId: try requireBrand()).prefix(20)
            let text = logs.isEmpty ? "Kayıt yok." : logs.map { "- \($0.title) [\($0.status.rawValue)] ne yapıldı: \($0.performed) id=\($0.id)" }.joined(separator: "\n")
            return ToolResult(text: text, isError: false, event: ChatEventRecord(kind: .toolRead, title: L("Çalışma kayıtları okundu"), status: "done"))
        case "genel_bakis":
            var o = try StatusService(store: store).overview()
            let ok: (StatusLine) -> Bool = { line in
                guard let allowed = allowedBrandIds else { return true }
                return line.brandId.map(allowed.contains) ?? false
            }
            o.overdueTasks = o.overdueTasks.filter(ok); o.dueThisWeek = o.dueThisWeek.filter(ok)
            o.awaiting = o.awaiting.filter(ok); o.verifiedThisWeek = o.verifiedThisWeek.filter(ok)
            var text = "Geciken görevler:\n" + o.overdueTasks.map { "- \($0.text) (\($0.detail))" }.joined(separator: "\n")
            text += "\nBu hafta teslim:\n" + o.dueThisWeek.map { "- \($0.text) (\($0.detail), \($0.dueDate ?? ""))" }.joined(separator: "\n")
            text += "\nYanıt bekleyen:\n" + o.awaiting.map { "- \($0.text) (\($0.detail))" }.joined(separator: "\n")
            text += "\nBu hafta doğrulanan işler:\n" + o.verifiedThisWeek.map { "- \($0.text) (\($0.detail))" }.joined(separator: "\n")
            return ToolResult(text: text, isError: false, event: ChatEventRecord(kind: .toolRead, title: L("Genel bakış okundu"), status: "done"))

        case "gorev_oner":
            let b = try requireBrand()
            let payload = ProposalPayload.CreateTask(title: try req(input, "baslik"), notes: opt(input, "notlar"),
                                                     priority: input["oncelik"]?.int, dueDate: opt(input, "son_tarih"))
            let p = try store.createProposal(sessionId: sessionId, brandId: b, kind: .createTask, summary: LF("Yeni görev: %@", payload.title), payload: payload)
            return proposalResult(p)
        case "gorevi_tamamla_oner":
            let b = try requireBrand()
            let taskId = try req(input, "gorev_id")
            let t = try store.task(taskId)
            let p = try store.createProposal(sessionId: sessionId, brandId: b, kind: .completeTask, summary: LF("Görevi tamamla: %@", t.title),
                                             payload: ProposalPayload.CompleteTask(taskId: taskId))
            return proposalResult(p)
        case "cikti_dosyasi_oner":
            let b = try requireBrand()
            let used = strings(input, "kullanilan_kaynaklar")
            for id in used { _ = try ownSource(id) }
            let payload = ProposalPayload.CreateOutput(fileName: try req(input, "dosya_adi"), title: try req(input, "baslik"),
                                                       content: try req(input, "icerik"), inputSourceIds: used)
            let p = try store.createProposal(sessionId: sessionId, brandId: b, kind: .createOutput, summary: LF("Çıktı dosyası: %@", payload.fileName), payload: payload)
            return proposalResult(p, detail: String(payload.content.prefix(400)))
        case "calisma_kaydi_oner":
            let b = try requireBrand()
            let payload = ProposalPayload.CreateWorkLog(title: try req(input, "baslik"), requested: try req(input, "ne_istendi"),
                                                        performed: try req(input, "ne_yapildi"), decision: opt(input, "karar"),
                                                        clientNotified: opt(input, "musteriye_bildirilen"), taskId: opt(input, "gorev_id"),
                                                        inputSourceIds: strings(input, "girdi_kaynaklari"), outputSourceIds: strings(input, "ciktilar"))
            let p = try store.createProposal(sessionId: sessionId, brandId: b, kind: .createWorkLog, summary: LF("Çalışma kaydı: %@", payload.title), payload: payload)
            return proposalResult(p, detail: payload.performed)
        case "marka_kaydi_oner":
            let b = try requireBrand()
            guard let kind = BrandRecordKind(rawValue: try req(input, "tur")) else { throw MarkaError.validation(L("Geçersiz kayıt türü.")) }
            let payload = ProposalPayload.CreateBrandRecord(kind: kind, title: try req(input, "baslik"), detail: opt(input, "detay"),
                                                            dueDate: opt(input, "tarih"), sourceId: opt(input, "kaynak_id"))
            let p = try store.createProposal(sessionId: sessionId, brandId: b, kind: .createBrandRecord, summary: LF("Marka kaydı: %@", payload.title), payload: payload)
            return proposalResult(p)
        case "bilgi_guncelle_oner":
            let b = try requireBrand()
            guard let kind = WikiPageKind(rawValue: try req(input, "tur")) else { throw MarkaError.validation(L("Geçersiz sayfa türü.")) }
            let claims: [WikiClaimInput] = try (input["iddialar"]?.array ?? []).map { c in
                WikiClaimInput(text: try req(c, "metin"), sourceId: try req(c, "kaynak_id"),
                               status: ClaimStatus(rawValue: opt(c, "durum") ?? "current") ?? .current, flagNote: opt(c, "not") ?? "")
            }
            let title = try req(input, "baslik")
            let revision = try store.writeWikiRevision(brandId: b, pageId: opt(input, "sayfa_id"), kind: kind, title: title,
                                                       body: opt(input, "govde") ?? "", claims: claims, links: strings(input, "baglantilar"),
                                                       note: L("AI önerisi"), actor: .ai)
            let p = try store.writer.write { db -> AIProposal in
                let p = AIProposal(sessionId: sessionId, brandId: b, kind: .wikiRevision, summary: LF("Bilgi sayfası: %@", title),
                                   payloadJSON: "{}", resultEntityId: revision.id)
                try p.insert(db)
                return p
            }
            return proposalResult(p, detail: LF("%d kaynaklı iddia", claims.count))
        default:
            throw MarkaError.validation(LF("Bilinmeyen araç: %@", name))
        }
    }

    func proposalResult(_ p: AIProposal, detail: String = "") -> ToolResult {
        ToolResult(text: "Öneri oluşturuldu (id=\(p.id)). Kullanıcı onayı bekleniyor; henüz uygulanmadı.", isError: false,
                   event: ChatEventRecord(kind: .proposal, title: p.summary, detail: detail, status: "pending", refId: p.id))
    }
}
