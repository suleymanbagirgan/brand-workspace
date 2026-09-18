import AppKit
import CoreText
import Foundation
import GRDB

public struct RefDescription: Sendable, Hashable {
    public var ref: RecordRef
    public var label: String
    public var date: Date?
}

extension Store {
    /// Bir referansın okunabilir açıklaması (rapor ekleri ve bağlantı listeleri için).
    public func describe(_ ref: RecordRef) throws -> RefDescription {
        try read { db in
            switch ref.kind {
            case .task:
                let t = try WorkTask.fetchOne(db, key: ref.id)
                return RefDescription(ref: ref, label: LF("Görev: %@", t?.title ?? "—"), date: t?.completedAt ?? t?.createdAt)
            case .source:
                let s = try Source.fetchOne(db, key: ref.id)
                return RefDescription(ref: ref, label: LF("Kaynak: %@", s?.title ?? "—"), date: s?.capturedAt)
            case .workLog:
                let l = try WorkLog.fetchOne(db, key: ref.id)
                let who = l?.verifiedBy.map { LF(" (doğrulayan: %@)", $0) } ?? ""
                return RefDescription(ref: ref, label: LF("Çalışma kaydı: %@", l?.title ?? "—") + who, date: l?.occurredAt)
            case .brandRecord:
                let r = try BrandRecord.fetchOne(db, key: ref.id)
                return RefDescription(ref: ref, label: LF("Marka kaydı: %@", r?.title ?? "—"), date: r?.createdAt)
            case .wikiPage:
                let p = try WikiPage.fetchOne(db, key: ref.id)
                return RefDescription(ref: ref, label: LF("Bilgi sayfası: %@", p?.title ?? "—"), date: p?.updatedAt)
            case .timeEntry:
                let e = try TimeEntry.fetchOne(db, key: ref.id)
                return RefDescription(ref: ref, label: LF("Süre kaydı: %@", DurationFormat.short(e?.seconds ?? 0)), date: e?.startedAt)
            case .report:
                return RefDescription(ref: ref, label: L("Rapor"), date: nil)
            }
        }
    }
}

public enum ReportSectionTitles {
    public static func title(_ kind: ReportSectionKind) -> String {
        switch kind {
        case .completedWork: L("Yapılan işler")
        case .deliverables: L("Teslim edilen çıktılar")
        case .openIssues: L("Açık konular")
        case .awaitingClient: L("Müşteri kararı bekleyenler")
        case .timeSpent: L("Harcanan süre")
        case .nextSteps: L("Sıradaki adımlar")
        }
    }
}

/// CoreText ile çok sayfalı A4 PDF üretir. Harici bağımlılık yok.
public struct ReportPDFRenderer {
    public var content: ReportContent
    public var isDraft: Bool
    public var versionNumber: Int
    public var describe: (RecordRef) -> RefDescription?

    public init(content: ReportContent, isDraft: Bool, versionNumber: Int, describe: @escaping (RecordRef) -> RefDescription?) {
        self.content = content; self.isDraft = isDraft; self.versionNumber = versionNumber; self.describe = describe
    }

    static let page = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
    static let margin: CGFloat = 56

    func attributed() -> NSAttributedString {
        let out = NSMutableAttributedString()
        let body = NSFont.systemFont(ofSize: 10.5)
        let para = NSMutableParagraphStyle()
        para.paragraphSpacing = 4
        para.lineHeightMultiple = 1.15
        let bullet = NSMutableParagraphStyle()
        bullet.paragraphSpacing = 3
        bullet.lineHeightMultiple = 1.15
        bullet.headIndent = 14
        bullet.firstLineHeadIndent = 0
        bullet.tabStops = [NSTextTab(textAlignment: .left, location: 14)]
        let ink = NSColor(calibratedWhite: 0.1, alpha: 1)
        let muted = NSColor(calibratedWhite: 0.42, alpha: 1)
        func add(_ s: String, _ attrs: [NSAttributedString.Key: Any]) { out.append(NSAttributedString(string: s, attributes: attrs)) }

        let dateFmt = DateFormatter()
        dateFmt.locale = Locale.current
        dateFmt.dateStyle = .medium
        add(content.title + "\n", [.font: NSFont.systemFont(ofSize: 17, weight: .semibold), .foregroundColor: ink, .paragraphStyle: para])
        let status = isDraft ? L("TASLAK — onaylanmadı") : L("Onaylandı")
        add(LF("Sürüm %1$d · %2$@ · Oluşturma: %3$@", versionNumber, status, dateFmt.string(from: Date())) + "\n\n",
            [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: isDraft ? NSColor.systemRed : muted, .paragraphStyle: para])

        if !content.intro.trimmed.isEmpty {
            add(content.intro.trimmed + "\n\n", [.font: body, .foregroundColor: ink, .paragraphStyle: para])
        }

        var refNumbers: [RecordRef: Int] = [:]
        var ordered: [RecordRef] = []
        func marks(_ refs: [RecordRef]) -> String {
            let nums = refs.map { r -> Int in
                if let n = refNumbers[r] { return n }
                ordered.append(r)
                refNumbers[r] = ordered.count
                return ordered.count
            }
            return nums.map { "[\($0)]" }.joined()
        }
        let itemsById = Dictionary(uniqueKeysWithValues: content.sections.flatMap(\.items).map { ($0.id, $0) })

        if !content.summary.isEmpty {
            add(L("Özet") + "\n", [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: ink, .paragraphStyle: para])
            for s in content.summary {
                let refs = s.itemIds.compactMap { itemsById[$0] }.flatMap(\.refs)
                add(s.text + " ", [.font: body, .foregroundColor: ink, .paragraphStyle: para])
                add(marks(refs) + "\n", [.font: NSFont.systemFont(ofSize: 7.5), .foregroundColor: muted, .baselineOffset: 3, .paragraphStyle: para])
            }
            add("\n", [.font: body])
        }

        for section in content.sections {
            add(ReportSectionTitles.title(section.kind) + "\n", [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: ink, .paragraphStyle: para])
            if section.kind == .timeSpent {
                add(LF("Toplam: %@", DurationFormat.short(content.totalSeconds)) + "\n", [.font: body, .foregroundColor: muted, .paragraphStyle: para])
            }
            if section.items.isEmpty {
                add(L("Bu dönemde kayıt yok.") + "\n\n", [.font: body, .foregroundColor: muted, .paragraphStyle: para])
                continue
            }
            for item in section.items {
                add("•\t" + item.text + " ", [.font: body, .foregroundColor: ink, .paragraphStyle: bullet])
                add(marks(item.refs) + "\n", [.font: NSFont.systemFont(ofSize: 7.5), .foregroundColor: muted, .baselineOffset: 3, .paragraphStyle: bullet])
            }
            add("\n", [.font: body])
        }

        add(L("Dayanak kayıtlar") + "\n", [.font: NSFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: muted, .paragraphStyle: para])
        let small = NSFont.systemFont(ofSize: 8)
        for (i, ref) in ordered.enumerated() {
            let d = describe(ref)
            let date = d?.date.map { " · " + dateFmt.string(from: $0) } ?? ""
            add("[\(i + 1)] \(d?.label ?? ref.id)\(date)\n", [.font: small, .foregroundColor: muted, .paragraphStyle: para])
        }
        return out
    }

    public func render() -> Data {
        let data = NSMutableData()
        var box = Self.page
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, [kCGPDFContextTitle: content.title] as CFDictionary) else { return Data() }
        let text = attributed()
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let frameRect = Self.page.insetBy(dx: Self.margin, dy: Self.margin)
        var location = 0
        var pageNo = 1
        repeat {
            ctx.beginPDFPage(nil)
            let path = CGPath(rect: frameRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
            CTFrameDraw(frame, ctx)
            let range = CTFrameGetVisibleStringRange(frame)
            drawFooter(ctx, pageNo: pageNo)
            if isDraft { drawWatermark(ctx) }
            ctx.endPDFPage()
            location += range.length
            pageNo += 1
            if range.length == 0 { break }
        } while location < text.length
        ctx.closePDF()
        return data as Data
    }

    private func drawFooter(_ ctx: CGContext, pageNo: Int) {
        let footer = NSAttributedString(string: "\(content.brandName) · \(pageNo)",
                                        attributes: [.font: NSFont.systemFont(ofSize: 8), .foregroundColor: NSColor(calibratedWhite: 0.5, alpha: 1)])
        let line = CTLineCreateWithAttributedString(footer)
        ctx.textPosition = CGPoint(x: Self.margin, y: 28)
        CTLineDraw(line, ctx)
    }

    private func drawWatermark(_ ctx: CGContext) {
        let mark = NSAttributedString(string: L("TASLAK"), attributes: [.font: NSFont.systemFont(ofSize: 90, weight: .bold),
                                                                         .foregroundColor: NSColor(calibratedRed: 0.8, green: 0.1, blue: 0.1, alpha: 0.08)])
        let line = CTLineCreateWithAttributedString(mark)
        ctx.saveGState()
        ctx.translateBy(x: Self.page.midX, y: Self.page.midY)
        ctx.rotate(by: .pi / 5)
        let bounds = CTLineGetBoundsWithOptions(line, [])
        ctx.textPosition = CGPoint(x: -bounds.width / 2, y: -bounds.height / 2)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}
