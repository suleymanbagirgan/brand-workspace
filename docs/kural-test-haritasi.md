# Bozulamaz kural – test haritası

Kök `CLAUDE.md` "Bozulamaz kurallar" listesindeki 7 kuralın her biri için en az bir gerçek test adı. Adlar `Tests/MarkaCoreTests` altında `func <ad>` olarak vardır; `KuralTestHaritasiTests` hem bu belgedeki hem de `docs/guvence-denetimi-*.md` "Düzeltme durumu" tablolarındaki her test adının var olduğunu ve 7 kuralın hepsinin haritada yer aldığını doğrular (eksik 0). Belgede backtick içinde yalnız test adı ya da `Dosya.testAdi` yazılır.

| # | Kural | Test adları |
|---|---|---|
| 1 | Marka yalıtımı | `CoreTests.oturumunMarkasiSonradanDegistirilemez`, `AITests.baskaMarkaKimligiIleAracReddedilir`, `AkisYapilacaklarTests.akisBaskaMarkaninOgesiniGetirmez`, `CoreTests.baskaMarkaninKaynagiBaglanamaz`, `IsolationTests.tumMarkalarKipindeHicbirMarkaKlasoruAcilmaz` |
| 2 | Kaynak değişmez | `CoreTests.hamKaynakDegistirilemezYalnizcaArsivlenir`, `ArsivGeriAlTests.arsivlemeGeriAlinabilir`, `ArsivGeriAlTests.baskaMarkaninKaynagiArsivdenCikarilamaz` |
| 3 | AI veri değiştirmez, öneri üretir | `EylemKaydiTests.aracYalnizOneriUretirGorevDegismez`, `EylemKaydiTests.oneriOnaydanOnceGorevDegistirmezOnaylaUygulanir`, `CoreTests.aiOnerisiOnaylanmadanGuncelSayilmazVeGeriDonulebilir`, `EylemKaydiTests.onaylananGorevGuncellemesiGeriAlinir` |
| 4 | Rapor maddesi dayanaksız olamaz | `ReportImportBackupTests.yalnizcaDogrulanmisKayitRaporaGirer`, `CoreTests.aiIddiasiKaynaksizVeyaBaskaMarkadanOlamaz`, `ReportImportBackupTests.surumOnayPaylasimVeKaynaksizMaddeEngeli`, `ReportImportBackupTests.geriCekilenKayitlaRaporOnaylanamaz` |
| 5 | Her yazma denetim olayı bırakır | `OrnekMarkaTests.herYazmaSistemAktoruyleDenetimIziBirakir`, `EylemKaydiTests.uygulamaDenetimIziBirakirVeGeriAlmaOncekiDegerleriYukler`, `GuvenceDuzeltmeTests.hizmetVeYetenekYazmaSilmeDenetimBirakir`, `ElleIsKaydiTests.elleIsKaydiKullaniciAktoruyleOlusturmaVeDogrulamaDenetimiBirakir` |
| 6 | İçerik yalnız izinli sağlayıcıya gider; günlük/tanı içerik taşımaz | `AITests.izinVerilmeyenSaglayiciyaOturumAcilamaz`, `GizlilikTests.raporOzetiIzinsizSaglayiciyaGitmez`, `DiagnosticsTests.taniMetniMarkaIcerikEpostaVeYolSizdirmaz`, `TerminalOneriTests.hataTaniKaydiIcerikVeDosyaAdiTasimaz` |
| 7 | Yapmadığımızı vaat etmeyiz | `BelgeTutarlilikTests.belgelerdeMutlakGizlilikIfadesiYok`, `BelgeTutarlilikTests.belgelerdeSabitTestSayisiYok`, `SurumTests.surumNumarasiXYZBicimindeVeReadmeIleAyni` |

## Sınırlar (doğrulanamayan ya da kısmi)

- Kural 5: "her yazma" için tek bir test tüm `Store` yazma yollarını tarayan kanıt vermez; harita örnek yolları kanıtlar. İçe aktarma ve paket yükleme denetimi testsizdir (`docs/guvence-denetimi-yalitim.md`, kanıtsız yollar listesi madde 9).
- Kural 6: günlüklerin içerik taşımadığı tanı metni ve hata kaydı testleriyle kanıtlanır; her `Logger` çağrısını tarayan bir test yoktur.
- Kural 7: belge testleri sabit test sayısı ve mutlak gizlilik ifadelerini yakalar; her iddianın doğruluğunu denetlemez (o iş `kalite-kapisi` ve elle denetimdedir).
