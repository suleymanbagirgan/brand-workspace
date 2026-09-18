import Foundation

/// Arayüz renkleri tek yerde (D8; 0.2.1: tek vurgu + yalnız gecikme için tehlike). Değerler WCAG AA'ya göre seçildi ve
/// `KontrastTests` ile bağlı: metin olarak kullanılan her renk, açık/koyu görünümün yüzeylerinde ve seçili satır zemininde
/// ≥ 4.5:1; dolgulu (birincil) düğmede beyaz yazı ≥ 4.5:1. Yeşil/turuncu durum renkleri yok; durum metinle söylenir.
public enum Palette {
    public struct RGB: Sendable, Hashable, CustomStringConvertible {
        public let r: UInt8, g: UInt8, b: UInt8
        public init(_ hex: UInt32) {
            r = UInt8((hex >> 16) & 0xFF); g = UInt8((hex >> 8) & 0xFF); b = UInt8(hex & 0xFF)
        }
        public var red: Double { Double(r) / 255 }
        public var green: Double { Double(g) / 255 }
        public var blue: Double { Double(b) / 255 }
        public var description: String { String(format: "#%02X%02X%02X", r, g, b) }

        /// WCAG 2.x göreli parlaklık.
        public var relativeLuminance: Double {
            func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
            return 0.2126 * lin(red) + 0.7152 * lin(green) + 0.0722 * lin(blue)
        }

        /// Bu rengin `alpha` opaklıkla `background` üzerine bindirilmiş hâli (ör. rozet zemini).
        public func over(_ background: RGB, alpha: Double) -> RGB {
            func mix(_ f: UInt8, _ b: UInt8) -> UInt32 { UInt32((Double(f) * alpha + Double(b) * (1 - alpha)).rounded()) }
            return RGB(mix(r, background.r) << 16 | mix(g, background.g) << 8 | mix(b, background.b))
        }
    }

    /// Açık ve koyu görünüm değeri.
    public struct Pair: Sendable, Hashable {
        public let light: RGB, dark: RGB
        public init(light: RGB, dark: RGB) { self.light = light; self.dark = dark }
    }

    /// WCAG kontrast oranı (1…21).
    public static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let (x, y) = (a.relativeLuminance, b.relativeLuminance)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /// Metin olarak kullanılan vurgu (onay bekleyen sayısı, seçim çizgisi, kayıt bağlantısı).
    public static let accentText = Pair(light: RGB(0xA0410E), dark: RGB(0xF79A5B))
    /// Dolgulu denetimlerin rengi (`.tint`): vurgulu düğme, onay kutusu. Üzerindeki yazı beyazdır.
    public static let accentFill = Pair(light: RGB(0xA0410E), dark: RGB(0xB34A0C))
    /// Yalnızca gecikme.
    public static let danger = Pair(light: RGB(0xB42318), dark: RGB(0xFF9A90))

    /// Metin rengi olarak kullanılanlar (denetim için).
    public static let textColors: [(name: String, pair: Pair)] = [
        ("accentText", accentText), ("danger", danger),
    ]

    /// Denetimde kullanılan macOS yüzeyleri (yaklaşık sistem değerleri): içerik zemini ve pencere zemini.
    public static let lightSurfaces = [RGB(0xFFFFFF), RGB(0xECECEC)]
    public static let darkSurfaces = [RGB(0x1E1E1E), RGB(0x323232)]
    /// Seçili satır zemini: açıkta siyahın, koyuda beyazın bu opaklıkta yüzeye bindirilmiş hâli (`Design.selection`).
    public static let selectionAlpha = 0.08
}
