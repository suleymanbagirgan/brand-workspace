import Foundation

/// Geçici rapor PDF'lerinin temizliği (U-45). Mail taslağı için `<veri alanı>/Gecici/<marka> rapor v<N>.pdf` yazılır;
/// bu dosyalar açılışta, `maxAge`'den eski olanlar silinir. Yalnız ürünün kendi adlandırdığı dosyalara dokunulur:
/// klasörün doğrudan altındaki, adı `… rapor v<sayı>.pdf` biçiminde olan düz dosyalar. Başka ad, alt klasör ve sembolik bağ kalır.
public enum GeciciRaporTemizligi {
    public static let folderName = "Gecici"
    public static let maxAge: TimeInterval = 7 * 86_400

    /// Ürünün yazdığı geçici rapor dosya adı mı? (`<marka> rapor v<sayı>.pdf`)
    public static func isProductFile(_ name: String) -> Bool {
        guard name.hasSuffix(".pdf"), let r = name.range(of: " rapor v", options: .backwards) else { return false }
        let digits = name[r.upperBound...].dropLast(4)
        return r.lowerBound > name.startIndex && !digits.isEmpty && digits.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// `directory` içindeki eski ürün dosyalarını siler; silinen dosya sayısını döndürür. Hata verirse o dosya atlanır.
    @discardableResult
    public static func clean(directory: URL, now: Date = Date(), maxAge: TimeInterval = GeciciRaporTemizligi.maxAge,
                             fileManager: FileManager = .default) -> Int {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]
        guard let items = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else { return 0 }
        var removed = 0
        for url in items where isProductFile(url.lastPathComponent) {
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isSymbolicLink != true, v.isRegularFile == true,
                  let modified = v.contentModificationDate, now.timeIntervalSince(modified) > maxAge else { continue }
            // Bilinçli yutma: silinemeyen geçici dosya bir sonraki açılışta yeniden denenir; sayı yalnız silineni sayar.
            if (try? fileManager.removeItem(at: url)) != nil { removed += 1 }
        }
        return removed
    }
}
