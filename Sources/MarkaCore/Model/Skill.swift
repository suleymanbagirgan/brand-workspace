import CryptoKit
import Foundation
import GRDB

/// Yetenek kütüphanesi kaydı (0.4.0). Biçim, ajan yetenekleri için yaygın SKILL.md düzenini izler: kısa bir `name` (küçük harf, rakam, tire;
/// en çok 64), ne yaptığını ve ne zaman kullanılacağını söyleyen `description` (en çok 1024) ve yönergeleri taşıyan gövde.
/// Bir ekip üyesine yetenek adıyla bağlanır; yapay zekâ çalışanın bağlamına tanım ve gövde girer. Yetenek yetki vermez: öneri kuralı değişmez.
public struct Skill: Codable, Sendable, Hashable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "skill"
    public var id: String
    public var name: String
    public var title: String
    public var description: String
    public var body: String
    /// Hazır paket anahtarı (`pazarlama`…), elle yazılana ve içe aktarılana boş.
    public var pack: String
    public var createdAt: Date
    public var updatedAt: Date
    /// Köken (E-07): `SkillOrigin.rawValue` (`manual`, `pack`, `file:<ad>`, `folder:<ad>`). Yalnız `Store` yazar; kayıt
    /// güncellenirken korunur. SKILL.md dışa aktarımına girmez.
    public var origin: String
    /// Kayıt anındaki gövdenin SHA-256 özeti (onaltılık; `Skill.digest(body:)`). Boşsa bilinmiyor (elle yazılan ya da
    /// v11 öncesi kayıt). "Yerel değişiklik var" bilgisi bundan çıkar.
    public var contentHash: String
    /// İçe aktarma tarihi; elle yazılan ve hazır paketten gelen kayıtta `nil`.
    public var importedAt: Date?

    public init(id: String = newID(), name: String, title: String = "", description: String, body: String = "", pack: String = "",
                createdAt: Date = Date(), updatedAt: Date = Date(),
                origin: String = SkillOrigin.manual.rawValue, contentHash: String = "", importedAt: Date? = nil) {
        self.id = id; self.name = name; self.title = title; self.description = description; self.body = body; self.pack = pack
        self.createdAt = createdAt; self.updatedAt = updatedAt
        self.origin = origin; self.contentHash = contentHash; self.importedAt = importedAt
    }

    public var displayTitle: String { title.isEmpty ? name : title }

    public var originKind: SkillOrigin { SkillOrigin(rawValue: origin) }
    /// Dosyadan ya da klasörden içe aktarıldı ("içe aktarıldı" rozeti).
    public var isImported: Bool { originKind.isImported }
    /// Gövde, kayıt anındaki özetten farklı. Özet bilinmiyorsa (boş) `false`.
    public var hasLocalChanges: Bool { !contentHash.isEmpty && Skill.digest(body: body) != contentHash }

    /// Gövdenin SHA-256 özeti (onaltılık, UTF-8).
    public static func digest(body: String) -> String {
        SHA256.hash(data: Data(body.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Yeteneğin nereden geldiği (E-07). Dosya ve klasör için yalnız son yol bileşeni saklanır (tam yol saklanmaz).
public enum SkillOrigin: Sendable, Hashable {
    case manual
    case pack
    case file(String)
    case folder(String)

    public var rawValue: String {
        switch self {
        case .manual: "manual"
        case .pack: "pack"
        case .file(let name): "file:" + name
        case .folder(let name): "folder:" + name
        }
    }

    /// Bilinmeyen değer `manual` sayılır.
    public init(rawValue: String) {
        if rawValue == "pack" { self = .pack }
        else if rawValue.hasPrefix("file:") { self = .file(String(rawValue.dropFirst(5))) }
        else if rawValue.hasPrefix("folder:") { self = .folder(String(rawValue.dropFirst(7))) }
        else { self = .manual }
    }

    public var isImported: Bool {
        switch self { case .file, .folder: true; case .manual, .pack: false }
    }

    /// İçe aktarılan dosya ya da klasörün adı; diğerlerinde boş.
    public var sourceName: String {
        switch self { case .file(let n), .folder(let n): n; case .manual, .pack: "" }
    }

    /// Kullanıcının verdiği adı sadeleştirir: yalnız son yol bileşeni, satır sonu yok, en çok 128 karakter.
    public static func cleanName(_ name: String) -> String {
        let last = name.split(separator: "/").last.map(String.init) ?? ""
        return String(last.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces).prefix(128))
    }
}

public enum SkillMarkdown {
    /// Türkçe karakterleri sadeleştirip `küçük-harf-tire` adı üretir ("SEO Denetimi" → "seo-denetimi").
    public static func slug(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: "ı", with: "i").lowercased()
        var out = ""
        var lastDash = true
        for ch in folded.unicodeScalars {
            if (ch >= "a" && ch <= "z") || (ch >= "0" && ch <= "9") { out.unicodeScalars.append(ch); lastDash = false }
            else if !lastDash { out += "-"; lastDash = true }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return String(out.prefix(64))
    }

    /// SKILL.md metnini çözer: `---` arasındaki `name:` ve `description:` satırları + gövde. Tanım ya da ad yoksa `nil`.
    public static func parse(_ text: String) -> (name: String, description: String, body: String)? {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard lines.first?.trimmed == "---", let end = lines.dropFirst().firstIndex(where: { $0.trimmed == "---" }) else { return nil }
        var fields: [String: String] = [:]
        for line in lines[1..<end] {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmed.lowercased()
            var value = String(line[line.index(after: colon)...]).trimmed
            if value.count >= 2, (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            fields[key] = value
        }
        guard let name = fields["name"], !name.isEmpty, let description = fields["description"], !description.isEmpty else { return nil }
        let body = lines[(end + 1)...].joined(separator: "\n").trimmed
        return (name, description, body)
    }

    /// Dışa aktarım: aynı biçimde SKILL.md.
    public static func export(_ skill: Skill) -> String {
        "---\nname: \(skill.name)\ndescription: \(skill.description.replacingOccurrences(of: "\n", with: " "))\n---\n\n\(skill.body)\n"
    }
}
