import Foundation
import GRDB

/// Finans kaydının türü: *ödeme* (danışmanlık ücreti planındaki bir satır) ya da *bütçe* (çalışma kalemi için planlanan tutar).
public enum FinanceKind: String, Codable, Sendable, CaseIterable { case payment, budget }

/// Ödeme satırının durumu.
public enum PaymentStatus: String, Codable, Sendable, CaseIterable {
    case planned, pending, collected
}

/// Marka başına finans kaydı (0.3.0). Tutar kuruş cinsinden tam sayı (₺); `nil` = "henüz belirlenmedi". Bu kayıtlar elle tutulur;
/// uygulama muhasebe, banka bağlantısı ya da otomatik tahsilat yapmaz.
public struct FinanceEntry: Codable, Sendable, Hashable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "financeEntry"
    public var id: String
    public var brandId: String
    public var kind: FinanceKind
    public var title: String
    public var amountMinor: Int64?
    /// `yyyy-MM-dd` (ödemede vade/tahsilat günü).
    public var date: String?
    /// Yalnız ödemede.
    public var status: PaymentStatus?
    public var note: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = newID(), brandId: String, kind: FinanceKind, title: String, amountMinor: Int64? = nil,
                date: String? = nil, status: PaymentStatus? = nil, note: String = "",
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id; self.brandId = brandId; self.kind = kind; self.title = title; self.amountMinor = amountMinor
        self.date = date; self.status = status ?? (kind == .payment ? .planned : nil); self.note = note
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public enum Money {
    /// "45.000", "45000", "45.000,50", "12,5", "₺ 1.250" gibi Türkçe yazımı kuruşa çevirir. Negatif ya da çözülemeyen → `nil`.
    public static func parseMinor(_ text: String) -> Int64? {
        var t = text.replacingOccurrences(of: "₺", with: "").replacingOccurrences(of: "TL", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "")
        guard !t.isEmpty, !t.hasPrefix("-") else { return nil }
        if t.contains(",") {
            t = t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        } else if t.range(of: #"^\d{1,3}(\.\d{3})+$"#, options: .regularExpression) != nil {
            t = t.replacingOccurrences(of: ".", with: "")
        }
        guard t.range(of: #"^\d+(\.\d{1,2})?$"#, options: .regularExpression) != nil, let d = Decimal(string: t, locale: Locale(identifier: "en_US")) else { return nil }
        let minor = NSDecimalNumber(decimal: d * 100).rounding(accordingToBehavior: nil).int64Value
        return minor
    }

    /// 4500000 → "₺45.000"; kuruşlu tutarda iki hane.
    public static func format(minor: Int64) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.numberStyle = .currency
        f.currencyCode = "TRY"
        f.currencySymbol = "₺"
        f.minimumFractionDigits = minor % 100 == 0 ? 0 : 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: Double(minor) / 100)) ?? "₺\(minor / 100)"
    }
}
