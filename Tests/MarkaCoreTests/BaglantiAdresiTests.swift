import Foundation
import Testing
@testable import MarkaCore

/// U-42: şemasız bağlantı adresi `https://` alır, ad boşsa alan adından dolar; güvenmediği girdi reddedilir.
@Suite struct BaglantiAdresiTests {
    @Test func semasizAdreseHttpsEklenirVeVarOlanSemaKorunur() {
        #expect(LinkAddress.normalize("ornek.com") == "https://ornek.com")
        #expect(LinkAddress.normalize("  www.ornek.com/yol?a=1 ") == "https://www.ornek.com/yol?a=1")
        #expect(LinkAddress.normalize("http://x.com") == "http://x.com")
        #expect(LinkAddress.normalize("HTTPS://ornek.com") == "HTTPS://ornek.com")
        #expect(LinkAddress.normalize("localhost:8080/panel") == "https://localhost:8080/panel")
    }

    @Test func tehlikeliBosluklulVeGecersizAdresReddedilir() {
        for bad in ["javascript:alert(1)", "JavaScript:alert(1)", "data:text/html,x", "file:///etc/passwd", "mailto:a@b.com",
                    "ftp://ornek.com", "orn ek.com", "ornek.com bir şey", "", "   ", "ornek", "http://", "https://", "//ornek.com", "ornek.com\nx"] {
            #expect(LinkAddress.normalize(bad) == nil, "reddedilmeliydi: \(bad)")
        }
    }

    @Test func baglantiAdiBossaAlanAdindanDolar() throws {
        #expect(LinkAddress.suggestedTitle(for: "ornek.com/yol") == "ornek.com")
        #expect(LinkAddress.suggestedTitle(for: "https://www.ornek.com") == "ornek.com")
        #expect(LinkAddress.suggestedTitle(for: "javascript:1") == nil)
        let store = try makeStore()
        let brand = try store.createBrand(name: "Kuzey Lojistik")
        let bos = try store.addLink(brandId: brand.id, title: "  ", address: "ornek.com")
        #expect(bos.title == "ornek.com" && bos.url == "https://ornek.com" && bos.kind == .link)
        let adli = try store.addLink(brandId: brand.id, title: "Sektör raporu", address: "http://x.com/r")
        #expect(adli.title == "Sektör raporu" && adli.url == "http://x.com/r")
        #expect(throws: (any Error).self) { try store.addLink(brandId: brand.id, title: "x", address: "javascript:alert(1)") }
        #expect(try store.sources(brandId: brand.id).count == 2)
    }
}
