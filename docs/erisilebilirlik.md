# Erişilebilirlik — kod düzeyinde tarama (2026-10-04)

> **Durum: kod düzeyinde tarama.** VoiceOver ile gerçek deneme YAPILMADI (ekran kilitliydi). Bu belge uygulamanın
> "erişilebilir" olduğunu iddia etmez; yalnız kaynakta ölçülebilen eksiklerin kapatıldığını gösterir.

## Araç
`scripts/erisilebilirlik-tarama.sh` — python3 + regex, bağımlılık yok, çıkış kodu her zaman 0 (bilgi aracı). Kurallar,
yanlış pozitif/negatifler ve sınırlar betiğin başında yazılı. Bilinçli atlama satıra `// a11y-tarama: yok-say — <neden>`
yorumuyla yapılır ve sayısı ayrıca raporlanır (gizlenmez).

## Önce / sonra

| Kural | Önce | Sonra |
|---|---|---|
| (a) simge düğmesi etiketsiz | 1 | 0 |
| (b) `onTapGesture` + trait/eylem yok | 5 | 0 |
| (d) renk-tek-başına durum | 4 | 0 |
| (e) alan etiketi eksik | 9 | 0 |
| **Bulgu toplamı** | **19** | **0** |
| Bilinçli atlanan (yanlış pozitif) | 0 | 4 |
| (c) `.font(.system(size:` (yalnız bilgi) | 254 | 254 |

## Yapılanlar
- **Simge düğmeleri:** menü çubuğu "Sıradaki görevler" zamanlayıcı düğmesi ve Yapılacaklar tamamlama halkası yalnız
  `.help` (ipucu) taşıyordu → `accessibilityLabel` eklendi; halkaya ayrıca durum değeri (`accessibilityValue`).
- **Durum metni:** `StatusCircle.State.title` (Yapılacak / Sürüyor / Bekliyor / Bitti). Halka `accessibilityHidden`
  olduğundan durum bu metinle verilir: planlama listesi satırı, takvim çipi, "Sıradaki teslimler" satırı, tamamlama düğmesi.
  Menü çubuğundaki kırmızı nokta → "Zamanlayıcı çalışıyor".
- **Tıklanabilir satırlar:** planlama listesi satırı ve takvim çipi → `.isButton` + `accessibilityAction`.
- **Alanlar:** Şirket ekranında yer tutucusu örnek olan alanlar (Şirket adı, Slogan, Web sitesi) görünür başlıkla
  etiketlendi; tüm `TextEditor`'lara (Biz kimiz, Misyon, hizmet ayrıntısı, yetenek tanımı/yönergeleri, üye hakkında,
  görev tarifi, marka profili düzenleyicisi) etiket.
- **Klavye:** İş kaydı düzenleyicisi ve rapor düzenleme "Kaydet" → ⌘S (Return çok satırlı alanda satır ekler, bu yüzden
  `.defaultAction` değil). Mevcut durum tarandı: menü komutları (⌘N, ⇧⌘N, ⌘K, ⌘J, ⇧⌘H, ⌘0–⌘9, ⌘F), tüm sheet'lerde
  Vazgeç = `.cancelAction`, onay sayfasında "Seçilenleri onayla" = `.defaultAction`; komut paleti ↑↓ + ↩ + Esc;
  ayrıntı paneli Esc + "Paneli kapat" erişilebilirlik eylemi; satır içi alanlarda Esc vazgeçer.
- **Yanlış pozitif (atlandı):** komut paleti satırı (trait `row()` yardımcısında), iki boş-zemin dokunuşu (yalnız seçimi
  kaldırır; karşılığı Esc), Yapılacaklar pano sütun başlığı (durum yanındaki metinle söylenir).

## Bilinen sınırlar
- VoiceOver gerçek denemesi **yapılmadı**; okuma sırası, odak halkası ve eylem menüsü doğrulanmadı.
- Kontrast ölçümü yok (açık/koyu).
- Dynamic Type: macOS'ta sistem metin boyutu sabit `.font(.system(size:))` değerlerini büyütmez; 254 sabit boyut var.
- Odak sırası (`FocusState`) yalnız giriş alanlarında açıkça yönetiliyor; sheet açılınca ilk alana odak verilmiyor
  (Üye/Hizmet/Yetenek sayfaları) — değiştirilmedi, gerçek pencerede denenmeli.
- Tarama sözdizimi ağacı kurmaz; yardımcı fonksiyonda verilen etiketi göremez, koşullu `Text` içeren etiketi metinli sayar.
- `StatusCircle.State.title` MarkaApp hedefinde; test hedefi yalnız MarkaCore'u gördüğü için birim testi yok.

## Sabah elle kontrol listesi (kurucu, ~10 dk)
VoiceOver: ⌘F5. Gezinme: VO = Control+Option.
1. Kenar çubuğunda VO+→ ile gez: marka adı ve "N öneri onay bekliyor" okunuyor mu?
2. Yapılacaklar'da tamamlama halkası: "Tamamla, Yapılacak, düğme" gibi okunuyor mu; VO+Boşluk tamamlıyor mu?
3. Planlama listesi satırı: başlık + durum + tarih okunuyor, VO+Boşluk ayrıntı panelini açıyor mu?
4. Takvim çipi: "düğme" olarak okunuyor ve paneli açıyor mu?
5. Akış › "Sıradaki teslimler": satırda durum (Sürüyor/Bekliyor…) okunuyor mu?
6. Menü çubuğu öğesi: zamanlayıcı düğmesi "Zamanlayıcıyı başlat/durdur" diye okunuyor mu; kırmızı nokta "Zamanlayıcı çalışıyor"?
7. Şirket ekranı: Şirket adı / Slogan / Web sitesi alanları "https://" yerine başlıkla mı okunuyor; Biz kimiz / Misyon?
8. Üye / Hizmet / Yetenek sayfası: Tab ile tüm alanlar sırayla geziliyor mu; Esc kapatıyor, ↩ kaydediyor mu?
9. İş kaydı düzenleyicisi: ⌘S kaydediyor, Esc vazgeçiyor mu; Return çok satırlı alanda satır ekliyor mu?
10. Rapor düzenlemede ⌘S kaydediyor, Esc vazgeçiyor mu?
11. Onay sayfası: ↩ "Seçilenleri onayla", Esc "Vazgeç"; onay kutuları "Seçili / Seçili değil" okunuyor mu?
12. Ayrıntı paneli açıkken Esc kapatıyor mu; ⌘K paleti ↑↓ ↩ Esc ile tamamen klavyeyle kullanılabiliyor mu?
