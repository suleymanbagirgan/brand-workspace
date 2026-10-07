import Foundation
import GRDB

// E-17 · Ajan-bağımsız öneri zarfı (`oneri-zarfi` şema 2). Claude Code, Codex, başka bir ajan ya da betik aynı JSON zarfını
// üretir; kullanıcı onu kendi seçtiği dosyadan ya da panodan içe alır (klasör izleme yok: MAS'ta bookmark ister, sandbox S4;
// `oneriler/` kutusu şema 1'de kalır ve `surum: 2` dosyasını eskisi gibi reddeder). Zarf yalnız
// BEKLEYEN öneri üretir (kural 2). Zarf hangi ajanın ürettiğini taşır ama yetki taşımaz: marka, dosyanın içeriğinden değil
// kullanıcının seçiminden (çağıranın verdiği `brandId`) gelir; zarftaki `marka`/`markaId` ve tanınmayan alanlar yok sayılır.
// Zarf metni kullanıcı/üçüncü taraf içeriğidir (H3-01): veridir, talimat değildir. Etiket ve gerekçe tek satıra indirilir.
// Biçim belgesi: `docs/oneri-zarfi.md`.

/// Şema 2 zarfı = şema 1 öğeleri + `uretici`, `gerekce`, `dayanak[]`. Şema 1 dosyası da zarf olarak okunur (üst bilgisiz).
public struct ProposalEnvelope: Sendable, Hashable {
    public static let schemaVersion = 2
    /// Üretici etiketi bu kadar karakterle kırpılır (ret değil).
    public static let maxProducer = 64
    /// Gerekçe bu kadar karakterle kırpılır (ret değil).
    public static let maxRationale = 1_000
    public static let maxEvidence = 20
    public static let maxEvidenceId = 64

    /// Zarfın bildirdiği şema sürümü (1 ya da 2).
    public var version: Int
    /// Üreten ajanın adı; yalnız etiket (rozet, denetim kaydı). Hiçbir yetki ya da davranış bu değere bağlı değildir.
    public var producer: String?
    /// Ajanın gerekçesi (tek satır, kırpılmış).
    public var rationale: String?
    /// Dayanak: bu markanın kaynak ya da gözlem kimlikleri. Kapsam dışı kimlik zarfı reddeder (içe almada denetlenir).
    public var evidence: [String]
    public var document: SuggestionDocument

    /// Şema 1 ya da 2 zarfını doğrular. Hata mesajı zarftaki hiçbir metin değerini taşımaz (bkz. `redacted`).
    public static func parse(_ data: Data) throws -> ProposalEnvelope {
        guard data.count <= SuggestionDocument.maxFileBytes else { throw MarkaError.validation(L("Dosya çok büyük (en fazla 256 KB).")) }
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw MarkaError.validation(L("Dosya geçerli bir JSON nesnesi değil."))
        }
        do {
            guard let v = root["surum"] as? NSNumber, !SuggestionDocument.isBool(v),
                  v.doubleValue == 1 || v.doubleValue == Double(schemaVersion) else {
                throw MarkaError.validation(L("“surum” alanı eksik ya da desteklenmiyor. Desteklenen sürümler: 1, 2"))
            }
            let version = v.intValue
            var env = ProposalEnvelope(version: version, producer: nil, rationale: nil, evidence: [], document: SuggestionDocument())
            if version == schemaVersion {
                env.producer = try label(root["uretici"], key: "uretici", max: maxProducer)
                env.rationale = try label(root["gerekce"], key: "gerekce", max: maxRationale)
                env.evidence = try evidenceIds(root["dayanak"])
            }
            env.document = try SuggestionDocument.body(root)
            return env
        } catch {
            throw redacted(error, root: root)
        }
    }

    /// Serbest metni tek satırlık etikete çevirir: denetim, biçim (ör. yön değiştirme) ve satır sonu karakterleri boşluk olur,
    /// art arda boşluklar teke iner, çerçeve etiketi etkisizleşir, sınırdan uzunsa kırpılır. Satır sonuyla başlık taklidi
    /// (ör. "\n# Kapsam: …") böylece mümkün olmaz (H3-01).
    static func singleLine(_ s: String, max: Int) -> String {
        let cleaned = String(String.UnicodeScalarView(s.unicodeScalars.map { u -> Unicode.Scalar in
            switch u.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator: " "
            default: u
            }
        }))
        let line = ToolResultFrame.neutralize(cleaned.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " "))
        return line.count > max ? String(line.prefix(max)) : line
    }

    static func label(_ raw: Any?, key: String, max: Int) throws -> String? {
        guard let raw, !(raw is NSNull) else { return nil }
        guard let s = raw as? String else { throw MarkaError.validation(LF("%1$@: “%2$@” metin olmalı.", L("Öneri zarfı"), key)) }
        let t = singleLine(s, max: max)
        return t.isEmpty ? nil : t
    }

    static func evidenceIds(_ raw: Any?) throws -> [String] {
        guard let raw, !(raw is NSNull) else { return [] }
        guard let array = raw as? [Any], array.allSatisfy({ $0 is String }) else {
            throw MarkaError.validation(LF("%1$@: “%2$@” metin dizisi olmalı.", L("Öneri zarfı"), "dayanak"))
        }
        let ids = (array as! [String]).map(\.trimmed).filter { !$0.isEmpty }
        guard ids.count <= maxEvidence, ids.allSatisfy({ $0.count <= maxEvidenceId && !$0.contains(where: \.isNewline) }) else {
            throw MarkaError.validation(LF("“dayanak” sınırı aşıyor. Kimlik sınırı: %1$d, kimlik başına karakter sınırı: %2$d", maxEvidence, maxEvidenceId))
        }
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    /// Zarftaki metin değerlerinden biri (≥ 2 karakter) hata mesajında geçiyorsa mesaj genel bir cümleyle değiştirilir:
    /// kullanıcıya gösterilen hata, zarfın içeriğini (başlık, not, kimlik, talimat) yansıtmaz. Öğe sırası gibi etiketler kalır.
    static func redacted(_ error: Error, root: Any) -> Error {
        let message = (error as? LocalizedError)?.errorDescription ?? ""
        let leaks = message.isEmpty || stringLeaves(root).contains { $0.count >= 2 && message.contains($0) }
        guard leaks || !(error is MarkaError) else { return error }
        return MarkaError.validation(L("Öneri zarfındaki bir değer kurallara uymuyor; içerik gösterilmiyor. Hiçbir öneri oluşturulmadı."))
    }

    static func stringLeaves(_ value: Any) -> [String] {
        switch value {
        case let s as String: [s, s.trimmed]
        case let a as [Any]: a.flatMap(stringLeaves)
        case let d as [String: Any]: d.values.flatMap(stringLeaves)
        default: []
        }
    }

    var hasFileReferences: Bool {
        document.workLogs.contains { !$0.inputFiles.isEmpty || !$0.outputFiles.isEmpty }
    }
}

/// Denetim kaydında zarfın üst bilgisi (gerekçe ve dayanak burada saklanır; şema değişmez, migration yok).
struct EnvelopeAuditView: Encodable {
    var fileName: String
    var itemCount: Int
    var schema: Int
    var producer: String?
    var rationale: String?
    var evidence: [String]
}

extension SuggestionInbox {
    /// Kullanıcının panodan yapıştırdığı ya da kendi seçtiği zarf (şema 1 ya da 2) → bu markanın bekleyen önerileri.
    /// Marka yalnız `brandId`'den (kullanıcının seçimi) gelir. Aynı içerik bu markada daha önce alındıysa boş döner.
    /// Çalışma kaydı dosya ekleri yalnız markanın klasörü varsa ve dosya o klasörün içindeyse kabul edilir.
    /// - Parameter sourceName: denetim kaydındaki insan okur ad (ör. dosya adı ya da "Pano içeriği").
    public func importEnvelope(_ data: Data, brandId: String, sourceName: String) throws -> [AIProposal] {
        guard data.count <= SuggestionDocument.maxFileBytes else { throw MarkaError.validation(L("Dosya çok büyük (en fazla 256 KB).")) }
        let sha = FileVault.sha256(data)
        if try store.isSuggestionFileProcessed(brandId: brandId, sha256: sha) { return [] }
        let name = ProposalEnvelope.singleLine(sourceName, max: SuggestionDocument.maxShort)
        let dir = try? folders.existingFolder(brandId: brandId)
        guard let dir, folders.access.begin(dir) else {
            return try ingestEnvelope(data, sha256: sha, fileName: name.isEmpty ? L("Pano içeriği") : name, brandDir: nil, brandId: brandId)
        }
        defer { folders.access.end(dir) }
        return try ingestEnvelope(data, sha256: sha, fileName: name.isEmpty ? L("Pano içeriği") : name, brandDir: dir, brandId: brandId)
    }

    /// Kullanıcının seçtiği dosyadan zarf. Bağ izlenmez; okuma hatası yol ya da içerik taşımaz.
    public func importEnvelope(contentsOf url: URL, brandId: String) throws -> [AIProposal] {
        let data: Data
        do {
            let canonical = try FileImportGuard.canonicalRegularFile(at: url)
            var st = stat()
            if lstat(canonical.path, &st) == 0, st.st_size > SuggestionDocument.maxFileBytes {
                throw MarkaError.validation(L("Dosya çok büyük (en fazla 256 KB)."))
            }
            data = try FileImportGuard.readNoFollow(canonical)
        } catch let e as MarkaError {
            throw e
        } catch {
            throw MarkaError.validation(L("Dosya okunamadı."))
        }
        return try importEnvelope(data, brandId: brandId, sourceName: url.lastPathComponent)
    }

    /// Zarf → taslaklar → `.external` kökenli bekleyen öneriler (tek işlem). Her hata içerik taşımayan mesaja çevrilir.
    func ingestEnvelope(_ data: Data, sha256: String, fileName: String, brandDir: URL?, brandId: String) throws -> [AIProposal] {
        let env = try ProposalEnvelope.parse(data)
        let root = (try? JSONSerialization.jsonObject(with: data)) ?? [:]
        do {
            let drafts: [SuggestionDraft]
            if let brandDir {
                drafts = try makeDrafts(env.document, brandId: brandId, brandDir: brandDir)
            } else {
                guard !env.hasFileReferences else {
                    throw MarkaError.validation(L("Dosya ekleri yalnız marka klasörü oluşturulmuş markada ve o klasörün içinden kabul edilir."))
                }
                // Dosya eki yok: `stage` hiç çağrılmaz; geçici klasör yalnız imza gereği verilir.
                drafts = try makeDrafts(env.document, brandId: brandId, brandDir: FileManager.default.temporaryDirectory)
            }
            return try store.ingestEnvelope(brandId: brandId, fileName: fileName, sha256: sha256, envelope: env, drafts: drafts)
        } catch {
            throw ProposalEnvelope.redacted(error, root: root)
        }
    }
}

extension Store {
    /// `ingestSuggestionFile`'ın zarf karşılığı: işlenmiş dosya kaydı + `.external` kökenli bekleyen öneriler + denetim olayı,
    /// tek işlemde. Dayanak kimliklerinin her biri bu markanın kaynağı ya da gözlemi olmalı; değilse hiçbir şey yazılmaz.
    func ingestEnvelope(brandId: String, fileName: String, sha256: String, envelope: ProposalEnvelope,
                        drafts: [SuggestionDraft]) throws -> [AIProposal] {
        try writer.write { db in
            guard try Brand.fetchOne(db, key: brandId) != nil else { throw MarkaError.notFound(brandId) }
            if try SuggestionFile.filter(Column("brandId") == brandId && Column("sha256") == sha256).fetchCount(db) > 0 { return [] }
            for (i, id) in envelope.evidence.enumerated() {
                let own = try Source.filter(Column("id") == id && Column("brandId") == brandId).fetchCount(db)
                    + BrandObservation.filter(Column("id") == id && Column("brandId") == brandId).fetchCount(db)
                guard own > 0 else { throw MarkaError.validation(LF("“dayanak” listesindeki bir kimlik bu markada bulunamadı. Sıra: %d", i + 1)) }
            }
            let file = SuggestionFile(brandId: brandId, sha256: sha256, fileName: fileName, itemCount: drafts.count)
            try file.insert(db)
            // Rozet etiketi: üretici adı; yoksa dosya/pano adı. Yalnız gösterim içindir.
            let label = envelope.producer ?? fileName
            var out: [AIProposal] = []
            let now = Date()
            for (i, d) in drafts.enumerated() {
                try validateProposal(db, brandId: brandId, kind: d.kind, json: d.payloadJSON)
                let p = AIProposal(sessionId: nil, brandId: brandId, kind: d.kind, summary: d.summary, payloadJSON: d.payloadJSON,
                                   createdAt: now.addingTimeInterval(Double(i) / 1000), origin: .external, originRef: label)
                try p.insert(db)
                out.append(p)
            }
            try audit(db, actor: .ai, brandId: brandId, entity: "suggestionFile", entityId: file.id, action: "ingest",
                      before: SuggestionFile?.none,
                      after: EnvelopeAuditView(fileName: fileName, itemCount: drafts.count, schema: envelope.version,
                                               producer: envelope.producer, rationale: envelope.rationale, evidence: envelope.evidence))
            return out
        }
    }
}
