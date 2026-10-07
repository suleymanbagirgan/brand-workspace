import Foundation

/// Geliştirme kancaları (`MARKA_*` ortam değişkenleri: ekran çizimi, deneme veri alanı, açılış sekmesi…).
/// MAS derlemesinde (`-DMAS`) hiçbiri okunmaz: sandbox'lı pakette Finder açılışı ortam vermez, container dışı yol erişimsizdir (S2).
/// Doğrudan dağıtımda davranış bugünküyle aynı: değer ortamdan okunur.
enum DevHook {
    static func value(_ name: String) -> String? {
        #if !MAS
        return ProcessInfo.processInfo.environment[name]
        #else
        return nil
        #endif
    }
}
