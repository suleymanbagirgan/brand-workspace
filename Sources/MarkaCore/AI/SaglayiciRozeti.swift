import Foundation

/// Sohbet panelindeki sağlayıcı rozeti (E-24). Metin sağlayıcının `capabilities.onDevice` yeteneğinden türer; sabit bir sağlayıcı
/// listesi yoktur. Rozet yalnız hangi modelle konuşulduğunu söyler: "veri hiç dışarı çıkmaz" gibi bir vaat taşımaz.
public struct ProviderBadge: Sendable, Equatable {
    public let onDevice: Bool
    public let text: String
    /// `help` ve VoiceOver etiketi.
    public let detail: String

    public static func make(kind: AIProviderKind, onDevice: Bool) -> ProviderBadge {
        if onDevice {
            return ProviderBadge(onDevice: true, text: L("Bu Mac'te çalışıyor"), detail: L("Bu sohbet bu Mac'teki modelle yürür."))
        }
        return ProviderBadge(onDevice: false, text: kind.displayName, detail: LF("Bu sohbet %@ ile yürür.", kind.displayName))
    }
}

extension ChatEngine {
    /// Kayıtlı sağlayıcının yeteneğinden rozet; sağlayıcı bu derlemede kayıtlı değilse `nil` (rozet yanlış bir şey söylemez).
    public nonisolated func badge(for kind: AIProviderKind) -> ProviderBadge? {
        guard let p = try? registry.provider(for: kind) else { return nil }
        return ProviderBadge.make(kind: kind, onDevice: p.capabilities.onDevice)
    }
}
