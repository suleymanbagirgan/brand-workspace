# Marka Bilgileri: yeniden tasarım, 20 fikir (2026-10-04)

Sorun: sayfa iki sabit kartla başlıyor, sağda boşluk kalıyordu; "Yapay zekâ ne okuyor?" gizliydi; boş bölüm ile dolu bölüm aynı görünüyordu; metin okuması zordu; eski metin terminali anlatıyordu.

| # | Fikir | Durum |
|---|---|---|
| 1 | İki ayrı kart yerine tek **bağlam durumu** kartı | yapıldı |
| 2 | Çubuk yerine **halka** gösterge (tamamsa yeşil, değilse marka rengi) | yapıldı |
| 3 | Durum cümlesi: "Yapay zekâ bu markayı tanıyor / henüz tam tanımıyor" | yapıldı |
| 4 | **Eksik bölüm çipleri**: tıklayınca ilgili karta kaydırır ve yazmaya açar | yapıldı |
| 5 | Süzgeç: Tümü / Dolu / Eksik (sayılarıyla) | yapıldı |
| 6 | Bölüm başına SF Symbol simgesi | yapıldı |
| 7 | Sözcük sayısı (dolu kartta) | yapıldı |
| 8 | "Son güncelleme" (göreli: "dün", "3 gün önce"); yeni `profileUpdatedAt` + test | yapıldı |
| 9 | Okuma tipografisi: 14 pt, geniş satır aralığı, en çok 680 pt satır uzunluğu | yapıldı |
| 10 | Kart eylemleri: kopyala ve kalem (üstüne gelince belirginleşir, klavyeyle de erişilir) | yapıldı |
| 11 | Boş kart: kesikli çerçeve, yazma soruları, **Yaz** ve **Asistana sor** | yapıldı |
| 12 | Düzenleyici: otomatik odak, sayaç rengi (%90 turuncu, aşınca kırmızı), Esc vazgeçer, ⌘↩ kaydeder | yapıldı |
| 13 | **Token tahmini** kartta ve toplamda ("~", karakter/3,5; ölçüm değil) | yapıldı |
| 14 | "Yapay zekâ gözüyle bak": boyut, kopyala, klasörde göster | yapıldı |
| 15 | Alt sekme sayıları: Hedefler N, Kişiler ve projeler N | yapıldı |
| 16 | **Sektör** satır içi düzenleme (tıkla, yaz, ↩ kaydeder, Esc vazgeçer, ⌘Z geri alır) | yapıldı |
| 17 | ⌘⇧E: sıradaki eksik bölüme git | yapıldı |
| 18 | VoiceOver: kart "Hedef kitle, dolu/boş" diye okunur, başlık özellikleri, simge gizli | yapıldı |
| 19 | Eşit yükseklikli iki sütun (Grid) korundu, filtreyle yeniden dizilir | yapıldı |
| 20 | "Kaydedildi ✓" iki saniyelik geri bildirim ("Hareketi Azalt"a saygılı) | yapıldı |

## Dürüst notlar
- **Yapay zekâ bölüm yazamaz.** "Asistana sor" yalnızca sohbette taslak çıkarır; kaydı kullanıcı yapar (profil bölümü için öneri türü yok). İstemde "bilmediğini uydurma" yazar.
- Eski metin "terminaldeki araç okur" diyordu; terminal kalktığı için "asistanın bağlamına girer" olarak düzeltildi.
- Token sayısı **tahmindir**; kesin sayı için sağlayıcının sayacı gerekir.
- Görüldü: açık ve koyu modda dolu durum, eksik durum (halka, çipler, kesikli kartlar), önizleme. **Görülmedi/denenmedi:** gerçek pencerede tıklama, hover, odak, ⌘⇧E, Esc/⌘↩, sektör düzenleme, kopyala, "Klasörde göster" (çizim aracı etkileşimi çalıştırmaz).
- Çizim aracının sabit yüksekliği, iki satırlı Grid'de satırlar arasında yapay bir boşluk gösterir; kaydırılan gerçek sayfada oluşmaz (doğrulanmadı).
