import Foundation

// Marka terminali oturumlarının yaşam döngüsü (0.2.1 U9). Kurucu AI ile terminalde çalışır; çalışan kabuk (ve içindeki
// Claude Code/Codex oturumu) yalnız şu durumlarda biter: kullanıcı kabuktan çıkar, marka arşivlenir ya da uygulama
// kapanır. Terminali gizlemek, başka markaya ya da Bugün'e geçmek, paneli yana/alta almak ve yalıtım ayarını değiştirmek
// oturumu **bitirmez**. Bu tür görünümden (AppKit) bağımsızdır: saf mantık, testle bağlı (`TerminalOturumTests`).

/// Oturumu etkileyebilecek olaylar.
public enum TerminalEvent: Sendable, Hashable {
    /// Terminal paneli gizlendi (⌘J, başlıktaki "Terminal").
    case hidden
    /// Başka markaya ya da Bugün'e geçildi.
    case selectionChanged
    /// Panel yana/alta alındı.
    case moved
    /// Terminal yalıtımı ayarı değişti.
    case isolationChanged
    /// Markanın kabuğu kendiliğinden bitti (kullanıcı `exit` yazdı ya da süreç öldü).
    case shellExited(brandId: String)
    /// Marka arşivlendi (ya da artık listede yok).
    case brandRemoved(brandId: String)
    /// Uygulama kapanıyor (kullanıcı onayladıktan sonra).
    case appQuit
}

/// Oturumun uygulamaya göre durumu.
public struct TerminalSessionInfo: Sendable, Hashable {
    public var brandId: String
    /// Oturum yalıtımlı profille mi başladı (başladığı andaki ayar; sonradan değişmez).
    public var isolated: Bool
    /// Kabuk süreci sürüyor mu.
    public var running: Bool

    public init(brandId: String, isolated: Bool, running: Bool = true) {
        self.brandId = brandId; self.isolated = isolated; self.running = running
    }
}

/// Marka başına tek terminal oturumu tutan önbellek. `Session` görünüm + süreçtir (uygulamada SwiftTerm görünümü);
/// önbellek süreci kendisi sonlandırmaz, sonlandırılacakları döndürür.
@MainActor
public final class TerminalSessionCache<Session: AnyObject> {
    private struct Entry {
        var info: TerminalSessionInfo
        let session: Session
    }
    private var entries: [String: Entry] = [:]

    public init() {}

    /// Markanın oturumu: sürüyorsa aynısı döner (yeniden ebeveynlenir, süreç yeniden başlamaz); yoksa ya da kabuk
    /// bittiyse `make` ile yenisi kurulur ve o anki yalıtım ayarıyla kaydedilir.
    public func session(for brandId: String, isolated: Bool, make: () throws -> Session) rethrows -> Session {
        if let e = entries[brandId], e.info.running { return e.session }
        let s = try make()
        entries[brandId] = Entry(info: TerminalSessionInfo(brandId: brandId, isolated: isolated), session: s)
        return s
    }

    /// Var olan oturum (başlatmaz).
    public func existing(_ brandId: String) -> Session? { entries[brandId]?.session }

    public func info(_ brandId: String) -> TerminalSessionInfo? { entries[brandId]?.info }

    /// Olayın sonucu: sonlandırılması gereken oturumlar. Önbellekten çıkarılır; çağıran süreçlerini sonlandırır.
    /// Gizleme, seçim değişikliği, yer değiştirme ve yalıtım değişikliği hiçbir oturumu bitirmez.
    @discardableResult
    public func handle(_ event: TerminalEvent) -> [Session] {
        switch event {
        case .hidden, .selectionChanged, .moved, .isolationChanged:
            return []
        case .shellExited(let id):
            // Süreç zaten bitti; görünüm yerinde kalır (son çıktı okunabilsin), bir sonraki gösterimde yenisi kurulur.
            entries[id]?.info.running = false
            return []
        case .brandRemoved(let id):
            guard let e = entries.removeValue(forKey: id) else { return [] }
            return e.info.running ? [e.session] : []
        case .appQuit:
            let running = entries.values.filter(\.info.running).map(\.session)
            entries = [:]
            return running
        }
    }

    /// Listede artık olmayan (arşivlenmiş) markaların oturumları: sonlandırılacaklar.
    public func prune(keeping brandIds: Set<String>) -> [Session] {
        entries.keys.filter { !brandIds.contains($0) }.flatMap { handle(.brandRemoved(brandId: $0)) }
    }

    /// Çalışan kabuk sayısı (uygulama kapanırken sorulacak soru için).
    public var runningCount: Int { entries.values.filter(\.info.running).count }

    /// Kapanışta sorulsun mu? `nil`: çalışan oturum yok, soru sorulmaz; değilse çalışan oturum sayısı.
    public var quitQuestionCount: Int? { runningCount > 0 ? runningCount : nil }

    /// Oturum, şu anki yalıtım ayarından farklı bir profille mi sürüyor (başlıkta tek satırla söylenir).
    public func isolationDiffers(_ brandId: String, current: Bool) -> Bool {
        guard let info = entries[brandId]?.info, info.running else { return false }
        return info.isolated != current
    }
}
