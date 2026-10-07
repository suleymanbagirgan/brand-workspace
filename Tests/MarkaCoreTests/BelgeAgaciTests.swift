import Foundation
import PDFKit
import Testing
@testable import MarkaCore

/// E-08: uzun belge içindekiler ağacı. Örnekler uydurmadır (Kuzey Lojistik).
@Suite struct BelgeAgaciTests {
    static let markdown = """
    Kuzey Lojistik hizmet sözleşmesi taslağı.

    # Taraflar
    Kuzey Lojistik ile danışman arasında.
    ## Tanımlar
    Hizmet: aylık içerik.
    ### Teslim
    Her ayın beşinde.
    ## Süre
    On iki ay.
    # Fesih
    Otuz gün önceden yazılı bildirim.
    ```
    # bu bir kod satırı, başlık değil
    ```
    # Ödeme
    Aylık fatura.
    """

    @Test func markdownUcDuzeyBaslikDogruAgacKurar() {
        let o = DocumentOutline.markdown(Self.markdown)
        #expect(o.origin == .markdown)
        #expect(o.roots.map(\.title) == [L("Belgenin başı"), "Taraflar", "Fesih", "Ödeme"])
        let taraflar = o.roots[1]
        #expect(taraflar.id == "1")
        #expect(taraflar.children.map(\.title) == ["Tanımlar", "Süre"])
        #expect(taraflar.children[0].children.map(\.title) == ["Teslim"])
        #expect(o.section(id: "1.1.1")?.title == "Teslim")
        #expect(o.section(id: "1.1.1")?.level == 3)
        #expect(o.section(id: "3")?.title == "Ödeme")
        // Kod bloğundaki "#" başlık sayılmaz; Fesih bölümünün metninde kalır.
        #expect(o.section(id: "2")?.text.contains("bu bir kod satırı") == true)
    }

    @Test func markdownBolumSatirAraligiVeKarakterSayisiDogru() {
        let o = DocumentOutline.markdown(Self.markdown)
        let teslim = o.section(id: "1.1.1")!
        #expect(teslim.startLine == 7)
        #expect(teslim.endLine == 8)
        #expect(teslim.characterCount == "### Teslim\nHer ayın beşinde.\n".count)
        let taraflar = o.section(id: "1")!
        #expect(taraflar.totalCharacterCount == taraflar.characterCount + taraflar.children.reduce(0) { $0 + $1.totalCharacterCount })
        #expect(o.section(id: "0")?.endLine == 2)
    }

    @Test func basliksizMetindeTekKokBolumOlur() {
        let text = "Örnek Kafe Zinciri için kısa not.\nBaşlık yok, yalnız düz metin.\n"
        for o in [DocumentOutline.markdown(text), DocumentOutline.plainText(text)] {
            #expect(o.origin == .none)
            #expect(o.roots.count == 1)
            #expect(o.roots[0].children.isEmpty)
            #expect(o.roots[0].text == text)
            #expect(o.roots[0].startLine == 1)
            #expect(o.roots[0].endLine == 3)
        }
    }

    @Test func bolumMetinleriBirlesinceOzgunMetneEsittirKayipSifir() {
        let numbered = "Kapak\n1. Giriş\nmetin\n1.1 Amaç\nayrıntı\n2. Fesih\nbitiş"
        for o in [DocumentOutline.markdown(Self.markdown), DocumentOutline.plainText(numbered),
                  DocumentOutline.markdown("# Tek\n"), DocumentOutline.markdown("")] {
            #expect(o.flatSections.map(\.text).joined() == o.text)
            #expect(o.flatSections.reduce(0) { $0 + $1.characterCount } == o.text.count)
        }
        let p = DocumentOutline.plainText(numbered)
        #expect(p.origin == .numberedHeadings)
        #expect(p.flatSections.map(\.id) == ["0", "1", "1.1", "2"])
    }

    @Test func numaraliCumleBaslikSayilmaz() {
        let o = DocumentOutline.plainText("2026 yılında Kuzey Lojistik büyüdü.\n3 Kişi katıldı, karar alındı.\n")
        #expect(o.origin == .none)
        #expect(o.roots.count == 1)
    }

    @Test func dortYuzBinKarakterSinirinaUyar() {
        let body = String(repeating: "a", count: 1000) + "\n"
        let text = "# Baş\n" + String(repeating: body, count: 450)
        #expect(text.count > TextExtractor.maxCharacters)
        let o = DocumentOutline.markdown(text)
        #expect(o.isTruncated)
        #expect(o.text.count == TextExtractor.maxCharacters)
        #expect(o.flatSections.reduce(0) { $0 + $1.characterCount } == TextExtractor.maxCharacters)
        #expect(o.flatSections.map(\.text).joined() == String(text.prefix(TextExtractor.maxCharacters)))
        #expect(!DocumentOutline.markdown("# Kısa\n").isTruncated)
    }

    // MARK: - PDF (ReportPDF ile üretilir)

    static func samplePDF() -> Data {
        let intro = """
        1. Giriş
        Kuzey Lojistik için hazırlanan teklif metni
        2. Kapsam
        Aylık içerik ve raporlama
        2.1 Teslim
        Her ayın beşinde teslim
        3. Ödeme
        Aylık fatura ile
        """
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let content = ReportContent(brandName: "Kuzey Lojistik", title: "Hizmet teklifi", periodStart: start,
                                    periodEnd: start.addingTimeInterval(86_400 * 7), intro: intro, summary: [],
                                    sections: [], warnings: [], totalSeconds: 0)
        return ReportPDFRenderer(content: content, isDraft: false, versionNumber: 1, describe: { _ in nil }).render()
    }

    @Test func anaHatsizPdfteNumaraliBaslikSezgisiCalisir() throws {
        let doc = try #require(PDFDocument(data: Self.samplePDF()))
        #expect(doc.outlineRoot == nil)
        let o = DocumentOutline.pdf(doc)
        #expect(o.origin == .pdfHeuristic)
        #expect(o.pageCount == doc.pageCount)
        let titles = o.flatSections.map(\.title)
        #expect(titles.contains("1. Giriş"))
        #expect(titles.contains("2.1 Teslim"))
        #expect(o.section(id: "2.1")?.title == "2.1 Teslim")
        #expect(o.section(id: "3")?.startPage == 1)
        #expect(o.flatSections.map(\.text).joined() == o.text)
    }

    @Test func anaHatliPdfteAnaHatKullanilir() throws {
        let doc = try #require(PDFDocument(data: Self.samplePDF()))
        let page = try #require(doc.page(at: 0))
        let root = PDFOutline()
        for (i, label) in ["Giriş", "Kapsam"].enumerated() {
            let item = PDFOutline()
            item.label = label
            item.destination = PDFDestination(page: page, at: .zero)
            root.insertChild(item, at: i)
        }
        let child = PDFOutline()
        child.label = "Teslim"
        child.destination = PDFDestination(page: page, at: .zero)
        root.child(at: 1)?.insertChild(child, at: 0)
        doc.outlineRoot = root

        let o = DocumentOutline.pdf(doc)
        #expect(o.origin == .pdfOutline)
        #expect(o.roots.filter { $0.id != "0" }.map(\.title) == ["Giriş", "Kapsam"])
        #expect(o.section(id: "2.1")?.title == "Teslim")
        #expect(o.section(id: "2.1")?.startPage == 1)
        // Ana hat başlığı sayfa metninde bulunur: bölüm o satırdan başlar.
        #expect(o.section(id: "2")?.text.contains("Kapsam") == true)
        #expect(o.section(id: "1")?.text.contains("Kapsam") == false)
        #expect(o.flatSections.map(\.text).joined() == o.text)
    }

    @Test func gecersizPdfVerisiNilDoner() {
        #expect(DocumentOutline.pdf(data: Data("pdf değil".utf8)) == nil)
    }
}
