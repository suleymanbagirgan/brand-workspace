import AppKit
import CryptoKit
import Foundation
import GRDB
import PDFKit
import UniformTypeIdentifiers

/// İçerik adresli, salt okunur dosya deposu. Aynı içerik bir kez saklanır.
public struct FileVault: Sendable {
    public let root: URL

    public init(root: URL) { self.root = root }

    public struct Stored: Sendable {
        public let relativePath: String
        public let sha256: String
        public let byteSize: Int
    }

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public func store(fileURL: URL) throws -> Stored {
        let data = try FileImportGuard.readNoFollow(fileURL)
        return try store(data: data, fileExtension: fileURL.pathExtension)
    }

    public func store(data: Data, fileExtension: String) throws -> Stored {
        let hash = Self.sha256(data)
        let ext = fileExtension.isEmpty ? "" : ".\(fileExtension.lowercased())"
        let rel = "\(hash.prefix(2))/\(hash)\(ext)"
        let url = root.appendingPathComponent(rel)
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)
        }
        return Stored(relativePath: rel, sha256: hash, byteSize: data.count)
    }

    public func url(for relativePath: String) -> URL { root.appendingPathComponent(relativePath) }
}

/// Dosya içe aktarımında marka yalıtımının tek denetim noktası. Sembolik bağların izlenmesini ve marka klasörü dışına
/// çıkan (ara klasörü başka markaya bağlı) yolların içe alınmasını engeller. Tüm içe aktarma yolları bunu kullanır.
public enum FileImportGuard {
    /// İçe aktarılacak dosyanın gerçek, düz bir dosya olduğunu doğrular; okunacak kanonik URL'yi döndürür.
    /// - Dosyanın kendisi sembolik bağsa reddedilir (`ciktilar/bag.txt -> <başka marka>/gizli.txt` gibi köprü kurulamaz).
    /// - `confineTo` verilirse: dosyanın tüm ara klasörleriyle çözülmüş gerçek yolu bu kanonik klasörün içinde kalmalı.
    ///   Ara klasör başka markaya giden bir bağ olsa bile `realpath` dışarı çıkar ve burada yakalanır.
    @discardableResult
    public static func canonicalRegularFile(at url: URL, confineTo root: URL? = nil) throws -> URL {
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        if values?.isDirectory == true { throw MarkaError.validation(L("Klasör eklenemez; dosyaları tek tek ekle.")) }
        if values?.isSymbolicLink == true {
            throw MarkaError.validation(L("Sembolik bağ içe aktarılamaz; bağın gösterdiği gerçek dosyayı seç."))
        }
        let canonical = SandboxProfile.canonical(url.path)
        if let root {
            let base = SandboxProfile.canonical(root.path)
            if canonical != base && !canonical.hasPrefix(base + "/") {
                throw MarkaError.validation(L("Bu dosya marka klasörünün dışını gösteriyor; içe aktarılmadı."))
            }
        }
        // Var olan dosya bir bağ ya da düz dosya değilse reddedilir. Var olmayan/okunamayan dosyanın gerçek sistem hatası
        // (yol taşıyan Cocoa hatası) `readNoFollow`'da yükseltilir; tanı süzgeci bu yolu zaten temizler.
        var st = stat()
        if lstat(canonical, &st) == 0 {
            if (st.st_mode & S_IFMT) == S_IFLNK {
                throw MarkaError.validation(L("Sembolik bağ içe aktarılamaz; bağın gösterdiği gerçek dosyayı seç."))
            }
            if (st.st_mode & S_IFMT) != S_IFREG { throw MarkaError.validation(L("Yalnızca düz dosyalar içe aktarılabilir.")) }
        }
        return URL(fileURLWithPath: canonical)
    }

    /// Dosyayı sembolik bağ izlemeden okur (`O_NOFOLLOW`): denetim ile okuma arasında dosya bağa çevrilse bile bağ izlenmez.
    public static func readNoFollow(_ url: URL) throws -> Data {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        if fd < 0 {
            if errno == ELOOP { throw MarkaError.validation(L("Sembolik bağ içe aktarılamaz; bağın gösterdiği gerçek dosyayı seç.")) }
            // Var olmayan/erişilemeyen dosya: gerçek sistem hatasını (yol taşıyan) yükselt.
            return try Data(contentsOf: url)
        }
        defer { close(fd) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        return (try? handle.readToEnd()) ?? Data()
    }
}

/// Dosyadan aranabilir metin çıkarır. Desteklenmeyen biçimde boş döner (dosya yine saklanır).
public enum TextExtractor {
    public static let maxCharacters = 400_000

    public static func extract(from url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        var text = ""
        switch ext {
        case "txt", "md", "markdown", "csv", "json", "html", "htm", "xml", "yaml", "yml", "swift", "log":
            text = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1)) ?? ""
        case "pdf":
            text = PDFDocument(url: url)?.string ?? ""
        case "docx":
            text = (try? NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML],
                                            documentAttributes: nil).string) ?? ""
        case "rtf":
            text = (try? NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.rtf],
                                            documentAttributes: nil).string) ?? ""
        default:
            text = ""
        }
        return text.count > maxCharacters ? String(text.prefix(maxCharacters)) : text
    }

    public static func mimeType(for url: URL) -> String {
        UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }
}

extension Store {
    public var vault: FileVault { FileVault(root: database.filesRoot) }

    public func sources(brandId: String, kinds: [SourceKind]? = nil, includeArchived: Bool = false) throws -> [Source] {
        try read { db in
            var q = Source.filter(Column("brandId") == brandId)
            if let kinds { q = q.filter(kinds.map(\.rawValue).contains(Column("kind"))) }
            if !includeArchived { q = q.filter(Column("archivedAt") == nil) }
            return try q.order(Column("capturedAt").desc).fetchAll(db)
        }
    }

    public func source(_ id: String) throws -> Source {
        guard let s = try read({ db in try Source.fetchOne(db, key: id) }) else { throw MarkaError.notFound(id) }
        return s
    }

    /// Metin kaynağı (not, görüşme notu, müşteri talebi, bağlantı) ekler.
    /// `openRequest`: müşteri talebi kaynağıyla birlikte, kaynağa bağlı açık bir "Müşteri talebi" kaydı da oluşturur.
    /// İkisi tek işlemde yazılır (biri başarısız olursa hiçbiri kalmaz) ve her biri denetim olayı bırakır.
    @discardableResult
    public func addTextSource(brandId: String, kind: SourceKind, title: String, body: String, url: String? = nil,
                              capturedAt: Date = Date(), openRequest: Bool = false, actor: Actor = .user) throws -> Source {
        let cleanTitle = title.trimmed
        guard !cleanTitle.isEmpty else { throw MarkaError.validation(L("Başlık boş olamaz.")) }
        if openRequest, kind != .clientRequest {
            throw MarkaError.validation(L("Açık talep kaydı yalnızca müşteri talebi kaynağıyla oluşturulur."))
        }
        if kind == .link {
            guard let url, let u = URL(string: url), u.scheme == "https" || u.scheme == "http" else {
                throw MarkaError.validation(L("Geçerli bir bağlantı gir (https://…)."))
            }
        } else if body.trimmed.isEmpty {
            throw MarkaError.validation(L("Metin boş olamaz."))
        }
        let data = Data((body + (url ?? "")).utf8)
        let source = Source(brandId: brandId, kind: kind, title: cleanTitle, body: body, sha256: FileVault.sha256(data),
                            byteSize: data.count, url: url, capturedAt: capturedAt, actor: actor)
        return try writer.write { db in
            let saved = try insertSource(db, source)
            if openRequest {
                let record = BrandRecord(brandId: brandId, kind: .request, title: cleanTitle, sourceId: saved.id)
                try record.insert(db)
                try audit(db, actor: actor, brandId: brandId, entity: "brandRecord", entityId: record.id,
                          action: "create", before: BrandRecord?.none, after: record)
            }
            return saved
        }
    }

    /// Dosya kaynağı ekler: orijinal dosya içerik adresli olarak kopyalanır, metni aranabilir yapılır.
    /// - Parameter confineTo: verilirse (marka klasöründen içe aktarma), dosyanın gerçek yolu bu klasörün içinde kalmalı;
    ///   sembolik bağlar ve klasör dışını gösteren yollar reddedilir. Kullanıcının elle seçtiği dosyada `nil`, ama bağ yine reddedilir.
    @discardableResult
    public func addFileSource(brandId: String, fileURL: URL, kind: SourceKind = .file, title: String? = nil,
                              capturedAt: Date? = nil, confineTo: URL? = nil, actor: Actor = .user) throws -> Source {
        let canonical = try FileImportGuard.canonicalRegularFile(at: fileURL, confineTo: confineTo)
        let values = try? canonical.resourceValues(forKeys: [.contentModificationDateKey])
        let stored = try vault.store(fileURL: canonical)
        let source = Source(brandId: brandId, kind: kind,
                            title: (title?.trimmed).flatMap { $0.isEmpty ? nil : $0 } ?? fileURL.deletingPathExtension().lastPathComponent,
                            body: TextExtractor.extract(from: canonical), fileName: fileURL.lastPathComponent,
                            filePath: stored.relativePath, mimeType: TextExtractor.mimeType(for: fileURL),
                            sha256: stored.sha256, byteSize: stored.byteSize,
                            capturedAt: capturedAt ?? values?.contentModificationDate ?? Date(), actor: actor)
        return try insertSource(source)
    }

    /// Yeni metin içerikli iş çıktısı dosyası üretir (AI veya kullanıcı).
    @discardableResult
    public func addGeneratedOutput(brandId: String, fileName: String, content: String, title: String,
                                   actor: Actor) throws -> Source {
        let data = Data(content.utf8)
        let ext = (fileName as NSString).pathExtension.isEmpty ? "md" : (fileName as NSString).pathExtension
        let stored = try vault.store(data: data, fileExtension: ext)
        let source = Source(brandId: brandId, kind: .workOutput, title: title.trimmed.isEmpty ? fileName : title,
                            body: content, fileName: fileName, filePath: stored.relativePath, mimeType: "text/markdown",
                            sha256: stored.sha256, byteSize: stored.byteSize, capturedAt: Date(), actor: actor)
        return try insertSource(source)
    }

    private func insertSource(_ source: Source) throws -> Source {
        try writer.write { db in try insertSource(db, source) }
    }

    private func insertSource(_ db: Database, _ source: Source) throws -> Source {
        guard try Brand.fetchOne(db, key: source.brandId) != nil else { throw MarkaError.notFound(source.brandId) }
        try source.insert(db)
        try audit(db, actor: source.actor, brandId: source.brandId, entity: "source", entityId: source.id,
                  action: "create", before: Source?.none, after: SourceAuditView(source))
        return source
    }

    public func setSourceArchived(_ id: String, archived: Bool, actor: Actor = .user) throws {
        try writer.write { db in
            guard var s = try Source.fetchOne(db, key: id) else { throw MarkaError.notFound(id) }
            let before = SourceAuditView(s)
            s.archivedAt = archived ? Date() : nil
            try s.update(db, columns: ["archivedAt"])
            try audit(db, actor: actor, brandId: s.brandId, entity: "source", entityId: id,
                      action: archived ? "archive" : "unarchive", before: before, after: SourceAuditView(s))
        }
    }

    public func fileURL(for source: Source) -> URL? {
        source.filePath.map { vault.url(for: $0) }
    }
}

/// Denetim olayında gövde metni tekrar saklanmaz (kaynak zaten değişmez).
struct SourceAuditView: Encodable {
    let id: String, brandId: String, kind: String, title: String, sha256: String, archivedAt: Date?
    init(_ s: Source) {
        id = s.id; brandId = s.brandId; kind = s.kind.rawValue; title = s.title; sha256 = s.sha256; archivedAt = s.archivedAt
    }
}
