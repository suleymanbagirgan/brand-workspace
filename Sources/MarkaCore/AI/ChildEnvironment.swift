import Foundation

/// Alt süreçlere (marka terminali, Codex App Server) aktarılan ortam. Uygulama API anahtarı tanımlı bir kabuktan
/// açılmış olabilir; bu anahtarlar marka terminaline ve Codex'e inmez. Codex'in ChatGPT girişi kendi `auth.json`
/// dosyasından gelir, `OPENAI_API_KEY`'e ihtiyaç duymaz.
public enum ChildEnvironment {
    /// Alt süreçten çıkarılan değişkenler.
    public static let removedKeys: Set<String> = ["ANTHROPIC_API_KEY", "ANTHROPIC_BASE_URL", "ANTHROPIC_AUTH_TOKEN", "OPENAI_API_KEY"]

    public static func sanitized(_ environment: [String: String]) -> [String: String] {
        environment.filter { !removedKeys.contains($0.key) }
    }

    /// Uygulamanın kendi ortamından süzülmüş kopya.
    public static var current: [String: String] { sanitized(ProcessInfo.processInfo.environment) }
}
