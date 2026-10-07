import Foundation

/// Marka klasörü erişim izni yok (sandbox geçişi S3). "Klasör yok" ile karıştırılmaz: kayıt var ama erişim verilmemiş.
/// `ipucuYol` yalnız kullanıcıya klasörü yeniden seçtirirken paneli yönlendirmek içindir; hata metnine ve tanı kaydına girmez.
public enum FolderAccessError: LocalizedError, Equatable {
    case izinGerekli(ipucuYol: String)

    public var errorDescription: String? {
        switch self {
        case .izinGerekli: L("Marka klasörüne erişim izni gerekli. Klasörü yeniden seç.")
        }
    }
}

/// Marka klasörlerine erişim arayüzü (sandbox geçişi S3). `BrandFolders` dosya sistemine bu arayüzden ulaşır.
///
/// - Varsayılan uygulama (`AbsolutePathFolderAccess`) bugünkü davranıştır: kök ve kayıtlı `folder.<id>` mutlak yolları
///   olduğu gibi kullanılır, kapsam başlat/bitir boş işlemdir. Doğrudan dağıtım bununla çalışır.
/// - İleride (S4) security-scoped bookmark ile çalışan bir uygulama eklenecek; izin yoksa `izinGerekli` fırlatır.
/// - `begin` `true` döndürdüyse her durumda tam bir kez `end` çağrılmalıdır (`BrandFolders.withAccess` bunu `defer` ile sağlar).
public protocol FolderAccess: Sendable {
    /// Marka klasörleri kökü. İzin yoksa `FolderAccessError.izinGerekli`.
    func root() throws -> URL
    /// Kayıtlı (mutlak) marka klasörü yolunu erişilebilir URL'ye çevirir. İzin yoksa `FolderAccessError.izinGerekli`.
    func folder(savedPath: String) throws -> URL
    /// Erişim kapsamını açar; açılamadıysa `false` (o zaman `end` çağrılmaz).
    func begin(_ url: URL) -> Bool
    /// `begin` ile açılan kapsamı kapatır.
    func end(_ url: URL)
}

/// Bugünkü davranış: mutlak yollar, izin denetimi yok, kapsam boş işlem.
public struct AbsolutePathFolderAccess: FolderAccess {
    public let rootURL: URL
    public init(root: URL) { self.rootURL = root }
    public func root() throws -> URL { rootURL }
    public func folder(savedPath: String) throws -> URL { URL(fileURLWithPath: savedPath, isDirectory: true) }
    public func begin(_ url: URL) -> Bool { true }
    public func end(_ url: URL) {}
}
