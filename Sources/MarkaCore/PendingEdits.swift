import Foundation

/// Bekleyen düzenleme kayıt defteri (U-07): kullanıcı bir alana yazarken uygulama kapanırsa yazılan kaybolmasın.
/// Alan, yazmaya başlayınca kendi kaydet kapanışını kimliğiyle kaydeder; kaydedince siler.
/// Kapanışta `flushAll()` kalanları eşzamanlı çağırır. Saf mantık: arayüz ve veritabanı bilmez.
@MainActor
public final class PendingEdits {
    public static let shared = PendingEdits()
    public init() {}

    private var order: [UUID] = []
    private var saves: [UUID: () -> Void] = [:]

    /// Bekleyen düzenleme sayısı.
    public var count: Int { saves.count }

    /// Alanın kaydet kapanışını (yeniden) kaydeder; aynı kimlik tek giriş kalır.
    public func register(_ id: UUID, save: @escaping () -> Void) {
        if saves[id] == nil { order.append(id) }
        saves[id] = save
    }

    /// Alan kendi kaydetti ya da kayboldu: bekleyen girişi siler (kaydetmeden).
    public func clear(_ id: UUID) {
        saves[id] = nil
        order.removeAll { $0 == id }
    }

    /// Tek alanı bekliyorsa kaydeder ve siler. Kaydedildiyse true.
    @discardableResult
    public func flush(_ id: UUID) -> Bool {
        guard let save = saves[id] else { return false }
        clear(id)
        save()
        return true
    }

    /// Kapanışta: bekleyen tüm düzenlemeleri kayıt sırasıyla, eşzamanlı kaydeder. Çağrılan kaydet sayısını döner.
    @discardableResult
    public func flushAll() -> Int {
        let ids = order
        var n = 0
        for id in ids where flush(id) { n += 1 }
        return n
    }
}
