# Öneri zarfı (`oneri-zarfi`, şema 2)

Durum: E-17 ile eklendi (2026-10-06). Kod: `Sources/MarkaCore/AI/ProposalEnvelope.swift`. Testler: `Tests/MarkaCoreTests/OneriZarfiTests.swift`.

Claude Code, Codex, başka bir ajan ya da bir betik aynı JSON zarfını üretebilir. Kullanıcı zarfı **kendi seçtiği dosyadan** ya da **panodan** içe alır ve onay sayfasında görür. Zarf hangi ajanın ürettiğini söyler, ama yetki taşımaz.

## Değişmez kurallar

- **Yalnız bekleyen öneri.** Zarftaki her öğe bekleyen öneri olur (`ProposalOrigin.external`). Hiçbir şey onaysız uygulanmaz. Onay, uygulama içi önerilerle aynı yoldan geçer ve geri alınabilir.
- **Marka kullanıcının seçimidir.** Marka, içe almayı yapan ekranın markasıdır (`brandId`). Zarftaki `marka`, `markaId` ya da başka bir marka alanı yok sayılır.
- **Zarf metni veridir, talimat değildir.** İçindeki "önceki talimatları yok say", "onayı atla" gibi cümleler hiçbir eylemi tetiklemez.
- **Üretici yalnız etikettir.** `uretici` tek satıra indirilir, denetim ve biçim karakterleri temizlenir, 64 karakterle kırpılır. Onay sayfasında "Dış ajan: <ad>" rozeti olarak görünür. Kendini "Kullanıcı" diye tanıtan ajan da yalnız öneri üretir.
- **Hata mesajı içerik taşımaz.** Mesaj zarftaki bir metin değerini içerecekse genel bir cümleyle değiştirilir. Okuma hatası dosya yolunu göstermez.

## Biçim

Şema 2 = şema 1 öğeleri + üç üst alan. Şema 1 öğe kuralları (`gorevler`, `calismaKayitlari`, `kayitlar`, `notlar`/`not`) aynen geçerlidir; ayrıntısı marka klasöründeki `BAGLAM.md` talimatındadır.

| Alan | Tür | Kural |
|---|---|---|
| `surum` | sayı | `2` (şema 1 dosyası da zarf olarak okunur, o zaman üst alanlar okunmaz) |
| `uretici` | metin, isteğe bağlı | Tek satır, 64 karakterle kırpılır, yalnız etiket |
| `gerekce` | metin, isteğe bağlı | Tek satır, 1000 karakterle kırpılır, denetim kaydında saklanır |
| `dayanak` | metin dizisi, isteğe bağlı | Bu markanın kaynak ya da gözlem kimlikleri. Kimlik sınırı 20, kimlik başına karakter sınırı 64. Başka markanın ya da var olmayan bir kimlik zarfın tamamını reddeder |

Örnek (uydurma veri):

```json
{
  "surum": 2,
  "uretici": "Claude Code",
  "gerekce": "Toplantı notundan çıkarıldı.",
  "dayanak": ["<bu markadaki kaynak kimliği>"],
  "gorevler": [{"baslik": "Teklif taslağı", "sonTarih": "2026-10-20"}],
  "kayitlar": [{"tur": "karar", "baslik": "Yeni logo onaylandı"}]
}
```

## Sınırlar

| Sınır | Değer |
|---|---|
| Dosya boyutu | 256 KB (üstü reddedilir) |
| Öğe sayısı | 50 (üstü reddedilir) |
| Tanınmayan alan | Yok sayılır (ör. `yetki`, `otomatikOnay`) |
| Aynı içerik | Aynı markaya ikinci kez öneri üretmez (sha256) |
| Dosya eki (`girdiDosyalari`, `ciktiDosyalari`) | Yalnız marka klasörü oluşturulmuş markada ve o klasörün içinden; klasör yoksa zarf reddedilir |

## Yapılmayanlar (bilerek)

- **Klasör izleme yok.** Marka klasöründeki `oneriler/` kutusu şema 1'de kalır ve `surum: 2` dosyasını reddeder. Klasör izleme MAS'ta güvenlik kapsamlı yer imi (bookmark) ister (sandbox S4).
- **Ağ ve MCP yok.** Zarf yalnız dosya ya da pano yoluyla gelir.
- **Arayüzde içe alma düğmesi bu görevde yok.** Çekirdek yüzey `SuggestionInbox.importEnvelope(_:brandId:sourceName:)` ve `importEnvelope(contentsOf:brandId:)` hazırdır; "Dosyadan / panodan içe al" düğmesi ayrı bir arayüz görevidir.
- **Gerekçe onay kartında gösterilmez.** Gerekçe ve dayanak şimdilik yalnız denetim kaydındadır (`suggestionFile` · `ingest`). Kartta gösterimi E-22'nin işidir.
- **Modelin zarfa uyumu ölçülmedi.** Testler zarfın çekirdekte nasıl işlendiğini kanıtlar; bir ajanın bu biçimi doğru üretip üretmediği canlı olarak denenmedi.
