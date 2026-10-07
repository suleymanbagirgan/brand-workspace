import Foundation

// Sessiz hata yok (H3-03). Yakalanan her hata ya kullanıcıya görünür (`visible`) ya da yedek değerle sürer ama
// içeriksiz tanı kaydına düşer (`value(or:)`, `attempt`). Bağlam sabit anahtardır; hata mesajı hiçbir yola yazılmaz.

/// Kullanıcıya gösterilecek hata: başlık ve hatanın kendi yerelleştirilmiş açıklaması (tanıya yazılmaz, yalnız ekrana).
public struct VisibleFailure: Sendable, Hashable {
    public var title: String
    public var message: String
    public init(title: String, message: String) { self.title = title; self.message = message }
}

extension DiagnosticsLog {
    /// İkincil okuma ya da bilinçli yutma: başarısızlıkta yedek değer döner, hata içeriksiz kaydedilir.
    public func value<T>(or fallback: @autoclosure () -> T, context: String, _ body: () throws -> T) -> T {
        do { return try body() } catch {
            record(error, context: context)
            return fallback()
        }
    }

    /// Sonucu gerekmeyen yan etki: başarısızsa kaydeder ve `false` döner (akış durmaz).
    @discardableResult
    public func attempt(context: String, _ body: () throws -> Void) -> Bool {
        do { try body(); return true } catch {
            record(error, context: context)
            return false
        }
    }

    /// Kaybı önemli işin (kayıt, geri alma, silme, dışa aktarma) hatası: içeriksiz kaydedilir, ekranda gösterilecek
    /// başlık ve açıklama döner.
    public func visible(_ error: Error, title: String, context: String) -> VisibleFailure {
        record(error, context: context)
        return VisibleFailure(title: title, message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
    }
}
