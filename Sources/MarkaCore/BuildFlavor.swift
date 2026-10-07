import Foundation

/// Derleme türü. Mac App Store derlemesi komut satırından açılır: `swift build -Xswiftc -DMAS` (Package.swift'e işaret yazılmaz).
/// Anahtar kapalıyken (varsayılan, doğrudan dağıtım) davranış bugünküyle aynıdır (sandbox geçişi S1).
public enum BuildFlavor {
    #if MAS
    public static let isMAS = true
    #else
    public static let isMAS = false
    #endif
}

extension AIProviderKind {
    /// Bu derlemede seçilebilen/oluşturulabilen sağlayıcılar. MAS derlemesinde Anthropic ve Apple (Codex süreç başlatır, yerel uç nokta ölçülmedi; MAS'ta yok).
    /// Kayıtlı `.codex` izni veri tabanında kalabilir (enum durumu silinmez) ama MAS'ta kullanılmaz.
    public static var selectable: [AIProviderKind] { selectable(mas: BuildFlavor.isMAS) }

    /// Derleme türüne göre seçilebilenler (E-25: MAS'ta Anthropic + Apple'ın cihaz üstü modeli; ağ ve süreç yok). Testte iki kip de denetlenir.
    static func selectable(mas: Bool) -> [AIProviderKind] { mas ? [.anthropic, .apple] : allCases }

    /// Bu derlemede kullanılabilir mi (MAS'ta `.codex` hayır).
    public var isSelectable: Bool { Self.selectable.contains(self) }
}
