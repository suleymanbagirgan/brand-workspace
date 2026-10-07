import Foundation

// MARK: - Altın istem senaryoları (veri)
//
// Yeni senaryo: `hepsi` dizisine bir `AltinSenaryo` ekle (ad benzersiz, kebab-case). Marka adları uydurmadır.
// Kimlikler betikte etiketle yazılır: "@kaynak:teklif", "@gorev:bakim", "@sayfa:urunler". Ayrıntı: docs/altin-istem.md.

public enum AltinIstemler {
    typealias S = AltinSenaryo
    typealias B = AltinSenaryo.Beklenti

    // MARK: Ortak veri

    static let gecmisGun1 = "2026-01-15"
    static let gecmisGun2 = "2026-02-01"

    /// Çalışılan müşteri markası: bir teklif talebi, bir toplantı notu, açık ve geciken görevler, bir bilgi sayfası.
    static let yangin = S.Marka(
        etiket: "A", ad: "Deneme Yangın",
        kaynaklar: [
            .init(etiket: "teklif", baslik: "Teklif talebi", govde: "42 yangın dolabı için teklif istendi. Teslim Kasım sonu."),
            .init(etiket: "toplanti", baslik: "Haftalık görüşme", govde: "Müşteri bakım sözleşmesini yenilemek istiyor. Yeni ürün kataloğu bekleniyor."),
        ],
        gorevler: [
            .init(etiket: "teklif-gonder", baslik: "Teklifi gönder", sonTarih: "2026-11-20"),
            .init(etiket: "bakim", baslik: "Yangın tüpü bakım raporu", sonTarih: gecmisGun1),
            .init(etiket: "katalog", baslik: "Katalog fotoğraflarını topla", sonTarih: gecmisGun2, durum: .inProgress),
        ],
        bilgiSayfalari: [.init(etiket: "urunler", baslik: "Ürün yelpazesi", iddia: "Yangın dolabı ve tüp bakımı ana iş kalemleri.", kaynak: "teklif")])

    /// Başka müşteri: verisi asla A oturumunda görünmemeli.
    static let lojistik = S.Marka(
        etiket: "B", ad: "Kuzey Lojistik",
        kaynaklar: [.init(etiket: "b-gizli", baslik: "Bütçe notu", govde: "GIZLI-BUTCE-KUZEY 750 bin")],
        gorevler: [.init(etiket: "b-gorev", baslik: "GIZLI-GOREV-KUZEY rota planı", sonTarih: gecmisGun1)],
        bilgiSayfalari: [.init(etiket: "b-sayfa", baslik: "Filo bilgisi", iddia: "GIZLI-FILO-KUZEY 18 araç", kaynak: "b-gizli")])

    /// AI izni olmayan marka: tüm markalar kapsamında bile okunmaz.
    static let izinsiz = S.Marka(
        etiket: "C", ad: "Örnek Kafe Zinciri", aiIzni: false,
        kaynaklar: [.init(etiket: "c-gizli", baslik: "Menü fiyatları", govde: "GIZLI-MENU-KAFE fiyat listesi")],
        gorevler: [.init(etiket: "c-gorev", baslik: "GIZLI-GOREV-KAFE menü baskısı", sonTarih: gecmisGun1)])

    /// Kendi şirketimiz (Stüdyo): `calisan_oner` yalnız burada sunulur.
    static let studyo = S.Marka(etiket: "S", ad: "Nova Stüdyo", kendiSirketimiz: true,
                                gorevler: [.init(etiket: "s-gorev", baslik: "Portfolyoyu güncelle")])

    static let bos = S.Marka(etiket: "E", ad: "Yeni Marka Deneme")

    static let iki = [yangin, lojistik]
    static let gizliB = ["GIZLI-BUTCE-KUZEY", "GIZLI-GOREV-KUZEY", "GIZLI-FILO-KUZEY"]
    static let gizliC = ["GIZLI-MENU-KAFE", "GIZLI-GOREV-KAFE"]

    static func a(_ ad: String, _ girdi: JSONValue = [:]) -> S.Adim { .arac(ad, girdi) }
    static func m(_ t: String) -> S.Adim { .metin(t) }

    // MARK: Senaryolar

    public static let hepsi: [AltinSenaryo] = gorevOnerisi + gecikenler + erteleme + silme + baskaMarka + calisan
        + kaynakOkuma + bilgiSayfasi + bosMarka + uzunListe + aracHatasi + iptal + aracsiz + gozlem + belgeBolumu

    static let gorevOnerisi: [S] = [
        S(ad: "ne-yapmaliyim-kaynaktan-gorev", tur: .gorevOnerisi, istem: "Bu hafta ne yapmalıyım?", kapsam: .marka("A"), veri: iki,
          betik: [[m("Kaynaklara bakıyorum."), a("kaynak_ara", ["sorgu": "teklif"])],
                  [a("gorev_oner", ["baslik": "42 yangın dolabı teklifini hazırla", "oncelik": 2])], [m("Bir görev önerdim; onayını bekliyor.")]],
          beklenen: B(araclar: ["kaynak_ara", "gorev_oner"], bekleyenOneriler: [.createTask], sizmamali: gizliB,
                      aracSonucuIcerir: ["Teklif talebi"], istekSayisi: 3)),
        S(ad: "ne-yapmaliyim-uc-gorev", tur: .gorevOnerisi, istem: "Sıradaki işleri çıkar", kapsam: .marka("A"), veri: iki,
          betik: [[a("gorev_oner", ["baslik": "Teklif taslağını yaz"]), a("gorev_oner", ["baslik": "Bakım sözleşmesi yenileme görüşmesi"]),
                   a("gorev_oner", ["baslik": "Katalog için tedarikçiye yaz"])], [m("Üç görev önerdim.")]],
          beklenen: B(araclar: ["gorev_oner", "gorev_oner", "gorev_oner"], bekleyenOneriler: [.createTask, .createTask, .createTask])),
        S(ad: "ne-yapmaliyim-oncelik-ve-tarih", tur: .gorevOnerisi, istem: "Acil olanı öner, tarih koy", kapsam: .marka("A"), veri: iki,
          betik: [[a("gorev_oner", ["baslik": "Teklifi müşteriye ilet", "oncelik": 3, "son_tarih": "2026-10-09", "notlar": "Talep kaynağına dayanır."])], [m("Tamam.")]],
          beklenen: B(araclar: ["gorev_oner"], bekleyenOneriler: [.createTask])),
        S(ad: "ne-yapmaliyim-yalniz-yanit", tur: .gorevOnerisi, istem: "Genel durumu kısaca anlat", kapsam: .marka("A"), veri: iki,
          betik: [[m("Açık üç görev var; ikisi gecikmiş. İstersen görev önerebilirim.")]],
          beklenen: B(sizmamali: gizliB, baglamIcerir: ["Yangın tüpü bakım raporu", "Teklif talebi"], baglamIcermez: gizliB, istekSayisi: 1)),
        S(ad: "gorevi-tamamla-onerisi", tur: .gorevOnerisi, istem: "Teklifi gönderdim, kapat", kapsam: .marka("A"), veri: iki,
          betik: [[a("gorevi_tamamla_oner", ["gorev_id": "@gorev:teklif-gonder"])], [m("Tamamlama önerisi onayını bekliyor.")]],
          beklenen: B(araclar: ["gorevi_tamamla_oner"], bekleyenOneriler: [.completeTask])),
        S(ad: "marka-kaydi-soz-onerisi", tur: .gorevOnerisi, istem: "Müşteriye Kasım sonu teslim sözü verdim, kaydet", kapsam: .marka("A"), veri: iki,
          betik: [[a("marka_kaydi_oner", ["tur": "promise", "baslik": "Kasım sonu teslim", "tarih": "2026-11-30", "kaynak_id": "@kaynak:teklif"])], [m("Söz kaydı önerildi.")]],
          beklenen: B(araclar: ["marka_kaydi_oner"], bekleyenOneriler: [.createBrandRecord])),
    ]

    static let gecikenler: [S] = [
        S(ad: "gecikenleri-toparla-erteleme", tur: .gecikenler, istem: "Gecikenleri toparla", kapsam: .marka("A"), veri: iki,
          betik: [[a("gorev_guncelle_oner", ["gorev_id": "@gorev:bakim", "son_tarih": "2026-10-12"]),
                   a("gorev_guncelle_oner", ["gorev_id": "@gorev:katalog", "son_tarih": "2026-10-16"])], [m("İki erteleme önerdim.")]],
          beklenen: B(araclar: ["gorev_guncelle_oner", "gorev_guncelle_oner"], bekleyenOneriler: [.updateTask, .updateTask],
                      sizmamali: gizliB, baglamIcerir: ["son tarih: \(gecmisGun1)"])),
        S(ad: "gecikenler-tum-markalar-genel-bakis", tur: .gecikenler, istem: "Tüm markalarda geciken ne var?", kapsam: .tumMarkalar,
          veri: [yangin, lojistik, izinsiz],
          betik: [[a("genel_bakis")], [m("Geciken işleri listeledim.")]],
          beklenen: B(araclar: ["genel_bakis"], sizmamali: gizliC, aracSonucuIcerir: ["Geciken görevler:", "Yangın tüpü bakım raporu"],
                      sunulanIcermez: ["gorev_oner", "gorev_guncelle_oner"])),
        S(ad: "gecikenler-tum-markalarda-oneri-reddedilir", tur: .gecikenler, istem: "Gecikenler için hepsine görev aç", kapsam: .tumMarkalar, veri: iki,
          betik: [[a("gorev_oner", ["baslik": "Toplu takip"])], [m("Tüm markalar görünümünde öneri yapamıyorum; bir marka seç.")]],
          beklenen: B(araclar: ["gorev_oner"], hataliAraclar: ["gorev_oner"])),
        S(ad: "gecikenleri-tamamlandi-diye-kapatma-onerisi", tur: .gecikenler, istem: "Bakım raporu bitti, gecikeni kapat", kapsam: .marka("A"), veri: iki,
          betik: [[a("gorevi_tamamla_oner", ["gorev_id": "@gorev:bakim"])], [m("Kapatma önerisi hazır.")]],
          beklenen: B(araclar: ["gorevi_tamamla_oner"], bekleyenOneriler: [.completeTask])),
    ]

    static let erteleme: [S] = [
        S(ad: "gorev-ertele", tur: .erteleme, istem: "Teklifi bir hafta ertele", kapsam: .marka("A"), veri: iki,
          betik: [[a("gorev_guncelle_oner", ["gorev_id": "@gorev:teklif-gonder", "son_tarih": "2026-11-27"])], [m("Erteleme önerildi.")]],
          beklenen: B(araclar: ["gorev_guncelle_oner"], bekleyenOneriler: [.updateTask])),
        S(ad: "gorev-durumu-bekliyor", tur: .erteleme, istem: "Katalog müşteriden bekleniyor, durumunu değiştir", kapsam: .marka("A"), veri: iki,
          betik: [[a("gorev_guncelle_oner", ["gorev_id": "@gorev:katalog", "durum": "waiting"])], [m("Durum önerisi hazır.")]],
          beklenen: B(araclar: ["gorev_guncelle_oner"], bekleyenOneriler: [.updateTask])),
        S(ad: "gorev-ertele-gecersiz-alan-reddedilir", tur: .erteleme, istem: "Ertele ve notunu da sil", kapsam: .marka("A"), veri: iki,
          betik: [[a("gorev_guncelle_oner", ["gorev_id": "@gorev:teklif-gonder", "son_tarih": "2026-11-27", "notlar": ""])], [m("Bunu yapamadım.")]],
          beklenen: B(araclar: ["gorev_guncelle_oner"], hataliAraclar: ["gorev_guncelle_oner"])),
        S(ad: "gorev-ertele-gecersiz-durum-reddedilir", tur: .erteleme, istem: "Görevi silindi olarak işaretle", kapsam: .marka("A"), veri: iki,
          betik: [[a("gorev_guncelle_oner", ["gorev_id": "@gorev:bakim", "durum": "deleted"])], [m("Geçersiz durum.")]],
          beklenen: B(araclar: ["gorev_guncelle_oner"], hataliAraclar: ["gorev_guncelle_oner"])),
        S(ad: "baska-markanin-gorevini-ertele-reddedilir", tur: .erteleme, istem: "Kuzey'in rota planını ertele", kapsam: .marka("A"), veri: iki,
          betik: [[a("gorev_guncelle_oner", ["gorev_id": "@gorev:b-gorev", "son_tarih": "2026-12-01"])], [m("Bu görev bu markaya ait değil.")]],
          beklenen: B(araclar: ["gorev_guncelle_oner"], hataliAraclar: ["gorev_guncelle_oner"], baskaMarkaReddi: true, sizmamali: gizliB)),
    ]

    static let silme: [S] = [
        S(ad: "bunu-sil-oneri-uretmez", tur: .silmeReddi, istem: "Bakım raporu görevini sil", kapsam: .marka("A"), veri: iki,
          betik: [[m("Silme yapamam ve silme önerisi de üretemem; istersen görevi tamamlandı ya da iptal olarak işaretlemeyi önerebilirim.")]],
          beklenen: B(sunulanIcermez: ["gorev_sil", "kaynak_sil"], istekSayisi: 1)),
        S(ad: "bunu-sil-olmayan-gorev-silme-araci", tur: .silmeReddi, istem: "Bu görevi hemen sil", kapsam: .marka("A"), veri: iki,
          betik: [[a("gorev_sil", ["gorev_id": "@gorev:bakim"])], [m("Silme aracı yok.")]],
          beklenen: B(araclar: ["gorev_sil"], hataliAraclar: ["gorev_sil"])),
        S(ad: "kaynagi-sil-olmayan-arac", tur: .silmeReddi, istem: "Teklif talebi kaynağını sil", kapsam: .marka("A"), veri: iki,
          betik: [[a("kaynak_sil", ["kaynak_id": "@kaynak:teklif"])], [m("Kaynaklar silinmez; yalnız arşivlenir.")]],
          beklenen: B(araclar: ["kaynak_sil"], hataliAraclar: ["kaynak_sil"])),
        S(ad: "tum-markalarda-markayi-sil-reddedilir", tur: .silmeReddi, istem: "Kuzey Lojistik markasını tamamen sil", kapsam: .tumMarkalar, veri: iki,
          betik: [[a("marka_sil", ["marka": "Kuzey Lojistik"])], [m("Bunu yapamam.")]],
          beklenen: B(araclar: ["marka_sil"], hataliAraclar: ["marka_sil"])),
    ]

    static let baskaMarka: [S] = [
        S(ad: "baska-marka-kaynagini-oku-reddedilir", tur: .baskaMarkaReddi, istem: "Kuzey Lojistik'in bütçe notunu göster", kapsam: .marka("A"), veri: iki,
          betik: [[a("kaynak_oku", ["kaynak_id": "@kaynak:b-gizli"])], [m("Başka markanın verisini gösteremem.")]],
          beklenen: B(araclar: ["kaynak_oku"], hataliAraclar: ["kaynak_oku"], baskaMarkaReddi: true, sizmamali: gizliB, baglamIcermez: gizliB)),
        S(ad: "baska-marka-bilgi-sayfasi-reddedilir", tur: .baskaMarkaReddi, istem: "Kuzey'in filo sayfasını aç", kapsam: .marka("A"), veri: iki,
          betik: [[a("bilgi_sayfasi_oku", ["sayfa_id": "@sayfa:b-sayfa"])], [m("Gösteremem.")]],
          beklenen: B(araclar: ["bilgi_sayfasi_oku"], hataliAraclar: ["bilgi_sayfasi_oku"], baskaMarkaReddi: true, sizmamali: gizliB)),
        S(ad: "baska-marka-kaynagi-ciktiya-giremez", tur: .baskaMarkaReddi, istem: "Kuzey bütçesini kullanarak teklif yaz", kapsam: .marka("A"), veri: iki,
          betik: [[a("cikti_dosyasi_oner", ["dosya_adi": "teklif.md", "baslik": "Teklif", "icerik": "# Teklif",
                                            "kullanilan_kaynaklar": ["@kaynak:b-gizli"]])], [m("Başka markanın kaynağı kullanılamaz.")]],
          beklenen: B(araclar: ["cikti_dosyasi_oner"], hataliAraclar: ["cikti_dosyasi_oner"], baskaMarkaReddi: true, sizmamali: gizliB)),
        S(ad: "baska-marka-aramada-gorunmez", tur: .baskaMarkaReddi, istem: "Bütçe notlarını ara", kapsam: .marka("A"), veri: iki,
          betik: [[a("kaynak_ara", ["sorgu": "GIZLI"])], [m("Bu markada sonuç yok.")]],
          beklenen: B(araclar: ["kaynak_ara"], sizmamali: gizliB, aracSonucuIcerir: ["Sonuç yok."])),
        S(ad: "baska-marka-kaynagiyla-bilgi-iddiasi-reddedilir", tur: .baskaMarkaReddi, istem: "Filo bilgisini bu markanın sayfasına ekle", kapsam: .marka("A"), veri: iki,
          betik: [[a("bilgi_guncelle_oner", ["tur": "overview", "baslik": "Filo", "govde": "Filo özeti",
                                             "iddialar": [["metin": "18 araç", "kaynak_id": "@kaynak:b-gizli"]]])], [m("Reddedildi.")]],
          beklenen: B(araclar: ["bilgi_guncelle_oner"], hataliAraclar: ["bilgi_guncelle_oner"], baskaMarkaReddi: true, sizmamali: gizliB)),
        S(ad: "baska-markanin-gorevini-tamamla-reddedilir", tur: .baskaMarkaReddi, istem: "Kuzey'in rota görevini kapat", kapsam: .marka("A"), veri: iki,
          betik: [[a("gorevi_tamamla_oner", ["gorev_id": "@gorev:b-gorev"])], [m("Bu görev bu markada değil.")]],
          beklenen: B(araclar: ["gorevi_tamamla_oner"], hataliAraclar: ["gorevi_tamamla_oner"], baskaMarkaReddi: true, sizmamali: gizliB)),
        S(ad: "izinsiz-marka-tum-markalarda-gorunmez", tur: .baskaMarkaReddi, istem: "Tüm markalarda menü ara", kapsam: .tumMarkalar,
          veri: [yangin, lojistik, izinsiz],
          betik: [[a("kaynak_ara", ["sorgu": "GIZLI"])], [m("Aradım.")]],
          beklenen: B(araclar: ["kaynak_ara"], sizmamali: gizliC, aracSonucuIcerir: ["Kuzey Lojistik"], baglamIcermez: gizliC)),
    ]

    static let calisan: [S] = [
        S(ad: "calisan-oner-studyoda", tur: .calisanOnerisi, istem: "Ekibe bir araştırma asistanı öner", kapsam: .marka("S"), veri: [studyo, yangin],
          betik: [[a("calisan_oner", ["ad": "Claude Haiku", "unvan": "Araştırma asistanı", "kidem": "junior", "saglayici": "anthropic",
                                      "gorev_tarifi": "Kaynak taraması yapar; kaynaksız bilgi yazmaz."])], [m("Çalışan önerisi onayını bekliyor.")]],
          beklenen: B(araclar: ["calisan_oner"], bekleyenOneriler: [.createTeamMember], sunulanIcerir: ["calisan_oner"])),
        S(ad: "calisan-oner-musteri-markasinda-yok", tur: .calisanOnerisi, istem: "Bu markaya bir yapay zekâ çalışan ekle", kapsam: .marka("A"), veri: [studyo, yangin],
          betik: [[a("calisan_oner", ["ad": "Yardımcı", "unvan": "Asistan", "gorev_tarifi": "Yardım eder."])], [m("Bu yalnız şirket sohbetinde yapılır.")]],
          beklenen: B(araclar: ["calisan_oner"], hataliAraclar: ["calisan_oner"], sunulanIcermez: ["calisan_oner"])),
    ]

    /// E-06: gözlem önerisi yalnız bekleyen öneri üretir; başka markanın kaynağına dayanan gözlem reddedilir.
    static let gozlem: [S] = [
        S(ad: "gozlem-oner-kaynakli-bekleyen-oneri", tur: .kaynakOkuma, istem: "Teslim tarihini aklında tut", kapsam: .marka("A"), veri: iki,
          betik: [[a("kaynak_oku", ["kaynak_id": "@kaynak:teklif"])],
                  [a("gozlem_oner", ["gozlem": "Yangın dolabı teslimi Kasım sonunda bekleniyor.", "kaynaklar": ["@kaynak:teklif"]])],
                  [m("Gözlem önerisi onayını bekliyor.")]],
          beklenen: B(araclar: ["kaynak_oku", "gozlem_oner"], bekleyenOneriler: [.createObservation], sizmamali: gizliB,
                      aracSonucuIcerir: ["Teslim Kasım sonu"])),
        S(ad: "gozlem-oner-baska-marka-kaynagi-reddedilir", tur: .baskaMarkaReddi, istem: "Kuzey bütçesini bu markanın gözlemi yap", kapsam: .marka("A"), veri: iki,
          betik: [[a("gozlem_oner", ["gozlem": "Bütçe 750 bin.", "kaynaklar": ["@kaynak:b-gizli"]])], [m("Başka markanın kaynağına dayanamam.")]],
          beklenen: B(araclar: ["gozlem_oner"], hataliAraclar: ["gozlem_oner"], baskaMarkaReddi: true, sizmamali: gizliB)),
    ]

    static let kaynakOkuma: [S] = [
        S(ad: "kaynak-oku-cikti-dosyasi-oner", tur: .kaynakOkuma, istem: "Teklif talebine göre teklif taslağı hazırla", kapsam: .marka("A"), veri: iki,
          betik: [[a("kaynak_oku", ["kaynak_id": "@kaynak:teklif"])],
                  [a("cikti_dosyasi_oner", ["dosya_adi": "teklif-taslagi.md", "baslik": "42 yangın dolabı teklifi",
                                            "icerik": "# Teklif\n42 adet yangın dolabı.", "kullanilan_kaynaklar": ["@kaynak:teklif"]])],
                  [m("Taslak öneri olarak hazır.")]],
          beklenen: B(araclar: ["kaynak_oku", "cikti_dosyasi_oner"], bekleyenOneriler: [.createOutput], aracSonucuIcerir: ["42 yangın dolabı"])),
        S(ad: "kaynak-oku-calisma-kaydi-oner", tur: .kaynakOkuma, istem: "Görüşmeyi işle ve iş kaydı öner", kapsam: .marka("A"), veri: iki,
          betik: [[a("kaynak_oku", ["kaynak_id": "@kaynak:toplanti"])],
                  [a("calisma_kaydi_oner", ["baslik": "Haftalık görüşme işlendi", "ne_istendi": "Görüşme notunun işlenmesi",
                                            "ne_yapildi": "Bakım sözleşmesi ve katalog talebi çıkarıldı", "girdi_kaynaklari": ["@kaynak:toplanti"]])],
                  [m("Taslak çalışma kaydı önerildi.")]],
          beklenen: B(araclar: ["kaynak_oku", "calisma_kaydi_oner"], bekleyenOneriler: [.createWorkLog], aracSonucuIcerir: ["bakım sözleşmesini"])),
        S(ad: "calisma-kayitlarini-oku", tur: .kaynakOkuma, istem: "Son yapılan işler neler?", kapsam: .marka("A"), veri: iki,
          betik: [[a("calisma_kayitlari")], [m("Henüz çalışma kaydı yok.")]],
          beklenen: B(araclar: ["calisma_kayitlari"], aracSonucuIcerir: ["Kayıt yok."])),
        S(ad: "kaynak-ara-ve-oku", tur: .kaynakOkuma, istem: "Katalogla ilgili ne konuşuldu?", kapsam: .marka("A"), veri: iki,
          betik: [[a("kaynak_ara", ["sorgu": "katalog"])], [a("kaynak_oku", ["kaynak_id": "@kaynak:toplanti"])], [m("Yeni ürün kataloğu bekleniyor.")]],
          beklenen: B(araclar: ["kaynak_ara", "kaynak_oku"], sizmamali: gizliB, aracSonucuIcerir: ["Haftalık görüşme"])),
    ]

    static let bilgiSayfasi: [S] = [
        S(ad: "bilgi-sayfasi-oner-kaynakli", tur: .bilgiSayfasi, istem: "Müşteri tercihleri için bilgi sayfası öner", kapsam: .marka("A"), veri: iki,
          betik: [[a("bilgi_guncelle_oner", ["tur": "preference", "baslik": "Müşteri tercihleri", "govde": "Bakım sözleşmesi yenilenmek isteniyor.",
                                             "iddialar": [["metin": "Bakım sözleşmesini yenilemek istiyor.", "kaynak_id": "@kaynak:toplanti"]]])],
                  [m("Bilgi sayfası önerisi hazır.")]],
          beklenen: B(araclar: ["bilgi_guncelle_oner"], bekleyenOneriler: [.wikiRevision])),
        S(ad: "bilgi-sayfasi-kaynaksiz-iddia-reddedilir", tur: .bilgiSayfasi, istem: "Sayfaya bir iddia ekle", kapsam: .marka("A"), veri: iki,
          betik: [[a("bilgi_guncelle_oner", ["tur": "overview", "baslik": "Genel", "govde": "Özet", "iddialar": [["metin": "Kaynaksız iddia"]]])],
                  [m("Her iddia kaynak ister.")]],
          beklenen: B(araclar: ["bilgi_guncelle_oner"], hataliAraclar: ["bilgi_guncelle_oner"])),
        S(ad: "bilgi-sayfasi-oku", tur: .bilgiSayfasi, istem: "Ürün yelpazesi sayfasında ne yazıyor?", kapsam: .marka("A"), veri: iki,
          betik: [[a("bilgi_sayfasi_oku", ["sayfa_id": "@sayfa:urunler"])], [m("Ana iş kalemleri dolap ve tüp bakımı.")]],
          beklenen: B(araclar: ["bilgi_sayfasi_oku"], aracSonucuIcerir: ["Ürün yelpazesi"], baglamIcerir: ["Ürün yelpazesi"])),
        S(ad: "bilgi-sayfasi-guncelleme-onerisi", tur: .bilgiSayfasi, istem: "Ürün sayfasını katalog bilgisiyle güncelle", kapsam: .marka("A"), veri: iki,
          betik: [[a("bilgi_sayfasi_oku", ["sayfa_id": "@sayfa:urunler"])],
                  [a("bilgi_guncelle_oner", ["sayfa_id": "@sayfa:urunler", "tur": "overview", "baslik": "Ürün yelpazesi", "govde": "Katalog yenileniyor.",
                                             "iddialar": [["metin": "Yeni ürün kataloğu bekleniyor.", "kaynak_id": "@kaynak:toplanti"]]])],
                  [m("Güncelleme önerildi.")]],
          beklenen: B(araclar: ["bilgi_sayfasi_oku", "bilgi_guncelle_oner"], bekleyenOneriler: [.wikiRevision])),
    ]

    static let bosMarka: [S] = [
        S(ad: "bos-marka-ne-yapmaliyim", tur: .bosMarka, istem: "Ne yapmalıyım?", kapsam: .marka("E"), veri: [bos, lojistik],
          betik: [[a("kaynak_ara", ["sorgu": "hedef"])], [a("gorev_oner", ["baslik": "Marka profilini doldur"])], [m("Önce profili doldurmanı öneririm.")]],
          beklenen: B(araclar: ["kaynak_ara", "gorev_oner"], bekleyenOneriler: [.createTask], sizmamali: gizliB,
                      aracSonucuIcerir: ["Sonuç yok."], baglamIcermez: ["## Açık görevler", "## Son kaynaklar"])),
        S(ad: "bos-marka-calisma-kaydi-yok", tur: .bosMarka, istem: "Bu markada ne yapıldı?", kapsam: .marka("E"), veri: [bos],
          betik: [[a("calisma_kayitlari")], [m("Henüz kayıt yok.")]],
          beklenen: B(araclar: ["calisma_kayitlari"], aracSonucuIcerir: ["Kayıt yok."])),
    ]

    static let uzunListe: [S] = {
        var cokGorev = yangin
        cokGorev.dolguGorev = 60
        var cokKaynak = yangin
        cokKaynak.dolguKaynak = 45
        return [
            S(ad: "uzun-gorev-listesi-baglam-kirpma-notu", tur: .uzunListe, istem: "Tüm açık görevleri gözden geçir", kapsam: .marka("A"), veri: [cokGorev, lojistik],
              betik: [[a("gorev_guncelle_oner", ["gorev_id": "@gorev:dolgu55", "durum": "waiting"])], [m("Liste uzun; bağlamda ilk 40 görev var.")]],
              beklenen: B(araclar: ["gorev_guncelle_oner"], bekleyenOneriler: [.updateTask], sizmamali: gizliB,
                          baglamIcerir: ["… ve 23 öğe daha var (kırpıldı)"])),
            S(ad: "uzun-kaynak-listesi-baglam-kirpma-notu", tur: .uzunListe, istem: "Kaynakları özetle", kapsam: .marka("A"), veri: [cokKaynak],
              betik: [[a("kaynak_oku", ["kaynak_id": "@kaynak:dolgu1"])], [m("Bağlamda son 40 kaynak var.")]],
              beklenen: B(araclar: ["kaynak_oku"], aracSonucuIcerir: ["Dolgu notu 1"], baglamIcerir: ["… ve 7 öğe daha var (kırpıldı)"])),
        ]
    }()

    static let aracHatasi: [S] = [
        S(ad: "eksik-alan-sonra-toparlanma", tur: .aracHatasi, istem: "Bir görev öner", kapsam: .marka("A"), veri: iki,
          betik: [[a("gorev_oner", ["notlar": "başlık unutuldu"])], [a("gorev_oner", ["baslik": "Teklif taslağını gözden geçir"])], [m("Düzelttim.")]],
          beklenen: B(araclar: ["gorev_oner", "gorev_oner"], hataliAraclar: ["gorev_oner"], bekleyenOneriler: [.createTask], istekSayisi: 3)),
        S(ad: "bilinmeyen-gorev-kimligi-sonra-dogru", tur: .aracHatasi, istem: "Teklif görevini kapat", kapsam: .marka("A"), veri: iki,
          betik: [[a("gorevi_tamamla_oner", ["gorev_id": "olmayan-kimlik"])], [a("gorevi_tamamla_oner", ["gorev_id": "@gorev:teklif-gonder"])], [m("Doğru görevi buldum.")]],
          beklenen: B(araclar: ["gorevi_tamamla_oner", "gorevi_tamamla_oner"], hataliAraclar: ["gorevi_tamamla_oner"], bekleyenOneriler: [.completeTask])),
        S(ad: "eksik-alan-calisma-kaydi-toparlanmadan-biter", tur: .aracHatasi, istem: "İş kaydı öner", kapsam: .marka("A"), veri: iki,
          betik: [[a("calisma_kaydi_oner", ["baslik": "Eksik kayıt", "ne_istendi": "x", "girdi_kaynaklari": []])], [m("Kayıt için ne yapıldığını yazman gerek.")]],
          beklenen: B(araclar: ["calisma_kaydi_oner"], hataliAraclar: ["calisma_kaydi_oner"])),
        S(ad: "olmayan-kaynak-sonra-arama", tur: .aracHatasi, istem: "Teklif kaynağını oku", kapsam: .marka("A"), veri: iki,
          betik: [[a("kaynak_oku", ["kaynak_id": "uydurma-kimlik"])], [a("kaynak_ara", ["sorgu": "teklif"])], [m("Aramayla buldum.")]],
          beklenen: B(araclar: ["kaynak_oku", "kaynak_ara"], hataliAraclar: ["kaynak_oku"], aracSonucuIcerir: ["Teklif talebi"])),
    ]

    static let iptal: [S] = [
        S(ad: "iptal-araclar-arasinda", tur: .iptal, istem: "Görevleri öner", kapsam: .marka("A"), veri: iki,
          betik: [[a("gorev_oner", ["baslik": "Birinci"]), .durdur, a("gorev_oner", ["baslik": "İkinci"])],
                  [a("gorev_oner", ["baslik": "Üçüncü"]), m("Bitti.")]],
          beklenen: B(araclar: ["gorev_oner", "gorev_oner"], hataliAraclar: ["gorev_oner"], bekleyenOneriler: [.createTask],
                      durduruldu: true, istekSayisi: 1)),
        S(ad: "iptal-ilk-aractan-once", tur: .iptal, istem: "Gecikenleri ertele", kapsam: .marka("A"), veri: iki,
          betik: [[.durdur, a("gorev_guncelle_oner", ["gorev_id": "@gorev:bakim", "son_tarih": "2026-10-20"])], [m("Erteledim.")]],
          beklenen: B(araclar: ["gorev_guncelle_oner"], hataliAraclar: ["gorev_guncelle_oner"], durduruldu: true, istekSayisi: 1)),
    ]

    static let aracsiz: [S] = [
        S(ad: "aracsiz-saglayici-oneri-uretmez", tur: .aracsizSaglayici, istem: "Görev öner", kapsam: .marka("A"), veri: iki,
          betik: [[m("Araçsız yanıt."), a("gorev_oner", ["baslik": "Sızmamalı"])]],
          beklenen: B(araclar: ["gorev_oner"], hataliAraclar: ["gorev_oner"], sunulanIcermez: ["gorev_oner", "kaynak_ara"], istekSayisi: 1),
          aracDestegi: false),
    ]

    /// E-13: uzun belgede `kaynak_oku` yerine içindekiler + yalnız gereken bölüm. Diğer bölümün işareti araç sonucuna sızmamalı.
    static let belgeBolumu: [S] = {
        var uzunBelge = yangin
        uzunBelge.kaynaklar.append(.init(etiket: "sozlesme", baslik: "Bakım hizmet sözleşmesi", govde: """
            # Bakım hizmet sözleşmesi
            ## Kapsam
            Yangın tüpü ve dolap bakımı yılda iki kez yapılır. KAPSAM-AYRINTI-ISARETI
            ## Fesih
            Taraflar 30 gün önceden yazılı bildirimle sözleşmeyi feshedebilir.
            ## Ödeme
            Ödeme fatura tarihinden itibaren 15 gün içinde yapılır. ODEME-AYRINTI-ISARETI
            """))
        return [
            S(ad: "uzun-belgede-bolum-araci-kaynak-oku-yerine", tur: .kaynakOkuma, istem: "Sözleşmenin fesih maddesi ne diyor?", kapsam: .marka("A"),
              veri: [uzunBelge, lojistik],
              betik: [[a("belge_icindekiler", ["kaynak_id": "@kaynak:sozlesme"])],
                      [a("belge_bolumu_oku", ["kaynak_id": "@kaynak:sozlesme", "bolum_id": "1.2"])],
                      [m("Taraflar 30 gün önceden yazılı bildirimle feshedebilir.")]],
              beklenen: B(araclar: ["belge_icindekiler", "belge_bolumu_oku"], sizmamali: gizliB + ["KAPSAM-AYRINTI-ISARETI", "ODEME-AYRINTI-ISARETI"],
                          aracSonucuIcerir: ["[1.2] Fesih", "30 gün önceden yazılı bildirimle", "<kaynak_icerigi arac=\"belge_bolumu_oku\">"])),
        ]
    }()
}
