import Foundation
import GRDB

/// Bir markada onay bekleyen her şey, tek yerde (0.2.1 onay bandı): terminal önerileri, uygulama içi öneriler ve bilgi
/// güncellemeleri. Salt okunur; karar mevcut yazma yolarıyla verilir (`decideSuggestions`, `applyProposal`/`rejectProposal`,
/// `approveRevision`/`rejectRevision`).
public struct PendingApprovals: Sendable, Hashable {
    /// Terminalden gelen (`oneriler/*.json`) bekleyen öneriler, dosya sırasıyla.
    public var suggestions: [AIProposal]
    /// Uygulama içinde oluşmuş (ör. eski sohbet) bekleyen öneriler; bilgi önerileri hariç.
    public var proposals: [AIProposal]
    /// Onay bekleyen bilgi sayfası sürümleri.
    public var revisions: [WikiRevision]

    public init(suggestions: [AIProposal] = [], proposals: [AIProposal] = [], revisions: [WikiRevision] = []) {
        self.suggestions = suggestions; self.proposals = proposals; self.revisions = revisions
    }

    public var count: Int { suggestions.count + proposals.count + revisions.count }
    public var isEmpty: Bool { count == 0 }
}

extension Store {
    /// Markanın onay bekleyenleri. Bilgi önerisinin `aiProposal` satırı ayrıca sayılmaz; sürümün kendisi sayılır.
    public func pendingApprovals(brandId: String) throws -> PendingApprovals {
        try read { db in
            let pending = try AIProposal.filter(Column("brandId") == brandId && Column("status") == ProposalStatus.pending.rawValue
                                                && Column("kind") != ProposalKind.wikiRevision.rawValue)
                .order(Column("createdAt")).fetchAll(db)
            let revisions = try WikiRevision.filter(Column("brandId") == brandId && Column("state") == RevisionState.proposed.rawValue)
                .order(Column("createdAt")).fetchAll(db)
            return PendingApprovals(suggestions: pending.filter { $0.origin == .terminal },
                                    proposals: pending.filter { $0.origin != .terminal },
                                    revisions: revisions)
        }
    }

    /// Kenar çubuğu için: marka kimliği → onay bekleyen sayısı (yalnızca sıfırdan büyükler). Tek okumada iki gruplu sorgu.
    public func pendingApprovalCounts() throws -> [String: Int] {
        try read { db in
            var out: [String: Int] = [:]
            let proposals = try Row.fetchAll(db, sql: """
                SELECT brandId, COUNT(*) AS n FROM aiProposal WHERE status = ? AND kind != ? GROUP BY brandId
                """, arguments: [ProposalStatus.pending.rawValue, ProposalKind.wikiRevision.rawValue])
            let revisions = try Row.fetchAll(db, sql: """
                SELECT brandId, COUNT(*) AS n FROM wikiRevision WHERE state = ? GROUP BY brandId
                """, arguments: [RevisionState.proposed.rawValue])
            for row in proposals + revisions {
                let id: String = row["brandId"], n: Int = row["n"]
                out[id, default: 0] += n
            }
            return out
        }
    }

    /// Son onaylanan (uygulanmış) öneriler, en yeni kararı üstte; bilgi önerileri hariç (geri alınamaz). "Geri al" için.
    public func recentlyAppliedProposals(brandId: String, limit: Int = 20) throws -> [AIProposal] {
        try read { db in
            try AIProposal.filter(Column("brandId") == brandId && Column("status") == ProposalStatus.applied.rawValue
                                  && Column("kind") != ProposalKind.wikiRevision.rawValue)
                .order(Column("decidedAt").desc, Column("createdAt").desc).limit(limit).fetchAll(db)
        }
    }
}

/// Marka ekranının üç bölümü (plan §4): Akış (ne yapıldı), Yapılacaklar (ne bekliyor), Rapor (müşteriye ne gidecek).
public enum BrandSection: String, CaseIterable, Sendable, Identifiable {
    case flow, todo, report
    public var id: String { rawValue }

    /// Menü kısayolu: ⌘1 Akış, ⌘2 Yapılacaklar, ⌘3 Rapor (⌘0 Bugün).
    public var shortcutDigit: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }

    /// Bir kaydın "bölümde aç" hedefi. Bilgi sayfası artık bir bölümde görünmez (`nil`).
    public static func section(for kind: RecordRef.Kind) -> BrandSection? {
        switch kind {
        case .task, .timeEntry: .todo
        case .source, .workLog: .flow
        case .brandRecord: .todo
        case .report: .report
        case .wikiPage: nil
        }
    }
}
