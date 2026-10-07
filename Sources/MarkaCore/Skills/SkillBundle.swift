import CryptoKit
import Foundation

/// SKILL.md klasör paketi (E-02). Kullanıcının seçtiği yerel klasör `SKILL.md` + `references/**/*.md` taşır.
/// Çözücü yalnız okur: veritabanına dokunmaz, ağ kullanmaz, süreç başlatmaz. Kaydetme kullanıcının önizlemeyi
/// onaylamasından sonra mevcut `Store.saveSkill` yolundan yapılır (yetenek yetki vermez; öneri kuralı değişmez).
///
/// Sınırlar: her dosya en çok 256 KB ve geçerli UTF-8; en çok 20 referans dosyası; sembolik bağlar izlenmez (atlanır,
/// `SKILL.md` sembolik bağsa paket reddedilir); `..` ya da mutlak yol içeren göreli yol reddedilir.
public struct SkillBundle: Sendable, Equatable {
    public struct File: Sendable, Equatable {
        /// Paket köküne göreli yol (`references/kontrol-listesi.md`).
        public var path: String
        public var text: String
        public var byteCount: Int
    }

    public var name: String
    /// Ad slug'a sadeleştiyse özgün yazım; aksi hâlde boş (bkz. `Store.importSkill`).
    public var title: String
    public var description: String
    /// `SKILL.md` gövdesi (ön bilgi hariç).
    public var body: String
    /// Yola göre sıralı referans dosyaları.
    public var references: [File]
    /// Okunmadan atlanan yollar (sembolik bağ, `.md` olmayan dosya, gizli dosya).
    public var skipped: [String]
    /// SHA-256 özeti (onaltılık): yola göre sıralı `yol\0içerik\0` dizisi üzerinden. Klasörün yeri ve dosya tarihleri girmez.
    public var digest: String
    public var totalBytes: Int

    /// Kütüphaneye yazılacak gövde: `SKILL.md` gövdesi + her referans, kullanıcı yöntemi çerçevesiyle (veri; yetki vermez).
    /// Referans metnindeki kod çitleri bozulur; kendi çerçevesini kapatıp talimat gibi görünemez.
    public var combinedBody: String {
        var s = body
        for ref in references {
            let fenced = ref.text.replacingOccurrences(of: "```", with: "ʼʼʼ").trimmed
            s += "\n\n## \(ContextBuilder.skillFrameTitle): \(ref.path)\n```\n\(fenced)\n```"
        }
        if !references.isEmpty { s += "\n\n" + ContextBuilder.skillFrameRule }
        return s.trimmed
    }
}

public struct SkillBundleLimits: Sendable, Equatable {
    public var maxFileBytes: Int
    public var maxReferences: Int
    public var maxDepth: Int
    public static let standard = SkillBundleLimits(maxFileBytes: 256 * 1024, maxReferences: 20, maxDepth: 6)
    public init(maxFileBytes: Int, maxReferences: Int, maxDepth: Int) {
        self.maxFileBytes = maxFileBytes; self.maxReferences = maxReferences; self.maxDepth = maxDepth
    }
}

/// Kaydetmeden önce kullanıcıya gösterilen "ne eklenecek" özeti.
public struct SkillBundlePreview: Sendable, Equatable {
    public enum Action: String, Sendable { case add, update }
    public var action: Action
    /// Güncellemede ezilecek mevcut kaydın kimliği.
    public var existingId: String?
    public var name: String
    public var title: String
    public var description: String
    public var referencePaths: [String]
    public var skipped: [String]
    public var digest: String
    public var totalBytes: Int
    public var combinedBody: String
    /// Birleşik gövde kütüphane sınırını (`Store.saveSkill`, 20 000 karakter) aşıyorsa kayıt reddedilecektir.
    public var exceedsLibraryLimit: Bool

    /// Onaydan sonra `Store.saveSkill`'e verilecek kayıt. Güncellemede mevcut kimlik ve paket anahtarı korunur.
    public func skill(existing: [Skill]) -> Skill {
        let old = existing.first { $0.id == existingId }
        return Skill(id: old?.id ?? newID(), name: name, title: title, description: description, body: combinedBody,
                     pack: old?.pack ?? "", createdAt: old?.createdAt ?? Date())
    }
}

public enum SkillBundleReader {
    public static let libraryBodyLimit = 20_000

    /// Klasörü okur ve doğrular. Hata durumunda açıklayıcı `MarkaError.validation` verir.
    public static func read(folder: URL, limits: SkillBundleLimits = .standard) throws -> SkillBundle {
        let fm = FileManager.default
        let skillURL = folder.appendingPathComponent("SKILL.md")
        let skillValues = try? skillURL.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
        if skillValues?.isSymbolicLink == true {
            throw MarkaError.validation(L("SKILL.md sembolik bağ olamaz; paketin içindeki gerçek dosya olmalı."))
        }
        guard fm.fileExists(atPath: skillURL.path), skillValues?.isRegularFile == true else {
            throw MarkaError.validation(L("Klasörde SKILL.md bulunamadı."))
        }
        let skillText = try readText(skillURL, path: "SKILL.md", limits: limits)
        guard let parsed = SkillMarkdown.parse(skillText) else {
            throw MarkaError.validation(L("SKILL.md biçimi okunamadı: başta --- arasında name ve description satırları olmalı."))
        }
        let rawName = parsed.name.trimmed
        let name = SkillMarkdown.slug(rawName)
        guard !name.isEmpty, rawName.count <= 64 else {
            throw MarkaError.validation(L("Yetenek adı küçük harf, rakam ve tireden oluşmalı (en çok 64 karakter)."))
        }
        guard parsed.description.count <= 1024 else { throw MarkaError.validation(LF("Tanım çok uzun (en çok %d).", 1024)) }

        var skipped: [String] = []
        var refs: [SkillBundle.File] = []
        let refRoot = folder.appendingPathComponent("references")
        let refValues = try? refRoot.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        if refValues?.isSymbolicLink == true {
            skipped.append("references")
        } else if refValues?.isDirectory == true {
            try walk(refRoot, relative: "references", depth: 1, limits: limits, refs: &refs, skipped: &skipped)
        }
        refs.sort { $0.path < $1.path }

        var hasher = SHA256()
        var total = skillText.utf8.count
        for (path, text) in [("SKILL.md", skillText)] + refs.map({ ($0.path, $0.text) }) {
            hasher.update(data: Data(path.utf8)); hasher.update(data: Data([0]))
            hasher.update(data: Data(text.utf8)); hasher.update(data: Data([0]))
        }
        total += refs.reduce(0) { $0 + $1.byteCount }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return SkillBundle(name: name, title: rawName == name ? "" : rawName, description: parsed.description, body: parsed.body,
                           references: refs, skipped: skipped.sorted(), digest: digest, totalBytes: total)
    }

    /// Önizleme: aynı adlı kütüphane kaydı varsa "güncelleme" olarak işaretlenir. Hiçbir şey yazılmaz.
    public static func preview(_ bundle: SkillBundle, existing: [Skill]) -> SkillBundlePreview {
        let match = existing.first { $0.name == bundle.name }
        let body = bundle.combinedBody
        return SkillBundlePreview(action: match == nil ? .add : .update, existingId: match?.id, name: bundle.name, title: bundle.title,
                                  description: bundle.description, referencePaths: bundle.references.map(\.path),
                                  skipped: bundle.skipped, digest: bundle.digest, totalBytes: bundle.totalBytes,
                                  combinedBody: body, exceedsLibraryLimit: body.count > libraryBodyLimit)
    }

    /// Paket içi göreli yol denetimi: boş, mutlak, `..` ya da `~` bileşenli yol reddedilir.
    public static func validateRelativePath(_ path: String) throws {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~"),
              !parts.contains(where: { $0 == ".." || $0 == "." || $0.isEmpty }) else {
            throw MarkaError.validation(L("Paket dışına çıkan yol reddedildi."))
        }
    }

    private static func walk(_ dir: URL, relative: String, depth: Int, limits: SkillBundleLimits,
                             refs: inout [SkillBundle.File], skipped: inout [String]) throws {
        guard depth <= limits.maxDepth else { skipped.append(relative); return }
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey, .fileSizeKey]
        let items = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for url in items {
            let rel = relative + "/" + url.lastPathComponent
            try validateRelativePath(rel)
            let v = try url.resourceValues(forKeys: Set(keys))
            if v.isSymbolicLink == true || url.lastPathComponent.hasPrefix(".") { skipped.append(rel); continue }
            if v.isDirectory == true {
                try walk(url, relative: rel, depth: depth + 1, limits: limits, refs: &refs, skipped: &skipped)
                continue
            }
            guard v.isRegularFile == true, url.pathExtension.lowercased() == "md" else { skipped.append(rel); continue }
            guard refs.count < limits.maxReferences else {
                throw MarkaError.validation(LF("Pakette çok fazla referans dosyası var; en çok %d.", limits.maxReferences))
            }
            if let size = v.fileSize, size > limits.maxFileBytes { throw tooLarge(rel, limits) }
            let text = try readText(url, path: rel, limits: limits)
            refs.append(.init(path: rel, text: text, byteCount: text.utf8.count))
        }
    }

    private static func readText(_ url: URL, path: String, limits: SkillBundleLimits) throws -> String {
        let data = try Data(contentsOf: url)
        guard data.count <= limits.maxFileBytes else { throw tooLarge(path, limits) }
        guard let text = String(data: data, encoding: .utf8) else {
            throw MarkaError.validation(LF("“%@” UTF-8 değil; yalnız UTF-8 metin okunur.", path))
        }
        return text
    }

    private static func tooLarge(_ path: String, _ limits: SkillBundleLimits) -> MarkaError {
        .validation(LF("“%@” çok büyük; dosya başına sınır KB olarak %d.", path, limits.maxFileBytes / 1024))
    }
}
