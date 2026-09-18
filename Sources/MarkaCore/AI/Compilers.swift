import Foundation

/// Yapılandırılmış AI görevleri için sağlayıcı seçimi.
public enum StructuredProvider: Sendable {
    case anthropic(AnthropicClient)
    case codex(CodexAppServer, model: String, cwd: URL)

    var kind: AIProviderKind {
        switch self { case .anthropic: .anthropic; case .codex: .codex }
    }

    func completeJSON(system: String, user: String, schema: JSONValue) async throws -> (JSONValue, UsageEntry) {
        switch self {
        case .anthropic(let client):
            let (json, r) = try await client.completeJSON(system: system, user: user, schema: schema)
            let cost = PriceTable.costMicros(model: r.model, input: r.inputTokens, output: r.outputTokens, cacheRead: r.cacheReadTokens, cacheWrite: r.cacheWriteTokens)
            return (json, UsageEntry(provider: .anthropic, model: r.model, sessionId: nil, brandId: nil, purpose: "", inputTokens: r.inputTokens,
                                     outputTokens: r.outputTokens, cacheReadTokens: r.cacheReadTokens, cacheWriteTokens: r.cacheWriteTokens, costMicros: cost))
        case .codex(let server, let model, let cwd):
            try await server.start()
            let (json, input, output) = try await server.completeJSON(cwd: cwd, model: model, instructions: system, prompt: user, schema: schema)
            return (json, UsageEntry(provider: .codex, model: model, sessionId: nil, brandId: nil, purpose: "", inputTokens: input,
                                     outputTokens: output, costMicros: nil))
        }
    }
}

/// Yeni kaynaktan bilgi sayfası önerileri üretir (llmwiki "ingest" yaklaşımı, onaylı akışla).
public struct KnowledgeCompiler: Sendable {
    public let store: Store
    public init(store: Store) { self.store = store }

    public struct Outcome: Sendable {
        public var proposedRevisions: [WikiRevision]
        public var rejected: [String]
        public var usage: UsageEntry
        /// Modelin ham JSON çıktısı (doğrulama aracı için; uygulama bunu kullanmaz). Marka içeriği taşır: tanıya ve günlüğe bağlanmaz.
        public var raw: JSONValue = .null
    }

    static var schema: JSONValue {
        let claim: JSONValue = ["type": "object", "additionalProperties": false, "required": ["metin", "kaynak_id", "durum", "not"],
                                "properties": ["metin": ["type": "string"], "kaynak_id": ["type": "string"],
                                               "durum": ["type": "string", "enum": ["current", "conflict", "stale"]], "not": ["type": "string"]]]
        let page: JSONValue = ["type": "object", "additionalProperties": false,
                               "required": ["sayfa_id", "tur", "baslik", "govde", "iddialar", "baglantilar"],
                               "properties": ["sayfa_id": ["type": "string"],
                                              "tur": ["type": "string", "enum": ["overview", "person", "goal", "project", "decision", "preference", "process"]],
                                              "baslik": ["type": "string"], "govde": ["type": "string"],
                                              "iddialar": ["type": "array", "items": claim], "baglantilar": ["type": "array", "items": ["type": "string"]]]]
        return ["type": "object", "additionalProperties": false, "required": ["sayfalar"],
                "properties": ["sayfalar": ["type": "array", "items": page]]]
    }

    func prompt(brandId: String, source: Source) throws -> (system: String, user: String) {
        let brand = try store.brand(brandId)
        let rules = try store.wikiRules(brandId: brandId)
        var index = ""
        for page in try store.wikiPages(brandId: brandId) where page.currentRevisionId != nil {
            let detail = try store.wikiPageDetail(page.id)
            index += "\n## \(page.title) [\(page.kind.rawValue)] sayfa_id=\(page.id)\n\(detail.current?.body ?? "")\n"
            for c in detail.claims { index += "- \(c.text) (kaynak_id=\(c.sourceId ?? "yok"), durum=\(c.status.rawValue))\n" }
        }
        let system = """
        Sen \(brand.name) markası için bir bilgi derleyicisisin. Yalnızca verilen yeni kaynağı ve mevcut sayfaları kullan.
        Kurallar:
        \(rules)

        Çıktı: güncellenmesi veya oluşturulması gereken sayfaların TAM yeni hâli. Değişmesi gerekmeyen sayfayı listeleme.
        - Mevcut sayfayı güncelliyorsan sayfa_id alanına onun kimliğini yaz, yeni sayfa için boş bırak.
        - Mevcut sayfadaki geçerli iddiaları koru (kendi kaynak_id'leriyle); yeni kaynakla çelişenleri "conflict", tarihi geçenleri "stale" yap ve not alanında nedenini yaz.
        - Yeni iddialar için kaynak_id olarak yalnızca yeni kaynağın kimliğini (\(source.id)) kullan.
        - baglantilar: ilişkili mevcut sayfaların sayfa_id değerleri.
        - Kaynakta olmayan bilgiyi ekleme. Değişiklik gerekmiyorsa boş liste döndür.
        """
        let body = source.body.count > 60_000 ? String(source.body.prefix(60_000)) : source.body
        let user = """
        # Mevcut bilgi sayfaları
        \(index.isEmpty ? "(henüz sayfa yok)" : index)

        # Yeni kaynak
        kaynak_id=\(source.id)
        başlık: \(source.title)
        tür: \(source.kind.rawValue)
        tarih: \(ISO8601DateFormatter().string(from: source.capturedAt))

        \(body.isEmpty ? "(bu dosyadan metin çıkarılamadı; yalnızca başlığa dayanma, boş liste döndür)" : body)
        """
        return (system, user)
    }

    public func propose(sourceId: String, provider: StructuredProvider) async throws -> Outcome {
        let source = try store.source(sourceId)
        let brand = try store.brand(source.brandId)
        guard brand.allows(provider.kind) else {
            throw MarkaError.providerNotAllowed(brand: brand.name, provider: provider.kind.displayName)
        }
        let (system, user) = try prompt(brandId: brand.id, source: source)
        var (json, usage) = try await provider.completeJSON(system: system, user: user, schema: Self.schema)
        usage.brandId = brand.id
        usage.purpose = "wiki"
        let u = usage
        try store.write { db in try u.insert(db) }
        var outcome = try apply(json: json, brandId: brand.id, usage: usage)
        outcome.raw = json
        return outcome
    }

    /// Model çıktısını doğrulayıp öneri olarak kaydeder. Geçersiz sayfa (başka marka kaynağı, kaynaksız iddia) reddedilir.
    public func apply(json: JSONValue, brandId: String, usage: UsageEntry) throws -> Outcome {
        var revisions: [WikiRevision] = []
        var rejected: [String] = []
        for page in json["sayfalar"]?.array ?? [] {
            let title = page["baslik"]?.string ?? ""
            do {
                guard let kind = WikiPageKind(rawValue: page["tur"]?.string ?? "") else { throw MarkaError.validation(L("Geçersiz sayfa türü.")) }
                let claims = (page["iddialar"]?.array ?? []).map {
                    WikiClaimInput(text: $0["metin"]?.string ?? "", sourceId: ($0["kaynak_id"]?.string).flatMap { $0.isEmpty ? nil : $0 },
                                   status: ClaimStatus(rawValue: $0["durum"]?.string ?? "") ?? .current, flagNote: $0["not"]?.string ?? "")
                }
                let pageId = (page["sayfa_id"]?.string).flatMap { $0.isEmpty ? nil : $0 }
                let revision = try store.writeWikiRevision(brandId: brandId, pageId: pageId, kind: kind, title: title,
                                                           body: page["govde"]?.string ?? "", claims: claims,
                                                           links: page["baglantilar"]?.array?.compactMap(\.string) ?? [],
                                                           note: L("Kaynaktan derlendi"), actor: .ai)
                try store.write { db in
                    try AIProposal(sessionId: nil, brandId: brandId, kind: .wikiRevision, summary: LF("Bilgi sayfası: %@", title),
                                   payloadJSON: "{}", resultEntityId: revision.id).insert(db)
                }
                revisions.append(revision)
            } catch {
                rejected.append("\(title): \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
            }
        }
        return Outcome(proposedRevisions: revisions, rejected: rejected, usage: usage)
    }
}

/// Rapor özeti için sağlayıcı seçimi (D5). Anthropic'e izin verilmiş ama anahtar yoksa sebep "izin yok" değil
/// "anahtar eklenmemiş"tir; Codex'e de izin varsa Codex kullanılır.
public enum SummaryProviderChoice: Equatable, Sendable {
    case anthropic, codex, missingAnthropicKey, notAllowed

    public static func choose(allowsAnthropic: Bool, hasAnthropicKey: Bool, allowsCodex: Bool) -> SummaryProviderChoice {
        if allowsAnthropic && hasAnthropicKey { return .anthropic }
        if allowsCodex { return .codex }
        return allowsAnthropic ? .missingAnthropicKey : .notAllowed
    }

    public var isAvailable: Bool { self == .anthropic || self == .codex }

    /// Kullanılamıyorsa kullanıcıya gösterilecek sebep (hata ve düğme yardım metni).
    public var unavailableReason: String? {
        switch self {
        case .anthropic, .codex: nil
        case .missingAnthropicKey: L("Claude API anahtarı eklenmemiş.")
        case .notAllowed: L("Bu markanın verisinin hiçbir AI sağlayıcısına gönderilmesine izin verilmemiş.")
        }
    }

    /// Düğmenin yardım metni: sebep + nereden düzeltileceği.
    public var help: String {
        switch self {
        case .anthropic, .codex: L("Özet yalnızca rapor maddelerine dayanan cümlelerden oluşur.")
        case .missingAnthropicKey: L("Claude API anahtarı eklenmemiş. Ayarlar › Genel bölümünden ekleyebilirsin.")
        case .notAllowed: L("Bu markanın verisinin hiçbir AI sağlayıcısına gönderilmesine izin verilmemiş. Marka sekmesindeki “AI izinleri” kartından izin verebilirsin.")
        }
    }
}

/// Rapor için AI özet cümleleri: her cümle rapor maddelerine dayanmak zorunda.
public struct ReportSummarizer: Sendable {
    public init() {}

    static var schema: JSONValue {
        ["type": "object", "additionalProperties": false, "required": ["cumleler"],
         "properties": ["cumleler": ["type": "array", "items": [
            "type": "object", "additionalProperties": false, "required": ["metin", "madde_idleri"],
            "properties": ["metin": ["type": "string"], "madde_idleri": ["type": "array", "items": ["type": "string"]]]]]]]
    }

    /// Rapor içeriği markanın verisidir: sağlayıcıya gitmeden önce markanın o sağlayıcıya izni çekirdekte denetlenir
    /// (arayüzdeki denetime güvenilmez).
    public func summarize(content: ReportContent, brand: Brand, provider: StructuredProvider) async throws
        -> (kept: [ReportSummarySentence], dropped: Int, usage: UsageEntry) {
        guard brand.allows(provider.kind) else {
            throw MarkaError.providerNotAllowed(brand: brand.name, provider: provider.kind.displayName)
        }
        return try await send(content: content, provider: provider)
    }

    private func send(content: ReportContent, provider: StructuredProvider) async throws -> (kept: [ReportSummarySentence], dropped: Int, usage: UsageEntry) {
        var lines = ""
        for section in content.sections where !section.items.isEmpty {
            lines += "\n## \(ReportSectionTitles.title(section.kind))\n"
            for item in section.items { lines += "- [madde_id=\(item.id)] \(item.text)\n" }
        }
        let system = """
        Müşteriye gidecek bir danışmanlık raporu için 2-4 cümlelik kısa özet yaz.
        - Yalnızca verilen maddelerdeki bilgiyi kullan; yeni bilgi, yorum, övgü veya tahmin ekleme.
        - Her cümle için dayandığı madde kimliklerini madde_idleri alanına yaz. Dayanağı olmayan cümle yazma.
        - Profesyonel, sade Türkçe.
        """
        let (json, usage) = try await provider.completeJSON(system: system, user: "# \(content.title)\n\(lines)", schema: Self.schema)
        let sentences = (json["cumleler"]?.array ?? []).map {
            ReportSummarySentence(text: $0["metin"]?.string ?? "", itemIds: $0["madde_idleri"]?.array?.compactMap(\.string) ?? [])
        }
        let (kept, dropped) = ReportBuilder.validatedSummary(sentences, content: content)
        return (kept, dropped.count, usage)
    }
}
