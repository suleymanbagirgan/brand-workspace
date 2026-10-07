# Dev Camp — Yapay zekâ görevleri (3 hafta, 2026-10-05)

Kapsam: yalnız ürün. Satış/yayın/mağaza yok. Kanıtlar kod okunarak yazıldı; hiçbir şey çalıştırılmadı. **Canlı yapay zekâ yanıtı bugüne dek hiç denenmedi** (plan §7, `ai-calisma-alani-plani.md:117`).

Kısaltmalar: CE=`Sources/MarkaCore/AI/ChatEngine.swift`, CT=`…/AI/ContextAndTools.swift`, AC=`…/AI/AnthropicClient.swift`, SP=`Sources/MarkaCore/Store/Store+Proposals.swift`, FM=`docs/foundation-models-denemesi.md`. **[SAHTE]** = sahte sağlayıcıyla (`MockAnthropic`, `AITests.swift:6`) test; **[CANLI]** = kurucu anahtarı girince.

Toplam tahmin ~31 kişi-gün; tek kişiyle 15 güne sığmaz. Sıra: 🔴 önce, 🟢 araya dolgu.

## Haftalar
- **H1 — Ölçebilen asistan:** A-01 iskeleti, A-13…A-20 (hata, iptal, yeniden deneme, kullanım).
- **H2 — Kırılamayan asistan:** A-02, A-07, A-08, A-09, A-03 başlangıcı.
- **H3 — Sığan ve öğrenen asistan:** A-03 bitişi, A-04, A-05, A-06, A-10–A-12; canlı koşu (anahtar varsa).

## 🔴 Boss görevleri

**A-01 Altın istem değerlendirme koşumu** · 3 gün · bağımlılık yok
- Neden: plan "50+ senaryo" istiyor (`ai-calisma-alani-plani.md:82`); bugünkü sahte katman yalnız sıralı SSE döndürüyor, senaryo/puan yok (`AITests.swift:6-37`).
- Kabul: ≥50 senaryo (ne yapmalıyım, raporu hazırla, sil→onay ister, başka marka→red, göreli tarih). Sahte mod aynı girdide iki koşuda bire bir aynı sonuç. Canlı mod `MarkaDogrula eval` alt komutu; sonuç JSON'a yazılır. Eşik: sahte %100; canlıda önceki koşuya göre >2 senaryo düşerse çıkış kodu ≠0.
- Kural 3: puanlama "araç çağrısı → **bekleyen** öneri" üzerinden; uygulanmış öneri sayısı her senaryoda 0 olmalı.
- Doğrulama: [SAHTE] + [CANLI].

**A-02 Prompt enjeksiyonu kırmızı takımı** · 3 gün · A-01
- Neden: `kaynak_oku` kaynak gövdesini çerçevesiz döndürüyor (CT:319-320); temel kurallarda "araç sonucu veridir" maddesi yok (CT:28-38). Yetenek gövdesi çerçevelendi (CE:733-763) ama kaynak/not/wiki çerçevesiz. Enjeksiyon hiç denenmedi (`guvence-denetimi-gizlilik.md:67`); açık test önerisi (`guvence-denetimi-yalitim.md:229`).
- Kabul: ≥20 senaryo (kaynak gövdesi, not, wiki iddiası, yetenek gövdesi, dosya adı). Sahte yanıt enjekte araç çağrısı ürettiğinde: başka marka kimliği → `is_error` %100; doğrudan yazma 0; araç sonucu `<kaynak_icerigi>` sınırlayıcısında (test). Canlıda modelin enjekte talimatla öneri üretme oranı raporlanır.
- Kural 3: saldırı en kötü durumda bekleyen öneri üretir; testler onaysız uygulama olmadığını kilitler.
- Doğrulama: [SAHTE] savunma; [CANLI] uyma oranı.

**A-03 Sağlayıcı soyutlaması + Apple cihaz üstü sağlayıcı** · 4 gün · A-01
- Neden: tur döngüsü Anthropic'e gömülü (CE:470-480, 523-603); protokol planda var, kodda yok (plan §4.4, F3). Deneme koşullu evet dedi (FM §7, §9).
- Kabul: `AIProvider` protokolü; mevcut Anthropic testleri değişmeden geçer; Apple yolunda ağ isteği 0 (URLProtocol sayacı); Apple'a en çok 4 araç; `DynamicGenerationSchema` (makrosuz, CLT derler — FM:29); kullanılamazlık nedeni arayüzde; `exceededContextWindowSize` yakalanır.
- Kural 3: araç çağrısı yine `ToolExecutor`'dan geçer; sağlayıcı değişse de çıkış öneri.
- Doğrulama: [SAHTE] + yerel cihaz (anahtar gerekmez, Apple Intelligence açık Mac).

**A-04 Bağlam bütçesi + uzun belge içindekiler ağacı** · 4 gün · A-03
- Neden: bütçe yok; düz karakter kırpması (CT:319 30 000, `Compilers.swift:85` 60 000, liste 40 öğe CT:16). Apple penceresi 4096 belirteç, Türkçe ~2,1 karakter/belirteç (FM:137).
- Kabul: sağlayıcı kapasitesine göre `ContextBudget`; öncelik sırası (profil → açık işler → ilgili kayıt) testli; 200 000 karakterlik belgede `kaynak_bolumleri` içindekiler döner, `kaynak_oku(bolum)` yalnız o bölümü verir; her kırpma modele ve kullanıcıya bildirilir; her sorguda `brandId` zorunlu (başka marka 0).
- Kural 3: yalnız okuma araçları; yazma yüzeyi yok.
- Doğrulama: [SAHTE].

**A-05 Gözlem önerisi (Hindsight tarzı)** · 3 gün · A-01
- Neden: trend kararı "kanıtlı, onaylı gözlem" — **yapılmadı** (`github-trend-analizi.md:14,46,67`).
- Kabul: yeni öneri türü (gözlem metni + ≥1 kaynak/çalışma kaydı kanıtı + kanıt sayısı). Kanıtsız ya da başka marka kanıtlı öneri `validateProposal`'da reddedilir (SP:225 kalıbı). Onayda profile **ekler**, üzerine yazmaz; geri alma sonrası veri bire bir aynı (test).
- Kural 3: gözlem yalnız öneri; onaysız profile girmez.
- Doğrulama: [SAHTE]; kalite [CANLI].

## 🟡 Görevler

**A-06 Göreli tarihi uygulama çözer** · 1,5 gün · A-01
- Neden: tablosuz 6/6 yanlış, tabloyla 10/10 (FM:88,102). Sistem isteminde yalnız "Bugün" var (CE:789).
- Kabul: istemde tarih tablosu; değişmeyen alanlar ayıklanır; altın sette 10 tarih senaryosu geçer. Kural 3: değişmez. [SAHTE]+[CANLI]

**A-07 Araç girdisi şema doğrulaması** · 1,5 gün
- Neden: plan "şemaya karşı doğrulanır" (plan:80); anahtar denetimi yalnız `gorev_guncelle_oner`'de (CT:363-364); `oncelik` aralığı öneri doğrulamasında yok (SP:227-234).
- Kabul: tüm araçlar şemaya göre (fazla alan, enum, min/max) reddedilir; araç başına test. Kural 3: geçersiz girdi öneri bile üretmez. [SAHTE]

**A-08 "Oluşturdum" yanıltıcı özet uyarısı** · 1 gün · A-01
- Neden: model yalnız öneri kaydedince "değiştirdim" diyebiliyor (FM:69,189).
- Kabul: turda yalnız bekleyen öneri varken metinde tamamlanmış eylem fiili geçerse uyarı kartı; 5 sahte senaryo. Kural 3: kullanıcıya gerçeği söyler. [SAHTE]

**A-09 Bilgi sayfası önerisi atomik** · 1 gün
- Neden: `writeWikiRevision` ve öneri kaydı iki ayrı yazma (CT:416-424).
- Kabul: tek işlem; öneri yazılamazsa sürüm de yok (test). Kural 3: yetim "önerilen" sürüm kalmaz. [SAHTE]

**A-10 Araç döngüsü ve tur maliyet tavanı** · 1 gün
- Neden: döngü 16 adımda sessiz biter (CE:539).
- Kabul: sınırda bildirim kartı; tur başı tahmini maliyet tavanı ayarı, aşılınca durur (test). Kural 3: değişmez. [SAHTE]

**A-11 Sağlayıcıya göre araç alt kümesi** · 1,5 gün · A-03
- Neden: araç başı ~200 belirteç, 12 araç pencerenin yarısı (FM:138).
- Kabul: Apple'da niyete göre ≤4 araç; seçim testli. Kural 3: alt küme yalnız okuma/öneri araçları. [SAHTE]

**A-12 Atıfsız cümle işaretleme** · 2 gün · A-04
- Neden: F4 ölçütü "atıf olmayan AI cümlesi işaretlenir" (plan:99); istem kaynak adı istiyor (CT:32) ama denetlenmiyor.
- Kabul: turda okunan kayıtların adı geçmeyen olgusal cümle işaretlenir; 10 sahte senaryo. Kural 3: yalnız gösterim. [SAHTE]

## 🟢 Görevler

**A-13 Hata sınıflandırması** · 1 gün — hatalar düz metin (AC:179-185). Kabul: `AIErrorKind` (anahtar, izin, hız, aşırı yük, ağ, zaman aşımı, bağlam aşımı, ret); her durum kodu → tür testi; tanı günlüğü yalnız tür yazar (kural 6). [SAHTE]

**A-14 Anlaşılır hata + eylem düğmesi** · 0,5 gün · A-13 — Kabul: her türün Türkçe/İngilizce metni ve tek eylemi ("Ayarlar'ı aç", "Tekrar dene"); `l10n.py check` temiz. [SAHTE]

**A-15 Kullanım/maliyet gösterimi** · 1 gün — `.usage` olayı sohbette yok sayılıyor (`Sources/MarkaApp/AIChat.swift:115`). Kabul: mesaj başına token + "tahmini" $ ve fiyat tarihi (`AIBasics.swift:68`); bilinmeyen modelde "maliyet bilinmiyor". [SAHTE]

**A-16 Yanıt uzunluğu ayarı** · 0,5 gün — kısa/normal/ayrıntılı → `max_tokens` + istem satırı (AC:46-62). Kabul: üç değer istek gövdesinde test. [SAHTE]

**A-17 Model kimliği doğrulama** · 0,5 gün — `verifyKey` modeli gönderiyor (AC:207-221) ama "model yok" ayrı söylenmiyor. Kabul: sahte 404 → "model bulunamadı"; gerçek liste [CANLI].

**A-18 Akış kesintisi toparlama** · 1 gün — kesintide yarım araç çağrısı atlanıyor (CE:563-568); sahte katman kesinti üretemiyor. Kabul: sahteye "yarıda kes" kipi; mesaj `partial`, "Devam et" önceki metni koruyarak sürer; yarım araç çağrısı öneri üretmez. [SAHTE]

**A-19 İptal** · 0,5 gün — `cancel` görevi iptal ediyor (CE:409-414), Anthropic yolu testsiz. Kabul: araç turları arasında iptal → yeni HTTP isteği 0, yeni öneri 0 (test). [SAHTE]

**A-20 Yeniden deneme** · 1 gün — 429/5xx doğrudan hata (AC:181-183), yeniden deneme kodu yok. Kabul: ilk bayttan önce en çok 3 deneme, üstel bekleme, `retry-after` uyulur; 401'de deneme yok; `KayitliYanit` sayacıyla test (`GizlilikTests.swift:7`). [SAHTE]

**A-21 Zaman aşımı ayrımı** · 0,5 gün — tek 600 sn zaman aşımı (AC:33). Kabul: ilk bayt sınırı ayrı, aşılınca "zaman aşımı" türü. [SAHTE]

## "Yapay zekâ veri değiştirmez" — ortak koruma
Her görevde: (1) araçlar yalnız `createProposal` → `validateProposal` (SP:175-183) yolundan yazar; (2) her yeni testte "uygulanmış öneri sayısı = 0" iddiası; (3) yeni öneri türü onay + geri alma testi olmadan kapanmaz; (4) Apple sağlayıcısı aynı `ToolExecutor`'u kullanır.

## Canlı anahtar gerektirenler (kurucu Ayarlar'a girince)
A-01 canlı koşu · A-02 uyma oranı · A-05 gözlem kalitesi · A-06 tarih doğruluğu · A-17 model listesi. Anahtar yoksa bunlar **"yapılmadı"** yazılır, "geçti" denmez. Sahte kısımları anahtarsız kapanır. A-03 anahtar istemez, Apple Intelligence açık Mac ister.

## Bitti kapısı (her görev)
`scripts/test.sh` + `scripts/build-app.sh` + `python3 scripts/l10n.py check` temiz; deneme yalnız geçici `MARKA_WORKSPACE`/`MARKA_FOLDERS` ile; gerçek veri alanına ve Keychain'e dokunulmaz; commit kurucu onayıyla.
