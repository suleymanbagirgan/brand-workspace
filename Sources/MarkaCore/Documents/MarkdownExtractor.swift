import AppKit
import Foundation

/// Biçimli Markdown çıkarımı (E-19; markitdown/docling fikri, özgün kod, yalnız sistem çerçeveleri).
///
/// Word (docx), RTF ve HTML kaynağını düz metin yerine yapısını koruyarak Markdown'a çevirir: yazı boyutu/kalınlık →
/// `#` başlık düzeyi, `NSTextList` → madde/numaralı liste, `NSTextTable` → Markdown tablosu. Çıktı
/// `DocumentOutline.markdown` ile içindekiler ağacına dönüşür. `TextExtractor`'dan ayrı API'dir; onun davranışı değişmez.
///
/// Sınırlar (ölçüldü, macOS 26): Apple'ın docx okuyucusu `styles.xml`'i uygulamaz; Word'ün *stil* tabanlı başlıkları
/// ("Başlık 1" stili, doğrudan biçim yok) düz paragraf olarak gelir. Word numaralı listesi (`numPr` + `decimal`) madde
/// imli liste olarak okunur. Apple'ın kendi docx yazıcısı listeyi metin imiyle ("\t•\t", "\t1\t") yazar; bu biçim tanınır.
/// pptx/xlsx kapsam dışıdır. Bozuk ya da desteklenmeyen dosyada sonuç boştur.
public enum MarkdownExtractor {
    /// Çıktı sınırı; `TextExtractor` ile aynı.
    public static var maxCharacters: Int { TextExtractor.maxCharacters }
    /// Bundan büyük girdi okunmaz (boş sonuç); bozuk/kötü niyetli dev dosyaya karşı.
    public static let maxInputBytes = 64 * 1024 * 1024

    public enum Format: String, Sendable, CaseIterable {
        case docx, rtf, html

        public init?(fileExtension ext: String) {
            switch ext.lowercased() {
            case "docx": self = .docx
            case "rtf": self = .rtf
            case "html", "htm": self = .html
            default: return nil
            }
        }
    }

    // MARK: - Girişler

    /// Dosyadan Markdown. Desteklenmeyen biçim, okunamayan ya da bozuk dosyada boş döner.
    /// HTML içe aktarımı WebKit kullanır; Apple belgeleri ana iş parçacığını şart koştuğu için ana aktördedir.
    @MainActor
    public static func markdown(from url: URL) -> String {
        guard let format = Format(fileExtension: url.pathExtension),
              let data = try? FileImportGuard.readNoFollow(url) else { return "" }
        switch format {
        case .docx, .rtf: return markdown(data: data, format: format)
        case .html: return markdown(html: data)
        }
    }

    /// docx/rtf verisinden Markdown (her iş parçacığında çağrılabilir). `.html` için `markdown(html:)` kullanılır.
    public static func markdown(data: Data, format: Format) -> String {
        guard !data.isEmpty, data.count <= maxInputBytes else { return "" }
        let type: NSAttributedString.DocumentType
        switch format {
        case .docx: type = .officeOpenXML
        case .rtf: type = .rtf
        case .html: return ""
        }
        guard let attributed = try? NSAttributedString(data: data, options: [.documentType: type], documentAttributes: nil)
        else { return "" }
        return markdown(attributed: attributed)
    }

    /// HTML verisinden Markdown. Dış kaynak yüklenmez: içe aktarmadan önce `sanitizedHTML` tüm URL taşıyan öğe ve
    /// öznitelikleri siler (img, link, style, script, iframe, `src`/`href`/`style`…). Ölçüm: süzgeçsiz içe aktarım uzak
    /// stil dosyasını gerçekten ister (`MarkdownCikarimTests`).
    @MainActor
    public static func markdown(html data: Data) -> String {
        guard let attributed = importHTML(data, sanitize: true) else { return "" }
        return markdown(attributed: attributed)
    }

    /// `sanitize: false` yalnız testte ağ ölçümünün duyarlılığını göstermek içindir.
    @MainActor
    static func importHTML(_ data: Data, sanitize: Bool) -> NSAttributedString? {
        guard !data.isEmpty, data.count <= maxInputBytes else { return nil }
        let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        let html = sanitize ? sanitizedHTML(raw) : raw
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
            .timeout: 5.0,
        ]
        return try? NSAttributedString(data: Data(html.utf8), options: options, documentAttributes: nil)
    }

    // MARK: - HTML süzgeci

    /// İçeriğiyle birlikte atılan öğeler.
    static let dropWithContent: Set<String> = ["script", "style", "template", "noscript", "iframe", "frameset"]
    /// Kendisi atılan (içeriği kalan ya da içeriksiz) öğeler.
    static let dropTag: Set<String> = ["img", "image", "link", "meta", "base", "embed", "object", "param", "source", "track",
                                       "video", "audio", "picture", "input", "frame", "applet", "area", "map", "portal"]
    /// Korunan öznitelikler (URL taşıyamaz; değer yalnız harf/rakam).
    static let keptAttributes: Set<String> = ["colspan", "rowspan", "start", "type", "reversed", "value"]

    /// HTML'i ağsız içe aktarım için sadeleştirir: yorum, `<!…>`/`<?…>` bildirimleri, dış kaynak yükleyebilen öğeler ve
    /// izinli birkaç sayısal öznitelik dışındaki bütün öznitelikler (`src`, `href`, `style`, `srcset`, `background`…) silinir.
    /// Metin içeriği aynen kalır.
    public static func sanitizedHTML(_ html: String) -> String {
        let s = Array(html.unicodeScalars)
        var out = String.UnicodeScalarView()
        out.reserveCapacity(s.count)
        var i = 0
        let n = s.count

        func lower(_ c: Unicode.Scalar) -> Unicode.Scalar {
            (c.value >= 65 && c.value <= 90) ? Unicode.Scalar(c.value + 32)! : c
        }
        func starts(_ lit: String, at k: Int) -> Bool {
            var j = k
            for c in lit.unicodeScalars {
                guard j < n, lower(s[j]) == c else { return false }
                j += 1
            }
            return true
        }
        func find(_ lit: String, from k: Int) -> Int? {
            var j = k
            while j < n { if starts(lit, at: j) { return j }; j += 1 }
            return nil
        }
        func isNameChar(_ c: Unicode.Scalar) -> Bool {
            CharacterSet.alphanumerics.contains(c) || c == "-" || c == ":" || c == "_"
        }
        func isSpace(_ c: Unicode.Scalar) -> Bool { c == " " || c == "\t" || c == "\n" || c == "\r" || c == "\u{0C}" }

        while i < n {
            let c = s[i]
            guard c == "<" else { out.append(c); i += 1; continue }
            if starts("<!--", at: i) {
                i = (find("-->", from: i + 4).map { $0 + 3 }) ?? n
                continue
            }
            if i + 1 < n, s[i + 1] == "!" || s[i + 1] == "?" {
                i = (find(">", from: i + 2).map { $0 + 1 }) ?? n
                continue
            }
            // Etiket adı.
            var j = i + 1
            var closing = false
            if j < n, s[j] == "/" { closing = true; j += 1 }
            let nameStart = j
            while j < n, isNameChar(s[j]) { j += 1 }
            guard j > nameStart, CharacterSet.letters.contains(s[nameStart]) else {
                out.append(contentsOf: "&lt;".unicodeScalars); i += 1; continue
            }
            let name = String(String.UnicodeScalarView(s[nameStart..<j].map(lower)))
            // Öznitelikler (tırnak içindeki `>` etiketi bitirmez).
            var attrs: [(String, String)] = []
            while j < n, s[j] != ">" {
                if isSpace(s[j]) || s[j] == "/" { j += 1; continue }
                let aStart = j
                while j < n, !isSpace(s[j]), s[j] != "=", s[j] != ">", s[j] != "/" { j += 1 }
                let aName = String(String.UnicodeScalarView(s[aStart..<j].map(lower)))
                if aStart == j { j += 1; continue }
                while j < n, isSpace(s[j]) { j += 1 }
                var value = ""
                if j < n, s[j] == "=" {
                    j += 1
                    while j < n, isSpace(s[j]) { j += 1 }
                    if j < n, s[j] == "\"" || s[j] == "'" {
                        let q = s[j]; j += 1
                        let vStart = j
                        while j < n, s[j] != q { j += 1 }
                        value = String(String.UnicodeScalarView(s[vStart..<min(j, n)]))
                        if j < n { j += 1 }
                    } else {
                        let vStart = j
                        while j < n, !isSpace(s[j]), s[j] != ">" { j += 1 }
                        value = String(String.UnicodeScalarView(s[vStart..<j]))
                    }
                }
                attrs.append((aName, value))
            }
            i = min(j + 1, n)   // `>` sonrası

            if dropWithContent.contains(name) {
                // Kapanış etiketi yoksa yalnız açılış etiketi atılır; kalan metin süzülmeye devam eder.
                if !closing, let end = find("</\(name)", from: i).flatMap({ k in find(">", from: k).map { $0 + 1 } }) { i = end }
                continue
            }
            if dropTag.contains(name) { continue }
            out.append(contentsOf: "<".unicodeScalars)
            if closing { out.append("/") }
            out.append(contentsOf: name.unicodeScalars)
            if !closing {
                for (aName, value) in attrs where keptAttributes.contains(aName) {
                    let clean = String(value.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.prefix(8))
                    out.append(contentsOf: " \(aName)=\"\(clean)\"".unicodeScalars)
                }
            }
            out.append(">")
        }
        return String(out)
    }

    // MARK: - Öznitelikli metin → Markdown

    private struct Paragraph {
        var text: String            // satır sonu hariç, ek (￼) karakterleri silinmiş
        var minSize: CGFloat
        var allBold: Bool
        var boldChars: Int
        var lists: [NSTextList]
        var tableBlock: NSTextTableBlock?
        var headerLevel: Int
    }

    private static let bulletMarkers: Set<Character> = ["•", "◦", "▪", "▫", "‣", "⁃", "–", "-", "*", "·", "○", "■", "□", "◆", "✓"]
    private static let textualBullet = try! NSRegularExpression(pattern: #"^\t([•◦▪▫‣⁃–\-*·○■□◆])\t(.*)$"#)
    private static let textualOrdered = try! NSRegularExpression(pattern: #"^\t(\d{1,4})[.)]?\t(.*)$"#)
    private static let markerPrefix = try! NSRegularExpression(pattern: #"^\t[^\t\n]{0,12}\t"#)

    /// Öznitelikli metni Markdown'a çevirir. Sonuç `maxCharacters` ile sınırlıdır.
    public static func markdown(attributed a: NSAttributedString) -> String {
        let paragraphs = collectParagraphs(a)
        guard !paragraphs.isEmpty else { return "" }

        // Gövde yazı boyutu: karakter ağırlıklı en yaygın boyut. Gövdenin çoğu kalınsa kalınlık başlık sayılmaz.
        var sizeWeight: [CGFloat: Int] = [:]
        var totalChars = 0, boldChars = 0
        for p in paragraphs where p.lists.isEmpty && p.tableBlock == nil {
            let w = p.text.count
            sizeWeight[(p.minSize * 2).rounded() / 2, default: 0] += w
            totalChars += w; boldChars += p.boldChars
        }
        let body = sizeWeight.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key ?? 12
        let boldIsSignal = totalChars == 0 || Double(boldChars) / Double(totalChars) < 0.5

        // Başlık adayları ve düzeyleri.
        func headingKind(_ p: Paragraph) -> (bySize: CGFloat?, boldOnly: Bool, explicit: Int)? {
            guard p.lists.isEmpty, p.tableBlock == nil else { return nil }
            let t = p.text.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, t.count <= 200, !t.contains("\n") else { return nil }
            if (1...6).contains(p.headerLevel) { return (nil, false, p.headerLevel) }
            let size = (p.minSize * 2).rounded() / 2
            if size >= body * 1.15 && size >= body + 1 { return (size, false, 0) }
            if boldIsSignal, p.allBold, size >= body - 0.5, t.count <= 120 { return (nil, true, 0) }
            return nil
        }
        let headingSizes = Array(Set(paragraphs.compactMap { headingKind($0)?.bySize })).sorted(by: >)
        func level(_ k: (bySize: CGFloat?, boldOnly: Bool, explicit: Int)) -> Int {
            if k.explicit > 0 { return k.explicit }
            if let s = k.bySize, let idx = headingSizes.firstIndex(of: s) { return min(idx + 1, 6) }
            return min(headingSizes.count + 1, 6)
        }

        var out = ""
        var outCount = 0
        var listLines: [String] = []
        // Liste sayaçları: düzey başına (liste kimliği, sayaç, im genişliği).
        var listStack: [(id: ObjectIdentifier?, counter: Int, indent: Int)] = []

        func emit(_ block: String) {
            guard outCount <= maxCharacters else { return }
            if !out.isEmpty { out += "\n\n"; outCount += 2 }
            out += block; outCount += block.count
        }
        func flushList() {
            if !listLines.isEmpty { emit(listLines.joined(separator: "\n")); listLines = [] }
            listStack = []
        }
        func addListItem(depth: Int, id: ObjectIdentifier?, ordered: Bool, start: Int, text: String,
                         explicitNumber: Bool = false) {
            if listStack.count > depth + 1 { listStack.removeLast(listStack.count - depth - 1) }
            while listStack.count < depth { listStack.append((nil, 0, 2)) }   // atlanmış ara düzey
            var counter = start
            if listStack.count == depth + 1 {
                if listStack[depth].id == id, !explicitNumber { counter = listStack[depth].counter + 1 }
                listStack.removeLast()
            }
            let marker = ordered ? "\(counter)." : "-"
            let indent = listStack.reduce(0) { $0 + $1.indent }
            listStack.append((id, counter, marker.count + 1))
            listLines.append(String(repeating: " ", count: indent) + marker + " " + clean(text))
        }

        var i = 0
        while i < paragraphs.count, outCount <= maxCharacters {
            let p = paragraphs[i]
            // Tablo: aynı tabloya ait ardışık paragraflar.
            if let block = p.tableBlock {
                flushList()
                let table = block.table
                var cells: [Int: [Int: String]] = [:]
                var maxCol = table.numberOfColumns - 1
                var maxRow = 0
                while i < paragraphs.count, let b = paragraphs[i].tableBlock, b.table === table {
                    let text = clean(paragraphs[i].text)
                    var row = cells[b.startingRow] ?? [:]
                    if !text.isEmpty { row[b.startingColumn] = [row[b.startingColumn], text].compactMap { $0 }.joined(separator: " ") }
                    else if row[b.startingColumn] == nil { row[b.startingColumn] = "" }
                    cells[b.startingRow] = row
                    maxRow = max(maxRow, b.startingRow); maxCol = max(maxCol, b.startingColumn)
                    i += 1
                }
                let cols = max(maxCol + 1, 1)
                var lines: [String] = []
                for r in 0...maxRow {
                    let row = (0..<cols).map { c in (cells[r]?[c] ?? "").replacingOccurrences(of: "|", with: "\\|") }
                    lines.append("| " + row.joined(separator: " | ") + " |")
                    if r == 0 { lines.append("|" + String(repeating: " --- |", count: cols)) }
                }
                emit(lines.joined(separator: "\n"))
                continue
            }
            i += 1
            let trimmed = p.text.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            // Liste (NSTextList).
            if let list = p.lists.last {
                let ns = p.text as NSString
                let text = markerPrefix.stringByReplacingMatches(in: p.text, range: NSRange(location: 0, length: ns.length),
                                                                 withTemplate: "")
                addListItem(depth: p.lists.count - 1, id: ObjectIdentifier(list), ordered: isOrdered(list),
                            start: max(list.startingItemNumber, 1), text: text)
                continue
            }
            // Metin imli liste (Apple docx yazıcısı: "\t•\tMadde", "\t1\tMadde").
            let ns = p.text as NSString
            let whole = NSRange(location: 0, length: ns.length)
            if let m = textualBullet.firstMatch(in: p.text, range: whole) {
                addListItem(depth: 0, id: nil, ordered: false, start: 1, text: ns.substring(with: m.range(at: 2)))
                continue
            }
            if let m = textualOrdered.firstMatch(in: p.text, range: whole) {
                let number = Int(ns.substring(with: m.range(at: 1))) ?? 1
                addListItem(depth: 0, id: nil, ordered: true, start: number, text: ns.substring(with: m.range(at: 2)),
                            explicitNumber: true)
                continue
            }
            flushList()
            if let k = headingKind(p) {
                let title = trimmed.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
                emit(String(repeating: "#", count: level(k)) + " " + title)
                continue
            }
            emit(bodyText(p.text))
        }
        flushList()
        return out.count > maxCharacters ? String(out.prefix(maxCharacters)) : out
    }

    private static func isOrdered(_ list: NSTextList) -> Bool {
        let unordered: Set<NSTextList.MarkerFormat> = [.disc, .circle, .square, .box, .check, .diamond, .hyphen]
        return !unordered.contains(list.markerFormat)
    }

    /// Tek satıra indirger: satır sonları ve sekmeler boşluk olur.
    private static func clean(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Gövde paragrafı: satır başı boşlukları (kod bloğu sanılmasın) silinir, `#`/`>` ile başlayan satır kaçışlanır
    /// (içindekiler ağacı onu başlık saymasın).
    private static func bodyText(_ s: String) -> String {
        s.split(separator: "\n", omittingEmptySubsequences: true).map { line -> String in
            var t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("#") || t.hasPrefix(">") || t.hasPrefix("```") || t.hasPrefix("~~~") { t = "\\" + t }
            return t
        }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private static func collectParagraphs(_ a: NSAttributedString) -> [Paragraph] {
        let ns = a.string as NSString
        var result: [Paragraph] = []
        var location = 0
        var produced = 0
        while location < ns.length, produced <= maxCharacters * 2 {
            let range = ns.paragraphRange(for: NSRange(location: location, length: 0))
            location = NSMaxRange(range)
            guard range.length > 0 else { break }
            var raw = ns.substring(with: range)
            while let last = raw.last, last.isNewline { raw.removeLast() }
            let text = raw.replacingOccurrences(of: "\u{FFFC}", with: "").replacingOccurrences(of: "\u{2028}", with: "\n")
            let style = a.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
            var minSize = CGFloat.greatestFiniteMagnitude
            var allBold = true
            var boldChars = 0
            a.enumerateAttribute(.font, in: range, options: []) { value, r, _ in
                let piece = ns.substring(with: r)
                let visible = piece.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) && $0 != "\u{FFFC}" }.count
                guard visible > 0 else { return }
                let font = value as? NSFont
                minSize = min(minSize, font?.pointSize ?? 12)
                let bold = font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
                if bold { boldChars += visible } else { allBold = false }
            }
            if minSize == .greatestFiniteMagnitude { minSize = 12; allBold = false }
            let tableBlock = style?.textBlocks.first as? NSTextTableBlock
            result.append(Paragraph(text: text, minSize: minSize, allBold: allBold, boldChars: boldChars,
                                    lists: style?.textLists ?? [], tableBlock: tableBlock,
                                    headerLevel: style?.headerLevel ?? 0))
            produced += text.count
        }
        return result
    }
}
