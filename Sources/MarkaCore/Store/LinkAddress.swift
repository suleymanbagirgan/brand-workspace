import Foundation

/// Bağlantı adresi yardımcısı (U-42): şemasız adrese `https://` ekler, güvenmediği girdiyi reddeder.
/// Yalnız `http` ve `https` kabul edilir; `javascript:`, `file:`, `data:` gibi şemalar ve boşluklu/geçersiz girdi `nil` döner.
public enum LinkAddress {
    /// Girdiyi temizleyip geçerli bir http(s) adresine çevirir; geçersizse `nil`.
    public static func normalize(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              text.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
        let lower = text.lowercased()
        var candidate = text
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            // olduğu gibi
        } else if let colon = text.firstIndex(of: ":"), text[text.startIndex..<colon].allSatisfy({ $0.isLetter || $0.isNumber || "+.-".contains($0) }),
                  text.first?.isLetter == true {
            // "localhost:8080" gibi alan:port ise şemasızdır; başka her şema (javascript:, mailto:, file:…) reddedilir.
            let after = text[text.index(after: colon)...]
            let portDigits = after.prefix { $0.isNumber }
            guard !portDigits.isEmpty, after.dropFirst(portDigits.count).first.map({ "/?#".contains($0) }) ?? true else { return nil }
            candidate = "https://" + text
        } else if text.contains("://") {
            return nil
        } else {
            candidate = "https://" + text
        }
        guard let url = URL(string: candidate), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty, host.contains(".") || host == "localhost" else { return nil }
        return candidate
    }

    /// Bağlantı adı boşsa kullanılacak ad: alan adı (başındaki `www.` atılır). Adres geçersizse `nil`.
    public static func suggestedTitle(for address: String) -> String? {
        guard let normalized = normalize(address), let host = URL(string: normalized)?.host else { return nil }
        return host.lowercased().hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

extension Store {
    /// Bağlantı kaynağı ekler: şemasız adrese `https://` ekler, ad boşsa alan adını kullanır; geçersiz adres reddedilir.
    @discardableResult
    public func addLink(brandId: String, title: String, address: String, capturedAt: Date = Date(), actor: Actor = .user) throws -> Source {
        guard let url = LinkAddress.normalize(address) else {
            throw MarkaError.validation(L("Geçerli bir bağlantı gir (https://…)."))
        }
        let name = title.trimmed.isEmpty ? (LinkAddress.suggestedTitle(for: url) ?? url) : title
        return try addTextSource(brandId: brandId, kind: .link, title: name, body: "", url: url, capturedAt: capturedAt, actor: actor)
    }
}
