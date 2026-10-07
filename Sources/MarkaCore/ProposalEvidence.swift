import Foundation
import GRDB

// E-22 · Onay kartında dayanak ("neden bu öneri"). Önerinin yükünden ve (dış ajan zarfıysa) zarfın denetim kaydından
// dayandığı kaynak ve gözlem kimliklerini çıkarır; yalnız önerinin markasına ait olanları çip olarak döndürür. Çip yalnız
// kimlik ve başlık taşır; içerik önizlemesi yoktur. Başka markanın kimliği hiçbir yoldan çipe dönüşmez (kural 1).

/// Bir önerinin dayanakları: çipler ve (varsa) dış ajanın gerekçesi. Çip yoksa öneri "dayanak yok" diye işaretlenir.
public struct ProposalEvidence: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable { case source, observation }

    /// Yükten çıkan kimlik. `kind == nil`: zarfın `dayanak[]` kimliği (kaynak ya da gözlem olabilir; çözümde belli olur).
    public struct Reference: Sendable, Hashable {
        public var kind: Kind?
        public var id: String
        public init(_ kind: Kind?, _ id: String) { self.kind = kind; self.id = id }
    }

    public struct Chip: Sendable, Hashable, Identifiable {
        public var kind: Kind
        public var id: String
        /// Kaynak başlığı ya da gözlem cümlesi; tek satır, `maxTitle` karakterle kırpılmış.
        public var title: String
    }

    /// Çip başlığı bu kadar karakterle kırpılır (önizleme değil, etiket).
    public static let maxTitle = 48

    public var chips: [Chip]
    /// Dış ajanın gerekçesi (zarf şema 2, tek satır). Gerekçe dayanak sayılmaz.
    public var rationale: String?
    public var hasEvidence: Bool { !chips.isEmpty }

    public init(chips: [Chip] = [], rationale: String? = nil) { self.chips = chips; self.rationale = rationale }

    /// Öneri yükünden dayanak kimlikleri (saf). Dayanak taşımayan türler boş döner.
    public static func references(kind: ProposalKind, payloadJSON: String) -> [Reference] {
        let data = Data(payloadJSON.utf8)
        func decode<T: Decodable>(_ t: T.Type) -> T? { try? JSONDecoder().decode(t, from: data) }
        switch kind {
        case .createWorkLog:
            guard let x = decode(ProposalPayload.CreateWorkLog.self) else { return [] }
            return (x.inputSourceIds + x.outputSourceIds).map { Reference(.source, $0) }
        case .createOutput:
            return (decode(ProposalPayload.CreateOutput.self)?.inputSourceIds ?? []).map { Reference(.source, $0) }
        case .createBrandRecord:
            return (decode(ProposalPayload.CreateBrandRecord.self)?.sourceId).map { [Reference(.source, $0)] } ?? []
        case .createObservation:
            guard let x = decode(ProposalPayload.CreateObservation.self) else { return [] }
            return x.evidenceSourceIds.map { Reference(.source, $0) } + (x.supersedesId.map { [Reference(.observation, $0)] } ?? [])
        // createTask, completeTask, updateTask, createNote, createTeamMember, wikiRevision ve sonradan eklenen türler:
        // yükte kaynak/gözlem kimliği yok. Yeni tür kimlik taşıyorsa buraya eklenir ve `OneriDayanagiTests`'e yazılır.
        default:
            return []
        }
    }

    /// Kimlikleri markanın kendi kaynak/gözlem başlıklarıyla çözer (saf). Haritada olmayan kimlik (başka markanın ya da
    /// silinmiş kaydın) atılır. Sıra korunur, tekrar atılır.
    public static func resolve(_ refs: [Reference], sources: [String: String], observations: [String: String],
                               rationale: String? = nil) -> ProposalEvidence {
        var seen = Set<String>()
        var chips: [Chip] = []
        for r in refs {
            let id = r.id.trimmed
            guard !id.isEmpty, seen.insert(id).inserted else { continue }
            if r.kind != .observation, let t = sources[id] {
                chips.append(Chip(kind: .source, id: id, title: label(t)))
            } else if r.kind != .source, let t = observations[id] {
                chips.append(Chip(kind: .observation, id: id, title: label(t)))
            }
        }
        return ProposalEvidence(chips: chips, rationale: rationale)
    }

    static func label(_ s: String) -> String { ProposalEnvelope.singleLine(s, max: maxTitle) }
}

/// Zarf denetim kaydının (`EnvelopeAuditView`) okunan hâli. `schema` zorunlu: terminal dosyasının kaydı buna çözülmez.
struct EnvelopeAuditRecord: Decodable {
    var fileName: String
    var itemCount: Int
    var schema: Int
    var producer: String?
    var rationale: String?
    var evidence: [String]
}

extension Store {
    /// Önerinin dayanakları, yalnız önerinin markası içinden okunur.
    public func proposalEvidence(_ p: AIProposal) throws -> ProposalEvidence {
        try read { db in
            var refs = ProposalEvidence.references(kind: p.kind, payloadJSON: p.payloadJSON)
            var rationale: String?
            if p.origin == .external, let env = try envelopeAudit(db, for: p) {
                rationale = env.rationale
                refs += env.evidence.map { ProposalEvidence.Reference(nil, $0) }
            }
            let ids = Array(Set(refs.map(\.id)))
            guard !ids.isEmpty else { return ProposalEvidence(rationale: rationale) }
            let sources = try Source.filter(Column("brandId") == p.brandId && ids.contains(Column("id"))).fetchAll(db)
            let observations = try BrandObservation.filter(Column("brandId") == p.brandId && ids.contains(Column("id"))).fetchAll(db)
            return ProposalEvidence.resolve(refs, sources: Dictionary(sources.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a }),
                                            observations: Dictionary(observations.map { ($0.id, $0.statement) }, uniquingKeysWith: { a, _ in a }),
                                            rationale: rationale)
        }
    }

    /// Dış ajan önerisinin geldiği zarfın denetim kaydı. Öneri dosya kimliğini taşımaz (şema değişmedi, migration yok);
    /// bu yüzden aynı markada öneriden hemen önce işlenmiş dosyalar sırayla denenir: kayıt zarf kaydı olmalı, rozet etiketi
    /// (`uretici` ya da dosya adı) önerinin `originRef`'iyle aynı olmalı ve öneri dosyadan sonraki öğe sayısı kadar ms içinde
    /// (artı 5 sn pay) oluşmuş olmalı. Hiçbiri tutmazsa gerekçe gösterilmez (yanlış gerekçe göstermektense hiç).
    func envelopeAudit(_ db: Database, for p: AIProposal) throws -> EnvelopeAuditRecord? {
        let files = try SuggestionFile.filter(Column("brandId") == p.brandId && Column("processedAt") <= p.createdAt)
            .order(Column("processedAt").desc).limit(5).fetchAll(db)
        for f in files {
            guard let e = try AuditEvent.filter(Column("brandId") == p.brandId && Column("entity") == "suggestionFile"
                                                && Column("entityId") == f.id && Column("action") == "ingest").fetchOne(db),
                  let json = e.afterJSON,
                  let v = try? JSONDecoder().decode(EnvelopeAuditRecord.self, from: Data(json.utf8)) else { continue }
            guard (v.producer ?? v.fileName) == p.originRef,
                  p.createdAt.timeIntervalSince(f.processedAt) <= Double(v.itemCount) / 1000 + 5 else { continue }
            return v
        }
        return nil
    }
}
