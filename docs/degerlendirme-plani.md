# Beta değerlendirme planı (5 bağımsız danışman)

Amaç, ürünün vaadini ölçmek. Talep ve fiyat henüz kanıtlanmadı; bu plan onları kanıtlamaz, yalnızca ilk sinyali toplar.

## Katılımcılar
- 5 bağımsız danışman ya da 2-5 kişilik ajans kurucusu. Her biri en az 3 markaya aktif hizmet veriyor ve macOS 14+ kullanıyor.
- AI kullanımı zorunlu değil. En az 2 katılımcının Anthropic API anahtarı veya Codex (ChatGPT) hesabı olmalı.
- Gerçek müşteri verisi katılımcının kendi Mac'inde kalır. Ekip hiçbir içerik görmez.

## Süre ve görevler (2 hafta)
| Gün | Görev | Başarı koşulu |
|---|---|---|
| 1 | Kurulum: ilk marka, 3 kaynak (1 görüşme notu, 1 talep, 1 dosya) | Masa ekranında kayıtlardan oluşan bir "sıradaki adım" görünüyor |
| 1-3 | Bir işi AI ile yapma (AI yoksa elle) ve çalışma kaydını doğrulama | En az 1 doğrulanmış çalışma kaydı var |
| 5 | Haftalık rapor taslağı, düzenleme, onay, PDF | 1 onaylı rapor ve paylaşım geçmişinde PDF kaydı |
| 6-14 | Normal kullanım | — |
| 14 | 20 dakikalık görüşme ve ölçüm özetinin paylaşımı | — |

## Ölçümler
Uygulama *Ayarlar › Veri › Tanı bilgisini kopyala* metninin sonunda bu değerleri yerel kayıtlardan hesaplar ve hiçbir yere göndermez. Katılımcı özeti kopyalayıp gönderir; özet marka adı ya da içerik içermez.

| Ölçüm | Tanım | Kaynak | Hedef (varsayım) |
|---|---|---|---|
| İlk kurulum süresi | İlk açılıştan kullanıcının eklediği ilk kaynağa kadar geçen dakika | `metrics.firstLaunchAt`, `source.createdAt` | medyan < 10 dk |
| Rapor hazırlama süresi | Raporun ilk taslak sürümünden onaylanan sürümüne kadar geçen dakika (medyan) | `reportVersion` | medyan < 15 dk |
| Kaynak hataları | Kullanıcının çelişkili/eskimiş işaretlediği iddialar, reddedilen ve geri alınan AI önerileri, raporda düzeltilen maddeler | `auditEvent`, `aiProposal`, `reportVersion` | Görüşmede her biri tek tek sorulur |
| Tekrar kullanım | Son 14 günde kullanıcı eylemi olan gün sayısı | `auditEvent.actor = user` | ≥ 3/5 katılımcıda 2. hafta ≥ 3 gün |

**Karşı ölçüt:** AI önerisinin yüksek kabul oranı hedef değildir. Oran yüksek ama düzeltilen madde sayısı da yüksekse bu kör onaya işaret eder.

## Kaynak hatasının doğrulanması
Görüşmede katılımcı onaylı raporundan rastgele 5 madde seçer. Her madde için dayanak kaydı açılır ve "Bu madde bu kayda doğru mu dayanıyor?" diye sorulur. Yanlış dayanak oranı elle not edilir; hedef < %5.

## Görüşme soruları
1. Bir markaya döndüğünde Masa ekranı "kaldığın yeri" ne kadar doğru gösterdi? Neyi eksik gösterdi?
2. Hangi durumda uygulamayı açmayı bıraktın veya başka araca döndün?
3. Rapor taslağında en çok neyi düzelttin?
4. Bu aracı ayda kaç TL'ye kullanırdın? (Yalnızca sinyaldir, fiyat kanıtı sayılmaz.)
5. AI'ın bir markanın bilgisini başka markaya taşıdığını düşündüğün bir an oldu mu?

## Karar ölçütü
- 5 katılımcıdan en az 3'ü rapor koşulunu tamamlar ve 2. hafta en az 3 gün kullanırsa sonraki aşama ödeme deneyi olur.
- Aksi hâlde en sık terk nedeni ürün kapsamına geri beslenir.
