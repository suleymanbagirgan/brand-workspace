# GitHub yapay zekâ depoları → Workspace AI: 30 görevlik bütünleştirme planı

Tarih: 2026-10-05. Hazırlayan: ürün yöneticisi rolü. Durum: **plan**. Bu belgedeki hiçbir görev "yapıldı" sayılmaz.
Aşama: **kuluçka, yalnız ürün.** Yayın, satış, harcama, imzalama ve mağaza gönderimi kapsam dışıdır.

"Bütünleştirmek" burada **fikri, biçimi ya da yöntemi özgün kodla ürüne işlemek** demektir. Hiçbir depo bağımlılık olarak eklenmez ve hiçbir deponun kodu kopyalanmaz (bkz. §6 lisans notu tablosu). Bu, `docs/github-trend-analizi.md` §E'deki kuralın devamıdır.

Girdiler: `docs/pazar/github-radar-2026-10-05.md` (16 proje; kurucu "ön yargısız, iyimser bak" dedi), `docs/github-trend-analizi.md` (60 repo, Durum tablosu), `docs/ai-calisma-alani-plani.md`, `docs/dagitim-ve-saglayicilar.md`, `docs/sandbox-gecis-analizi.md`, `docs/bilinen-sinirlar.md`, `docs/Workspace AI Dev CAMP PLAN.md` (Radar fırsatlarındaki 8 fikir görev olarak bağlandı, bkz. §2), `docs/foundation-models-denemesi.md`, mevcut kod (`Sources/MarkaCore`, `Sources/MarkaApp`), GitHub API (`gh api repos/<ad>`, 2026-10-05/06 UTC) ve web araması.

---

## 0. Değişmez kurallar (30 görevin hepsinde geçerli)

1. **Marka yalıtımı.** Her okuma ve yazma `brandId` ile kapsanır. Başka markanın verisi hiçbir sonuçta, bağlamda, gözlemde, şablonda ya da izde görünmez. Yeni her Store yüzeyi ya `brandId` alır ya da `docs/yalitim-izin-listesi.md`'ye gerekçesiyle girer (`YalitimOzellikTests` bunu yakalar).
2. **Yapay zekâ yalnız öneri üretir, insan onaylar.** Doğrudan yazma yoktur. Yeni yapay zekâ çıktısı (gözlem, şablon, dış ajan zarfı, radar özeti) bekleyen öneri olarak düşer. Onayla uygulanır ve geri alınabilir. Her yazma `Store.audit` bırakır.
3. **İzin verilmeyen sağlayıcıya içerik gitmez.** Marka × sağlayıcı izni zorunludur ve varsayılan olarak kapalıdır. Günlük, tanı, iz kaydı ve ölçüm marka adı ya da içerik taşımaz.
4. **MAS/sandbox uyumu.** Ağ çağrısı ve dış süreç yalnız `#if !MAS` içinde ya da izinli yolda olur. `scripts/mas-tarama.sh` temiz kalır. Kullanıcının kurulu ikilisi çalıştırılmaz.
5. **Yapmadığımızı vaat etmeyiz.** Ölçülmeyen ya da doğrulanmayan şey `docs/bilinen-sinirlar.md`'ye yazılır. Arayüz metni mutlak gizlilik cümlesi kurmaz.
6. **Çeviri anahtarı Türkçedir.** Metin `L("Türkçe metin")` ile yazılır, İngilizcesi `Resources/en.lproj/Localizable.strings`'e eklenir ve `python3 scripts/l10n.py check` temiz kalır.
7. **Yeni migration yalnız gerekçeyle açılır.** Gerekçe görevde yazılıdır. Bir dalgada en çok **bir** migration görevi olur. Numara uygulama anında son migration'dan sonraki sayıdır (bugün son: `v9_olcek_indeksleri`). Bu plandaki `v10`/`v11`/`v12` yer tutucudur, çünkü şu an başka ajanlar da çalışıyor.
8. **Her görev test ile kapanır ve `scripts/gelistir-kapisi.sh` (bayraksız) `KAPI: GEÇTİ` verir.** Ekranla doğrulanamayan kısım "doğrulanamadı" diye raporlanır, "bitti" sayılmaz.
9. **Depo herkese açıktır.** Örneklerde yalnız uydurma adlar kullanılır (Deneme Yangın, Kuzey Lojistik, Örnek Kafe Zinciri). Gerçek veri alanına, `open` komutuna ve çalışan uygulama sürecine dokunulmaz. Deneme yalnız geçici `MARKA_WORKSPACE` ve `MARKA_FOLDERS` ile yapılır. Commit ve push yalnız kurucu onayıyla olur. Alt ajana iş verirken bu yasaklar göreve **kopyalanır**.
10. **Dış kod yoktur.** Depolardan yalnız fikir, biçim ve yöntem alınır. Uygulama özgün yazılır. AGPL ve FSL lisanslı depolarda kod okunmaz, yalnız README düzeyinde fikir alınır.

**Dosya sahipliği kuralı.** Aynı dalgadaki görevler aynı dosyaya dokunmaz. Mevcut dosyada yalnız hedefli ekleme yapılır: yeni `case`, yeni fonksiyon, tek satırlık bağlantı. **Tek bilinçli istisna** `Resources/en.lproj/Localizable.strings`'tir. Bu dosyaya yalnız ekleme yapılır: her görev dosyanın sonuna kendi `/* E-xx */` yorumlu bloğunu yazar, dalga sonunda bloklar sırayla birleştirilir ve kapıdaki `l10n check` denetler. `Package.swift` hiçbir görevde değişmez: `Tests/Fixtures/**` dosyaları kaynak (resource) olarak bildirilmez, testte `#filePath`'e göreli yolla okunur.

**Sıcak dosyalar ve dalgaları** (çakışma denetimi için):

| Dosya | Dokunan görev (dalga) |
|---|---|
| `Database/AppDatabase.swift` (migration) | E-01 (A) · E-07 (B) · E-21 (E) |
| `Model/Models.swift` | E-06 (B) · E-11 (C) · E-17 (D) · E-25 (E) |
| `AI/ContextAndTools.swift` | E-06 (B) · E-13 (C) · E-16 (D) · E-21 (E) |
| `AI/ChatEngine.swift` | E-11 (C) · E-20 (D) · E-25 (E) · E-30 (F) |
| `MarkaApp/AppModel.swift`, `SettingsView.swift` | E-11 (C) · E-20 (D) · E-25 (E) |
| `MarkaApp/ProposalInbox.swift` | E-06 (B) · E-17 (D) · E-22 (E) |
| `MarkaApp/CompanyView.swift` | E-14 (C) · E-18 (D) |
| `MarkaApp/BrandSections.swift` | E-12 (C) · E-21 (E) |
| `Status/Diagnostics.swift` | E-05 (A) · E-30 (F) |
| `scripts/gelistir-kapisi.sh` | E-15 (C) · E-26 (F) |

---

## 1. Ne zaten var (tekrar önerilmez)

`docs/github-trend-analizi.md` §E ve kamp günlüğüne göre bunlar yapıldı: org ağacı ve işe alımın onaya düşmesi (paperclip), rol ile oturumun ayrılması (openrig), SKILL.md modeli ile tek dosya içe ve dışa aktarma (`Skill`, `SkillMarkdown`, `importSkill`), 3 hazır yetenek paketi (özgün metin), `AIProvider` katmanı ve `FakeProvider` (H2-01), kırmızı takım ve altın istem koşucusu (`EnjeksiyonKirmiziTakimTests`, `Eval/AltinIstem*`), liste bağlam bütçesi (`ContextLimits.listItems`, `BaglamButcesiTests`), docx/rtf/pdf düz metin çıkarımı (`TextExtractor`), terminal öneri JSON köprüsü (`SuggestionInbox`, şema 1), yalıtım özellik testi, kapsam ölçümü ve tek komut kapı.

Bu plan yalnız **yapılmayanları** ya da var olanın açıkça "yapılmadı" diye yazılmış uzantısını ele alır. Bunlar: hindsight gözlemi (Durum #10), PageIndex (Durum #11), yanıt uzunluğu (Durum #12, kalan kısmı), SKILL.md kökeni ve önizlemesi (`bilinen-sinirlar` §4 "Yapılmadı"), ekip şablonları, yerel model, yolculuk testleri ve yerel kara kutu.

## 2. Radar'dan ürüne (iyimser okuma, sonra sınır)

| Radar projesi | Ürüne ne katabilir (önce) | Sınır (sonra) | Görev |
|---|---|---|---|
| tester-army/e2e | Doğal dille yazılmış kullanıcı yolculuğu. Başarılı adımı kaydedip modelsiz yeniden oynatma | Ürün web değil, SwiftUI. Yolculuk çekirdek düzeyinde ve sahte sağlayıcıyla koşar | E-09, E-26 |
| pbakaus/impeccable | Tasarım kalite kapısı. `PRODUCT.md`/`DESIGN.md` ile kalıcı tasarım bağlamı | Kural yaratıcı yargının yerini tutmaz. Kapı yalnız eşik ve gerilemeyi yakalar | E-04, E-15, E-27 |
| coreyhaines31/marketingskills | Ortak ürün bağlamı ve birlikte çalışan yetenekler. Danışmana en yakın içerik | Paket zaten özgün metinle yapıldı. Burada yalnız **klasör biçimi** ve `references/` alınır | E-02, E-07, E-14 |
| DietrichGebert/ponytail | "Önce yazmadan çözebilir miyim" ilkesi. Kısa yanıt | Ajan dosyalarına ilke ve yanıt uzunluğu ayarı olarak girer | E-20, E-27 |
| earthtojake/text-to-cad | (ürünle bağı yok) | Kapsam dışı (§8) | — |
| Panniantong/Agent-Reach | Rakip ve pazar takibi, yani **marka radarı** | Kazıma, giriş ve anti-bot MAS ile ve gizlilikle çelişir. Radar yalnız kullanıcının eklediği bağlantı ve notlarla çalışır | E-21 |
| getsentry/sentry | Kara kutu: hata anına giden içeriksiz iz | SDK yok, veri dışarı gitmez. Yerel iz kırıntısı ve tanı raporu | E-05, E-30 |
| calesthio/OpenMontage, OpenCut-app/OpenCut | (video üretimi) | Kapsam dışı (§8) | — |
| pingdotgg/t3code | Birden çok ajanın tek yüzeyden izlenmesi | Uzaktan erişim ve ağ kapsam dışı. Fikrin özü "ajan-bağımsız onay" olarak alınır | E-17 |
| caddyserver/caddy | (sunucu katmanı) | Ürün yerel uygulama, sunucu yok. Kapsam dışı | — |
| michael-denyer/pstack-claude | Hangi ajan olursa olsun aynı prosedür | **Ajan-bağımsız onay protokolü**: herhangi bir ajanın üretebileceği tek öneri zarfı | E-17 |
| addyosmani/agent-skills | Kıdemli çalışma yöntemini küçük yeteneklere bölmek | Yetenek içe aktarma (klasör) ve ekip şablonu | E-02, E-10 |
| thedotmack/claude-mem | Oturumlar arası kalıcı hafıza | Hafıza otomatik yazılmaz. **Onaylı marka belleği**: kanıt sayılı gözlem, onayla girer, bayatlar | E-01, E-06, E-12, E-16 |
| garrytan/gstack | Rollerden oluşan sanal ekip | **Ekip şablonları**: şablon kurulumu = onay bekleyen çalışan önerileri | E-10, E-18 |
| antirez/ds4 | Şirket içinde çalışan model | Ürüne doğrudan girmez (donanım, beta). Fikir: **yerel model sağlayıcısı**, yerel uç nokta ya da Foundation Models üzerinden | E-03, E-11, E-24, E-25 |

CAMP Radar fırsatlarındaki 8 fikrin görev karşılığı:

| Fikir | Görevler |
|---|---|
| Ekip şablonları | E-10, E-18 |
| Onaylı marka belleği | E-01, E-06, E-12, E-16, E-22 |
| Ajan-bağımsız onay protokolü | E-17 |
| Yetenek içe aktarma | E-02, E-07, E-14 |
| Yerel model sağlayıcısı | E-03, E-11, E-24, E-25, E-29 |
| Marka radarı | E-21 |
| Ajan dosyalarına kalite ilkeleri | E-27 |
| Yolculuk betikleri | E-09, E-26 |

## 3. Yeni bulunan açık kaynak depolar (web araması + GitHub API)

Radarda ve trend kataloğunda **olmayan** depolar aşağıda. Lisans ve "son etkinlik" (`pushed_at`, yani son push; sürüm değil) `gh api repos/<ad>` ile 2026-10-05/06 UTC'de okundu. **Yıldız ve sürüm sayısı bilinçli olarak yazılmadı.**

| # | Depo | Alan | Lisans (API) | Son push | Ürüne fikir |
|---|---|---|---|---|---|
| 1 | getzep/graphiti | ajan hafızası | Apache-2.0 | 2026-10-05 | Zamansal olgu: yeni kanıt eski olguyu silmez, `invalidatedAt` ile kapatır → gözlem bayatlama (E-01, E-16) |
| 2 | mem0ai/mem0 | ajan hafızası | Apache-2.0 | 2026-10-05 | Hafıza işlemleri: ekle, güncelle, sil, değiştirme → öneri türleri (E-06) |
| 3 | letta-ai/letta | ajan hafızası | Apache-2.0 | 2026-09-10 | Bağlamda sabit "çekirdek bellek bloğu" ile aranan arşiv ayrımı → bağlama yalnız onaylı ve geçerli gözlemler (E-16) |
| 4 | ml-explore/mlx-swift-lm | yerel model / MLX | MIT | 2026-10-05 | Swift'te cihaz üstü LLM. MAS'ta yerel model araştırması (E-29) |
| 5 | osaurus-ai/osaurus | yerel model, macOS | MIT | 2026-10-05 | Yerel sunucuya bağlanan yerli macOS uygulaması deseni → yerel uç nokta sağlayıcısı (E-03, E-11) |
| 6 | carbocation/CarbocationLocalLLM | yerel model, Swift | MIT | 2026-08-25 | Tek Swift API arkasında yerel model ya da Apple Intelligence; model ayar paneli (E-25, E-29) |
| 7 | docling-project/docling | belge/PDF anlama | MIT | 2026-10-05 | Belgeyi başlık, tablo ve okuma sırasıyla yapıya çevirme → biçimli Markdown çıkarımı (E-19) |
| 8 | microsoft/markitdown | belge → Markdown | MIT | 2026-10-04 | Ofis belgesini LLM'e uygun Markdown'a çevirme (E-19) |
| 9 | awaithumans/awaithumans-human-in-the-loop-ai-agents | insan-döngüde onay | Apache-2.0 | 2026-09-11 | Tipli yanıt ve denetim izi olan "dur, insana sor, devam et" zarfı (E-17) |
| 10 | humanlayer/humanlayer | insan-döngüde onay | API: NOASSERTION (LICENSE dosyası "Apache Software License 2.0" bölümü taşıyor; tamamı okunmadı) | 2026-06-19 | Yüksek riskli araç çağrısını onaya bağlama (E-17) |
| 11 | promptfoo/promptfoo | değerlendirme / kırmızı takım | MIT | 2026-10-06 | Senaryo matrisi ve saldırı türü kataloğu → yeni kanallar için kırmızı takım (E-23) |
| 12 | langfuse/langfuse | yapay zekâ izlenebilirliği | API: NOASSERTION (karma; LICENSE "Portions…" diye başlıyor) | 2026-10-05 | Tur başına iz: süre, belirteç, araç, sonuç → **içeriksiz** yerel tur izi (E-30) |
| 13 | modelcontextprotocol/swift-sdk | MCP | API: NOASSERTION (LICENSE: MIT'ten Apache-2.0'a geçiş metni) | 2026-05-07 | MAS'ta süreç-içi ya da HTTP MCP istemcisi araştırması (E-28) |
| 14 | twentyhq/twenty | danışmanlık / CRM | API: NOASSERTION (LICENSE: çoğunlukla AGPLv3 + ticari dosyalar) | 2026-10-06 | Yalnız kavram düzeyinde okundu (kişi, fırsat, takip). Kod okunmaz. Kapsam dışı kararı §8'de |
| 15 | basicmachines-co/basic-memory | yerel Markdown hafıza | AGPL-3.0 | 2026-10-06 | "Bilgi düz dosyada, insan okuyabilir" fikri. Bizde wiki zaten var. Kod okunmaz |

Arama sonucunda adı geçen ama deposu **doğrulanamayanlar** (tabloya girmedi): Impri, Phantasm, hitloop, Kalairos, Ryumem, a11y-lens, Intopia A11y skill. Bunlar §10'da listelendi.

---

## 4. Görevler (E-01 … E-30)

Katman: **çekirdek** = `Sources/MarkaCore`, **arayüz** = `Sources/MarkaApp`, **araç** = `scripts/`, testler ve değerlendirme, **belge** = `docs/` ve ajan dosyaları. Boyut: S ≈ yarım gün, M ≈ 1–2 gün, L ≈ 3+ gün (**ölçülmedi**, kamp deneyimi tahminlerin bol olduğunu gösterdi). Her kabul ölçütüne ek olarak **`scripts/gelistir-kapisi.sh` → `KAPI: GEÇTİ`** zorunludur (§0 kural 8), bu yüzden tek tek tekrar yazılmadı.

### Dalga A: temeller (yeni dosya ağırlıklı)

**E-01 · Kanıt sayılı marka gözlemi modeli**
- Kaynak: vectorize-io/hindsight, getzep/graphiti, thedotmack/claude-mem
- Ürüne dönüşen: Yapay zekânın bir marka hakkında öğrendiği şey "gözlem" olarak saklanır: tek cümle, dayandığı kaynak kimlikleri ve kanıt sayısı. Gözlemin üzerine yazılmaz. Yeni kanıt eskisini `invalidatedAt` ile kapatır, böylece "ne zaman neyi biliyorduk" geçmişi kaybolmaz.
- Katman: çekirdek
- Dosya: YENİ `Model/Observation.swift`, YENİ `Store/Store+Observations.swift`, YENİ `Tests/MarkaCoreTests/GozlemTests.swift`. `Database/AppDatabase.swift`'e yalnız yeni migration `v10_gozlemler` eklenir. **Gerekçe:** yeni tablo `observation (id, brandId, statement, evidenceSourceIds, evidenceCount, status, validFrom, invalidatedAt, supersededBy, createdAt)`; mevcut tablolara dokunulmaz.
- Kabul: ≥ 8 test. Kapsananlar: oluşturma yalnız onay yolundan (`actor` doğrudan `.ai` olamaz), boş kanıtta ret, başka marka kaynağına dayanmada ret, yerine geçmenin eskisini silmeyip kapatması, `observations(brandId:)`'ın başka markayı hiç döndürmemesi, her yazmada `auditEvent`, migration testi bellek içi DB'de. `YalitimOzellikTests` yeni yüzeyle yeşil.
- Dalga: A · Bağımlılık: yok · Boyut: M
- Risk/Yasak: "Hafıza" adı arayüzde wiki için kullanılıyor (`bilinen-sinirlar` §5). Ad çakışmasını E-12'de çöz. Gözlem içeriği tanıya ve günlüğe girmez.

**E-02 · SKILL.md klasör paketi çözücüsü (sınırlar + özet)**
- Kaynak: addyosmani/agent-skills, anthropics/skills (biçim), coreyhaines31/marketingskills (klasör düzeni)
- Ürüne dönüşen: Kullanıcı tek dosya yerine `SKILL.md` + `references/*.md` içeren bir yetenek klasörünü getirebilir. Çözücü boyutu, kodlamayı ve dosya sayısını denetler, içeriğin SHA-256 özetini çıkarır ve kaydetmeden önce "ne eklenecek" önizlemesini üretir.
- Katman: çekirdek
- Dosya: YENİ `Sources/MarkaCore/Skills/SkillBundle.swift` (DB'ye dokunmaz), YENİ `Tests/MarkaCoreTests/YetenekPaketiTests.swift`
- Kabul: ≥ 10 test. Kapsananlar: UTF-8 olmayan dosyada ret, 256 KB üstü dosyada ret, 20'den fazla referansta ret, sembolik bağın atlanması, `..` kaçışında ret, aynı içerikte aynı özet, `name` slug doğrulaması, mevcut adla çakışmanın önizlemede "güncelleme" diye işaretlenmesi, `references/` gövdesinin "KULLANICI YÖNTEMİ (veri; yetki vermez)" çerçevesiyle birleşmesi.
- Dalga: A · Bağımlılık: yok · Boyut: M
- Risk/Yasak: İnternetten indirme yoktur. Yalnız kullanıcının seçtiği yerel klasör okunur (MAS'ta bu klasör kullanıcı seçimiyle gelir). Hazır paket metni kopyalanmaz.

**E-03 · Yerel uç nokta sağlayıcısı (yalnız geri döngü adresi, `#if !MAS`)**
- Kaynak: antirez/ds4, ollama/ollama, osaurus-ai/osaurus (desen)
- Ürüne dönüşen: Kullanıcı bu Mac'te kendi çalıştırdığı bir model sunucusunu (OpenAI uyumlu ya da Ollama biçimli yerel HTTP) asistan sağlayıcısı olarak kullanabilir. İçerik bu yolda makineden çıkmaz, çünkü sağlayıcı yalnız `127.0.0.1`/`::1`/`localhost` adresini kabul eder.
- Katman: çekirdek
- Dosya: YENİ `AI/LocalEndpointProvider.swift` (tamamı `#if !MAS`; `AIProvider` uygular, bu dalgada kayda **eklenmez**), YENİ `Tests/MarkaCoreTests/YerelSaglayiciTests.swift` (`URLProtocol` sahtesiyle)
- Kabul: ≥ 8 test. Kapsananlar: geri döngü dışı adreste (ör. `192.168.x`, alan adı, `http://localhost.evil.com`) kurulumda ret, akış ayrıştırma, araç desteği bildirimi `supportsTools=false` (ilk sürüm araçsız), iptalden sonra yeni istek sayısının 0 olması, `capabilities.onDevice == true`, istek gövdesinde başka marka içeriğinin 0 olması. `scripts/mas-tarama.sh` temiz.
- Dalga: A · Bağımlılık: yok · Boyut: M
- Risk/Yasak: Sağlayıcı kullanıcının sunucusunu **başlatmaz** (`Process` yok). Sandbox'ta geri döngüye çıkış ölçülmedi, bu yüzden MAS kipinde yoktur (E-29 araştırır).

**E-04 · Tasarım denetimi betiği (impeccable esinli, özgün)**
- Kaynak: pbakaus/impeccable (kalite kapısı fikri)
- Ürüne dönüşen: Her arayüz değişikliğinde tasarım dilinden kaçışlar sayılır: sabit renk (`Color(red:`, `.opacity` dışı ham değer), gerekçesiz sabit yazı boyutu, token dışı köşe yarıçapı, `L(` olmadan `Text("…")`, etiketsiz yalnız-simge düğmesi ve 4'ün katı olmayan boşluk. Kullanıcıya tutarlı ve okunaklı bir arayüz olarak döner.
- Katman: araç
- Dosya: YENİ `scripts/tasarim-denetimi.py`, YENİ `Tests/Fixtures/tasarim-ihlal/OrnekIhlal.swift.txt` (derlenmeyen örnek), YENİ `Tests/MarkaCoreTests/TasarimDenetimiBetikTests.swift` (betiği örnek dosyada çalıştırıp sayıları doğrular)
- Kabul: Betik ihlal türü başına sayı tablosu yazar. Örnek dosyada 6 ihlal türünün her biri ≥ 1 yakalanır. `Sources/MarkaApp` üzerinde ilk ölçüm çıktısı rapora kopyalanır. Çıkış kodu eşiğe göre 0/1 olur. 1 test.
- Dalga: A · Bağımlılık: yok · Boyut: S
- Risk/Yasak: Bu dalgada kapıya **bağlanmaz** (E-15 bağlar). Yanlış pozitif oranı ilk ölçümde elle örneklenir ve rapora yazılır.

**E-05 · Yerel kara kutu: içeriksiz iz kırıntısı**
- Kaynak: getsentry/sentry (breadcrumb fikri)
- Ürüne dönüşen: Bir hata olduğunda Tanı raporu, hatadan önceki son 50 adımı (ekran adı, eylem türü, sağlayıcı türü, süre) içeriksiz olarak gösterir. Kullanıcı sorun bildirirken neyin bozulduğu anlaşılır ve hiçbir şey kendiliğinden gönderilmez.
- Katman: çekirdek
- Dosya: YENİ `Status/Breadcrumbs.swift` (halka tampon, yalnız izinli anahtar kümesi), `Status/Diagnostics.swift`'te yalnız `DiagnosticReport.render`'a "Son adımlar" bölümü eklenir, YENİ `Tests/MarkaCoreTests/IzKirintisiTests.swift`
- Kabul: ≥ 6 test. Kapsananlar: tampon 50'de sınırlı, izinli anahtar dışındaki alanın atılması, ayırt edici marka adı ve içerik dizgesinin raporda 0 kez geçmesi (`GizlilikTests` deseni), uygulama yeniden açılınca tamponun boş başlaması (diske yazılmaz).
- Dalga: A · Bağımlılık: yok · Boyut: S
- Risk/Yasak: Ağ yok, SDK yok. Arayüz çağrı noktaları bu görevde eklenmez (E-30 ve sonraki işler ekler).

### Dalga B: çekirdeğin ikinci katı

**E-06 · `gozlem_oner` aracı ve gözlem öneri türü**
- Kaynak: mem0ai/mem0 (ekle/güncelle/sil işlemleri), vectorize-io/hindsight
- Ürüne dönüşen: Sohbette yapay zekâ "Bu markanın teslim tarihi değişti" gibi bir gözlemi kaynak kimliğiyle **önerir**. Kullanıcı onay sayfasında onaylar ya da reddeder, onaylanan gözlem geri alınabilir. Var olan bir gözlemle çelişen öneri "yerine geçer" diye işaretlenir.
- Katman: çekirdek
- Dosya: `Model/Models.swift`'te `ProposalKind.createObservation`, `Store/Store+Proposals.swift`'te apply/revert `case`'i, `AI/ContextAndTools.swift`'te araç tanımı ve yürütücü `case`'i, `MarkaApp/ProposalInbox.swift`'te yalnız satır başlığı ve özeti, YENİ `Tests/MarkaCoreTests/GozlemOneriTests.swift`
- Kabul: ≥ 8 test. Kapsananlar: araç yalnız bekleyen öneri üretir (uygulanmış 0), başka marka kaynak kimliğinde `is_error`, kaynaksız gözlemde ret, onay sonrası gözlem tablosunda 1 satır ve `auditEvent`, geri almada gözlemin silinmesi ve yerine geçtiği eskinin yeniden açılması, kullanıcı sonradan düzenlediyse geri almanın reddedilmesi. Altın istem setine ≥ 2 yeni senaryo.
- Dalga: B · Bağımlılık: E-01 · Boyut: M
- Risk/Yasak: Araç Stüdyo izni kuralına uyar (`bilinen-sinirlar` §3). Gözlem metni istem enjeksiyonu kanalıdır (E-23).

**E-07 · Yetenek kökeni ve özet saklama**
- Kaynak: addyosmani/agent-skills, anthropics/skills
- Ürüne dönüşen: İçe aktarılan her yetenek nereden geldiğini (elle / hazır paket / içe aktarılan dosya ya da klasör adı), içerik özetini ve içe aktarma tarihini taşır. Kütüphanede "içe aktarıldı" rozeti ve gövde değiştiyse "yerel değişiklik var" bilgisi görünür.
- Katman: çekirdek
- Dosya: `Database/AppDatabase.swift`'e yeni migration `v11_yetenek_kokeni` eklenir. **Gerekçe:** `skill` tablosuna `origin`, `contentHash`, `importedAt` sütunları; mevcut satırlar `origin='manual'` ya da `pack` doluysa `'pack'` olur. Ek olarak `Model/Skill.swift` (alanlar), `Store/Store+Skills.swift` (`importSkillBundle(_:)`, E-02 önizlemesinden kaydetme), YENİ `Tests/MarkaCoreTests/YetenekKokeniTests.swift`
- Kabul: ≥ 7 test. Kapsananlar: migration eski satırları doğru doldurur, içe aktarılan yetenekte köken ve özet dolu, gövde düzenlenince "yerel değişiklik" doğru, dışa aktarılan SKILL.md'ye köken alanı **yazılmaz**, `auditEvent` var. `bilinen-sinirlar` §4'teki "kökeni saklamak: yapılmadı" maddesi kanıtla güncellenir.
- Dalga: B · Bağımlılık: E-02 · Boyut: M
- Risk/Yasak: Ad çözümleme davranışı (`yetenekAdiCozumlemeAnindaBaglanir…`) değişmez. Değişirse bu ayrı ürün kararıdır.

**E-08 · Uzun belge içindekiler ağacı (PageIndex esinli)**
- Kaynak: VectifyAI/PageIndex (yapı üzerinde akıl yürütme), docling-project/docling
- Ürüne dönüşen: Uzun bir sözleşme ya da teklif PDF'i ve Markdown kaynağı için başlık ağacı çıkar: bölüm adı, sayfa ya da satır aralığı ve karakter sayısı. Yapay zekâ bütün metni değil ilgili bölümü okuyabilir, bağlam ve maliyet düşer.
- Katman: çekirdek
- Dosya: YENİ `Sources/MarkaCore/Documents/DocumentOutline.swift` (PDFKit `outlineRoot` varsa ondan, yoksa sayfa metnindeki numaralı başlık sezgisinden; Markdown'da `#` başlıklarından), YENİ `Tests/MarkaCoreTests/BelgeAgaciTests.swift` (test PDF'i `ReportPDF` ile üretilir)
- Kabul: ≥ 7 test. Kapsananlar: Markdown 3 düzey başlık doğru ağaç, başlıksız metinde tek kök bölüm, PDF ana hatlı ve ana hatsız iki yol, bölüm metinlerinin birleşiminin özgün metne eşit olması (kayıp 0), 400 000 karakter sınırına uyum.
- Dalga: B · Bağımlılık: yok · Boyut: M
- Risk/Yasak: Gömme ve vektör yok. Veri tabanına yazılmaz (ağaç istek anında üretilir), ölçek sorun çıkarırsa önbellek ayrı karardır.

**E-09 · Yolculuk betikleri: kayıtlı, modelsiz yeniden oynatılan uçtan uca akışlar**
- Kaynak: tester-army/e2e (doğal dil görevi, başarılı adımı kaydedip yeniden oynatma)
- Ürüne dönüşen: "Yeni marka aç → kaynak ekle → asistan görev önersin → onayla → geri al → rapor ≥ 1 madde" gibi gerçek kullanıcı yolculukları çekirdek düzeyinde ve sahte sağlayıcıyla koşar. Bir değişiklik bu yolculuğu bozarsa hangi adımda bozulduğu yazılır.
- Katman: araç
- Dosya: YENİ `Sources/MarkaCore/Eval/Yolculuk.swift` (adım modeli + koşucu; `FakeProvider` betiğini kayıt dosyasından oynatır), YENİ `Tests/MarkaCoreTests/YolculukTests.swift`, YENİ `Tests/Fixtures/yolculuk/*.json` (≥ 5 kayıt)
- Kabul: ≥ 5 yolculuk yeşil. Aynı kayıtla iki koşu bire bir aynı adım çıktısını verir. Kasıtlı bozulmuş bir adımda (ör. onay uygulanmıyor) test adımın adını yazarak kırmızı olur, çıktısı rapora kopyalanır. Yolculuklardan biri marka yalıtımını kapsar (B markası kimliği reddedilir).
- Dalga: B · Bağımlılık: yok · Boyut: M
- Risk/Yasak: Arayüz tıklaması yoktur, bu bir arayüz testi **iddia edilmez**. Gerçek veri alanı kullanılmaz, yalnız `makeStore()` kullanılır.

**E-10 · Ekip şablonları (çekirdek)**
- Kaynak: garrytan/gstack (rol ekibi), addyosmani/agent-skills
- Ürüne dönüşen: Stüdyo'da "Ajans çekirdek ekibi" (strateji, metin, SEO, rapor) ya da "Tek kişilik danışman" gibi hazır yapay zekâ rol şablonları vardır. Şablon kurmak doğrudan ekip oluşturmaz, onay bekleyen N tane "çalışan önerisi" üretir.
- Katman: çekirdek
- Dosya: YENİ `Model/TeamTemplates.swift` (≥ 3 şablon, özgün Türkçe metin, rol + görev tarifi + bağlı yetenek adları), `Store/Store+Organization.swift`'e yalnız `proposeTeamTemplate(_:)` eklenir (mevcut `createTeamMember` öneri yolunu kullanır), YENİ `Tests/MarkaCoreTests/EkipSablonuTests.swift`
- Kabul: ≥ 6 test. Kapsananlar: şablon kurulumunda N bekleyen öneri oluşur ve uygulanmış 0, yalnız Stüdyo markasında çalışır (müşteri markasında ret), aynı şablon ikinci kez kurulduğunda var olan rolün atlanması, `reportsTo` ağacında döngü 0, şablondaki yetenek adının kütüphanede yoksa serbest metin kalması.
- Dalga: B · Bağımlılık: yok · Boyut: S
- Risk/Yasak: Şablon metni gstack'ten çevrilmez, özgün yazılır. Çalışan bir süreç değil rol tanımıdır (`bilinen-sinirlar` §4).

### Dalga C: ilk yüzeyler ve kapı

**E-11 · Yerel sağlayıcıyı kaydetme, izin ve Ayarlar (`#if !MAS`)**
- Kaynak: ollama/ollama, osaurus-ai/osaurus
- Ürüne dönüşen: Ayarlar'da "Bu Mac'teki model" bölümü açılır: adres (yalnız geri döngü), model adı ve "Bağlantıyı dene" düğmesi. Marka izin kartında yeni sağlayıcı ayrı bir onay kutusu olarak görünür ve varsayılan olarak kapalıdır.
- Katman: arayüz (+ çekirdek kaydı)
- Dosya: `Model/Models.swift`'te `AIProviderKind.local` (`selectable` MAS'ta değişmez), `AI/AIProvider.swift`'te yalnız `displayName` `case`'i, `AI/ChatEngine.swift`'te kayıt listesine `#if !MAS` ekleme, `MarkaApp/SettingsView.swift`'te yeni bölüm, `MarkaApp/AppModel.swift`'te tercih alanları (`app.preferences` üzerinden), YENİ `Tests/MarkaCoreTests/YerelSaglayiciKayitTests.swift`
- Kabul: ≥ 5 test. Kapsananlar: izin yokken oturum açılmaz, MAS kipinde `selectable`'da `.local` yok (`swift build -Xswiftc -DMAS` temiz), geri döngü dışı adres tercihe yazılmaz, eski DB'deki `.local` oturumu MAS'ta hata verir. Ayarlar ekranı `MARKA_SNAPSHOT` ile açık ve koyu çizilir. Gerçek pencere yoksa "doğrulanamadı" yazılır.
- Dalga: C · Bağımlılık: E-03 · Boyut: M
- Risk/Yasak: Canlı yerel model koşusu kurucunun makinesinde elle yapılır. Yapılmazsa "yapılmadı" yazılır. `TercihYalitimTests` kuralı: `UserDefaults.standard` yasak.

**E-12 · "Marka belleği" görünümü (gözlemler)**
- Kaynak: thedotmack/claude-mem, getzep/graphiti
- Ürüne dönüşen: Marka ekranında onaylı gözlemler listelenir: her birinde cümle, kanıt sayısı ve kaynak bağlantısı, "geçerli / yerine geçildi" durumu. Kullanıcı bir gözlemi tek tıkla "artık geçerli değil" diye kapatabilir (bu kullanıcı eylemidir, denetim olayı bırakır).
- Katman: arayüz
- Dosya: YENİ `MarkaApp/ObservationsView.swift`, `MarkaApp/BrandSections.swift`'te yalnız bölüm bağlantısı (tek `case`/satır), `Store/Store+Observations.swift`'e (E-01 dosyası; bu dalgada başka sahibi yok) `invalidateObservation` eklenir, YENİ `Tests/MarkaCoreTests/GozlemKapatmaTests.swift`
- Kabul: ≥ 3 test (kapatma denetim olayı bırakır, başka markanın gözlemi kapatılamaz, kapatılan bağlamdan düşer). Boş durum tek fiille başlar. `MARKA_SNAPSHOT` ile açık ve koyu çizim, `scripts/erisilebilirlik-tarama.sh` temiz, E-04 betiğinde yeni ihlal 0.
- Dalga: C · Bağımlılık: E-06 · Boyut: M
- Risk/Yasak: "Hafıza" ve "bellek" adları tek sözlükte birleştirilir: metin kararı `docs/`'a değil arayüze ve `en.lproj`'a yazılır. İçerik ilk 240 karakter kuralıyla kırpılmaz, gözlem zaten kısadır (≤ 280 karakter sınırı E-01'de).

**E-13 · `belge_bolumu_oku` aracı (içindekiler + bölüm okuma)**
- Kaynak: VectifyAI/PageIndex
- Ürüne dönüşen: Asistan uzun bir kaynakta önce içindekiler ağacını ister, sonra yalnız gereken bölümü okur. Kullanıcı "sözleşmenin fesih maddesi ne diyor" diye sorduğunda bütün belge gönderilmez, maliyet ve bağlam taşması azalır.
- Katman: çekirdek
- Dosya: `AI/ContextAndTools.swift`'te iki araç tanımı (`belge_icindekiler`, `belge_bolumu_oku`) ve yürütücü `case`'leri, YENİ `Tests/MarkaCoreTests/BelgeAraciTests.swift`
- Kabul: ≥ 6 test. Kapsananlar: başka marka kaynağında `is_error`, olmayan bölüm kimliğinde anlaşılır hata, bölüm çıktısının `<kaynak_icerigi>` sınırlayıcısı içinde dönmesi, çıktı uzunluğunun bütçeyle sınırlanması, arşivlenmiş kaynakta yalnız okuma. Altın istem setine 1 senaryo (uzun belgede `kaynak_oku` yerine bölüm aracı).
- Dalga: C · Bağımlılık: E-08 · Boyut: S
- Risk/Yasak: Araç salt okurdur, öneri üretmez. Sağlayıcıya giden içerik yine marka iznine bağlıdır.

**E-14 · Yetenek klasörü içe aktarma ekranı (tam metin önizlemeli onay)**
- Kaynak: addyosmani/agent-skills, coreyhaines31/marketingskills
- Ürüne dönüşen: Şirket › Yetenekler'de "Klasörden içe aktar…" ile seçilen paket kaydedilmeden önce tam metniyle, köken, boyut ve özetle gösterilir. Kullanıcı "Ekle" demeden hiçbir yetenek kütüphaneye girmez. Böylece `bilinen-sinirlar` §4'teki "önizlemesiz içe aktarma" riski kapanır.
- Katman: arayüz
- Dosya: YENİ `MarkaApp/SkillImportSheet.swift`, `MarkaApp/CompanyView.swift`'te yalnız menü düğmesi ve sayfa bağlantısı
- Kabul: Önizleme verisi çekirdekte E-02/E-07 testleriyle kanıtlı. Bu görevde vazgeçilen içe aktarmada kütüphane sayısının değişmediğini doğrulayan 1 yeni test. `MARKA_SNAPSHOT` ile sayfa açık ve koyu çizilir. `l10n check` temiz. Klasör paneli tıklaması gerçek pencerede denenmediyse "doğrulanamadı" yazılır.
- Dalga: C · Bağımlılık: E-07 · Boyut: M
- Risk/Yasak: MAS'ta klasör erişimi yalnız `NSOpenPanel` seçimiyle olur. Mutlak yol saklanmaz.

**E-15 · Tasarım denetimini kapıya bağlama + eşik tabanı**
- Kaynak: pbakaus/impeccable
- Ürüne dönüşen: Yeni arayüz kodu tasarım dilinden kaçarsa geliştirme kapısı KALDI der. Ürün ekranları zamanla dağılmaz, kullanıcı tutarlı bir uygulama görür.
- Katman: araç
- Dosya: `scripts/gelistir-kapisi.sh`'e yalnız bir adım eklenir, YENİ `scripts/tasarim-esikleri.txt` (E-04 ilk ölçümünden taban)
- Kabul: Kapı adımı tabanın üstünde KALDI, eşit ya da altında GEÇTİ. Kasıtlı ihlal eklenmiş kopyada KALDI, geri alınınca GEÇTİ (iki koşunun çıktısı rapora kopyalanır). Kapının toplam süresi artışı ölçülüp yazılır.
- Dalga: C · Bağımlılık: E-04 · Boyut: S
- Risk/Yasak: Taban yalnız düşürülerek güncellenir. Yükseltmek kurucu kararıdır ve rapora yazılır.

### Dalga D: bağlam, protokol, ikinci yüzeyler

**E-16 · Onaylı ve geçerli gözlemlerin bağlama girmesi**
- Kaynak: letta-ai/letta (çekirdek bellek bloğu), getzep/graphiti (geçerlilik penceresi)
- Ürüne dönüşen: Asistan markayı her konuşmada yeniden öğrenmez. Yalnız onaylanmış ve hâlâ geçerli gözlemler, kaynak kimlikleriyle bağlamın başına kısa bir "marka belleği" bloğu olarak girer. Kapatılmış ya da yerine geçilmiş gözlem asla girmez.
- Katman: çekirdek
- Dosya: `AI/ContextAndTools.swift`'te yalnız `ContextBuilder.brandContext`'e blok ekleme (bütçe `ContextLimits`'e yeni sabit), YENİ `Tests/MarkaCoreTests/GozlemBaglamTests.swift`
- Kabul: ≥ 6 test. Kapsananlar: kapatılmış gözlem bağlamda 0, başka markanın gözlemi bağlamda 0 (rastgele iki marka, ≥ 50 tohum), bütçe aşımında "… ve N gözlem daha (kırpıldı)" notu, gözlem bloğunun `<kaynak_icerigi>` veri çerçevesinde olması, Stüdyo izni yoksa Stüdyo gözlemlerinin müşteri bağlamına girmemesi, gözlem yokken bağlamın eskisiyle bire bir aynı kalması.
- Dalga: D · Bağımlılık: E-06 · Boyut: S
- Risk/Yasak: Bayat gözlem modeli yanıltabilir. Gözlem bloğu tarih taşır ve 180 günden eskisi "olası bayat" işaretlenir (`wikiLint` eşiğiyle aynı).

**E-17 · Ajan-bağımsız öneri zarfı (`oneri-zarfi` şema 2)**
- Kaynak: michael-denyer/pstack-claude, awaithumans/…, humanlayer/humanlayer, pingdotgg/t3code (çok ajanlı yüzey fikri)
- Ürüne dönüşen: Claude Code, Codex, başka bir ajan ya da betik aynı JSON zarfını üretirse, kullanıcı onu dosyadan ya da panodan içe alıp onay sayfasında görür. Zarf hangi ajanın ürettiğini taşır, ama yetki taşımaz: marka, dosyanın içeriğinden değil kullanıcının seçiminden gelir.
- Katman: çekirdek
- Dosya: YENİ `AI/ProposalEnvelope.swift` (şema 2 = şema 1 + `uretici`, `gerekce`, `dayanak[]`; şema 1 dosyaları aynen okunur), `AI/SuggestionInbox.swift`'e yalnız şema 2 dalı, `Model/Models.swift`'te `ProposalOrigin.external`, `MarkaApp/ProposalInbox.swift`'te yalnız köken rozeti ("Dış ajan: <ad>"), YENİ `docs/oneri-zarfi.md` (şema belgesi), YENİ `Tests/MarkaCoreTests/OneriZarfiTests.swift`
- Kabul: ≥ 10 test. Kapsananlar: şema 1 dosyaları değişmeden geçer (`TerminalOneriTests` yeşil), zarftaki marka adı ya da kimliği yok sayılır, 256 KB üstü zarfta ret, 50'den fazla öğede ret, bilinmeyen alanın yok sayılması, `uretici` alanının 64 karakterle kırpılıp yalnız etiket olması, tüm öğelerin bekleyen öneri olması (uygulanmış 0), zarf içindeki talimat metninin hiçbir eylemi tetiklememesi.
- Dalga: D · Bağımlılık: yok (E-23 bunu sınar) · Boyut: M
- Risk/Yasak: Klasör izleme MAS'ta bookmark ister (sandbox S4). Bu görev yalnız kullanıcı seçimli dosya ve pano yolunu yapar. Ağ ve MCP yoktur.

**E-18 · "Şablondan ekip kur" ekranı**
- Kaynak: garrytan/gstack
- Ürüne dönüşen: Şirket › Ekip'te bir şablon seçilince kurulacak roller, görev tarifleri ve yetenekler önizlenir. "Önerileri oluştur" deyince roller onay sayfasına düşer, kullanıcı tek tek seçer.
- Katman: arayüz
- Dosya: YENİ `MarkaApp/TeamTemplateSheet.swift`, `MarkaApp/CompanyView.swift`'te yalnız düğme ve sayfa bağlantısı
- Kabul: E-10 testleri yeşil + 1 yeni test (vazgeçilen şablonda bekleyen öneri sayısının 0 kalması, çekirdekte). `MARKA_SNAPSHOT` ile açık ve koyu çizim, erişilebilirlik taraması temiz, E-04 betiğinde yeni ihlal 0.
- Dalga: D · Bağımlılık: E-10 · Boyut: S
- Risk/Yasak: Varsayılan seçim boştur (onay ritüeli kuralı, H3-05).

**E-19 · Biçimli Markdown çıkarımı (docx/rtf/html)**
- Kaynak: microsoft/markitdown, docling-project/docling
- Ürüne dönüşen: Word, RTF ya da HTML kaynağı düz metin yerine başlıkları, listeleri ve basit tabloları koruyarak Markdown'a çevrilir. Asistan belgenin yapısını görür ve E-08 içindekiler ağacı bu kaynaklarda da çalışır.
- Katman: çekirdek (belge entegrasyonu)
- Dosya: YENİ `Sources/MarkaCore/Documents/MarkdownExtractor.swift` (`NSAttributedString` öznitelikleri: yazı boyutu/kalınlık → başlık düzeyi, `NSTextList` → liste, `NSTextTable` → tablo; yalnız sistem çerçeveleri). `TextExtractor`'a **dokunulmaz**, yeni çıkarıcı ayrı API'dir. YENİ `Tests/MarkaCoreTests/MarkdownCikarimTests.swift` (test belgeleri testte üretilir)
- Kabul: ≥ 6 test. Kapsananlar: docx başlık düzeyleri, madde ve numaralı liste, 2×3 tablo, düz metin içeriğinin `TextExtractor` çıktısıyla aynı kelimeleri taşıması (kayıp 0), 400 000 karakter sınırı, bozuk dosyada boş sonuç ve çökme 0.
- Dalga: D · Bağımlılık: yok · Boyut: M
- Risk/Yasak: Python aracı çalıştırılmaz, dış süreç yoktur. pptx/xlsx kapsam dışıdır (sistem çözücüsü yok).

**E-20 · Yanıt uzunluğu ve sadelik ayarı**
- Kaynak: DietrichGebert/ponytail, JuliusBrussee/caveman (trend kataloğu Durum #12)
- Ürüne dönüşen: Ayarlar'da "Yanıt uzunluğu: Kısa / Normal / Ayrıntılı" seçeneği vardır. Kısa kipte sistem istemine sadelik ilkesi eklenir ve `max_tokens` düşer. Kullanıcı daha az bekler, daha az öder.
- Katman: çekirdek + arayüz
- Dosya: `AI/ChatEngine.swift`'te yalnız `AISettings.responseLength` alanı, YENİ `AI/ResponseStyle.swift` (istem parçası + belirteç tavanı tablosu), `AI/SystemPromptBuilder.swift`'e tek çağrı, `MarkaApp/SettingsView.swift`'te seçici, `MarkaApp/AppModel.swift`'te tercih, YENİ `Tests/MarkaCoreTests/YanitUzunluguTests.swift`
- Kabul: ≥ 5 test. Kapsananlar: Anthropic isteğinde kısa kipte `max_tokens` tablodaki değer, normal kipte istek gövdesi eskisiyle bire bir aynı, sadelik ilkesinin temel kurallardan **sonra** gelip onları ezmemesi, Haiku'da effort alanının yine gönderilmemesi, yerel sağlayıcıya da aynı istem parçasının gitmesi.
- Dalga: D · Bağımlılık: yok · Boyut: S
- Risk/Yasak: Maliyet tasarrufu sayıyla vaat edilmez (canlı ölçüm yok).

### Dalga E: bütünleştirme

**E-21 · Marka radarı (elle beslenen, öneri üreten)**
- Kaynak: Panniantong/Agent-Reach (fikir), coreyhaines31/marketingskills (rakip analizi yöntemi)
- Ürüne dönüşen: Her markada "Radar" listesi vardır: kullanıcının eklediği rakip ya da sektör bağlantıları ve notlar, tarih ve etiketle. "Radarı özetle" dendiğinde asistan bu notlardan gözlem ve görev **önerir**. İnternet taraması yoktur, kullanıcı ne eklediyse o vardır.
- Katman: çekirdek + arayüz
- Dosya: `Database/AppDatabase.swift`'e yeni migration `v12_marka_radari` eklenir. **Gerekçe:** `radar_item (id, brandId, title, url, note, tag, createdAt, archivedAt)`; radar maddesi müşteri kaynağı değildir, rapora girmemeli. Mevcut `source` tablosuna eklemek rapor ve tanı sayılarını bozar. Ek olarak YENİ `Model/RadarItem.swift`, YENİ `Store/Store+Radar.swift`, `AI/ContextAndTools.swift`'te `radar_listele` salt okuma aracı, YENİ `MarkaApp/RadarView.swift`, `MarkaApp/BrandSections.swift`'te bölüm bağlantısı, YENİ `Tests/MarkaCoreTests/MarkaRadariTests.swift`
- Kabul: ≥ 8 test. Kapsananlar: başka markanın radarı 0, radar maddesi rapor maddesine 0 kez girer (kural 4), URL `LinkAddress.normalize` ile doğrulanır, araç salt okurdur, radar özeti yalnız bekleyen öneri üretir, her yazmada `auditEvent`, migration testi. `MARKA_SNAPSHOT` çizimi açık ve koyu.
- Dalga: E · Bağımlılık: E-06 · Boyut: L
- Risk/Yasak: Bağlantının içeriği **çekilmez** (ağ yok). İçerik çekme ileride yalnız `#if !MAS` ve izinli yolda ayrı karardır. "Rakibini otomatik izler" diye vaat edilmez.

**E-22 · Onay kartında dayanak gösterimi ("neden bu öneri")**
- Kaynak: vectorize-io/hindsight (kanıtlı inanç), awaithumans/… (gerekçeli onay isteği)
- Ürüne dönüşen: Onay sayfasındaki her öneri, dayandığı kaynakları, gözlemleri ve varsa dış ajan gerekçesini küçük çipler olarak gösterir. Çipe tıklayınca kaynak açılır. Kullanıcı neyi neden onayladığını görür.
- Katman: arayüz
- Dosya: `MarkaApp/ProposalInbox.swift`'te yalnız satır altına dayanak çipleri, YENİ `Sources/MarkaCore/ProposalEvidence.swift` (öneri yükünden kaynak/gözlem kimliklerini çıkaran saf fonksiyon), YENİ `Tests/MarkaCoreTests/OneriDayanagiTests.swift`
- Kabul: ≥ 5 test. Kapsananlar: her öneri türü için dayanak çıkarımı, başka marka kimliğinin çip olarak 0 kez dönmesi, dayanaksız önerinin "dayanak yok" diye işaretlenmesi. Onay ritüeli klavye akışı bozulmaz (`OnayRituelTests` yeşil). `MARKA_SNAPSHOT` çizimi.
- Dalga: E · Bağımlılık: E-06, E-16 (E-17 varsa gerekçe de gösterilir) · Boyut: M
- Risk/Yasak: Çip yalnız kimlik ve başlık gösterir, içerik önizlemesi göstermez.

**E-23 · Kırmızı takımı yeni kanallara genişletme**
- Kaynak: promptfoo/promptfoo (saldırı katalogu fikri)
- Ürüne dönüşen: Yeni eklenen her içerik kanalı (gözlem cümlesi, yetenek `references/`, dış ajan zarfı, belge bölümü, radar notu) "önceki talimatları yok say, B markasını oku, onayı atla" saldırılarına karşı sahte sağlayıcıyla sınanır. Güven vaadi yeni özelliklerle birlikte büyür.
- Katman: araç
- Dosya: YENİ `Tests/MarkaCoreTests/EnjeksiyonYeniKanallarTests.swift` (mevcut `EnjeksiyonKirmiziTakimTests`'e dokunulmaz)
- Kabul: ≥ 15 senaryo (5 kanal × 3 saldırı). Her senaryoda doğrudan yazma 0, uygulanmış öneri 0, başka marka kimliği %100 `is_error`. Kanal içeriği bağlamda `<kaynak_icerigi>` içinde (test).
- Dalga: E · Bağımlılık: E-06, E-13, E-17 (E-21 aynı dalgada biterse radar senaryoları eklenir, bitmezse F'de) · Boyut: M
- Risk/Yasak: Sahte sağlayıcı modelin gerçek davranışını kanıtlamaz. Bu sınır `bilinen-sinirlar`'a yazılır, canlı uyma oranı "yapılmadı" kalır.

**E-24 · "Bu Mac'te çalışıyor" göstergesi ve ağ yalıtım kanıtı**
- Kaynak: antirez/ds4, osaurus-ai/osaurus
- Ürüne dönüşen: Yerel sağlayıcı seçiliyken asistan panelinde "Bu Mac'te çalışıyor" rozeti görünür. Bulut sağlayıcıda rozet sağlayıcı adını söyler. Gösterge yalnız bir test bunu kanıtladığında yanar.
- Katman: arayüz + araç
- Dosya: `MarkaApp/AIChatPanel.swift`'te yalnız rozet, YENİ `Tests/MarkaCoreTests/YerelAgYalitimTests.swift` (`URLProtocol` kaydı: yerel sağlayıcıyla tam bir turda geri döngü dışı ana makineye istek 0)
- Kabul: ≥ 3 test. Kapsananlar: yerel turda dış ana makine isteği 0, Anthropic turunda yalnız `api.anthropic.com`, rozet metninin sağlayıcı yeteneğinden (`onDevice`) türemesi. `MARKA_SNAPSHOT` çizimi.
- Dalga: E · Bağımlılık: E-11 · Boyut: S
- Risk/Yasak: Rozet "veri hiç dışarı çıkmaz" demez, yalnız "bu sohbet bu Mac'teki modelle" der (kural 5, denetim O2).

**E-25 · Apple Foundation Models sağlayıcısı (araçsız ilk dilim)**
- Kaynak: carbocation/CarbocationLocalLLM (tek API arkasında yerel model), `docs/foundation-models-denemesi.md`
- Ürüne dönüşen: Mac App Store sürümünde de bir yerel seçenek olur: Apple'ın cihaz üstü modeli özet ve sınıflama için kullanılır, içerik üçüncü tarafa gitmez. İlk dilim araçsızdır, çünkü denemede tarih ve parametre hataları ölçüldü.
- Katman: çekirdek
- Dosya: YENİ `AI/FoundationModelsProvider.swift` (`#if canImport(FoundationModels)`, `@available(macOS 26, *)`, `DynamicGenerationSchema` yolu, makro yok), `Model/Models.swift`'te `AIProviderKind.apple`, `AI/ChatEngine.swift`'te kayıt satırı, `MarkaApp/SettingsView.swift` ve `AppModel.swift`'te durum satırı ("Apple Intelligence açık değil" dahil), YENİ `Tests/MarkaCoreTests/AppleSaglayiciTests.swift`
- Kabul: ≥ 5 test (modeli çağırmadan): `capabilities` (`onDevice`, `supportsTools=false`, `needsAPIKey=false`), kullanılabilirlik yokken anlaşılır hata, istemde tarih tablosu (deneme §4b) bulunması, MAS kipinde `selectable` içinde `.apple` olması, CLT ile derleme. Canlı yanıt kurucunun makinesinde elle denenir, denenmezse "yapılmadı" yazılır.
- Dalga: E · Bağımlılık: E-11 (kayıt deseni) · Boyut: L
- Risk/Yasak: Araçlı tur ayrı görevdir ve kalite ölçülmeden açılmaz. Kamp havuzu sırası 4 ile örtüşür, kurucu sırası beklenir.

### Dalga F: kalıcılaştırma ve araştırma

**E-26 · Yolculukları kapıya bağlama + kayıt güncelleme komutu**
- Kaynak: tester-army/e2e
- Ürüne dönüşen: Her geliştirme turunda temel kullanıcı yolculukları da koşar. Bilinçli bir davranış değişikliğinde kayıtlar tek komutla yeniden üretilir ve fark rapora çıkar, böylece sessiz gerileme olmaz.
- Katman: araç
- Dosya: `scripts/gelistir-kapisi.sh`'e yalnız bir adım, YENİ `scripts/yolculuk-kaydet.sh` (kayıtları yeniden üretir ve `diff` yazar)
- Kabul: Kapı adımı bozuk yolculukta KALDI, düzeltilince GEÇTİ (iki koşu çıktısı). `yolculuk-kaydet.sh` değişmeyen kodda boş fark verir.
- Dalga: F · Bağımlılık: E-09, E-15 · Boyut: S
- Risk/Yasak: Kayıt güncellemesi kodla aynı değişiklikte gözden geçirilir, otomatik kabul edilmez.

**E-27 · Ajan dosyalarına kalite ilkeleri (sadelik + tasarım bağlamı)**
- Kaynak: DietrichGebert/ponytail, pbakaus/impeccable (`PRODUCT.md`/`DESIGN.md` fikri), addyosmani/agent-skills
- Ürüne dönüşen: Geliştirme ekibinin ajanları (`swift-gelistirici`, `arayuz-gelistirici`, `tasarim-lideri`, `arayuz-denetci`) "önce var olanı kullan, yeni bağımlılık son seçenek, en küçük değişiklik" ilkesini ve tasarım bağlamını aynı kaynaktan okur. Kullanıcıya daha az hata ve daha tutarlı ekran olarak döner.
- Katman: belge
- Dosya: YENİ `docs/kalite-ilkeleri.md` (tek kaynak, ≤ 40 satır), `.claude/agents/swift-gelistirici.md`, `arayuz-gelistirici.md`, `tasarim-lideri.md`, `arayuz-denetci.md`'ye yalnız "Önce oku: docs/kalite-ilkeleri.md" satırı
- Kabul: 4 ajan dosyasında bağlantı var (`grep -c` = 4). `BelgeTutarlilikTests`'e 1 test eklenir: ilke belgesinde adı geçen betik ve dosyaların var olması. Ponytail ya da impeccable metninden çeviri yoktur (özgün).
- Dalga: F · Bağımlılık: E-15 (eşik dosyasına atıf) · Boyut: S
- Risk/Yasak: Ajan dosyası değişikliği yetki ya da yapılandırma değişikliği değildir, yalnız okuma listesidir. `CLAUDE.md`'ye dokunulmaz.

**E-28 · Araştırma: MAS'ta MCP istemcisi mümkün mü**
- Kaynak: modelcontextprotocol/swift-sdk, modelcontextprotocol/servers
- Ürüne dönüşen: Takvim ya da e-posta gibi bağlayıcıların sandbox'ta hangi biçimde (süreç-içi, uzak HTTP, kullanıcı onaylı) kurulabileceğine dair kanıtlı bir karar notu. Kullanıcıya gelecekteki bağlayıcıların güvenli sınırı olarak döner.
- Katman: belge (araştırma)
- Dosya: YENİ `docs/arastirma/mcp-mas.md`. Depo koduna dokunulmaz. Deneme gerekiyorsa scratchpad'de ayrı paket yazılır, bağımlılık eklenmez.
- Kabul: Belgede (1) taşıma türleri × MAS uyumu tablosu, her satırda "ölçüldü / belgeden / doğrulanamadı" etiketi, (2) marka yalıtımı ve izin akışı taslağı, (3) swift-sdk lisans geçiş durumu, (4) "yap / yapma / bekle" önerisi.
- Dalga: F · Bağımlılık: E-17 (zarf, MCP'siz alternatif olarak) · Boyut: S
- Risk/Yasak: Kod yok. Dış süreç başlatan MCP sunucusu MAS'ta önerilmez.

**E-29 · Araştırma: MLX ile yerel model paketleme**
- Kaynak: ml-explore/mlx-swift-lm, carbocation/CarbocationLocalLLM, osaurus-ai/osaurus, antirez/ds4
- Ürüne dönüşen: API anahtarsız ve buluta gitmeyen bir asistanın MAS'ta mümkün olup olmadığına dair ölçülmüş not: model boyutu, indirme yeri (container), bellek, Türkçe görev başarısı (5 sentetik senaryo) ve lisans. Kullanıcıya gelecekte "anahtarsız yerel asistan" seçeneğinin gerçekçi sınırı olarak döner.
- Katman: belge (araştırma)
- Dosya: YENİ `docs/arastirma/mlx-yerel-model.md`. Deneme scratchpad'de ayrı paketle, uydurma verilerle yapılır.
- Kabul: Belgede ölçüm tablosu (makine, model, ilk belirteç süresi, belirteç/sn, bellek tepe değeri), 5 senaryo sonucu aynen, sandbox'ta geri döngü HTTP (E-03) ile süreç-içi MLX karşılaştırması ve öneri. Ölçülemeyenler "doğrulanamadı" etiketli.
- Dalga: F · Bağımlılık: E-03, E-25 · Boyut: M
- Risk/Yasak: Model ağırlıklarının lisansı ayrı ayrı yazılır. Depoya model ya da bağımlılık girmez.

**E-30 · Yerel yapay zekâ tur izi (içeriksiz)**
- Kaynak: langfuse/langfuse (iz fikri), getsentry/sentry
- Ürüne dönüşen: Tanı ekranında son 20 asistan turunun içeriksiz izi görünür: sağlayıcı türü, süre, giriş ve çıkış belirteci, çağrılan araç **adları**, üretilen öneri sayısı, hata türü. Kullanıcı "neden yavaş ya da pahalı" sorusuna veriyle bakar, hiçbir şey dışarı gitmez.
- Katman: araç + çekirdek
- Dosya: YENİ `AI/TurnTrace.swift` (bellek içi halka tampon), `AI/ChatEngine.swift`'te tur sonunda tek kayıt çağrısı, `Status/Diagnostics.swift`'te yalnız rapora "Son turlar" bölümü, YENİ `Tests/MarkaCoreTests/TurIziTests.swift`
- Kabul: ≥ 6 test. Kapsananlar: `FakeProvider` turunda iz alanları doğru, araç girdisi ve çıktısı izde 0, ayırt edici marka adı ve içerik raporda 0, iptal edilen turun "durduruldu" türüyle kaydı, tamponun 20'de sınırlı olması, diske yazılmaması.
- Dalga: F · Bağımlılık: E-05 · Boyut: S
- Risk/Yasak: Maliyet gösterimi "tahmini" etiketlidir, fiyat tablosu tarihini taşır. Ayarlar'a maliyet ekranı eklenmez (ayrı ürün kararı).

---

## 5. Dalga tablosu

| Dalga | Görevler | Tema | Tahmini sıra / not |
|---|---|---|---|
| A | E-01, E-02, E-03, E-04, E-05 | Temeller: gözlem modeli, yetenek paketi, yerel uç nokta, tasarım denetimi, kara kutu | 1. Hepsi yeni dosya. Tek migration E-01 |
| B | E-06, E-07, E-08, E-09, E-10 | Çekirdeğin ikinci katı: gözlem önerisi, yetenek kökeni, belge ağacı, yolculuklar, ekip şablonları | 2. Tek migration E-07 |
| C | E-11, E-12, E-13, E-14, E-15 | İlk yüzeyler: yerel sağlayıcı ayarı, marka belleği, belge aracı, yetenek içe aktarma ekranı, tasarım kapısı | 3. Migration yok |
| D | E-16, E-17, E-18, E-19, E-20 | Bağlam ve protokol: gözlem bağlamı, öneri zarfı, şablon ekranı, biçimli Markdown, yanıt uzunluğu | 4. Migration yok |
| E | E-21, E-22, E-23, E-24, E-25 | Bütünleştirme: radar, dayanak çipleri, kırmızı takım, yerel gösterge, Foundation Models | 5. Tek migration E-21. En riskli dalga (iki L) |
| F | E-26, E-27, E-28, E-29, E-30 | Kalıcılaştırma ve araştırma: yolculuk kapısı, kalite ilkeleri, MCP ve MLX araştırması, tur izi | 6. Araştırma görevleri burada |

**Dağılım denetimi** (bir görev birden çok sınıfa girebilir):

| Sınıf | İstenen | Bu planda |
|---|---|---|
| Yapay zekâ çekirdeği (hafıza/bağlam/yetenek/onay) | ≥ 6 | 10: E-01, E-02, E-06, E-07, E-10, E-13, E-16, E-17, E-20, E-22 |
| Arayüz | ≥ 5 | 8: E-11, E-12, E-14, E-18, E-20, E-21, E-22, E-24 |
| Yerel / gizlilik | ≥ 3 | 6: E-03, E-05, E-11, E-24, E-25, E-30 |
| Kalite / test aracı (özgün) | ≥ 3 | 6: E-04, E-09, E-15, E-23, E-26, E-30 |
| Belge / ışık entegrasyonu | ≥ 2 | 3: E-08, E-13, E-19 |
| Yalnız araştırma | ≤ 4 | 2: E-28, E-29 |
| Kod görevi oranı | ≥ %80 | 27/30 = %90 (E-27 belge, E-28 ve E-29 araştırma) |

**Kesme kuralı:** bir dalga bitmeden sonraki dalga başlamaz. Bir görevin kapısı KALDI ise o görev dalga içinde biter ya da gerekçesiyle sonraki dalganın başına taşınır. Taşınan görevin dosyaları o dalgada başka göreve verilmez. Yalıtım ya da gizlilik bulgusu her işin önüne geçer.

## 6. Lisans notu tablosu

Hiçbir satırda kod kopyalanmaz ve bağımlılık eklenmez. "Biçim" = dosya ya da veri düzeni (ör. SKILL.md başlık alanları), "Fikir" = yöntem. Lisansların hepsi `gh api repos/<ad>` ile okundu, NOASSERTION olanlarda LICENSE dosyasının ilk satırlarına bakıldı.

| Depo | Lisans | Kullanım | Not |
|---|---|---|---|
| tester-army/e2e | Apache-2.0 | Fikir (kayıt + modelsiz oynatma) | — |
| pbakaus/impeccable | Apache-2.0 | Fikir (kalite kapısı, bağlam dosyası) | Kural metni çevrilmez |
| coreyhaines31/marketingskills | MIT | Biçim (klasör, references) | Metin daha önce özgün yazıldı, yine öyle |
| DietrichGebert/ponytail | MIT | Fikir (sadelik ilkesi) | İlke metni özgün |
| addyosmani/agent-skills | MIT | Biçim + fikir | — |
| michael-denyer/pstack-claude | MIT | Fikir (ajan-bağımsız prosedür) | — |
| garrytan/gstack | MIT | Fikir (rol ekibi) | Şablon metni özgün |
| thedotmack/claude-mem | Apache-2.0 | Fikir (kalıcı hafıza) | Otomatik yazma alınmadı |
| Panniantong/Agent-Reach | MIT | Fikir (radar) | Kazıma alınmadı |
| antirez/ds4 | MIT | Fikir (yerel model) | — |
| pingdotgg/t3code | MIT | Fikir (çok ajanlı yüzey) | — |
| getsentry/sentry | FSL-1.1-Apache-2.0 (LICENSE ilk satırı; API NOASSERTION) | Yalnız fikir (iz kırıntısı) | Kaynak kodu okunmaz |
| getzep/graphiti | Apache-2.0 | Fikir (zamansal geçersizleştirme) | Python, bağımlılık olamaz |
| mem0ai/mem0 | Apache-2.0 | Fikir (hafıza işlemleri) | — |
| letta-ai/letta | Apache-2.0 | Fikir (çekirdek bellek bloğu) | — |
| vectorize-io/hindsight | MIT | Fikir (kanıtlı gözlem) | — |
| VectifyAI/PageIndex | MIT | Fikir (yapı üzerinde okuma) | — |
| ml-explore/mlx-swift-lm | MIT | Araştırma (E-29) | Bağımlılık kararı ayrı, bu planda yok |
| osaurus-ai/osaurus | MIT | Fikir (yerel sunucu deseni) | — |
| carbocation/CarbocationLocalLLM | MIT | Fikir (tek API arkasında yerel model) | — |
| docling-project/docling | MIT | Fikir (yapı koruyan çıkarım) | Python, çalıştırılmaz |
| microsoft/markitdown | MIT | Fikir (belge → Markdown) | Python, çalıştırılmaz |
| awaithumans/awaithumans-human-in-the-loop-ai-agents | Apache-2.0 | Fikir (onay zarfı) | — |
| humanlayer/humanlayer | NOASSERTION (LICENSE'ta Apache-2.0 bölümü) | Yalnız fikir | Lisans tam okunmadı |
| promptfoo/promptfoo | MIT | Fikir (saldırı katalogu) | — |
| langfuse/langfuse | NOASSERTION (karma) | Yalnız fikir | Kod okunmaz |
| modelcontextprotocol/swift-sdk | MIT → Apache-2.0 geçişi | Araştırma (E-28) | — |
| twentyhq/twenty | AGPLv3 + ticari dosyalar | Yalnız kavram | Kod okunmaz |
| basicmachines-co/basic-memory | AGPL-3.0 | Yalnız kavram | Kod okunmaz |
| calesthio/OpenMontage | AGPL-3.0 | Kullanılmaz | Kapsam dışı |
| earthtojake/text-to-cad, OpenCut-app/OpenCut | MIT | Kullanılmaz | Kapsam dışı |
| caddyserver/caddy | Apache-2.0 | Kullanılmaz | Kapsam dışı |

Depomuzun kendisi lisanssızdır (tüm hakları saklı). Özgün yazılan metin ve kod bu durumu değiştirmez. Esinlenilen depoya teşekkür gerekiyorsa yalnız belge düzeyinde, kaynak adı verilerek yazılır.

## 7. Kullanıcı (kurucu) kararı bekleyenler (plan seçmez, yalnız listeler)

- E-11/E-24/E-25'in canlı koşusu: yerel model sunucusu ve Apple Intelligence açık bir Mac (kamp K-11).
- E-25'in sırası: kamp havuzu sıra 4 ile örtüşüyor, kurucu sırayı açmalı.
- E-21 için yeni migration (`v12`) ve "Radar" adı.
- E-12 adlandırması: "Hafıza" (wiki) ile "Marka belleği" (gözlem) ayrımı.
- Commit ve push (kamp K-2). Bu plan hiçbir şeyi commit etmez.

## 8. Bilinçle KAPSAM DIŞI bıraktıklarım

| Ne | Gerekçe |
|---|---|
| earthtojake/text-to-cad | Ürünün işi (çok markalı danışman çalışma alanı) ile bağı yok |
| calesthio/OpenMontage, OpenCut-app/OpenCut (video üretimi/düzenleme) | Çıktı türü uzak vizyon (trend kataloğu §B ile aynı karar). AGPL (OpenMontage). Ağır dış araç (FFmpeg, Blender) MAS ile çelişir |
| caddyserver/caddy | Ürün yerel macOS uygulaması, sunucu yayınlamıyor |
| pingdotgg/t3code'un uzaktan erişimi | Uzaktan oturum, ağ ve kimlik doğrulama yükü; MAS ve gizlilik riski. Fikrin özü E-17'ye alındı |
| Agent-Reach tarzı otomatik internet tarama | Platform girişi, çerez ve anti-bot gerekir, kırılgandır; App Store 5.1.2 ve kural 6 riski. Radar elle beslenir (E-21) |
| Sentry SDK / herhangi bir uzak hata servisi | "Uygulama hiçbir şeyi kendiliğinden göndermez" kuralı. Yerine E-05 + E-30 |
| graphiti, mem0, letta, docling, markitdown'u bağımlılık yapmak | Python ya da sunucu bileşeni gerekir, MAS'ta dış süreç yok, bağımlılık yasağı |
| MLX'i bu planda bağımlılık olarak eklemek | Önce ölçüm (E-29). Model boyutu, lisans ve sandbox doğrulanmadı |
| MCP istemcisi kodu | Önce araştırma (E-28). Dış süreç MCP sunucuları MAS'ta çalışmaz |
| CRM boru hattı (twenty esinli kişi/fırsat/aşama) | Ürün kararı gerekir (Stüdyo sadeleşmesi K-10 açık). twenty AGPL, yalnız kavram okundu |
| Yapay zekânın hafızaya kendiliğinden yazması (claude-mem'in otomatik kaydı) | Kural 3'e aykırı. Yalnız onaylı gözlem (E-06) |
| gstack sürecinin bütünüyle alınması | Radarın kendi uyarısı: çok görüşlü. Yalnız rol şablonu alındı |
| Ekip "canlı istasyon" görselleştirmesi (starnet) | Trend Durum #9 "kısmen" ve sade karar verilmiş. Değer düşük |
| Codex onay politikası düzeltmeleri | Kamp havuzu 15. Yalnız doğrudan dağıtımda geçerli, gerçek Codex ölçümü ister |
| Sandbox S4–S9, imza, App Store, ödeme, yayın | Kuluçka kuralı ve kamp havuzu 6. Kurucu "sonra" dedi |
| pptx/xlsx metin çıkarımı | Sistem çerçevesinde çözücü yok, dış araç gerekir |

## 9. Kaynaklar (web araması)

- [awaithumans (enterprisedna dizini)](https://enterprisedna.co/directories/open-source/awaithumans) · [HumanLayer tanıtımı (DEV)](https://dev.to/mysterious_xuanwu_5a00815/give-your-ai-agents-a-human-supervisor-introducing-humanlayer-3adi) · [Phantasm (DEV)](https://dev.to/edwinkys/phantasm-a-human-approval-layer-for-ai-agents-491k) · [Impri](https://www.hunted.space/dashboard/impri) · [hitloop (PyPI)](https://pypi.org/project/hitloop/)
- [MLX ve Foundation Models yazısı](https://medium.com/@nuthalapativarun/mlx-is-now-a-first-class-citizen-in-apples-ai-stack-run-any-hugging-face-model-through-foundation-9dfb8dad2191) · [CarbocationLocalLLM (awesome.ecosyste.ms)](https://awesome.ecosyste.ms/projects/github.com%2Fcarbocation%2Fcarbocationlocalllm) · [Osaurus incelemesi](https://www.promptquorum.com/power-local-llm/osaurus-ai-review) · [Kuzco](https://hunted.space/product/kuzco) · [SwiftAI (HN)](https://hn.svelte.dev/item/45052200)
- [Graphiti özeti](https://thegtmdirectory.com/tools/graphiti/md) · [Ryumem (PyPI)](https://pypi.org/project/ryumem/) · [Kalairos llms.txt](https://cdn.jsdelivr.net/npm/kalairos@1.7.0/llms.txt) · [memvee (PyPI)](https://pypi.org/project/memvee/)
- [Intopia × Figma erişilebilirlik yeteneği](https://intopia.digital/articles/figma-x-intopia-building-accessibility-into-ai-generated-prototypes/) · [awesome-design-skills](https://www.sourcepulse.org/projects/29041733)
- Lisans ve son push: `gh api repos/<ad>` (GitHub REST API), 2026-10-05/06 UTC.

## 10. Doğrulanamayanlar (internet kaynaklı bilgiler)

- **Radar belgesindeki yıldız sayıları ve sürüm etiketleri** (ör. "~155K", "v4.12.0") doğrulanmadı ve bu plana taşınmadı. Radar lisansları API ile doğrulandı (sentry hariç tümü radarla uyumlu; sentry API'de NOASSERTION, LICENSE ilk satırı FSL-1.1-Apache-2.0).
- **Yeni depoların yıldız ve sürüm sayıları** bilinçli olarak sorgulanmadı ve yazılmadı. "Son push" bir sürüm ya da sağlık göstergesi değildir.
- humanlayer, langfuse, twenty ve swift-sdk için API `NOASSERTION` döndü. LICENSE dosyalarının yalnız ilk satırları okundu, lisansların tam kapsamı doğrulanmadı.
- Arama sonuçlarında geçen ama deposu açılıp doğrulanmayanlar: Impri ("MIT, MCP + REST"), Phantasm, hitloop, Kuzco, SwiftAI'ın güncelliği (API'de son push 2025-12-15), Kalairos, Ryumem, memvee, OpenMemory, a11y-lens, Intopia yeteneği ve onun "%91,1 / %47,0" başarı oranları. Hiçbiri görevde kaynak olarak kullanılmadı.
- "MLX artık Foundation Models üzerinden her modeli çalıştırıyor" iddiası (Medium yazısı) doğrulanmadı. E-29 bunu ölçmeden kullanmaz.
- Sandbox'lı uygulamanın geri döngü adresine (`127.0.0.1`) `network.client` yetkisiyle bağlanabildiği doğrulanmadı. E-03 bu yüzden `#if !MAS`.
- Foundation Models'in Türkçe araçlı görev kalitesi yalnız 5 senaryolu denemeyle ölçüldü (`docs/foundation-models-denemesi.md`). Genelleme yapılmaz.
- Tüm boyut tahminleri ölçülmedi.

---

## 11. Uygulama günlüğü · 2026-10-05/06 (30/30 görev kod+test ya da belge düzeyinde kapandı)

Kapı: `KAPI: GEÇTİ` (9 adım, 621 test; başlangıç 415). Tasarım tabanı 154 ≤ 154. Yolculuk 11/11. Migration: v10 (gözlem), v11 (yetenek kökeni), v12 (marka radarı).

| Dalga | Görevler | Sonuç |
|---|---|---|
| A | E-01 gözlem modeli, E-02 SKILL.md paket çözücü, E-03 yerel uç nokta sağlayıcısı, E-04 tasarım denetimi betiği, E-05 kara kutu | Bitti. Tip adı `Observation` → `BrandObservation` (`@Observable` çakışması) |
| B | E-06 `gozlem_oner`, E-07 yetenek kökeni, E-08 belge ağacı, E-09 yolculuklar, E-10 ekip şablonları | Bitti. **E-07 plan dışı hata düzeltmesi:** migration sonrası eski okuma bağlantısı şema önbelleği (`invalidateReadOnlyConnections`) |
| C | E-11 yerel ayar + `.local`, E-12 marka belleği, E-13 belge araçları, E-14 yetenek içe aktarma ekranı, E-15 tasarım kapısı | Bitti |
| D | E-16 gözlem bağlamı, E-17 öneri zarfı, E-18 şablon ekranı, E-19 biçimli Markdown, E-20 yanıt uzunluğu | Bitti |
| E | E-21 radar, E-22 dayanak çipleri, E-23 kırmızı takım (20 test, açık yok), E-24 yerel rozet, E-25 Apple modeli | Bitti |
| F | E-26 yolculuk kapısı, E-27 kalite ilkeleri, E-28 MCP araştırması (yapma/yap/bekle), E-29 MLX araştırması (bekle), E-30 tur izi | Bitti |

### Doğrulanamayanlar (hepsi için)
Canlı model (Claude, Codex, Apple, yerel) hiç denenmedi; tıklama, klavye, VoiceOver ve çoğu ekran çizimi doğrulanmadı; sandbox'lı yerel adres bağlantısı ve MAS imzalı paket ölçülmedi; Word'ün kendi docx'i denenmedi.

### Havuz (kurucu kararı ya da sonraki iş)
1. Sohbet panelinde `.apple` seçilemiyor (`AIChat.available`).
2. `MarkdownExtractor` içe aktarmaya bağlı değil (`TextExtractor` kullanılıyor).
3. Dış ajan gerekçesinin kesin bağı: öneri zarf dosyası kimliğini taşımalı (migration ister).
4. Yetenek boyut sınırı: paket 256 KB, kütüphane 20.000 karakter, hangisi esas?
5. Stüdyo gözlemi müşteri bağlamına girsin mi? (şimdi girmiyor)
6. `Breadcrumbs.shared` için kayıt noktaları yok; tanı raporunda "son_adimlar" boş.
7. Bayatlık eşiği 180 gün iki yerde (bağlam, `wikiLint`).
8. `Localizable.strings` içinde 10 yinelenen anahtar (kapı saymıyor).
9. Tasarım tabanı 154 (153 karışık boşluk, 1 ham renk `NotchTimer.swift:80`); tür bazlı taban yok.
10. Kapı yolculuk kayıt sonuçlarını (`yolculuk-kaydet.sh`) çağırmıyor: kurucu kararı.
11. Çeviri anahtarı: etiket adında görünmez karakter çerçeve kaçışı denenmedi.
12. Radar yalnız görev önerir; gözlem önerisi için kaynak şartı kararı.
13. E-29 yan etkisi: `~/Library/Containers` altında 2 boş kapsayıcı (`com.ornek.e29.sb`, `com.ornek.e29.sbnet`); macOS silmeye izin vermedi.
