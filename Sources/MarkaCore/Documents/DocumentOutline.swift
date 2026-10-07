import Foundation
import PDFKit

/// Uzun belge için içindekiler ağacı (PageIndex esinli; özgün kod).
///
/// Yapay zekânın bütün metni değil ilgili bölümü okuyabilmesi için başlık ağacı çıkarır: bölüm adı, satır
/// (PDF'te ayrıca sayfa) aralığı ve karakter sayısı. Gömme ya da vektör yoktur, veri tabanına yazılmaz; ağaç istek
/// anında üretilir. Girdi `TextExtractor.maxCharacters` sınırında kesilir (`isTruncated`).
///
/// Kayıp yoktur: `flatSections` sırasıyla bölüm metinleri birleştirildiğinde `text`'e bire bir eşittir.
public struct DocumentOutline: Sendable, Hashable {
    public enum Origin: String, Sendable, Hashable {
        /// Markdown `#` başlıkları.
        case markdown
        /// Düz metinde numaralı başlık sezgisi ("1. Giriş", "2.3 Fesih").
        case numberedHeadings
        /// PDF'in kendi ana hattı (`outlineRoot`).
        case pdfOutline
        /// Ana hatsız PDF; sayfa metninde numaralı başlık sezgisi.
        case pdfHeuristic
        /// Hiç başlık bulunamadı; tek kök bölüm.
        case none
    }

    public struct Section: Sendable, Hashable, Identifiable {
        /// Ağaçtaki yol: "1", "1.2", "1.2.3". Başlıktan önceki metin "0".
        public var id: String
        public var title: String
        /// 1 en üst düzey.
        public var level: Int
        /// 1 tabanlı, kapsayıcı. Bölümün kendi metni (alt bölümler hariç).
        public var startLine: Int
        public var endLine: Int
        /// Yalnız PDF'te; 1 tabanlı, kapsayıcı.
        public var startPage: Int?
        public var endPage: Int?
        /// Bölümün kendi metni (başlık satırı dahil, alt bölümler hariç).
        public var text: String
        public var children: [Section]

        public var characterCount: Int { text.count }
        /// Alt bölümlerle birlikte toplam karakter.
        public var totalCharacterCount: Int { characterCount + children.reduce(0) { $0 + $1.totalCharacterCount } }
    }

    public var origin: Origin
    /// Ağacın çıkarıldığı (gerekirse kesilmiş) metin. PDF'te sayfa metinleri "\n" ile birleştirilir.
    public var text: String
    public var isTruncated: Bool
    public var pageCount: Int?
    public var roots: [Section]

    /// Belge sırasıyla düzleştirilmiş bölümler.
    public var flatSections: [Section] {
        var out: [Section] = []
        func walk(_ s: Section) { out.append(s); s.children.forEach(walk) }
        roots.forEach(walk)
        return out
    }

    public func section(id: String) -> Section? { flatSections.first { $0.id == id } }

    // MARK: - Girişler

    /// Markdown kaynağı: kod bloğu (```) dışındaki `#`…`######` başlıkları.
    public static func markdown(_ raw: String) -> DocumentOutline {
        let (text, truncated) = limit(raw)
        let lines = Self.lines(of: text)
        var inFence = false
        var heads: [Heading] = []
        for (i, line) in lines.enumerated() {
            let t = line.content.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") || t.hasPrefix("~~~") { inFence.toggle(); continue }
            if inFence { continue }
            if let h = markdownHeading(t) { heads.append(Heading(start: line.start, line: i + 1, level: h.level, title: h.title)) }
        }
        return build(origin: heads.isEmpty ? .none : .markdown, text: text, truncated: truncated, lines: lines, heads: heads, pageStarts: nil)
    }

    /// Düz metin: numaralı başlık sezgisi.
    public static func plainText(_ raw: String) -> DocumentOutline {
        let (text, truncated) = limit(raw)
        let lines = Self.lines(of: text)
        let heads = numberedHeadings(lines)
        return build(origin: heads.isEmpty ? .none : .numberedHeadings, text: text, truncated: truncated, lines: lines, heads: heads, pageStarts: nil)
    }

    public static func pdf(data: Data) -> DocumentOutline? {
        PDFDocument(data: data).map { pdf($0) }
    }

    /// PDF: ana hat varsa ondan, yoksa sayfa metnindeki numaralı başlıklardan.
    public static func pdf(_ document: PDFDocument) -> DocumentOutline {
        var joined = ""
        var pageOffsets: [Int] = []   // karakter ofseti
        for i in 0..<document.pageCount {
            if i > 0 { joined += "\n" }
            pageOffsets.append(joined.count)
            joined += document.page(at: i)?.string ?? ""
        }
        let (text, truncated) = limit(joined)
        let lines = Self.lines(of: text)
        let pageStarts = pageOffsets.filter { $0 <= text.count }.map { text.index(text.startIndex, offsetBy: $0) }

        var heads: [Heading] = []
        var origin: Origin = .none
        if let root = document.outlineRoot, root.numberOfChildren > 0 {
            var items: [(title: String, level: Int, page: Int)] = []
            func walk(_ node: PDFOutline, level: Int) {
                for i in 0..<node.numberOfChildren {
                    guard let child = node.child(at: i) else { continue }
                    let page = (child.destination?.page).map { document.index(for: $0) } ?? NSNotFound
                    let title = (child.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if page != NSNotFound, page < pageStarts.count, !title.isEmpty { items.append((title, level, page)) }
                    walk(child, level: level + 1)
                }
            }
            walk(root, level: 1)
            var cursor = text.startIndex
            for item in items {
                let pageStart = pageStarts[item.page]
                let pageEnd = item.page + 1 < pageStarts.count ? pageStarts[item.page + 1] : text.endIndex
                let from = max(cursor, pageStart)
                var start = from
                if from < pageEnd, let r = text.range(of: item.title, options: [.caseInsensitive], range: from..<pageEnd) {
                    start = lineStart(containing: r.lowerBound, in: text)
                    if start < from { start = from }
                }
                cursor = start
                heads.append(Heading(start: start, line: lineNumber(of: start, lines: lines), level: item.level, title: item.title))
            }
            if !heads.isEmpty { origin = .pdfOutline }
        }
        if heads.isEmpty {
            heads = numberedHeadings(lines)
            if !heads.isEmpty { origin = .pdfHeuristic }
        }
        var out = build(origin: origin, text: text, truncated: truncated, lines: lines, heads: heads, pageStarts: pageStarts)
        out.pageCount = document.pageCount
        return out
    }

    // MARK: - İç

    struct Line { var start: String.Index; var content: Substring }
    struct Heading { var start: String.Index; var line: Int; var level: Int; var title: String }

    static func limit(_ raw: String) -> (String, Bool) {
        raw.count > TextExtractor.maxCharacters ? (String(raw.prefix(TextExtractor.maxCharacters)), true) : (raw, false)
    }

    /// Satırlar; her satırın başlangıç dizini (satır sonu karakterleri içerik dışında).
    static func lines(of text: String) -> [Line] {
        var out: [Line] = []
        var start = text.startIndex
        var i = text.startIndex
        while i < text.endIndex {
            if text[i].isNewline {
                out.append(Line(start: start, content: text[start..<i]))
                start = text.index(after: i)
            }
            i = text.index(after: i)
        }
        out.append(Line(start: start, content: text[start..<text.endIndex]))
        return out
    }

    static func lineStart(containing idx: String.Index, in text: String) -> String.Index {
        var i = idx
        while i > text.startIndex {
            let p = text.index(before: i)
            if text[p].isNewline { break }
            i = p
        }
        return i
    }

    static func lineNumber(of idx: String.Index, lines: [Line]) -> Int {
        var lo = 0, hi = lines.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lines[mid].start <= idx { lo = mid } else { hi = mid - 1 }
        }
        return lo + 1
    }

    static func markdownHeading(_ t: String) -> (level: Int, title: String)? {
        let hashes = t.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = t.dropFirst(hashes)
        guard let first = rest.first, first == " " || first == "\t" else { return nil }
        var title = rest.trimmingCharacters(in: .whitespaces)
        while title.hasSuffix("#") { title.removeLast() }
        title = title.trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : (hashes, title)
    }

    /// "1. Giriş", "2.3 Fesih", "4) Ödeme" — kısa satır, numaradan sonra büyük harfle başlayan başlık.
    static let numbered = try! NSRegularExpression(pattern: #"^(\d{1,3}(?:\.\d{1,3}){0,4})[.)]?\s+(\p{Lu}.{0,118})$"#)

    static func numberedHeadings(_ lines: [Line]) -> [Heading] {
        var heads: [Heading] = []
        for (i, line) in lines.enumerated() {
            let t = line.content.trimmingCharacters(in: .whitespaces)
            guard t.count <= 120, !t.hasSuffix("."), !t.hasSuffix(","), !t.hasSuffix(";") else { continue }
            let ns = t as NSString
            guard let m = numbered.firstMatch(in: t, range: NSRange(location: 0, length: ns.length)) else { continue }
            let number = ns.substring(with: m.range(at: 1))
            let level = number.split(separator: ".").count
            heads.append(Heading(start: line.start, line: i + 1, level: level, title: t))
        }
        return heads
    }

    static func page(of idx: String.Index, starts: [String.Index]) -> Int {
        var p = 0
        for (i, s) in starts.enumerated() where s <= idx { p = i }
        return p + 1
    }

    static func build(origin: Origin, text: String, truncated: Bool, lines: [Line], heads: [Heading],
                      pageStarts: [String.Index]?) -> DocumentOutline {
        let lastLine = lines.count
        func pages(_ a: String.Index, _ b: String.Index) -> (Int?, Int?) {
            guard let ps = pageStarts, !ps.isEmpty else { return (nil, nil) }
            let endIdx = b > a ? text.index(before: b) : a
            return (page(of: a, starts: ps), page(of: endIdx, starts: ps))
        }
        guard !heads.isEmpty else {
            let (sp, ep) = pages(text.startIndex, text.endIndex)
            let root = Section(id: "1", title: L("Belge"), level: 1, startLine: 1, endLine: lastLine,
                               startPage: sp, endPage: ep, text: text, children: [])
            return DocumentOutline(origin: .none, text: text, isTruncated: truncated, pageCount: nil, roots: [root])
        }
        // Düz bölümler (belge sırasıyla), sonra düzeye göre ağaç.
        var flat: [(Section, Int)] = []   // (bölüm, düzey); id sonra verilir
        if heads[0].start > text.startIndex {
            let pre = String(text[text.startIndex..<heads[0].start])
            let (sp, ep) = pages(text.startIndex, heads[0].start)
            flat.append((Section(id: "0", title: L("Belgenin başı"), level: 1, startLine: 1, endLine: max(1, heads[0].line - 1),
                                 startPage: sp, endPage: ep, text: pre, children: []), 0))
        }
        for (k, h) in heads.enumerated() {
            let end = k + 1 < heads.count ? heads[k + 1].start : text.endIndex
            let endLine = k + 1 < heads.count ? max(h.line, heads[k + 1].line - 1) : lastLine
            let (sp, ep) = pages(h.start, end)
            flat.append((Section(id: "", title: h.title, level: h.level, startLine: h.line, endLine: endLine,
                                 startPage: sp, endPage: ep, text: String(text[h.start..<end]), children: []), h.level))
        }
        // Yığınla ağaç kur; atlanan düzeyler (# sonra ###) doğrudan alt bölüm olur.
        var roots: [Section] = []
        var stack: [Section] = []
        func pop() {
            let done = stack.removeLast()
            if stack.isEmpty { roots.append(done) } else { stack[stack.count - 1].children.append(done) }
        }
        for (s, lvl) in flat {
            if lvl == 0 { roots.append(s); continue }
            while let top = stack.last, top.level >= lvl { pop() }
            stack.append(s)
        }
        while !stack.isEmpty { pop() }
        // Kimlik ve görünen düzey: ağaçtaki gerçek konuma göre.
        func number(_ list: inout [Section], prefix: String, depth: Int) {
            var n = 0
            for i in list.indices {
                if list[i].id == "0" { continue }
                n += 1
                list[i].id = prefix.isEmpty ? "\(n)" : "\(prefix).\(n)"
                list[i].level = depth
                number(&list[i].children, prefix: list[i].id, depth: depth + 1)
            }
        }
        number(&roots, prefix: "", depth: 1)
        return DocumentOutline(origin: origin, text: text, isTruncated: truncated, pageCount: nil, roots: roots)
    }
}
