import Foundation
import GRDB

/// Beta değerlendirme ölçümleri. Yalnızca yerel kayıtlardan hesaplanır; hiçbir yere gönderilmez.
public struct BetaMetrics: Sendable, Hashable, Codable {
    public var firstLaunchAt: Date?
    /// İlk açılıştan kullanıcının eklediği ilk kaynağa kadar geçen dakika.
    public var setupMinutes: Double?
    /// Onaylanan raporlarda ilk taslaktan onaya kadar geçen süre (dakika, medyan).
    public var medianReportPrepMinutes: Double?
    public var approvedReports: Int
    public var proposalsApplied: Int
    public var proposalsRejected: Int
    public var proposalsReverted: Int
    /// Kullanıcının çelişkili/eskimiş olarak işaretlediği iddialar (kaynak hatası göstergesi).
    public var claimsFlaggedByUser: Int
    /// Rapor sürümlerinde kullanıcının metnini değiştirdiği maddeler.
    public var reportItemsEdited: Int
    /// Son 14 günde kullanıcı eylemi olan gün sayısı.
    public var activeDaysLast14: Int
    public var activeDaysTotal: Int

    public static let firstLaunchKey = "metrics.firstLaunchAt"

    public static func compute(store: Store, now: Date = Date()) throws -> BetaMetrics {
        try store.read { db in
            let iso = ISO8601DateFormatter()
            let firstLaunch = try String.fetchOne(db, sql: "SELECT value FROM setting WHERE key = ?", arguments: [firstLaunchKey]).flatMap { iso.date(from: $0) }
            let firstSource = try Date.fetchOne(db, sql: "SELECT MIN(createdAt) FROM source WHERE actor = 'user'")
            var setup: Double?
            if let a = firstLaunch, let b = firstSource, b >= a { setup = b.timeIntervalSince(a) / 60 }

            var prep: [Double] = []
            for report in try Report.filter(Column("status") == ReportStatus.approved.rawValue).fetchAll(db) {
                let versions = try ReportVersion.filter(Column("reportId") == report.id).order(Column("number")).fetchAll(db)
                if let first = versions.first, let approved = versions.last(where: { $0.approvedAt != nil })?.approvedAt {
                    prep.append(approved.timeIntervalSince(first.createdAt) / 60)
                }
            }
            prep.sort()
            let median = prep.isEmpty ? nil : prep[prep.count / 2]

            func proposals(_ s: ProposalStatus) throws -> Int { try AIProposal.filter(Column("status") == s.rawValue).fetchCount(db) }
            let flagged = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM auditEvent WHERE entity = 'wikiClaim' AND action = 'flag' AND actor = 'user' AND afterJSON NOT LIKE '%\"status\":\"current\"%'") ?? 0
            var edited = 0
            for v in try ReportVersion.fetchAll(db) {
                if let c = try? Store.decoder.decode(ReportContent.self, from: Data(v.contentJSON.utf8)) {
                    edited = max(edited, 0) + c.sections.flatMap(\.items).filter(\.edited).count
                }
            }
            let days = try Date.fetchAll(db, sql: "SELECT at FROM auditEvent WHERE actor = 'user'")
            let cal = Calendar.current
            let distinct = Set(days.map { cal.startOfDay(for: $0) })
            let cutoff = cal.startOfDay(for: now.addingTimeInterval(-13 * 86400))
            return BetaMetrics(firstLaunchAt: firstLaunch, setupMinutes: setup, medianReportPrepMinutes: median, approvedReports: prep.count,
                               proposalsApplied: try proposals(.applied), proposalsRejected: try proposals(.rejected),
                               proposalsReverted: try proposals(.reverted), claimsFlaggedByUser: flagged, reportItemsEdited: edited,
                               activeDaysLast14: distinct.filter { $0 >= cutoff }.count, activeDaysTotal: distinct.count)
        }
    }

    /// Kullanıcının isterse kopyalayıp paylaşacağı özet (marka adı veya içerik içermez).
    public var shareableSummary: String {
        func f(_ v: Double?) -> String { v.map { String(format: "%.1f", $0) } ?? "—" }
        return """
        Marka Çalışma Alanı beta ölçümleri (içerik içermez)
        ilk_kurulum_dk: \(f(setupMinutes))
        rapor_hazirlama_medyan_dk: \(f(medianReportPrepMinutes)) (onaylı rapor: \(approvedReports))
        ai_oneri_uygulanan/reddedilen/geri_alinan: \(proposalsApplied)/\(proposalsRejected)/\(proposalsReverted)
        kullanici_isaretli_iddia: \(claimsFlaggedByUser)
        raporda_duzeltilen_madde: \(reportItemsEdited)
        aktif_gun_son14: \(activeDaysLast14) (toplam: \(activeDaysTotal))
        """
    }
}
