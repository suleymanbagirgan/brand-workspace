import Foundation

/// "Yapay zekâya sor" ile gelen, asistan paneli açılınca gönderilecek tek istem (H2-02, U-11).
/// İstem hangi marka için sorulduysa o markaya aittir; başka markaya gitmez.
public struct PendingPrompt: Equatable, Sendable {
    public let brandId: String
    public let text: String

    public init(brandId: String, text: String) {
        self.brandId = brandId
        self.text = text
    }
}

/// Bekleyen istem yuvası. Saf mantık: arayüz, ağ ve veritabanı bilmez.
///
/// Kural (U-11: anahtar yokken basılan istem sonra kendiliğinden ücretli çağrı yapmasın, marka karışmasın):
/// - Sağlayıcı hazır değilken istem **hiç bekletilmez**; varsa eskisi de silinir.
/// - Tüketim yalnız **aynı marka** için ve yalnız **sağlayıcı hazırken** olur; tek seferliktir.
/// - Başka markada tüketme denemesi ya da sağlayıcı yokken tüketme denemesi istemi göndermeden siler.
public struct PendingPromptSlot: Equatable, Sendable {
    public private(set) var pending: PendingPrompt?

    public init() {}

    /// İstemi bekletir. Sağlayıcı hazır değilse ya da istem boşsa bekletmez (eskisini de siler). Bekletildiyse true.
    @discardableResult
    public mutating func request(_ text: String, brandId: String, providerReady: Bool) -> Bool {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard providerReady, !clean.isEmpty, !brandId.isEmpty else {
            pending = nil
            return false
        }
        pending = PendingPrompt(brandId: brandId, text: clean)
        return true
    }

    /// Paneldeki marka için bekleyen istemi alır. Her çağrıda yuva boşalır; istem yalnız marka aynıysa ve sağlayıcı hazırsa döner.
    public mutating func take(brandId: String, providerReady: Bool) -> PendingPrompt? {
        guard let p = pending else { return nil }
        pending = nil
        guard p.brandId == brandId, providerReady else { return nil }
        return p
    }

    /// Seçili marka değişti: bekleyen istem başka markaya aitse gönderilmeden silinir.
    public mutating func brandChanged(to brandId: String?) {
        if pending?.brandId != brandId { pending = nil }
    }

    /// Sağlayıcı bağlantısı koptu (anahtar silindi, izin kaldırıldı): bekleyen istem gönderilmeden silinir.
    public mutating func providerLost() {
        pending = nil
    }
}

/// Asistan panelinin açılıştaki durumu (H2-02, U-34/T-12): sağlayıcı bağlı değilken boş panel yer kaplamasın.
public enum AssistantPanelDefault {
    /// `savedChoice`: kullanıcının bilinçli seçimi ("1" açık, "0" kapalı, nil hiç seçmedi).
    /// Seçim varsa ona uyulur; yoksa panel yalnız bir sağlayıcı bağlıyken açık başlar.
    public static func isOpen(savedChoice: String?, providerConnected: Bool) -> Bool {
        switch savedChoice {
        case "1": return true
        case "0": return false
        default: return providerConnected
        }
    }
}
