# Marka yalıtımı: Store yüzeyi izin listesi

H2-06 (G-01) · kural 1 (marka yalıtımı) ve kural 5 (her yazma denetim olayı bırakır).

Bu belge **testle bağlıdır**: `Tests/MarkaCoreTests/YalitimOzellikTests.swift` her koşuda `Sources/MarkaCore/Store/Store.swift` ve
`Store+*.swift` içindeki `Store` gövdelerinde duran her `public func`'u kaynak taramasıyla çıkarır ve şu kuralları uygular:

- Zorunlu `brandId: String` parametresi (dış ya da iç ad) almayan her yüzey **§1'de gerekçesiyle** yer almalıdır. Listede olmayan
  yeni yüzey `storeGenelYuzeyiTaranirKapsamsizlarIzinListesinde` testini kırar: ya `brandId` eklenir ya da buraya bilinçli bir
  satır yazılır. Artık var olmayan ya da kapsamlı hâle gelen satır da testi kırar (liste bayatlamaz).
- `brandId: String?` kapsam sayılmaz (`nil` tüm markalar demektir); bu yüzeyler de §1'dedir.
- Adı yazma önekiyle başlayan (`save`, `set`, `create`, `add`, `delete`, `update`, `assign`, `archive`, `restore`, `apply`,
  `reject`, `revert`, `start`, `stop`, `verify`, `retract`, `ingest`, `decide`, `import`, `install`, `write` + büyük harf) her yüzey
  `herYazmaYuzeyiDenetimOlayiBirakir` testinde gerçekten çağrılır ve en az bir `auditEvent` bırakmalıdır; bırakmayanlar **§2'de
  gerekçesiyle** yer alır.
- Kapsamlı her okuma yüzeyi `rastgeleIkiMarkaHerYuzeydeSizintiYok` testinde (200 tohumlu rastgele iki marka) A markasıyla
  çağrılır; sonuçta B'nin hiçbir kimliği ya da işareti geçmez. Bu listedeki kimlikle okuyan ve isteğe bağlı `brandId` alan
  okumalar da aynı testte A'nın değerleriyle çağrılır.

Satır biçimi: `| \`seçici\` | tür | gerekçe |`. Gerekçe hücresinde `|` kullanılmaz. Seçici Swift yazımıdır (`ad(etiket:etiket:)`).

Kapsam sınırı: tarama yalnız `Sources/MarkaCore/Store/` klasörüdür. Başka klasördeki `extension Store` dosyaları (Wiki, Raporlar,
Bugün, Örnek, Eylemler, AI) ve `read`/`write` içindeki ham SQL bu taramaya girmez.

## 1. Kapsamsız yüzey izin listesi

### Çalışma alanı düzeyi (markadan bağımsız veri)

| Yüzey | Tür | Gerekçe |
|---|---|---|
| `brands(includeArchived:)` | okuma | Marka listesinin kendisi (ad, özet, sağlayıcı izni); marka içeriği taşımaz. AI tarafı izin süzgecini bu listeyle kurar. |
| `ownBrand()` | okuma | Tekil Stüdyo (kendi şirket) markası; markadan bağımsız çalışma alanı verisi. |
| `archivedBrands()` | okuma | Arşivlenmiş marka listesi (Ayarlar › Veri); yalnız marka satırları, içerik yok. |
| `createBrand(name:summary:sector:isOwn:actor:)` | yazma | Yeni markayı doğurur; marka kimliği burada üretilir, başka markanın verisine dokunmaz. Denetim olayı yeni markaya yazılır. |
| `createStudio(name:actor:)` | yazma | Stüdyo markası + tekil şirket profili; markadan bağımsız çalışma alanı verisi, tek işlem. |
| `companyProfile()` | okuma | Tekil şirket profili; markadan bağımsız çalışma alanı verisi. Müşteri bağlamına yalnız Stüdyo izniyle girer (B1 düzeltmesi). |
| `saveCompanyProfile(_:actor:)` | yazma | Tekil şirket profili; markadan bağımsız. Yalnız kendi şirket markasının adını eşitler (denetimli). |
| `services()` | okuma | Şirketin hizmet listesi; markadan bağımsız çalışma alanı verisi. |
| `saveService(_:actor:)` | yazma | Şirket hizmeti; markadan bağımsız çalışma alanı verisi. |
| `deleteService(_:actor:)` | yazma | Şirket hizmeti silme; markadan bağımsız çalışma alanı verisi. |
| `teamMembers(kind:includeArchived:)` | okuma | Ekip çalışma alanı düzeyindedir; markaya bağ `brandAssignment` ile ayrı tutulur (`brandTeam(brandId:)` kapsamlıdır). |
| `saveTeamMember(_:actor:)` | yazma | Ekip üyesi çalışma alanı düzeyindedir; marka ataması bu yoldan yapılmaz. |
| `archiveTeamMember(_:actor:)` | yazma | Ekip üyesi arşivi; çalışma alanı düzeyi. Arşivdeki üye marka ekibine ve bağlama girmez (B3). |
| `restoreTeamMember(_:actor:)` | yazma | Ekip üyesini geri alır; çalışma alanı düzeyi, marka verisine dokunmaz. |
| `proposeTeamTemplate(_:reportsToId:)` | yazma | Ekip şablonu kurulumu: yalnız Stüdyo (kendi şirket) markasına bekleyen "çalışan önerisi" açar (`createProposal` yolu, müşteri markasında ret); veriyi kendisi değiştirmez, oluşturma anı `createProposal` ile aynı denetim istisnasındadır (bkz. §2). |
| `orgChart()` | okuma | Organizasyon şeması; yalnız ekip üyeleri, marka içeriği yok. |
| `assignments(memberId:)` | okuma | Üyenin atandığı marka kimlikleri ve rol; marka verisi okunmaz. |
| `memberActivity()` | okuma | Bilinçli markalar arası istisna (B6): yalnız sayı ve tarih döner, içerik dönmez, AI bağlamına girmez. |
| `skills()` | okuma | Yetenek kütüphanesi; markadan bağımsız çalışma alanı verisi. |
| `saveSkill(_:actor:)` | yazma | Yetenek kütüphanesi; markadan bağımsız çalışma alanı verisi. |
| `deleteSkill(_:actor:)` | yazma | Yetenek kütüphanesi; markadan bağımsız çalışma alanı verisi. |
| `importSkill(markdown:fileName:actor:)` | yazma | SKILL.md içe aktarımı; kütüphane markadan bağımsızdır (sınırlar G-06/G-21 işi). Köken yalnız dosya adını saklar (E-07). |
| `importSkillBundle(_:folderName:actor:)` | yazma | SKILL.md klasör paketi (E-02 önizlemesi onaylandıktan sonra); kütüphane markadan bağımsızdır. Köken yalnız klasör adını saklar (E-07). |
| `installSkillPack(_:actor:)` | yazma | Hazır yetenek paketi; markadan bağımsız çalışma alanı verisi. |
| `setting(_:)` | okuma | Anahtar/değer ayarı. Markaya özgü anahtar marka kimliğini anahtarın içinde taşır (`folder.<brandId>`); değer içerik değil yol ya da bayraktır. |
| `setSetting(_:_:)` | yazma | Anahtar/değer ayarı (ilk açılış, karşılama, klasör yolu); marka içeriği yazmaz. Denetim istisnası §2'de. |
| `read(_:)` | okuma | Ham GRDB okuma kapısı; kapsamı çağıran sorgu taşır. Bu tarayıcı kapının içindeki ham SQL'i denetleyemez (bilinen sınır). |
| `write(_:)` | yazma | Ham GRDB yazma kapısı; kapsam ve denetim çağıranın sorumluluğudur. Denetim istisnası §2'de. |

### Markalar arası sayı (yalnız kimlik → sayı)

| Yüzey | Tür | Gerekçe |
|---|---|---|
| `pendingApprovalCounts()` | okuma | Kenar çubuğu rozeti: marka kimliği → onay bekleyen sayısı. İçerik, başlık ya da kimlik dışı alan dönmez. |
| `openTaskCounts()` | okuma | Kenar çubuğu: marka kimliği → açık görev sayısı. İçerik dönmez; AI tarafı `permitted` süzgecinden geçirir. |

### Tek çalışan sayaç (çalışma alanı kuralı)

| Yüzey | Tür | Gerekçe |
|---|---|---|
| `runningTimer()` | okuma | Aynı anda tek sayaç çalışır (çalışma alanı kuralı); araç çubuğundaki sayaç her markada aynıdır. AI bağlamına girmez. |
| `longRunningTimer(now:)` | okuma | Unutulmuş sayaç uyarısı (U-03); tek sayaç kuralı gereği çalışma alanı düzeyinde. |
| `stopTimer(at:)` | yazma | Tek çalışan sayacı durdurur; kayıt kendi markasına yazılır ve denetim olayı o markaya düşer. |
| `startTimer(taskId:at:)` | yazma | Marka görevin kendisinden alınır (`TimeEntry.brandId = task.brandId`); tek sayaç kuralı başka markadaki sayacı durdurur, veri taşımaz. |
| `startTimerReportingHandoff(taskId:at:)` | yazma | `startTimer` ile aynı; durdurulan sayacın görev başlığını ve marka adını kullanıcıya bildirim için döndürür. Aynı kullanıcı, AI bağlamına girmez. |
| `addManualTime(taskId:seconds:endingAt:note:)` | yazma | Marka görevin kendisinden alınır; süre kaydı yalnız o göreve ve markasına yazılır. |

### İsteğe bağlı marka (`nil` = tüm markalar)

| Yüzey | Tür | Gerekçe |
|---|---|---|
| `tasks(brandId:statuses:limit:)` | okuma | `nil` yalnız Bugün ve tüm markalar görünümünde (kullanıcının kendi ekranı). AI tüm markalar oturumu sonucu `permitted` süzgecinden geçirir. A ile çağrı özellik testinde. |
| `timeEntries(brandId:from:to:)` | okuma | `nil` haftalık süre özeti için (tüm markalar). Marka verildiğinde `TimeEntry.brandId` ile süzer; özellik testinde A ile. |
| `workLogs(brandId:statuses:)` | okuma | `nil` tüm markalar görünümü ve AI tüm markalar oturumu (izinli markalar süzülür). Marka verildiğinde kapsamlı; özellik testinde A ile. |
| `setSourceArchived(_:brandId:archived:actor:)` | yazma | `brandId` verilirse kaynağın o markaya ait olduğu denetlenir (`brandScope`); arayüz her zaman görünen markayı verir. Yalnız arşiv damgası değişir. |

### Kimlikle okuyanlar (kimlik markanın kendi listesinden gelir)

| Yüzey | Tür | Gerekçe |
|---|---|---|
| `brand(_:)` | okuma | Kimlik markanın kendisidir; dönen tek marka satırıdır. |
| `task(_:)` | okuma | Kimlik markanın kendi listesinden gelir. AI aracı sonucu oturum markasıyla karşılaştırır (`brandScope`). |
| `source(_:)` | okuma | Kimlik markanın kendi listesinden gelir. AI aracı `ownSource` ile marka ve izin denetler. |
| `workLogDetail(_:)` | okuma | Kayıt ve bağlı kaynak/görev; bağlar yazılırken aynı marka zorunludur (`saveWorkLog` `brandScope`), bu yüzden detay markayı aşmaz. |
| `needsWorkLog(taskId:)` | okuma | Yalnız Bool döner; içerik dönmez. |
| `knowledgeUndo(proposalId:)` | okuma | Sayfanın markası önerinin markasıyla eşleşmezse `nil` döner; yalnız iki kimlik döner. |
| `proposalPreview(_:)` | okuma | Önizleme önerinin kendi `brandId`'siyle hesaplanır (`previewTaskEdit(brandId:)`). |
| `proposer(of:)` | okuma | Oturumun markası önerinin markasından farklıysa kimse dönmez (B6). |
| `proposals(sessionId:)` | okuma | Oturumun markası sonradan değişmez (`aiSession_scope_fixed` tetikleyicisi); oturumun önerileri o markadadır. |
| `auditTrail(entity:entityId:)` | okuma | Verilen kaydın kendi geçmişi; kimlik markanın kendi listesinden gelir. |
| `fileURL(for:)` | okuma | Verilen `Source` değerinden dosya yolu üretir; veritabanı okumaz. |

### Markanın kendisini değiştirenler

| Yüzey | Tür | Gerekçe |
|---|---|---|
| `updateBrand(_:actor:)` | yazma | Kimlik markanın kendisidir; `isOwn` korunur (B5), ad tekilliği denetlenir. |
| `setBrandArchived(_:archived:)` | yazma | Markanın kendi durumu; veri silinmez, Stüdyo arşivlenemez. |
| `setBrandLogo(_:fileURL:)` | yazma | Markanın kendi logosu; dosya içerik adresli depoya kopyalanır. |
| `setAIProviders(_:providers:)` | yazma | Markanın kendi sağlayıcı izni (kural 6); yalnız o markanın satırı. |

### Kaydı kendi `brandId` alanında taşıyan yazmalar

Kayıt markasını değerin içinde taşır. Bağlı kimlikler (proje, kaynak, görev) aynı markada olmalıdır. Aynı kimlik başka markada
zaten varsa yazma reddedilir (H2-06 düzeltmesi: kimlik çakışmasıyla başka markanın kaydı bu markaya taşınamaz; kanıt
`rastgeleIkiMarkaHerYuzeydeSizintiYok`, 200 tohum).

| Yüzey | Tür | Gerekçe |
|---|---|---|
| `saveTask(_:actor:)` | yazma | Görev `brandId` taşır; proje aynı markada olmalı; mevcut kimlik başka markadaysa `brandScope`. |
| `saveRecord(_:actor:)` | yazma | Marka kaydı `brandId` taşır; kaynak aynı markada olmalı; mevcut kimlik başka markadaysa `brandScope`. |
| `saveContact(_:)` | yazma | Kişi `brandId` taşır; mevcut kimlik başka markadaysa `brandScope`. |
| `saveProject(_:)` | yazma | Proje `brandId` taşır; mevcut kimlik başka markadaysa `brandScope`. |
| `saveFinanceEntry(_:actor:)` | yazma | Finans kaydı `brandId` taşır; marka var olmalı; mevcut kimlik başka markadaysa reddedilir (`notFound`, 0.3.0'dan beri). |
| `saveWorkLog(_:inputSourceIds:outputSourceIds:actor:)` | yazma | İş kaydı `brandId` taşır; kaynak ve görev aynı markada olmalı; mevcut kimlik başka markadaysa `brandScope`. |
| `saveUserWorkLog(_:inputSourceIds:outputSourceIds:verifiedBy:)` | yazma | Elle iş kaydı (H2-03); `saveWorkLog` kurallarına ek olarak mevcut kimlik başka markadaysa ya da AI yazdıysa reddedilir. |

### Kimlikle yazanlar (işlem kaydın kendi markasına uygulanır)

Kimlik markanın kendi listesinden gelir. İşlem kaydın kendi markasında kalır, denetim olayı o markaya yazılır ve sonuç başka
markanın verisini döndürmez.

| Yüzey | Tür | Gerekçe |
|---|---|---|
| `deleteContact(_:)` | yazma | Kişiyi siler; denetim olayı kişinin markasına yazılır, veri taşınmaz. |
| `deleteRecord(_:)` | yazma | Marka kaydını siler; denetim olayı kaydın markasına yazılır. |
| `deleteFinanceEntry(_:actor:)` | yazma | Finans kaydını siler; denetim olayı kaydın markasına yazılır. |
| `deleteTask(_:)` | yazma | Görevi siler (süre kaydı varsa reddeder, U-01); denetim olayı görevin markasına yazılır. |
| `setTaskStatus(_:_:actor:)` | yazma | `saveTask` üzerinden; görevin kendi markası değişmez. |
| `applyProposal(_:)` | yazma | Öneri kendi markasına uygulanır; yük her uygulamada önerinin markasıyla yeniden doğrulanır (`validateProposal`). |
| `rejectProposal(_:)` | yazma | Önerinin durumunu değiştirir; denetim olayı önerinin markasına yazılır. |
| `revertProposal(_:)` | yazma | Uygulanmış öneriyi geri alır; sonuç kaydının markası değişmez, kullanıcı düzenlemesi varsa reddeder. |
| `verifyWorkLog(_:verifiedBy:)` | yazma | İş kaydını doğrular (AI doğrulayamaz); kaydın markası değişmez. |
| `retractWorkLog(_:)` | yazma | İş kaydını geri çeker; kaydın markası değişmez. |

## 2. Denetim olayı istisnaları

Aşağıdaki yazma yüzeyleri kendi başına `auditEvent` bırakmaz. Liste dışındaki her yazma yüzeyi testte çağrılır ve en az bir
denetim olayı bırakmak zorundadır.

| Yazma yüzeyi | Gerekçe |
|---|---|
| `createProposal(sessionId:brandId:kind:summary:payload:)` | Öneri veri değişikliği değil, bekleyen öneri satırıdır (kural 3). Veriye dokunan karar (`applyProposal`, `rejectProposal`, `revertProposal`, `decideSuggestions`) denetim olayı yazar. Açık soru: oluşturma anı denetim izinde görünmez; G-05 (denetim izi zinciri) ile birlikte karar verilecek. |
| `setSetting(_:_:)` | Uygulama ayarı (ilk açılış zamanı, karşılama bayrağı, marka klasörü yolu); marka içeriği değil. Ayar tablosu denetim izinin konusu değil. |
| `write(_:)` | Ham GRDB yazma kapısı; denetim olayı kapının içindeki çağıranın sorumluluğudur (Store işlevleri kendi `audit` çağrısını yapar). |
