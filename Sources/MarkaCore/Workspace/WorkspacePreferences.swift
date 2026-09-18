import CryptoKit
import Foundation

/// Tercih ve Keychain yalıtımı (D1). Varsayılan veri alanıyla açılan uygulama gerçek tercihleri (`UserDefaults.standard`,
/// yani `com.markacalismaalani.app` alanı) ve gerçek Keychain hesabını kullanır. `MARKA_WORKSPACE` ile başka bir veri
/// alanı verilirse o alanın yolundan türetilen ayrı bir tercih takımı ve ayrı Keychain hesap adı kullanılır; böylece
/// deneme kopyasında model seçmek, son markayı hatırlamak ya da API anahtarını "Kaldır"mak gerçek kopyaya dokunmaz.
/// `MARKA_SNAPSHOT` (ekran çizimi) kipi hiçbir kalıcı tercihe yazmaz.
public struct PreferenceScope: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        /// Varsayılan veri alanı: gerçek tercihler, gerçek Keychain hesabı.
        case standard
        /// `MARKA_WORKSPACE` ile verilen ayrı veri alanı.
        case trial
        /// `MARKA_SNAPSHOT` ekran çizimi: tercih yazılmaz.
        case snapshot
    }

    /// Uygulamanın paket kimliği; `UserDefaults.standard` bu alana yazar.
    public static let appDomain = "com.markacalismaalani.app"

    public let kind: Kind
    /// `nil` = `UserDefaults.standard`. Aksi hâlde ayrı tercih takımının adı.
    public let suiteName: String?
    /// Keychain hesap adlarına eklenen sonek; gerçek alanda boş.
    public let keychainSuffix: String

    /// Tercihler kalıcı olarak yazılır mı? Ekran çizimi kipinde yazılmaz.
    public var persistsPreferences: Bool { kind != .snapshot }

    public static let standard = PreferenceScope(kind: .standard, suiteName: nil, keychainSuffix: "")

    /// Ortamdan kapsamı çıkarır. Veri alanı varsayılanla aynıysa (sembolik bağlar ve sondaki "/" dahil) standart kapsamdır.
    public static func resolve(workspace: URL, defaultWorkspace: URL, snapshot: Bool) -> PreferenceScope {
        let key = pathKey(workspace)
        if snapshot {
            return PreferenceScope(kind: .snapshot, suiteName: "\(appDomain).anlik.\(key)", keychainSuffix: ".anlik.\(key)")
        }
        if normalizedPath(workspace) == normalizedPath(defaultWorkspace) { return .standard }
        return PreferenceScope(kind: .trial, suiteName: "\(appDomain).deneme.\(key)", keychainSuffix: ".deneme.\(key)")
    }

    /// Bu kapsamdaki Keychain hesap adı (ör. `anthropic-api-key` → `anthropic-api-key.deneme.1a2b…`).
    public func keychainAccount(_ base: String) -> String { base + keychainSuffix }

    static func normalizedPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.resolvingSymlinksInPath().path
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }

    /// Yoldan türetilen kararlı, kısa ad (SHA-256'nın ilk 16 onaltılık hanesi). Yolun kendisi ad içinde görünmez.
    static func pathKey(_ url: URL) -> String {
        SHA256.hash(data: Data(normalizedPath(url).utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

/// Kapsama göre tercih okuma/yazma. Uygulama tercihlere yalnızca bunun üzerinden erişir.
public final class PreferenceStore: @unchecked Sendable {
    public let scope: PreferenceScope
    /// SwiftUI `.defaultAppStorage` için. Standart kapsamda `UserDefaults.standard`.
    public let defaults: UserDefaults
    private var memory: [String: String] = [:]
    private let lock = NSLock()

    public init(scope: PreferenceScope) {
        self.scope = scope
        if let name = scope.suiteName, let suite = UserDefaults(suiteName: name) {
            defaults = suite
        } else {
            defaults = .standard
        }
    }

    public func string(forKey key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        if !scope.persistsPreferences { return memory[key] }
        return defaults.string(forKey: key)
    }

    public func set(_ value: String?, forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        if !scope.persistsPreferences { memory[key] = value; return }
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}
