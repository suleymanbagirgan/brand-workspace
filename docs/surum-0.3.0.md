# 0.3.0 — Terminal merkezli yeni arayüz (devam ediyor)

Tarih: 2026-10-01. Önceki: 0.2.1 (Braun sadeleştirmesi). Yön değişikliği: kurucu ve UX tasarımcı, terminali ürünün merkezine koyan
ve bölümleri genişleten bir tasarım teslimi onayladı (`marka-ekran-tasarimi`). 0.2.1'in "tek turuncu vurgu, 4 yazı stili" kuralı
bu sürümde yerini tasarımın dili aldı (indigo vurgu, ölçüler `Design.swift`'te). Sürüm numarası henüz yükseltilmedi.

## Yapılanlar
- **Terminal sütunu:** sağda sabit, sürüklenebilir (315–600 pt, genişlik hatırlanır), koyu tema; başlık, oturum durumu,
  Claude Code ve Codex başlatma düğmeleri, klasör yolu, kabuk ve yalıtım durumu. Marka başına tek kabuk (oturum sekmesi yok).
- **Marka bölümleri (altı):** Akış · Görevler (Liste · Pano · Gantt · Takvim) · Dosyalar · Marka Bilgileri (Hedefler dahil) · Finans · Rapor
  (⌘1–⌘6). Tasarım teslimindeki sekizli yapı Apple HIG'in "en çok altı sekme" kuralına göre birleştirildi (bkz. `docs/tasarim-denetimi.md`). Akış tasarımda
  yok ama iş kaydı doğrulamasının yeridir; korundu.
- **Marka Bilgileri:** `ProfileSection` bölümleri (hedef kitle, konumlandırma, iletişim dili, kapsam, rakipler, kısıtlar, başarı
  ölçütleri). Doldurulan bölümler `BAGLAM.md`'ye girer; boş bölüm girmez ve kendiliğinden doldurulmaz. Tablo: `brandProfile`
  (migration `v3_marka_profili`).
- **Finans:** ödeme planı ve çalışma bütçeleri, elle tutulur. Tablo: `financeEntry` (migration `v4_finans`), tutar kuruş cinsinden
  tam sayı (₺). Uygulama muhasebe, banka bağlantısı ya da otomatik tahsilat yapmaz; ekranda böyle yazar.
- **Komut paleti (⌘K), kenar çubuğunda arama kutusu, sistem kenar çubuğu malzemesi, pencere minimum boyutu 1100×700.**
- Rapor başlığı, görev ayrıntı paneli (kapatma düğmesi, "Tamamlandı olarak işaretle") yenilendi.
- Rapor testi sabit saatle düzeltildi (görev bitiş zamanı artık testte sabit).

## Doğrulanmayanlar (açıkça)
- Pencere görüntüsü alınamadı (ekran kilitli ya da izin yok). Tüm görsel denetim `MARKA_SNAPSHOT` ile yapıldı; bu araç sistem
  malzemesini (vibrancy/cam), AppKit görünümlerini (terminal) ve `Menu`'leri çizmez. Terminal paneli, komut paleti, kenar çubuğu
  malzemesi ve sürükleme tutamacı gerçek pencerede elle denenmedi.
- macOS 26 cam davranışı ikincil kaynaklara dayanır (Apple sayfaları okunamadı).

## Yapılmayanlar
- Tasarımdaki görev kodları (MC-101), "İlgili çalışma" sütunu, görev ayrıntısında beklenen çıktı ve kontrol listesi, "Planı birlikte
  oluştur", Koyu görünüm düğmesi, "Seçili marka" kenar çubuğu bölümü, oturum sekmeleri.
- Onay sayfasının yeni tasarımı.

## Güvenlik notu
`MARKA_SNAPSHOT` yalnızca `MARKA_WORKSPACE` ve `MARKA_FOLDERS` ile geçici dizinlerde çalıştırılır; aksi halde gerçek veri
alanına ve marka klasörlerine dokunur (1 Eki 2026'da yaşandı).
