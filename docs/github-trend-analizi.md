# GitHub trend kataloğu → Workspace AI (60 repo, tek tek)

Kaynak: kurucunun `github-trending-tum-repositoryler.md` dosyası (26 Eylül–3 Ekim 2026, 60 repo). Dosya yalnızca özet veriyor; "okudum" demek repo kodunu okuduğum anlamına gelmez. Derin bakış yalnızca 6 repo için yapıldı (aşağıda işaretli, alan adları o raporda doğrulanamayanlar belirtildi).

Ölçüt: **Workspace AI = çok markalı danışmanın yerel macOS çalışma alanı; yapay zekâ öneri üretir, insan onaylar; veriler yerel saklanır, yapay zekâ içeriği yalnız izin verilen sağlayıcıya gider; App Store hedefi (sandbox, kendi kendini güncelleme yok, rastgele ikili çalıştırma yok).**

## A. Doğrudan ürüne giren fikirler (12)

| Repo | Aldığımız fikir | Nerede |
|---|---|---|
| paperclipai/paperclip ★ | Şirket gibi agent organizasyonu: `reportsTo` ağacı (döngüsüz), `capabilities`, `status`, insan+agent aynı şemada, **işe alım = onay bekleyen kayıt**, aylık bütçe üç katman | Biz kimiz (yapıldı: ağaç, döngü engeli). Sıradaki: "çalışan ekle" önerisi onaya düşer; üye başına kullanım/bütçe (`usageEntry` zaten var) |
| mvschwarz/openrig ★ | Kalıcı **rol** ≠ geçici **oturum**; `CULTURE.md` (ortak kültür dosyası); koltuk başına izin kipi denetim izine yazılır | Rol = `TeamMember`; sohbet oturumu ayrı. Şirket "kültür" metni bağlama giriyor (yapıldı: Biz/Misyon) |
| block/buzz ★ | İnsan ve agent aynı odada; hash zincirli denetim günlüğü; kimlik ile kapsam | Marka başına "oda": ekip + sohbet. Denetim günlüğüne zincir (sonra) |
| vectorize-io/hindsight ★ | retain/recall/reflect; **gözlem = kanıt sayılı inanç**, üzerine yazılmaz; mental model | "Öğrenme": yapay zekâ gözlemi **öneri** olarak yazar, onaylanırsa "Biz kimiz"/marka profiline girer |
| anthropics/skills ★ | SKILL.md standardı: `name` (≤64, küçük harf-tire), `description` (≤1024, ne zaman kullanılır), `allowed-tools`, `references/` | Yetenek kütüphanesi: yetenek = SKILL.md benzeri kayıt; çalışana bağlanır |
| coreyhaines31/marketingskills | CRO, metin yazarlığı, SEO, reklam, analitik, büyüme: hazır çalışma yöntemleri | **Danışman için en yakın içerik.** Hazır yetenek paketi olarak sunulabilir (lisans MIT; kaynak göstererek) |
| mattpocock/skills, google/skills, ComposioHQ/awesome-claude-skills | Küçük, bağımsız yetenekler; katalog | Yetenek kütüphanesi için kaynak/örnek; içe aktarma biçimi SKILL.md |
| VectifyAI/PageIndex | Uzun belgede vektör yerine **yapı üzerinde akıl yürütme** | Dosya bağlamı: uzun sözleşme/teklif için içindekiler ağacı + bölüm seçme (gömme yerine ya da yanında) |
| mksglu/context-mode | Araç çıktısı bağlamı doldurmasın | Bağlam motoru: token bütçesi, uzun çıktıyı özetleyip referansla verme |
| JuliusBrussee/caveman, DietrichGebert/ponytail | Kısa yanıt = düşük maliyet; "önce yazmadan çözebilir miyim" | Sistem istemi ilkeleri; yanıt uzunluğu ayarı |
| androoAGI/starnet | Çoklu agent çalışmasını **görselleştirme** (piksel uzay istasyonu) | "Ekip canlı görünümü" fikri: kim ne üzerinde, hangi öneri bekliyor (sade, oyunsuz) |
| obra/superpowers | Agent'a baştan sona yöntem (planla, test et, incele) | Çalışan görev tarifi şablonları: "plan → öneri → kontrol" |

## B. Sonra / koşullu (8)

| Repo | Neden koşullu |
|---|---|
| modelcontextprotocol/servers | MCP bağlayıcıları (takvim, dosya, e-posta). MAS sandbox'ında dış süreç sorunlu; yalnız süreç-içi/URL tabanlı bağlayıcı |
| Panniantong/Agent-Reach | Rakip/sosyal dinleme yeteneği; internet erişimi ve gizlilik (5.1.2(i)) izni gerekir |
| NVIDIA/OpenShell, google/ax | Yalıtım örüntüleri; bizde karşılığı sandbox + onay. Doğrudan kullanılmaz, ilke olarak okunur |
| openclaw/openclaw | WhatsApp/Slack kanalında asistan; müşteri iletişim kanalı için vizyon, ama kişisel veri ve MAS kuralları ağır |
| colbymchenry/codegraph | Kod bilgi grafı; bizde wiki bağları (`wikiLink`) var, kod işi odağımız değil |
| openbao/openbao | Gizli yönetimi; bizde Keychain yeterli |
| heygen-com/hyperframes, debpalash/VoiceStudio | İçerik üretim çıktısı (video/ses); "çıktı türü" olarak uzak vizyon |
| dream-num/univer | Elektronik tablo yüzeyi; web SDK, yerel SwiftUI'ye uymaz |

## C. İlgisiz (40)

wifit3, kubernetes-the-hard-way, ai-engineering-from-scratch, tick-stock-panel, Model-Optimizer, openbao dışındaki altyapı (runner-images, hey, sentry, effect, openship, dbx, scriptc), tensorflow, vscode, llvm-project, next.js, PipePipe, Madeira, PLFM_RADAR, coursebook, up, reclip, yoinks, GhostTrack, UniMate, tilelang, reverse-skill, mobile-mcp, claude-code-action, claude-plugins-official, cursor/plugins, firebase-ios-sdk, MoneyPrinterTurbo ve kalanlar. Ürüne girmez; ikisi güvenlik odaklı (wifit3, GhostTrack, reverse-skill) ve ürünün ilkelerine aykırı kullanım alanına girer.

## D. Çıkan ürün kararları

1. **Yetenek kütüphanesi** (SKILL.md biçimi) ve çalışana bağlama.
2. **Çalışan olarak çalıştır:** oturum, çalışanın görev tarifi + yetenekleri ile açılır; çıkan her öneri çalışanın adıyla görünür.
3. **İşe alım = öneri:** yapay zekâ "şu rolde çalışan öner" diyebilir; onayınla ekibe girer (paperclip).
4. **Öğrenme gözlemleri** (hindsight): kanıtlı, onaylı.
5. **Bağlam bütçesi** (context-mode, PageIndex).
6. **Ekip görünümü** (starnet'ten esinli, sade).

Her madde `docs/ai-calisma-alani-plani.md` aşamalarına bağlanır (F1: eylem kaydı, F4: bağlam, F6: sistem entegrasyonu).

## E. Durum (2026-10-03, gece)

"Kurmak" burada **fikri ürüne işlemek** demektir; hiçbir repo bağımlılık olarak eklenmedi, hiçbirinin kodu kopyalanmadı.

| # | Repo (fikir) | Durum | Kanıt |
|---|---|---|---|
| 1 | paperclip: org ağacı, insan+agent aynı şema | **Yapıldı** | `TeamMember`, döngü engeli, `orgChart()`; `SirketVeEkipTests` |
| 2 | paperclip: işe alım = onay bekleyen kayıt | **Yapıldı** | `createTeamMember` önerisi, `calisan_oner` aracı (yalnız Stüdyo sohbeti); onay/geri alma testi |
| 3 | openrig: kalıcı rol ≠ oturum | **Yapıldı** | `AISession.memberId`, `personaPrompt`; rol yetkisi testleri |
| 4 | openrig: ortak kültür dosyası | **Kısmen** | Şirket "biz kimiz"/misyon metni bağlama giriyor; ayrı kültür dosyası yok |
| 5 | anthropics/skills: SKILL.md | **Yapıldı** | `Skill`, `SkillMarkdown.parse/export`, içe aktarma; `YetenekTests` |
| 6 | marketingskills (fikir) | **Yapıldı (özgün metin)** | "Pazarlama ve büyüme" paketi, 6 yetenek |
| 7 | superpowers (plan → öneri → kontrol) | **Yapıldı (özgün metin)** | "Çalışma yöntemi" paketi + "Yazılım ve tasarım" paketi |
| 8 | mattpocock/google/awesome-skills: yetenek kaynağı | **Biçim olarak** | SKILL.md içe aktarma var; katalog tarama/indirme yok |
| 9 | starnet: ekip canlı görünümü | **Kısmen (sade)** | Ekip satırında bekleyen öneri/son çalışma; `memberActivity()`. Görsel "istasyon" yok |
| 10 | hindsight: kanıtlı gözlem | **Yapılmadı** | Mevcut hafıza (wiki + kaynaklı iddia) bu işi kısmen görüyor; ayrı gözlem katmanı sonraki iş |
| 11 | PageIndex: yapı üzerinde okuma | **Yapılmadı** | Uzun belge içindekiler ağacı, F4 (bağlam motoru) |
| 12 | context-mode / caveman / ponytail | **Yapılmadı** | Bağlam bütçesi ve yanıt uzunluğu ayarı, F4 |

Ek yapılan (katalogdan bağımsız, kurucunun isteğiyle): **Stüdyo** = kendi şirketimiz de bir iş alanı (`Brand.isOwn`): görev, dosya, finans, rapor + Şirket sekmesi (Genel, Hizmetler, Ekip, Şema, Yetenekler).
