import AppKit
import Foundation
import Testing
@testable import MarkaCore

/// E-19: biçimli Markdown çıkarımı (docx/rtf/html). Test belgeleri testte kodla üretilir; ikili fixture yoktur.
/// Örnek içerik uydurmadır (Kuzey Lojistik).
@Suite struct MarkdownCikarimTests {

    // MARK: - Belge üreticileri

    /// Başlık (24/18/14 kalın), madde ve numaralı liste, 2×3 tablo ve gövde paragrafları taşıyan öznitelikli metin.
    static func ornekBelge() -> NSAttributedString {
        let m = NSMutableAttributedString()
        let govde = NSFont(name: "Helvetica", size: 12)!
        func kalin(_ size: CGFloat) -> NSFont { NSFont(name: "Helvetica-Bold", size: size)! }
        func ekle(_ s: String, _ font: NSFont, _ style: NSParagraphStyle? = nil) {
            var attrs: [NSAttributedString.Key: Any] = [.font: font]
            if let style { attrs[.paragraphStyle] = style }
            m.append(NSAttributedString(string: s + "\n", attributes: attrs))
        }
        func listeStili(_ list: NSTextList) -> NSParagraphStyle {
            let p = NSMutableParagraphStyle(); p.textLists = [list]; return p
        }
        ekle("Ana Başlık", kalin(24))
        ekle("Kuzey Lojistik için hazırlanan aylık içerik planı giriş metni.", govde)
        ekle("Alt Bölüm", kalin(18))
        let madde = NSTextList(markerFormat: .disc, options: 0)
        for s in ["Elma kasası", "Armut kasası"] { ekle("\t\(madde.marker(forItemNumber: 1))\t\(s)", govde, listeStili(madde)) }
        let numara = NSTextList(markerFormat: .decimal, options: 0)
        for (i, s) in ["Birinci adım", "İkinci adım"].enumerated() {
            ekle("\t\(numara.marker(forItemNumber: i + 1))\t\(s)", govde, listeStili(numara))
        }
        ekle("Tablodan önce açıklama.", govde)
        let tablo = NSTextTable(); tablo.numberOfColumns = 3
        for (r, satir) in [["Ürün", "Adet", "Fiyat"], ["Kalem", "3", "45"]].enumerated() {
            for (c, hucre) in satir.enumerated() {
                let blok = NSTextTableBlock(table: tablo, startingRow: r, rowSpan: 1, startingColumn: c, columnSpan: 1)
                let p = NSMutableParagraphStyle(); p.textBlocks = [blok]
                ekle(hucre, r == 0 ? kalin(12) : govde, p)
            }
        }
        ekle("Üçüncü Düzey", kalin(14))
        ekle("#etiket ile başlayan gövde satırı başlık değildir.", govde)
        ekle("Son paragraf teslim tarihini anlatır.", govde)
        return m
    }

    static func veri(_ a: NSAttributedString, _ type: NSAttributedString.DocumentType) throws -> Data {
        try a.data(from: NSRange(location: 0, length: a.length), documentAttributes: [.documentType: type])
    }

    static let ornekHTML = """
    <html><head><title>Kuzey Lojistik</title></head><body>
    <h1>Ana Başlık</h1><p>Kuzey Lojistik için hazırlanan aylık içerik planı giriş metni.</p>
    <h2>Alt Bölüm</h2><ul><li>Elma kasası</li><li>Armut kasası</li></ul>
    <ol><li>Birinci adım</li><li>İkinci adım</li></ol>
    <table><tr><th>Ürün</th><th>Adet</th><th>Fiyat</th></tr><tr><td>Kalem</td><td>3</td><td>45</td></tr></table>
    <h3>Üçüncü Düzey</h3><p>Son paragraf teslim tarihini anlatır.</p></body></html>
    """

    /// Word'ün yazdığı yapıda en küçük docx: `numPr` madde listesi, `w:tbl` tablo, başlıklar hem stil hem doğrudan biçimle.
    /// `dogrudanBicim: false` yalnız stil tabanlı başlık üretir (Apple okuyucusunun sınırını ölçmek için).
    static func wordBenzeriDocx(dogrudanBicim: Bool = true) -> Data {
        func p(_ ppr: String, _ text: String, rpr: String = "") -> String {
            "<w:p><w:pPr>\(ppr)</w:pPr><w:r>\(rpr.isEmpty ? "" : "<w:rPr>\(rpr)</w:rPr>")<w:t>\(text)</w:t></w:r></w:p>"
        }
        func baslik(_ duzey: Int, _ text: String, sz: Int) -> String {
            p("<w:pStyle w:val=\"Heading\(duzey)\"/>", text, rpr: dogrudanBicim ? "<w:b/><w:sz w:val=\"\(sz)\"/>" : "")
        }
        func hucre(_ t: String) -> String { "<w:tc><w:p><w:r><w:t>\(t)</w:t></w:r></w:p></w:tc>" }
        let madde = "<w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"1\"/></w:numPr>"
        let govde = [
            baslik(1, "Ana Başlık", sz: 48), p("", "Kuzey Lojistik için hazırlanan aylık içerik planı giriş metni."),
            baslik(2, "Alt Bölüm", sz: 36), p(madde, "Elma kasası"), p(madde, "Armut kasası"),
            "<w:tbl><w:tblGrid><w:gridCol/><w:gridCol/><w:gridCol/></w:tblGrid><w:tr>\(hucre("Ürün"))\(hucre("Adet"))\(hucre("Fiyat"))</w:tr>"
                + "<w:tr>\(hucre("Kalem"))\(hucre("3"))\(hucre("45"))</w:tr></w:tbl>",
            baslik(3, "Üçüncü Düzey", sz: 28), p("", "Son paragraf teslim tarihini anlatır."),
        ].joined()
        let w = "xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\""
        let bas = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        let rel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        let stiller = (1...3).map { d in
            "<w:style w:type=\"paragraph\" w:styleId=\"Heading\(d)\"><w:name w:val=\"heading \(d)\"/><w:pPr><w:outlineLvl w:val=\"\(d - 1)\"/></w:pPr><w:rPr><w:b/><w:sz w:val=\"\(48 - d * 8)\"/></w:rPr></w:style>"
        }.joined()
        let parcalar: [(String, String)] = [
            ("[Content_Types].xml", bas + "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/><Override PartName=\"/word/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml\"/><Override PartName=\"/word/numbering.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml\"/></Types>"),
            ("_rels/.rels", bas + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"\(rel)/officeDocument\" Target=\"word/document.xml\"/></Relationships>"),
            ("word/_rels/document.xml.rels", bas + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"\(rel)/styles\" Target=\"styles.xml\"/><Relationship Id=\"rId2\" Type=\"\(rel)/numbering\" Target=\"numbering.xml\"/></Relationships>"),
            ("word/styles.xml", bas + "<w:styles \(w)>\(stiller)</w:styles>"),
            ("word/numbering.xml", bas + "<w:numbering \(w)><w:abstractNum w:abstractNumId=\"0\"><w:lvl w:ilvl=\"0\"><w:start w:val=\"1\"/><w:numFmt w:val=\"bullet\"/><w:lvlText w:val=\"•\"/></w:lvl></w:abstractNum><w:num w:numId=\"1\"><w:abstractNumId w:val=\"0\"/></w:num></w:numbering>"),
            ("word/document.xml", bas + "<w:document \(w)><w:body>\(govde)<w:sectPr/></w:body></w:document>"),
        ]
        return SikistirmasizZip.yap(parcalar.map { ($0.0, Data($0.1.utf8)) })
    }

    static func kelimeler(_ s: String) -> [String: Int] {
        var sayac: [String: Int] = [:]
        for k in s.components(separatedBy: CharacterSet.alphanumerics.inverted) where !k.isEmpty { sayac[k, default: 0] += 1 }
        return sayac
    }

    static func gecici(_ data: Data, uzanti: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("markdown-cikarim-\(UUID().uuidString).\(uzanti)")
        try data.write(to: url)
        return url
    }

    // MARK: - Başlık düzeyleri

    @Test func docxBaslikDuzeyleriMarkdownBasliginaCevrilir() throws {
        // Word yapısında docx (doğrudan biçimli başlık) ve Apple yazıcısının ürettiği docx.
        let word = MarkdownExtractor.markdown(data: Self.wordBenzeriDocx(), format: .docx)
        let apple = MarkdownExtractor.markdown(data: try Self.veri(Self.ornekBelge(), .officeOpenXML), format: .docx)
        for md in [word, apple] {
            let satirlar = md.components(separatedBy: "\n")
            #expect(satirlar.contains("# Ana Başlık"), "\(md)")
            #expect(satirlar.contains("## Alt Bölüm"), "\(md)")
            #expect(satirlar.contains("### Üçüncü Düzey"), "\(md)")
            #expect(!satirlar.contains { $0.hasPrefix("#") && $0.contains("giriş metni") })
        }
    }

    @Test func rtfVeHtmlBaslikDuzeyleriKorunur() async throws {
        let rtf = MarkdownExtractor.markdown(data: try Self.veri(Self.ornekBelge(), .rtf), format: .rtf)
        let html = await MarkdownExtractor.markdown(html: Data(Self.ornekHTML.utf8))
        for md in [rtf, html] {
            let satirlar = md.components(separatedBy: "\n")
            #expect(satirlar.contains("# Ana Başlık"), "\(md)")
            #expect(satirlar.contains("## Alt Bölüm"), "\(md)")
            #expect(satirlar.contains("### Üçüncü Düzey"), "\(md)")
        }
    }

    // MARK: - Listeler

    @Test func maddeVeNumaraliListeKorunur() async throws {
        let rtf = MarkdownExtractor.markdown(data: try Self.veri(Self.ornekBelge(), .rtf), format: .rtf)
        let appleDocx = MarkdownExtractor.markdown(data: try Self.veri(Self.ornekBelge(), .officeOpenXML), format: .docx)
        let html = await MarkdownExtractor.markdown(html: Data(Self.ornekHTML.utf8))
        for md in [rtf, appleDocx, html] {
            #expect(md.contains("- Elma kasası\n- Armut kasası"), "\(md)")
            #expect(md.contains("1. Birinci adım\n2. İkinci adım"), "\(md)")
        }
        // Word yapısındaki numPr madde listesi.
        let word = MarkdownExtractor.markdown(data: Self.wordBenzeriDocx(), format: .docx)
        #expect(word.contains("- Elma kasası\n- Armut kasası"), "\(word)")
    }

    @Test func icIceListeGirintiliYazilir() {
        let m = NSMutableAttributedString()
        let dis = NSTextList(markerFormat: .decimal, options: 0)
        let ic = NSTextList(markerFormat: .hyphen, options: 0)
        func ekle(_ s: String, _ lists: [NSTextList]) {
            let p = NSMutableParagraphStyle(); p.textLists = lists
            m.append(NSAttributedString(string: s + "\n", attributes: [.paragraphStyle: p, .font: NSFont(name: "Helvetica", size: 12)!]))
        }
        ekle("\t1.\tPlan", [dis]); ekle("\t-\tTaslak", [dis, ic]); ekle("\t2.\tYayın", [dis])
        #expect(MarkdownExtractor.markdown(attributed: m) == "1. Plan\n   - Taslak\n2. Yayın")
    }

    // MARK: - Tablo

    @Test func ikiyeUcTabloMarkdownTablosunaCevrilir() async throws {
        let beklenen = "| Ürün | Adet | Fiyat |\n| --- | --- | --- |\n| Kalem | 3 | 45 |"
        let rtf = MarkdownExtractor.markdown(data: try Self.veri(Self.ornekBelge(), .rtf), format: .rtf)
        let word = MarkdownExtractor.markdown(data: Self.wordBenzeriDocx(), format: .docx)
        let html = await MarkdownExtractor.markdown(html: Data(Self.ornekHTML.utf8))
        for md in [rtf, word, html] { #expect(md.contains(beklenen), "\(md)") }
    }

    // MARK: - Kayıp yok

    @Test func duzMetinKelimeleriTextExtractorIleAyniKayipSifir() throws {
        let kaynaklar: [(Data, String, MarkdownExtractor.Format)] = [
            (try Self.veri(Self.ornekBelge(), .rtf), "rtf", .rtf),
            (try Self.veri(Self.ornekBelge(), .officeOpenXML), "docx", .docx),
            (Self.wordBenzeriDocx(), "docx", .docx),
        ]
        for (data, uzanti, bicim) in kaynaklar {
            let url = try Self.gecici(data, uzanti: uzanti)
            defer { try? FileManager.default.removeItem(at: url) }
            let duz = Self.kelimeler(TextExtractor.extract(from: url))
            let md = Self.kelimeler(MarkdownExtractor.markdown(data: data, format: bicim))
            #expect(!duz.isEmpty)
            let kayip = duz.filter { (md[$0.key] ?? 0) < $0.value }
            #expect(kayip.isEmpty, "kayıp kelime (\(uzanti)): \(kayip)")
        }
    }

    // MARK: - Sınır ve bozuk dosya

    @Test func ciktiDortYuzBinKarakterleSinirli() throws {
        let m = NSMutableAttributedString()
        let font = NSFont(name: "Helvetica", size: 12)!
        let satir = "Kuzey Lojistik aylık rapor satırı, teslim ve ölçüm notu içerir.\n"
        for i in 0..<9_000 { m.append(NSAttributedString(string: "\(i) " + satir, attributes: [.font: font])) }
        #expect(m.length > 500_000)
        let md = MarkdownExtractor.markdown(data: try Self.veri(m, .rtf), format: .rtf)
        #expect(md.count == TextExtractor.maxCharacters)
        #expect(MarkdownExtractor.maxCharacters == 400_000)
    }

    @Test func bozukDosyadaBosSonucVeCokmeYok() async throws {
        var rastgele = SystemRandomNumberGenerator()
        let gurultu = Data((0..<4096).map { _ in UInt8.random(in: 0...255, using: &rastgele) })
        let docx = Self.wordBenzeriDocx()
        let yarim = docx.prefix(docx.count / 2)
        for (data, bicim) in [(Data(), MarkdownExtractor.Format.docx), (Data(), .rtf), (gurultu, .docx), (Data(yarim), .docx),
                              (Data("PK\u{3}\u{4}bozuk".utf8), .docx), (gurultu, .rtf)] {
            #expect(MarkdownExtractor.markdown(data: data, format: bicim) == "", "\(bicim) \(data.count)")
        }
        // Başı geçerli, sonu bozuk RTF: Apple okuyucusu okunabilen kısmı verir (TextExtractor ile aynı); çökme yok.
        _ = MarkdownExtractor.markdown(data: Data("{\\rtf1 kapanmamış".utf8) + gurultu, format: .rtf)
        #expect(await MarkdownExtractor.markdown(html: Data()) == "")
        _ = await MarkdownExtractor.markdown(html: gurultu)   // çökmez; içerik anlamsız olabilir
        // Var olmayan dosya ve desteklenmeyen uzantı.
        let yok = FileManager.default.temporaryDirectory.appendingPathComponent("yok-\(UUID().uuidString).docx")
        #expect(await MarkdownExtractor.markdown(from: yok) == "")
        let pptx = try Self.gecici(Data("x".utf8), uzanti: "pptx")
        defer { try? FileManager.default.removeItem(at: pptx) }
        #expect(await MarkdownExtractor.markdown(from: pptx) == "")
    }

    // MARK: - E-08 içindekiler ağacıyla uyum

    @Test func icindekilerAgaciDocxRtfHtmlCiktisiylaKurulur() async throws {
        let docx = try Self.gecici(Self.wordBenzeriDocx(), uzanti: "docx")
        let rtf = try Self.gecici(try Self.veri(Self.ornekBelge(), .rtf), uzanti: "rtf")
        let html = try Self.gecici(Data(Self.ornekHTML.utf8), uzanti: "html")
        defer { [docx, rtf, html].forEach { try? FileManager.default.removeItem(at: $0) } }
        for url in [docx, rtf, html] {
            let o = DocumentOutline.markdown(await MarkdownExtractor.markdown(from: url))
            #expect(o.origin == .markdown, "\(url.pathExtension)")
            #expect(o.flatSections.map(\.title) == ["Ana Başlık", "Alt Bölüm", "Üçüncü Düzey"], "\(url.pathExtension)")
            #expect(o.flatSections.map(\.level) == [1, 2, 3])
            #expect(o.roots.count == 1 && o.roots[0].children.first?.children.first?.title == "Üçüncü Düzey")
            #expect(o.flatSections.map(\.text).joined() == o.text)   // kayıp yok
        }
    }

    @Test func diyezleBaslayanGovdeSatiriBaslikSayilmaz() throws {
        let md = MarkdownExtractor.markdown(data: try Self.veri(Self.ornekBelge(), .rtf), format: .rtf)
        #expect(md.contains("\\#etiket ile başlayan"))
        #expect(!DocumentOutline.markdown(md).flatSections.contains { $0.title.contains("etiket") })
    }

    /// Bilinen sınır (ölçüm): Apple docx okuyucusu `styles.xml`'i uygulamaz; yalnız stil tabanlı başlık düz paragraf
    /// olarak gelir. Metin kaybolmaz.
    @Test func yalnizStilTabanliWordBasligindaMetinKaybolmaz() {
        let md = MarkdownExtractor.markdown(data: Self.wordBenzeriDocx(dogrudanBicim: false), format: .docx)
        for kelime in ["Ana Başlık", "Alt Bölüm", "Üçüncü Düzey", "Elma kasası", "Kalem"] { #expect(md.contains(kelime)) }
    }

    // MARK: - Ağ erişimi yok

    static func uzakKaynakliHTML(_ port: UInt16) -> String {
        let u = "http://127.0.0.1:\(port)"
        return """
        <!DOCTYPE html><html><head><base href="\(u)/"><link rel="stylesheet" href="\(u)/a.css">
        <link rel="preload" href="\(u)/b.js"><meta http-equiv="refresh" content="0;url=\(u)/c">
        <style>@import url("\(u)/d.css"); body { background: url(\(u)/e.png) }</style><script src="\(u)/f.js"></script></head>
        <body background="\(u)/g.png"><h1>Ana Başlık</h1><p style="background-image:url('\(u)/h.png')">Giriş metni.</p>
        <img src="\(u)/i.png" srcset="\(u)/j.png 2x"><iframe src="\(u)/k.html"></iframe><video poster="\(u)/l.png" src="\(u)/m.mp4"></video>
        <object data="\(u)/n.svg"></object><embed src="\(u)/o.swf"><audio src="\(u)/p.mp3"><source src="\(u)/q.ogg"></audio>
        <svg><image href="\(u)/r.png"/></svg><input type="image" src="\(u)/s.png"><table background="\(u)/t.png"><tr><td>Hücre</td></tr></table>
        <p>Son söz.</p></body></html>
        """
    }

    @Test func htmlSuzgeciUzakKaynakTasiyanHerSeyiSiler() {
        let temiz = MarkdownExtractor.sanitizedHTML(Self.uzakKaynakliHTML(8))
        #expect(!temiz.contains("127.0.0.1"), "\(temiz)")
        #expect(!temiz.lowercased().contains("url("))
        #expect(temiz.contains("Giriş metni.") && temiz.contains("Hücre") && temiz.contains("<h1>Ana Başlık</h1>"))
        // Tırnak içindeki `>` etiketi bitirmez; öznitelik kalıntısı metne sızmaz.
        let zor = MarkdownExtractor.sanitizedHTML(#"<p title="a>b" style="background:url(http://127.0.0.1/x)">Metin</p>"#)
        #expect(zor == "<p>Metin</p>")
        #expect(MarkdownExtractor.sanitizedHTML("<td colspan=\"2\" onclick=\"x()\">a</td>") == "<td colspan=\"2\">a</td>")
    }

    @Test @MainActor func htmlIceAktarimdaUzakKaynakIcinAgaCikilmaz() async throws {
        // Duyarlılık: süzgeçsiz içe aktarım aynı dinleyiciye gerçekten bağlanır (ölçüm araç çalışıyor demek).
        let kontrol = try YerelDinleyici()
        _ = MarkdownExtractor.importHTML(Data(Self.uzakKaynakliHTML(kontrol.port).utf8), sanitize: false)
        try await Task.sleep(for: .milliseconds(500))
        let kontrolSayisi = kontrol.durdur()
        #expect(kontrolSayisi > 0, "süzgeçsiz içe aktarım ağa çıkmadı; ölçüm duyarsız")

        let dinleyici = try YerelDinleyici()
        let md = MarkdownExtractor.markdown(html: Data(Self.uzakKaynakliHTML(dinleyici.port).utf8))
        try await Task.sleep(for: .milliseconds(1500))
        #expect(dinleyici.durdur() == 0)
        #expect(md.contains("# Ana Başlık") && md.contains("Giriş metni.") && md.contains("Hücre"), "\(md)")
    }
}

// MARK: - Yardımcılar

/// Sıkıştırmasız (stored) ZIP yazıcısı: docx'i testte kodla üretmek için. CRC-32 elle hesaplanır.
enum SikistirmasizZip {
    static let tablo: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ d: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in d { c = tablo[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }

    static func yap(_ dosyalar: [(String, Data)]) -> Data {
        var out = Data(), merkez = Data()
        func u16(_ v: Int, _ d: inout Data) { d.append(contentsOf: [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)]) }
        func u32(_ v: UInt32, _ d: inout Data) { for i in 0..<4 { d.append(UInt8((v >> (8 * UInt32(i))) & 0xFF)) } }
        for (ad, veri) in dosyalar {
            let adVeri = Data(ad.utf8), crc = crc32(veri), ofset = UInt32(out.count)
            u32(0x0403_4B50, &out); u16(20, &out); u16(0, &out); u16(0, &out); u16(0, &out); u16(0x21, &out)
            u32(crc, &out); u32(UInt32(veri.count), &out); u32(UInt32(veri.count), &out); u16(adVeri.count, &out); u16(0, &out)
            out.append(adVeri); out.append(veri)
            u32(0x0201_4B50, &merkez); u16(20, &merkez); u16(20, &merkez); u16(0, &merkez); u16(0, &merkez); u16(0, &merkez)
            u16(0x21, &merkez); u32(crc, &merkez); u32(UInt32(veri.count), &merkez); u32(UInt32(veri.count), &merkez)
            u16(adVeri.count, &merkez); u16(0, &merkez); u16(0, &merkez); u16(0, &merkez); u16(0, &merkez); u32(0, &merkez)
            u32(ofset, &merkez); merkez.append(adVeri)
        }
        let merkezOfset = UInt32(out.count)
        out.append(merkez)
        u32(0x0605_4B50, &out); u16(0, &out); u16(0, &out); u16(dosyalar.count, &out); u16(dosyalar.count, &out)
        u32(UInt32(merkez.count), &out); u32(merkezOfset, &out); u16(0, &out)
        return out
    }
}

/// 127.0.0.1'de geçici TCP dinleyicisi: gelen bağlantıları sayar ve hemen kapatır (yanıt vermez). Dış ağa çıkmaz.
final class YerelDinleyici: @unchecked Sendable {
    let port: UInt16
    private let fd: Int32
    private let kilit = NSLock()
    private var sayi = 0
    private var calisiyor = true
    private let bitti = DispatchSemaphore(value: 0)

    struct Hata: Error {}

    init() throws {
        let s = socket(AF_INET, SOCK_STREAM, 0)
        guard s >= 0 else { throw Hata() }
        var adres = sockaddr_in()
        adres.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        adres.sin_family = sa_family_t(AF_INET)
        adres.sin_addr.s_addr = inet_addr("127.0.0.1")
        adres.sin_port = 0
        let bagla = withUnsafePointer(to: &adres) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bagla == 0, listen(s, 32) == 0 else { close(s); throw Hata() }
        var uzunluk = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &adres) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(s, $0, &uzunluk) }
        }
        port = UInt16(bigEndian: adres.sin_port)
        fd = s
        Thread.detachNewThread { [self] in dongu() }
    }

    private func dongu() {
        while kilit.withLock({ calisiyor }) {
            var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            if poll(&p, 1, 50) > 0 {
                let c = accept(fd, nil, nil)
                if c >= 0 { kilit.withLock { sayi += 1 }; close(c) }
            }
        }
        bitti.signal()
    }

    /// Dinlemeyi bitirir; gelen bağlantı sayısını döndürür.
    func durdur() -> Int {
        kilit.withLock { calisiyor = false }
        bitti.wait()
        close(fd)
        return kilit.withLock { sayi }
    }
}
