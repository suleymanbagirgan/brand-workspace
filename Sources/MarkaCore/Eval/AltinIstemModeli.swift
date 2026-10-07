import Foundation

// MARK: - Altın istem koşumu: veri modeli (H3-02, A-01 kısmi)
//
// Bir senaryo = kullanıcı istemi + markada hazır veri + sahte sağlayıcının OYNADIĞI yanıt/araç çağrıları + BEKLENEN sonuç.
// Puanlama "araç çağrısı → bekleyen öneri" üzerinden yapılır; uygulanmış öneri her senaryoda 0 olmalı (kural 3).
// Sahte kip ChatEngine'in araç yürütücüsünü, marka yalıtımını ve öneri kutusunu sınar; modelin gerçek davranışını ÖLÇMEZ.

public struct AltinSenaryo: Sendable {
    public enum Tur: String, Sendable, Codable, CaseIterable {
        case gorevOnerisi = "gorev-onerisi"
        case gecikenler
        case erteleme
        case silmeReddi = "silme-reddi"
        case baskaMarkaReddi = "baska-marka-reddi"
        case calisanOnerisi = "calisan-onerisi"
        case kaynakOkuma = "kaynak-okuma"
        case bilgiSayfasi = "bilgi-sayfasi"
        case bosMarka = "bos-marka"
        case uzunListe = "uzun-liste"
        case aracHatasi = "arac-hatasi"
        case iptal
        case aracsizSaglayici = "aracsiz-saglayici"
    }

    /// Sahte sağlayıcının bir model yanıtındaki adımı. Araç girdisindeki `@kaynak:<etiket>`, `@gorev:<etiket>`,
    /// `@sayfa:<etiket>` dizgileri koşuda gerçek kimliklerle değiştirilir.
    public enum Adim: Sendable {
        case metin(String)
        case arac(String, JSONValue)
        /// Kullanıcının "Durdur"a basması (`ChatEngine.cancel`).
        case durdur
    }

    public enum Kapsam: Sendable {
        /// Marka etiketi (`Marka.etiket`).
        case marka(String)
        case tumMarkalar
    }

    public struct Kaynak: Sendable {
        public var etiket: String
        public var baslik: String
        public var govde: String
    }

    public struct Gorev: Sendable {
        public var etiket: String
        public var baslik: String
        public var sonTarih: String? = nil
        public var durum: TaskStatus = .todo
    }

    /// Kullanıcının yazdığı (doğrudan onaylı) bilgi sayfası; tek iddia, aynı markanın kaynağına dayanır.
    public struct BilgiSayfasi: Sendable {
        public var etiket: String
        public var baslik: String
        public var iddia: String
        public var kaynak: String
    }

    public struct Marka: Sendable {
        public var etiket: String
        public var ad: String
        public var kendiSirketimiz = false
        /// `false`: markanın hiçbir AI sağlayıcısına izni yok.
        public var aiIzni = true
        public var kaynaklar: [Kaynak] = []
        public var gorevler: [Gorev] = []
        public var bilgiSayfalari: [BilgiSayfasi] = []
        /// Bağlam kırpma senaryoları için eklenecek dolgu görev/kaynak sayısı (etiketler `dolgu1`, `dolgu2`, …).
        public var dolguGorev = 0
        public var dolguKaynak = 0
    }

    public struct Beklenti: Sendable {
        /// Çağrılan araçlar, çağrı sırasıyla (tam eşleşme).
        public var araclar: [String] = []
        /// Hata dönen araçlar, çağrı sırasıyla (tam eşleşme).
        public var hataliAraclar: [String] = []
        /// Oluşan bekleyen önerilerin türleri (çoklu küme: sayı tam eşleşir, sıra gözetilmez).
        public var bekleyenOneriler: [ProposalKind] = []
        /// En az bir araç "başka markanın verisi" gerekçesiyle reddedilmeli mi?
        public var baskaMarkaReddi = false
        /// Araç sonuçlarında, yanıtta ve kayıtlı geçmişte görünmemesi gereken metinler (başka/izinsiz markanın verisi).
        public var sizmamali: [String] = []
        /// Araç sonuçlarının (birleşik) içermesi gerekenler.
        public var aracSonucuIcerir: [String] = []
        /// Sağlayıcıya giden bağlamın (sistem istemi) içermesi / içermemesi gerekenler.
        public var baglamIcerir: [String] = []
        public var baglamIcermez: [String] = []
        /// Sağlayıcıya sunulan araç listesinde olması / olmaması gerekenler.
        public var sunulanIcerir: [String] = []
        public var sunulanIcermez: [String] = []
        /// Tur "Durduruldu" bildirimiyle bitmeli mi?
        public var durduruldu = false
        /// Sağlayıcıya giden model isteği sayısı; `nil` = denetlenmez.
        public var istekSayisi: Int? = nil
    }

    public var ad: String
    public var tur: Tur
    public var istem: String
    public var kapsam: Kapsam
    public var veri: [Marka]
    /// Her iç dizi bir model isteğinin yanıtı. Betik bitince tur biter.
    public var betik: [[Adim]]
    public var beklenen: Beklenti
    public var aracDestegi = true
}

/// Bir senaryoda ölçülen davranış. Kimlik, zaman ve araç sonucu metni taşımaz (iki koşu karşılaştırılabilir).
public struct AltinGozlem: Codable, Sendable, Equatable {
    public var araclar: [String]
    public var hataliAraclar: [String]
    public var bekleyenOneriler: [String]
    /// Bu koşuda uygulanmış (applied) öneri sayısı; her senaryoda 0 olmalı.
    public var uygulanmisOneri: Int
    /// Görev, kaynak, çalışma kaydı, marka kaydı, ekip ya da onaylı bilgi sürümü değişti mi? (AI veri değiştirmez.)
    public var veriDegisti: Bool
    public var baskaMarkaReddi: Bool
    public var sizanlar: [String]
    public var durduruldu: Bool
    public var sunulanAraclar: [String]
    public var istekSayisi: Int
}

public struct AltinSonuc: Codable, Sendable, Equatable {
    public static let gecti = "GEÇTİ"
    public static let kaldi = "KALDI"
    public var senaryo: String
    public var tur: String
    public var sonuc: String
    public var neden: String
    public var sureMs: Int
    public var gozlem: AltinGozlem
    public var gectiMi: Bool { sonuc == Self.gecti }
}

public struct AltinRapor: Codable, Sendable, Equatable {
    public var kip: String
    public var toplam: Int
    public var gecen: Int
    public var kalan: Int
    public var sonuclar: [AltinSonuc]

    /// Süre (zamana bağlı tek alan) sıfırlanmış kopya: determinizm karşılaştırması bunun üzerinden yapılır.
    public func maskeli() -> AltinRapor {
        var r = self
        r.sonuclar = r.sonuclar.map { var s = $0; s.sureMs = 0; return s }
        return r
    }

    public func json(maskele: Bool = false) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try e.encode(maskele ? maskeli() : self)
    }
}
