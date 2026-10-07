import Foundation
import GRDB

/// Terminal ve Codex'in çalıştığı marka klasörleri. Veri tabanına yazmazlar; yalnızca bağlam anlık görüntüsü ve çıktılar.
public struct BrandFolders: Sendable {
    public let root: URL
    public let store: Store
    /// Dosya sistemine erişim arayüzü (S3). Varsayılan: bugünkü mutlak yol davranışı (`AbsolutePathFolderAccess`).
    public let access: any FolderAccess

    public init(root: URL, store: Store) { self.init(root: root, store: store, access: AbsolutePathFolderAccess(root: root)) }

    public init(root: URL, store: Store, access: any FolderAccess) { self.root = root; self.store = store; self.access = access }

    /// Bloğu erişim kapsamı içinde çalıştırır: `begin` başarısızsa `izinGerekli`; başarılıysa `end` her durumda (hata dahil) tam bir kez.
    public func withAccess<T>(_ url: URL, _ body: (URL) throws -> T) throws -> T {
        guard access.begin(url) else { throw FolderAccessError.izinGerekli(ipucuYol: url.path) }
        defer { access.end(url) }
        return try body(url)
    }

    public static var defaultRoot: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Marka Çalışma Alanı", isDirectory: true)
    }

    /// "Tüm markalar" kapsamının klasör adı. Marka ad alanının dışındadır: bu ada sahip bir marka bu klasörü paylaşamaz.
    public static let allBrandsFolderName = "_Tüm Markalar"

    static func safeName(_ name: String) -> String {
        let cleaned = name.components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>")).joined(separator: "-").trimmed
        return cleaned.isEmpty ? "Marka" : cleaned
    }

    public func folder(for scope: SessionScope) throws -> URL {
        let fm = FileManager.default
        switch scope {
        case .allBrands:
            let rootURL = try access.root()
            let u = rootURL.appendingPathComponent(Self.allBrandsFolderName, isDirectory: true)
            try withAccess(rootURL) { _ in try fm.createDirectory(at: u, withIntermediateDirectories: true) }
            return u
        case .brand(let id):
            let key = "folder.\(id)"
            if let saved = try store.setting(key) {
                let u = try access.folder(savedPath: saved)
                try withAccess(u) { _ in try fm.createDirectory(at: u.appendingPathComponent("ciktilar"), withIntermediateDirectories: true) }
                return u
            }
            let brand = try store.brand(id)
            let base = Self.safeName(brand.name)
            let rootURL = try access.root()
            func candidate(_ n: Int) -> URL { rootURL.appendingPathComponent(n == 1 ? base : "\(base) \(n)", isDirectory: true) }
            let u: URL = try withAccess(rootURL) { _ in
                var n = 1
                var u = candidate(n)
                // Rezerve "_Tüm Markalar" adı marka klasörü olamaz: aynı ada sahip marka "… 2" alır, tüm-markalar klasörünü paylaşmaz.
                while fm.fileExists(atPath: u.path) || u.lastPathComponent == Self.allBrandsFolderName {
                    n += 1
                    u = candidate(n)
                }
                try fm.createDirectory(at: u.appendingPathComponent("ciktilar"), withIntermediateDirectories: true)
                return u
            }
            try store.setSetting(key, u.path)
            return u
        }
    }

    /// Markanın daha önce oluşturulmuş klasörü; hiç oluşturulmadıysa `nil` (klasör oluşturmaz, ayar yazmaz).
    public func existingFolder(brandId: String) throws -> URL? {
        guard let saved = try store.setting("folder.\(brandId)") else { return nil }
        // İzin yoksa `nil` değil `izinGerekli` fırlar: "klasör yok" ile "izin yok" ayrılır (varsayılan uygulamada izin hep var).
        let u = try access.folder(savedPath: saved)
        return try withAccess(u) { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
    }

    /// BAGLAM.md: yalnızca bu markanın bağlamı; tek tüketicisi Codex'tir (Anthropic yolu dosya kullanmaz).
    /// Y1: yalnız markanın Codex izni varsa yazılır; izin yoksa hiçbir şey yazılmaz, klasör oluşturulmaz (var olan dosya silinmez,
    /// kullanıcı dosyalarına dokunulmaz) ve `nil` döner. Dosya iCloud'a eşitlenebileceği için şirket profili, ekip, görev tarifi ve
    /// yetenek gövdesi içermez (`brandContext(provider: nil)`).
    @discardableResult
    public func writeContextFile(brandId: String) throws -> URL? {
        let brand = try store.brand(brandId)
        guard brand.allows(.codex) else { return nil }
        let dir = try folder(for: .brand(brandId))
        return try withAccess(dir) { dir in
            // Öneri kutusu: terminaldeki araçlar yaptıklarını buraya JSON olarak bırakır (bkz. `SuggestionInbox`).
            try? FileManager.default.createDirectory(at: dir.appendingPathComponent(SuggestionInbox.folderName), withIntermediateDirectories: true)
            let body = """
            <!-- Marka Çalışma Alanı tarafından oluşturuldu. Elle düzenleme uygulamaya geri yazılmaz. -->
            # \(brand.name) — çalışma bağlamı

            Bu klasör yalnızca **\(brand.name)** markasına aittir. Diğer markaların bilgisi burada yoktur ve kullanılmamalıdır.

            - Ürettiğin dosyaları `ciktilar/` klasörüne kaydet. Uygulamada *Klasörden içe al* ile markanın kaynaklarına iş çıktısı olarak eklenir.
            - Bu klasördeki araçlar (Claude Code, Codex CLI) uygulamanın veri tabanına yazamaz. Görev, çalışma kaydı, marka kaydı ve not eklemek için aşağıdaki öneri dosyasını yaz; uygulama kullanıcıya onaylatır.

            \(Self.suggestionInstructions)

            \(try ContextBuilder(store: store).brandContext(brandId: brandId, provider: nil))
            """
            let url = dir.appendingPathComponent("BAGLAM.md")
            try body.write(to: url, atomically: true, encoding: .utf8)
            writeAgentPointers(in: dir)
            return url
        }
    }

    /// Uygulamanın ürettiği yönlendirme dosyalarının ilk satırı: yalnızca bununla başlayan dosya yeniden yazılır.
    public static let agentPointerMarker = "<!-- Marka Çalışma Alanı tarafından oluşturuldu: BAGLAM.md'ye yönlendirir. -->"

    /// Claude Code `CLAUDE.md`'yi, Codex CLI `AGENTS.md`'yi kendiliğinden okur; BAGLAM.md'yi okumayabilir. İkisi de BAGLAM.md'ye
    /// yönlendirilir, böylece "görev ekle" denince öneri dosyası yazılır. Kullanıcının kendi dosyası (işaretsiz) hiç değiştirilmez.
    func writeAgentPointers(in dir: URL) {
        let rule = "Görev, çalışma kaydı, marka kaydı ya da not eklemen istenince: `*_oner` araçların varsa (uygulama içi sohbet) onları kullan; "
            + "yoksa (terminal) uygulamanın veri tabanına yazamazsın, BAGLAM.md'deki şemayla `oneriler/<tarih>-<konu>.json` yaz. "
            + "Markdown görev listesi yazma. Uygulama kullanıcıya onaylatır."
        let files = [
            ("CLAUDE.md", "\(Self.agentPointerMarker)\n# Marka klasörü\n\n\(rule)\n\n@BAGLAM.md\n"),
            ("AGENTS.md", "\(Self.agentPointerMarker)\n# Marka klasörü\n\nÇalışmaya başlamadan önce `BAGLAM.md` dosyasını oku (markanın bağlamı ve kuralları).\n\n\(rule)\n"),
        ]
        for (name, text) in files {
            let url = dir.appendingPathComponent(name)
            var st = stat()
            if lstat(url.path, &st) == 0 {
                // Bağ ya da kullanıcının kendi dosyası: dokunulmaz.
                guard (st.st_mode & S_IFMT) == S_IFREG, let data = try? FileImportGuard.readNoFollow(url),
                      String(decoding: data.prefix(200), as: UTF8.self).hasPrefix(Self.agentPointerMarker) else { continue }
            }
            // Bilinçli yutma: yönlendirme dosyası kolaylıktır (BAGLAM.md asıl kaynak); yazılamazsa terminal aracı yine çalışır.
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// BAGLAM.md'deki öneri dosyası talimatı (şema sürüm 1). Tek kaynak: testler de bu metni ayrıştırılabilir örnek için kullanır.
    public static let suggestionInstructions = """
    ## Yaptıklarını uygulamaya aktarma: `oneriler/` (öneri dosyası)

    Oturumun sonunda ya da kullanıcı isteyince (ör. "görev ekle", "yaptıklarımızı aktar") yaptıklarını **`oneriler/<tarih>-<konu>.json`**
    olarak yaz (ör. `oneriler/2026-09-18-web-sitesi.json`). Uygulama dosyayı okur, kullanıcıya "Terminalden N öneri · İncele" olarak
    gösterir; kullanıcı onayladıkları bu markada oluşur ve geri alınabilir. İşlenen dosya `oneriler/islenmis/` altına taşınır.

    - Bu yol terminal (Claude Code, Codex CLI) içindir. Uygulama içi sohbette `*_oner` araçların varsa onları kullan.
    - Görev listesini markdown olarak yazma (`ciktilar/gorevler.md` gibi): uygulama onu görev olarak okumaz, yalnızca dosya olur.
    - Marka, dosyanın bulunduğu klasörden belirlenir; dosyaya marka adı ya da kimliği yazma (yazılırsa yok sayılır).
    - Tek dosyada birden çok tür olabilir (gün sonu dökümü). Dosya UTF-8 JSON, en fazla 256 KB ve toplam 50 öğe.
    - Geçersiz dosya hiç öneri oluşturmaz; uygulama hatayı kullanıcıya gösterir. Düzeltip yeniden yaz (yeni içerik yeniden okunur).

    Şema (`surum`: 1 zorunlu; diziler isteğe bağlı ama en az biri dolu; tarihler `YYYY-AA-GG`):
    - `gorevler[]`: `baslik` (zorunlu, ≤200), `aciklama`, `durum` (`yapilacak` | `suruyor` | `bekliyor` | `bitti`), `sonTarih`,
      `oncelik` (`dusuk` | `orta` | `yuksek`), `sorumlu`, `proje` (markadaki proje adı). `durum: bitti` olan ve markada aynı başlıklı
      açık görev varsa yeni görev açılmaz, o görevin tamamlanması önerilir; belirli bir görevi tamamlamak için `gorevId` ver (yalnızca `bitti` ile).
    - `calismaKayitlari[]` (taslak düşer, doğrulamayı kullanıcı yapar): `baslik` (zorunlu), `neIstendi`, `neYapildi` (zorunlu), `karar`,
      `kimOnayladi`, `musteriyeBildirilen`, `tarih`, `gorev` (görev başlığı) ya da `gorevId`, `girdiDosyalari[]` ve `ciktiDosyalari[]`
      (bu klasöre göreli yollar, ör. `ciktilar/rapor.md`; onayda kaynak olarak eklenip kayda bağlanır), `girdiKaynaklari[]` /
      `ciktiKaynaklari[]` (aşağıdaki listedeki kaynak kimlikleri).
    - `kayitlar[]`: `tur` (`hedef` | `talep` | `soz` | `karar` | `teklif` | `sozlesme` | `tarih`), `baslik` (zorunlu), `aciklama`, `sonTarih`.
    - `notlar[]`: `tur` (`not` | `gorusme`), `baslik` (zorunlu), `metin` (zorunlu), `tarih`.

    Örnek:
    ```json
    {
      "surum": 1,
      "gorevler": [
        {"baslik": "Web sitesi", "aciklama": "Ana sayfa taslağı", "durum": "yapilacak", "sonTarih": "2026-09-30", "oncelik": "yuksek"},
        {"baslik": "Katalog metinleri", "durum": "bitti"}
      ],
      "calismaKayitlari": [
        {"baslik": "Marka tanımı yazıldı", "neIstendi": "Klinik için marka tanımı", "neYapildi": "Konumlandırma ve ton metni hazırlandı",
         "gorev": "Web sitesi", "ciktiDosyalari": ["ciktilar/marka-tanimi.md"]}
      ],
      "kayitlar": [
        {"tur": "soz", "baslik": "Cuma'ya kadar site taslağı gönderilecek", "sonTarih": "2026-09-26"}
      ],
      "notlar": [
        {"tur": "gorusme", "baslik": "Müşteriyle ön görüşme", "metin": "Öncelik web sitesi; reklam kampanyası sonra.", "tarih": "2026-09-18"}
      ]
    }
    ```
    """

    public struct FileState: Sendable, Hashable { public var modified: Date; public var size: Int }

    public func snapshot(_ dir: URL) -> [String: FileState] {
        var out: [String: FileState] = [:]
        // /var ↔ /private/var gibi sembolik bağlar: göreli yol iki tarafta da aynı biçimden hesaplanır.
        let base = dir.resolvingSymlinksInPath().path
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey],
                                                     options: [.skipsHiddenFiles]) else { return out }
        for case let url as URL in e {
            let v0 = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
            // Sembolik bağlar atlanır: başka markaya (ya da uygulama verisine) giden bağ marka klasörünün içeriği sayılmaz.
            // Bağ bir klasöre işaret ediyorsa içine de inilmez.
            if v0?.isSymbolicLink == true { e.skipDescendants(); continue }
            guard let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey]), v.isDirectory != true else { continue }
            let full = url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent).path
            guard full.hasPrefix(base + "/") else { continue }
            let rel = String(full.dropFirst(base.count + 1))
            // Uygulamanın ürettiği bağlam/yönlendirme dosyaları klasörün içeriği sayılmaz.
            if rel == "BAGLAM.md" || rel == "CLAUDE.md" || rel == "AGENTS.md" { continue }
            out[rel] = FileState(modified: v.contentModificationDate ?? .distantPast, size: v.fileSize ?? 0)
        }
        return out
    }

    public static func diff(before: [String: FileState], after: [String: FileState]) -> [(path: String, change: String)] {
        var changes: [(String, String)] = []
        for (path, state) in after.sorted(by: { $0.key < $1.key }) {
            if let old = before[path] { if old != state { changes.append((path, "modified")) } } else { changes.append((path, "added")) }
        }
        for path in before.keys.sorted() where after[path] == nil { changes.append((path, "deleted")) }
        return changes
    }

    /// Klasördeki, henüz kaynak olarak eklenmemiş dosyalar (sha256 ile karşılaştırılır).
    public func importableFiles(brandId: String) throws -> [URL] {
        let dir = try folder(for: .brand(brandId))
        let known = Set(try store.sources(brandId: brandId, includeArchived: true).map(\.sha256))
        return try withAccess(dir) { dir in
            // `snapshot` sembolik bağları zaten atlar; içerik yine bağ izlemeden (O_NOFOLLOW) ve marka klasörüne hapsedilerek okunur.
            // Öneri kutusu (`oneriler/`) iş çıktısı adayı değildir; öneri olarak ayrıca okunur.
            return snapshot(dir).keys.sorted().filter { !$0.hasPrefix(SuggestionInbox.folderName + "/") }.compactMap { rel in
                let url = dir.appendingPathComponent(rel)
                guard let canonical = try? FileImportGuard.canonicalRegularFile(at: url, confineTo: dir),
                      let data = try? FileImportGuard.readNoFollow(canonical), data.count < 50_000_000 else { return nil }
                return known.contains(FileVault.sha256(data)) ? nil : url
            }
        }
    }
}
