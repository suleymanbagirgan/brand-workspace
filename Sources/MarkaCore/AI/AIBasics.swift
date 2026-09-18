import Foundation
import Security

/// Sohbette görünen etkinlik kartı (kalıcı).
public struct ChatEventRecord: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case toolRead, proposal, fileChange, command, approval, notice, error, usage
    }
    public var id: String
    public var kind: Kind
    public var title: String
    public var detail: String
    public var status: String
    /// İlgili kayıt (öneri kimliği, kaynak kimliği vb.)
    public var refId: String?

    public init(id: String = newID(), kind: Kind, title: String, detail: String = "", status: String = "", refId: String? = nil) {
        self.id = id; self.kind = kind; self.title = title; self.detail = detail; self.status = status; self.refId = refId
    }
}

extension Store {
    public static func decodeEvents(_ json: String) throws -> [ChatEventRecord] {
        try decoder.decode([ChatEventRecord].self, from: Data(json.utf8))
    }
}

public enum ApprovalDecision: String, Sendable { case accept, acceptForSession, decline, cancel }

public struct ApprovalRequest: Sendable, Identifiable, Hashable {
    public enum Kind: String, Sendable { case command, fileChange }
    public var id: String
    public var kind: Kind
    public var title: String
    public var detail: String
    public var reason: String
}

/// Sağlayıcıdan uygulamaya akan olaylar.
public enum AIEvent: Sendable {
    case textDelta(String)
    case event(ChatEventRecord)
    case eventUpdated(ChatEventRecord)
    case approvalNeeded(ApprovalRequest)
    case usage(UsageEntry)
    case finished(stopReason: String)
    case failed(String)
}

// MARK: - Fiyatlar

public struct ModelPrice: Sendable, Hashable, Identifiable {
    public var id: String
    public var displayName: String
    /// USD / 1M token
    public var input: Double
    public var output: Double
    public var cacheRead: Double
    public var cacheWrite: Double
    public var supportsAdaptiveThinking: Bool
    /// `output_config.effort` kabul ediyor mu? Haiku 4.5 etmez; gönderilirse API 400 döner.
    /// Kaynak: https://platform.claude.com/docs/en/build-with-claude/effort (desteklenen modeller listesi)
    public var supportsEffort: Bool
}

/// Anthropic API liste fiyatları (Anthropic model tablosu, 2026-06-24 önbelleği). Tahmin amaçlıdır; faturayı Anthropic belirler.
public enum PriceTable {
    public static let pricedAt = "2026-06-24"
    public static let anthropic: [ModelPrice] = [
        ModelPrice(id: "claude-opus-5", displayName: "Claude Opus 5", input: 5, output: 25, cacheRead: 0.5, cacheWrite: 6.25, supportsAdaptiveThinking: true, supportsEffort: true),
        ModelPrice(id: "claude-sonnet-5", displayName: "Claude Sonnet 5", input: 2, output: 10, cacheRead: 0.2, cacheWrite: 2.5, supportsAdaptiveThinking: true, supportsEffort: true),
        ModelPrice(id: "claude-haiku-4-5", displayName: "Claude Haiku 4.5", input: 1, output: 5, cacheRead: 0.1, cacheWrite: 1.25, supportsAdaptiveThinking: false, supportsEffort: false),
    ]
    public static let defaultAnthropicModel = "claude-opus-5"

    public static func price(for model: String) -> ModelPrice? {
        anthropic.first { model.hasPrefix($0.id) }
    }

    /// Mikro-USD cinsinden tahmini maliyet. Bilinmeyen modelde nil.
    public static func costMicros(model: String, input: Int, output: Int, cacheRead: Int, cacheWrite: Int) -> Int? {
        guard let p = price(for: model) else { return nil }
        let usd = (Double(input) * p.input + Double(output) * p.output + Double(cacheRead) * p.cacheRead + Double(cacheWrite) * p.cacheWrite) / 1_000_000
        return Int((usd * 1_000_000).rounded())
    }

    public static func formatUSD(micros: Int) -> String {
        let usd = Double(micros) / 1_000_000
        return usd < 0.01 && usd > 0 ? String(format: "<$0.01") : String(format: "$%.2f", usd)
    }
}

// MARK: - Keychain

public enum Keychain {
    static let servicePrefix = "com.markacalismaalani.app."

    public static func save(_ secret: String, account: String) throws {
        let service = servicePrefix + account
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(secret.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw MarkaError.ai(LF("Anahtar Keychain'e kaydedilemedi (%d).", Int(status))) }
    }

    public static func load(account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: servicePrefix + account,
                                kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    public static func delete(account: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: servicePrefix + account, kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
    }
}
