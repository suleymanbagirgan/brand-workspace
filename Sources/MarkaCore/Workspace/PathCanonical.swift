import Foundation

/// Yol kanonikleştirme: Codex'ten bağımsız ortak yardımcı (sandbox geçişi S1).
///
/// Eskiden `SandboxProfile.canonical` içindeydi; `FileImportGuard` ve `SuggestionInbox` marka yalıtımı için de kullandığı için
/// buraya taşındı. MAS derlemesinde (`-Xswiftc -DMAS`) seatbelt profili derlenmez ama bu yardımcı derlenir. Davranış bire bir aynıdır.
public enum PathCanonical {
    /// Sembolik bağları çözülmüş mutlak yol. Henüz var olmayan yolda var olan en uzun üst klasör çözülür, kalanı eklenir.
    public static func canonical(_ path: String) -> String {
        let standardized = (path as NSString).standardizingPath
        var head = standardized
        var tail: [String] = []
        while head.count > 1 {
            if let resolved = realpathString(head) {
                return tail.reversed().reduce(resolved) { ($0 as NSString).appendingPathComponent($1) }
            }
            tail.append((head as NSString).lastPathComponent)
            head = (head as NSString).deletingLastPathComponent
        }
        return standardized
    }

    private static func realpathString(_ path: String) -> String? {
        guard let p = realpath(path, nil) else { return nil }
        defer { free(p) }
        return String(cString: p)
    }
}
