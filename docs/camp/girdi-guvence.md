# Dev Camp — Güvence görevleri (2026-10-05)

Rol: marka-yalitim-muhafizi + veri-gizliligi-denetcisi. Yöntem: salt okuma (belge + kod + test adları). Derleme/test çalıştırılmadı; sayılar `grep` sayımıdır, **ölçüm değildir**. Kapsam: yalnız ürün; satış/yayın/mağaza yok.

**Bağlam kanıtları:** Store'da 104 `public func`; 72'si imzasında `brandId`/`brand:` taşımıyor (çoğu kimlikle çalışır: `task(_ id)`, `applyProposal`). `auditEvent` tablosunda tetikleyici yok (`AppDatabase.swift:332-343`; yalnız `source_immutable`, `aiSession_scope_fixed` var). `Sources`'ta `FileProtection`/şifreleme izi: 0. Codex: `approvalPolicy "never"`, `dangerFullAccess` (`CodexAppServer.swift:374-375,418`). Yedek doğrulama yalnız `integrity_check` + migration (`BackupService.swift:108-128`). `@Test` sayısı 255, `bilinen-sinirlar.md` "200 test" diyor.

Toplam tahmin ≈ 27 gün > 15 iş günü: iki paralel hat (Store/veri · AI/içe aktarım) ya da 🟢'lerin bir kısmı kesilir.

## 🔴 Boss

**G-01 · Store yüzey taraması + yalıtım özellik testi** · Kural 1, 5
Neden: 72/104 yüzey `brandId` almıyor; yalıtım testleri tek tek senaryo (`OrnekMarkaTests.ornekMarkaBaskaMarkayaVeriSizdirmaz`, `EylemKaydiTests.baskaMarkanin…`), sistematik değil.
Kabul: (1) `storeGenelYuzeyiTaranirKapsamsizlarIzinListesinde` — kaynak tarar, `brandId`siz her yüzey gerekçeli izin listesinde, yeni eklenen kırmızı; (2) `rastgeleIkiMarkaHerYuzeydeSizintiYok` — ≥200 tohumlu rastgele çift × tüm okuma yüzeyleri, B verisi A sonucunda 0; (3) her yazma yüzeyi ≥1 `auditEvent` bırakır (aynı test, yüzey başına).
4 gün · Bağımlılık yok · Doğrulama: `scripts/test.sh`, ardından muhafız denetimi.

**G-02 · Codex `never` politikası ve ağ riski tasarımı** · Kural 6, 3, 7
Neden: onaysız komut + açık ağ + ev dizini okunur (gizlilik Y2, yalıtım B2, `bilinen-sinirlar §4`). Profil yalnız Unix soketi köprüsünü kapatıyor (`BrandSandbox.swift:108`).
Kabul: tasarım belgesi (sohbet turunda `untrusted`/`on-request` + mevcut `handleCodexRequest` onay kartı; okuma yasağına `~/Desktop`, `~/Downloads`, marka kökü dışı `~/Documents`); testler `codexSohbetTuruOnaysizPolitikaKullanmaz`, `codexProfiliMasaustuVeIndirilenleriKapatir` (+ gerçek sandbox varyantı); sentetik enjeksiyon senaryosu `MarkaDogrula codex`'te. Ağ kısıtı konamıyorsa gerekçe `bilinen-sinirlar`'a yazılır.
3 gün · Bağımlılık: — · Doğrulama: test + `swift run MarkaDogrula codex` (geçici `MARKA_WORKSPACE`/`MARKA_FOLDERS`).

**G-03 · Yedek / dışa aktarım / geri yükleme bütünlüğü** · Kural 2, 7
Neden: manifest isteğe bağlı (`try?` → "?"), dosya özeti yok; `copyTree` var olanı ezmez, fazlayı silmez (`:70-82`); `exportBrand` dosya kopyasını `try?` ile sessizce düşürür (`:204`).
Kabul: manifestte dosya başına SHA-256; testler `degistirilmisDosyaliYedekReddedilir`, `eksikDosyaliYedekReddedilir`, `manifestsizYedekReddedilir`, `geriYuklemeSonrasiDosyaKumesiYedekleAyni`, `disaAktarimEksikDosyayiRaporlar` (5).
2.5 gün · Bağımlılık: — · Doğrulama: test (yalnız geçici klasör).

**G-04 · Dinlenme halinde şifreleme değerlendirmesi** · Kural 6, 7
Neden: veri tabanı, `Files`, `Yedekler` ve dışa aktarım düz metin; şifreleme izi yok.
Kabul: karar belgesi — SQLCipher (GRDB uyumu, anahtar Keychain'de), `NSFileProtection` (macOS'ta etkisi), yalnız yedek/dışa aktarım şifreleme, FileVault varsayımı; seçilen yol için spike + `sifreliYedekAnahtarsizAcilmaz`; seçilmezse `bilinen-sinirlar` satırı. Önce `hazir-cozum-avcisi`.
2 gün · Bağımlılık: G-03 · Doğrulama: belge incelemesi + test.

**G-05 · Denetim izi hash zinciri ve değiştirilemezlik** · Kural 5
Neden: `auditEvent` UPDATE/DELETE'e açık; olaylar değiştirilse fark edilmez.
Kabul: `prevHash`/`hash` sütunu + `BEFORE UPDATE/DELETE` `RAISE`; testler `denetimOlayiGuncellenemez`, `denetimOlayiSilinemez`, `zincirTekSatirDegisinceKirilir`, `eskiOlaylarGocteZincireBaglanir` (4). Geri yükleme sonrası zincir doğrulanır.
2.5 gün · Bağımlılık: G-01 (yazma listesi) · Doğrulama: test + migration yedek testi.

**G-06 · İçe aktarım hostile girdi dayanıklılığı (fuzz)** · Kural 1, 2, 3
Neden: `importSkill` boyut sınırı yok (`Store+Skills.swift:51-57`); JoiTodo satır satır `JSONSerialization` (`JoiTodoImporter.swift:118-120`); kanıtsız yol #10.
Kabul: tohumlu derlem ≥500 girdi (10 MB, UTF-8 olmayan, BOM, NUL, iç içe ```, derin JSON, dev satır, başka markanın kimliği); `iceAktarimFuzzCokmezSinirliSuredeBiter` — çökme 0, girdi başına süre sınırı, hata açıklayıcı, ham kaynak değişmez.
2.5 gün · Bağımlılık: G-21 · Doğrulama: test.

## 🟡

**G-07 · Codex onay metni (Y2)** · Kural 6, 7 — Kabul: denetimdeki önerilen TR/EN metin; `l10n.py check` temiz; metin anahtarını arayan 1 test. 0.5 gün · Bağ.: G-02.
**G-08 · B2 kalanı: SKILL.md kökeni + içe aktarma onayı + ad eşleşme bildirimi** · Kural 3, 1 — Kabul: `iceAktarilanYetenekKokeniniSaklar`, `ayniAdliYetenekEklenincePasifBekler` (2). 2 gün.
**G-09 · B9 Codex devamında eski rol ölçümü** · Kural 1 — Kabul: `MarkaDogrula codex` adımı (rol → atama kaldır → devam → rol sorgusu); sonuç belgede "ölçüldü". 1 gün · Bağ.: G-02.
**G-10 · Kanıtsız yollar #1–6** · Kural 1, 6 — Kabul: 6 test (yürütücü `calisan_oner` reddi, Anthropic `tools` JSON'unda yokluğu, Codex `startThread(tools:)`, atamadan çıkarılınca `personaPrompt` boş, 6000 bütçe, tüm markalar istemi). 1.5 gün.
**G-11 · Dışa aktarım kapsamı** · Kural 1, 7 — Neden: `BrandExport`'ta finans, AI oturum/öneri, denetim olayı yok (finans `brandId` taşıyor). Kabul: `brandIdSutunluHerTabloDisaAktarimdaYaDaGerekceliDislamada` (şema taraması). 1 gün.
**G-12 · O2 mutlak "veri bu Mac'te" metinleri** · Kural 7 — Kabul: metinler düzeltildi, depo genelinde ifade araması 0. 0.5 gün.

## 🟢

**G-13 · Test sayısı tutarsızlığı** · Kural 7 — 255 `@Test` / belge 200. Kabul: belge güncel + sayıyı bağlayan 1 test (README sürüm testi gibi). 0.5 gün.
**G-14 · B8 `calisan_oner`** · Kural 1 — ekip satırına kimlik, `saglayici` enum. Kabul: 2 test. 0.5 gün.
**G-15 · D1 tüm markalar geçmişi** · Kural 6 — izin daralınca oturum durur. Kabul: `izinDaralincaTumMarkalarOturumuDevamEtmez`. 0.5 gün.
**G-16 · D3 varsayılan anahtar** · Kural 6 — `{ nil }`; `TercihYalitimTests` MarkaCore + MarkaDogrula'yı da tarar. Kabul: 1 test. 0.5 gün.
**G-17 · D4 göreli yol** · Kural 6 — Kabul: `codexTalimatiEvDiziniYoluTasimaz`. 0.5 gün.
**G-18 · D5 kişisel iz** · Kural 6 — `NSUserName()`; tarama deseni depo dışı. Kabul: izlenen dosyalarda kullanıcı adı araması 0. 0.5 gün.
**G-19 · D6 + D8 metinleri** · Kural 7 — Kabul: önerilen TR/EN metin; `l10n.py check` temiz. 0.5 gün.
**G-20 · D7 rapor özeti marka eşleşmesi** · Kural 1, 6 — `ReportContent.brandId`. Kabul: `baskaMarkaninIcerigiOzetlenemez`. 0.5 gün.
**G-21 · `importSkill` sınırları** · Kural 3 — Kabul: `buyukDosyaReddedilir`, `utf8OlmayanReddedilir`, `serbestMetinleCakisanAdBildirilir` (3). 0.5 gün.
**G-22 · Kök neden / kanıt bağı testi** · Kural 7 — denetim belgelerindeki "Kanıt testi" adları gerçekten var mı. Kabul: `denetimBelgesindekiHerKanitTestiMevcut` (belge → test adı eşleşmesi, eksik 0). 0.5 gün.

## Doğrulama zinciri (her görev)
`scripts/test.sh` + `scripts/build-app.sh` + `python3 scripts/l10n.py check` temiz → muhafız/gizlilik denetimi → `kalite-kapisi`. Gerçek veri alanı, Keychain ve `open` yasağı alt ajan görevine kopyalanır.
