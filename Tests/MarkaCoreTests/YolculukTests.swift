import Foundation
import Testing
@testable import MarkaCore

/// E-09: yolculuk betikleri. Kayıtlar `Tests/Fixtures/yolculuk/*.json`; sahte sağlayıcıyla çekirdek düzeyinde oynatılır.
/// Bu testler arayüz tıklaması içermez; bir ARAYÜZ testi olarak sunulmaz.
@Suite struct YolculukTests {
    static let klasor = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/yolculuk")

    static func hepsi() throws -> [Yolculuk] { try YolculukKosucu.yukleKlasor(klasor) }

    static func bul(_ ad: String) throws -> Yolculuk {
        try #require(try hepsi().first { $0.ad == ad }, "kayıt yok: \(ad)")
    }

    @Test func enAzBesYolculukKaydiVarVeAdlariBenzersiz() throws {
        let h = try Self.hepsi()
        #expect(h.count >= 5)
        #expect(Set(h.map(\.ad)).count == h.count)
        #expect(h.allSatisfy { !$0.adimlar.isEmpty && $0.adimlar.allSatisfy { !$0.ad.isEmpty } })
    }

    @Test func butunYolculuklarYesilKosarVeHerAdimBeklentiTasir() async throws {
        for y in try Self.hepsi() {
            let s = await YolculukKosucu.kos(y)
            #expect(s.gecti, "\(s.ozet)")
            #expect(s.adimlar.count == y.adimlar.count && s.adimlar.allSatisfy(\.gecti))
        }
        // Her yolculukta en az bir adım ölçülür beklenti taşır (yalnız "hata vermedi" sayılmaz).
        for y in try Self.hepsi() { #expect(y.adimlar.contains { $0.bekle != nil }, "\(y.ad)") }
    }

    @Test func ayniKayitlaIkiKosuBireBirAyniAdimCiktisiniVerir() async throws {
        for y in try Self.hepsi() {
            let a = await YolculukKosucu.kos(y)
            let b = await YolculukKosucu.kos(y)
            #expect(a == b, "\(y.ad)")
            #expect(a.adimlar.map(\.cikti) == b.adimlar.map(\.cikti))
            // Çıktı kimlik ya da zaman damgası taşımaz (her koşuda farklı olurdu).
            let metin = a.adimlar.map(\.cikti).joined(separator: "\n")
            #expect(metin.range(of: #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-"#, options: .regularExpression) == nil)
            #expect(metin.range(of: #"\d{4}-\d{2}-\d{2}T"#, options: .regularExpression) == nil)
        }
    }

    @Test func onayUygulanmazsaYolculukOnayAdimindaKirmiziOlurVeAdiYazar() async throws {
        let y = try Self.bul("yeni-marka-gorev-onayla-geri-al-rapor")
        let s = await YolculukKosucu.kos(y, bozulma: .onayUygulanmaz)
        #expect(!s.gecti)
        #expect(s.bozulanAdim == "Öneriyi onayla")
        #expect(s.ozet.contains("«Öneriyi onayla»"))
        #expect(s.neden.contains("uygulanmış öneri") && s.neden.contains("görev sayısı"))
        // Kırılan adımdan sonrası koşulmaz; öncesi yeşil kalır.
        #expect(s.adimlar.last?.ad == "Öneriyi onayla" && s.adimlar.dropLast().allSatisfy(\.gecti))
        print("KASITLI-BOZULMA-CIKTISI: \(s.ozet)")
    }

    @Test func geriAlmaYapilmazsaYolculukGeriAlAdimindaKirmiziOlur() async throws {
        let y = try Self.bul("gorev-erteleme-onayla-geri-al")
        let s = await YolculukKosucu.kos(y, bozulma: .geriAlmaYapilmaz)
        #expect(!s.gecti && s.bozulanAdim == "Ertelemeyi geri al")
        #expect(s.neden.contains("uygulanmış öneri") && s.neden.contains("geri alınan öneri"))
    }

    @Test func kayitDegisincePuanlamaYanlisBeklentiyiYakalar() async throws {
        var y = try Self.bul("oneri-reddedilir-hicbir-sey-yazilmaz")
        let i = try #require(y.adimlar.firstIndex { $0.eylem == .asistan })
        y.adimlar[i].bekle?.bekleyenOneri = 3
        let s = await YolculukKosucu.kos(y)
        #expect(!s.gecti && s.bozulanAdim == y.adimlar[i].ad)
        #expect(s.neden.contains("bekleyen öneri: beklenen 3, gelen 2"))
    }

    @Test func eksikEtiketVeBilinmeyenMarkaAdimHatasiOlarakAdiylaRaporlanir() async {
        let y = Yolculuk(ad: "hatali", aciklama: "", adimlar: [
            Yolculuk.Adim(ad: "Var olmayan markaya kaynak", eylem: .kaynakEkle, marka: "Z", etiket: "x", baslik: "Not")])
        let s = await YolculukKosucu.kos(y)
        #expect(!s.gecti && s.bozulanAdim == "Var olmayan markaya kaynak")
        #expect(s.neden.contains("bilinmeyen marka etiketi: Z"))
    }

    @Test func beklenenHataAdimiBasariliOlursaKirmiziOlur() async {
        let y = Yolculuk(ad: "hata-beklenir", aciklama: "", adimlar: [
            Yolculuk.Adim(ad: "Marka aç", eylem: .markaAc, etiket: "A", baslik: "Deneme Yangın"),
            Yolculuk.Adim(ad: "Hata beklenen ama başarılı", eylem: .gorevEkle, marka: "A", etiket: "g", baslik: "Görev",
                          bekle: .init(hata: true))])
        let s = await YolculukKosucu.kos(y)
        #expect(!s.gecti && s.bozulanAdim == "Hata beklenen ama başarılı" && s.neden.contains("hata beklendi"))
    }

    @Test func yalitimYolculuguBaskaMarkaKimliginiReddederVeIcerikSizmaz() async throws {
        let y = try Self.bul("marka-yalitimi-baska-marka-reddedilir")
        let s = await YolculukKosucu.kos(y)
        #expect(s.gecti, "\(s.ozet)")
        let ad = try #require(s.adimlar.first { $0.ad == "A oturumu B kaynağını okumayı dener" })
        #expect(ad.cikti.contains("reddedilen: kaynak_oku") && ad.cikti.contains("bekleyen öneri: 0"))
        #expect(!s.adimlar.map(\.cikti).joined().contains("GIZLI-BUTCE-KUZEY"))
        let capraz = try #require(s.adimlar.last)
        #expect(capraz.cikti.hasPrefix("reddedildi:"))
        // Sızıntı beklentisi gerçekten denetlenir: sızdıran bir kayıt kırmızı olmalı.
        var sizan = y
        let i = try #require(sizan.adimlar.firstIndex { $0.eylem == .asistan })
        sizan.adimlar[i].bekle?.sizmamali = ["bu markadan erişemiyorum"]   // yanıtta görünen metin
        let k = await YolculukKosucu.kos(sizan)
        #expect(!k.gecti && k.neden.contains("sızıntı"))
    }

    @Test func raporluYolculukDayanaksizMaddeUretmezKayitYokkenBostur() async throws {
        let y = try Self.bul("elle-is-kaydi-raporu-doldurur")
        let s = await YolculukKosucu.kos(y)
        #expect(s.gecti, "\(s.ozet)")
        let bos = try #require(s.adimlar.first { $0.ad == "Kayıt yokken rapor maddesiz" })
        #expect(bos.cikti.contains("completedWork=0"))
        let dolu = try #require(s.adimlar.last)
        #expect(dolu.cikti.contains("completedWork=1"))
    }

    @Test func kayitDosyalariSekliyleYuklenirVeBilinmeyenEylemReddedilir() throws {
        let gecersiz = Data(#"{"ad":"x","aciklama":"","adimlar":[{"ad":"a","eylem":"uydur"}]}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Yolculuk.self, from: gecersiz) }
        // Kayıt dosyaları gerçek ad ya da kişisel yol taşımaz.
        let metin = try FileManager.default.contentsOfDirectory(at: Self.klasor, includingPropertiesForKeys: nil)
            .map { try String(contentsOf: $0, encoding: .utf8) }.joined()
        #expect(!metin.contains("/Users/") && !metin.contains("@gmail"))
    }
}
