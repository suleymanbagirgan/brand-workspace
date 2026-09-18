import Foundation
import GRDB

/// Rapor ekranının dönem seçimi (0.2.1): dört sabit dönem; ayrı "içeren tarih" seçimi yok.
public enum ReportRange: String, CaseIterable, Sendable, Identifiable {
    case thisWeek, lastWeek, thisMonth, lastMonth
    public var id: String { rawValue }

    public var period: ReportPeriod {
        switch self {
        case .thisWeek, .lastWeek: .weekly
        case .thisMonth, .lastMonth: .monthly
        }
    }

    /// Dönemin aralığı (hafta pazartesi başlar; `StatusService.turkishCalendar`).
    public func interval(now: Date, calendar: Calendar = StatusService.turkishCalendar) -> DateInterval {
        let component: Calendar.Component = period == .weekly ? .weekOfYear : .month
        let current = calendar.dateInterval(of: component, for: now)!
        switch self {
        case .thisWeek, .thisMonth: return current
        case .lastWeek, .lastMonth:
            return calendar.dateInterval(of: component, for: current.start.addingTimeInterval(-1))!
        }
    }
}

/// Rapor ekranının gösterdiği şey: dönemin canlı önizlemesi (doğrulanmış iş kayıtlarından) ya da kullanıcının düzenlediği /
/// onayladığı kayıtlı sürüm. Salt okunur; yazma mevcut çekirdek yollarıyla yapılır (`createReportDraft`, `saveReportVersion`,
/// `approveReport`, `recordShare`).
public struct ReportPreview: Sendable {
    public var period: ReportPeriod
    public var interval: DateInterval
    /// Kayıtlardan şimdi kurulan içerik.
    public var live: ReportContent
    /// Dönemin raporu (varsa) ve son sürümü.
    public var report: Report?
    public var version: ReportVersion?
    public var saved: ReportContent?
    /// Son sürüm kullanıcının (düzenlenmiş ya da onaylı): önizleme onu gösterir. Değilse canlı içerik gösterilir.
    public var showsSaved: Bool
    /// Kayıtlı sürüm gösterilirken, sürümden sonra doğrulanan ya da artık doğrulanmış olmayan iş kaydı sayısı.
    public var changedWorkLogs: Int
    /// Dönemde doğrulanmamış iş kaydı sayısı (rapora girmez).
    public var unverifiedWorkLogs: Int

    public var content: ReportContent { showsSaved ? (saved ?? live) : live }
    public var isApproved: Bool { showsSaved && version?.approvedAt != nil }
    /// Gösterilen içerik için yeni sürüm gerekmiyorsa son sürüm (PDF/e-posta onu kullanır).
    public var reusableVersion: ReportVersion? {
        guard let version, let saved else { return nil }
        return showsSaved || saved.sameItems(as: live) ? version : nil
    }
    /// Dönemde rapora girecek doğrulanmış iş kaydı yok ve kayıtlı sürüm de yok: "Bu dönemde doğrulanmış iş kaydı yok."
    public var isEmpty: Bool { !showsSaved && (live.section(.completedWork)?.items.isEmpty ?? true) }
}

extension ReportVersion {
    /// Sürüm kayıtlardan kendiliğinden mi oluştu (`createReportDraft`: ilk PDF/e-posta anı, eski "taslak oluştur", plan)?
    /// Onaylı ya da elle düzenlenmiş sürüm kullanıcınındır.
    public func isFromRecords(content: ReportContent) -> Bool {
        let fromRecordsNotes: Set<String> = ["Kayıtlardan oluşturuldu", L("Kayıtlardan oluşturuldu")]
        return approvedAt == nil && fromRecordsNotes.contains(note) && !content.isCustomized
    }
}

extension ReportContent {
    /// Kullanıcı eli değmiş içerik: giriş notu, özet ya da düzenlenmiş madde.
    public var isCustomized: Bool {
        !intro.trimmed.isEmpty || !summary.isEmpty || sections.contains { $0.items.contains(where: \.edited) }
    }

    /// Madde kimliklerinden bağımsız karşılaştırma (her kurulumda kimlikler yeniden üretilir).
    public func sameItems(as other: ReportContent) -> Bool {
        func key(_ c: ReportContent) -> [String] {
            [c.title, c.intro.trimmed, String(c.totalSeconds)] + c.summary.map(\.text)
                + c.sections.flatMap { s in [s.kind.rawValue] + s.items.map { i in i.text + "|" + i.refs.map { $0.kind.rawValue + ":" + $0.id }.joined(separator: ",") } }
        }
        return key(self) == key(other)
    }

    /// Sunum için: boş bölümler (ve süre yoksa "Harcanan süre") atılır. Maddeler, özet ve dayanaklar aynen kalır.
    public var withoutEmptySections: ReportContent {
        var c = self
        c.sections = sections.filter { !$0.items.isEmpty && ($0.kind != .timeSpent || totalSeconds > 0) }
        return c
    }

    /// Doğrulanmış iş kaydı kimlikleri ("Yapılan işler" maddelerinin dayanakları).
    var workLogIds: Set<String> {
        Set((section(.completedWork)?.items ?? []).flatMap(\.refs).filter { $0.kind == .workLog }.map(\.id))
    }
}

extension Store {
    /// Dönemin raporu (marka + dönem türü + başlangıç).
    public func report(brandId: String, period: ReportPeriod, start: Date) throws -> Report? {
        try read { db in
            try Report.filter(Column("brandId") == brandId && Column("period") == period.rawValue && Column("periodStart") == start).fetchOne(db)
        }
    }

    /// Dönemde doğrulanmamış (taslak) iş kaydı sayısı. Geri çekilenler sayılmaz.
    public func unverifiedWorkLogCount(brandId: String, interval: DateInterval) throws -> Int {
        try read { db in
            try WorkLog.filter(Column("brandId") == brandId && Column("status") == WorkLogStatus.draft.rawValue
                               && Column("occurredAt") >= interval.start && Column("occurredAt") < interval.end).fetchCount(db)
        }
    }

    /// Rapor ekranının önizlemesi. Salt okunur.
    public func reportPreview(brandId: String, period: ReportPeriod, interval: DateInterval, now: Date = Date(),
                              calendar: Calendar = StatusService.turkishCalendar) throws -> ReportPreview {
        let live = try ReportBuilder(store: self, calendar: calendar).build(brandId: brandId, period: interval, now: now)
        let report = try report(brandId: brandId, period: period, start: interval.start)
        var version: ReportVersion?
        var saved: ReportContent?
        if let vid = report?.currentVersionId {
            version = try read { db in try ReportVersion.fetchOne(db, key: vid) }
            saved = try version.map { try content(of: $0) }
        }
        let showsSaved = version.map { v in !v.isFromRecords(content: saved!) } ?? false
        var changed = 0
        if showsSaved, let version, let saved {
            let liveIds = live.workLogIds
            let savedIds = saved.workLogIds
            let reverified = try read { db in
                try WorkLog.filter(liveIds.contains(Column("id")) && Column("verifiedAt") > version.createdAt).fetchCount(db)
            }
            changed = reverified + savedIds.subtracting(liveIds).count
        }
        return ReportPreview(period: period, interval: interval, live: live, report: report, version: version, saved: saved,
                             showsSaved: showsSaved, changedWorkLogs: changed,
                             unverifiedWorkLogs: try unverifiedWorkLogCount(brandId: brandId, interval: interval))
    }
}
