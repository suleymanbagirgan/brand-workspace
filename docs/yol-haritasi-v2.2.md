# Yol haritası v2.2 — kullanıcı gözüyle (3 Eki 2026)

Kurucu planlamayı devretti; yayın bu aşamada düşünülmüyor. Ölçüt: danışman her sabah uygulamayı açtığında "bugün neye bakmalıyım" sorusunu 5 saniyede
cevaplayabilmeli ve terminaldeki AI'nın işini güvenle onaylayıp müşteriye rapor verebilmeli. Yoğunluk azaltılır, ne yapılacağı her ekranda söylenir.

## Yapıldı (v2.2)
Özet ekranı (künye, kutucuklar, sıradaki teslimler, akış), onay sayfası (kartlı, simgeli), Pano (kanban + sürükle-bırak), Rapor hazırlık kartı (✓/! satırları ve
eylem düğmeleri; tuval açık renkli), Marka Bilgileri dört alt sekme (Profil · Hedefler · Kişiler ve projeler · Ayrıntılar ve izinler).

## Sırada (öncelik sırasıyla, hepsi kullanıcı değeri)
1. **Hızlı ekleme (⌥⌘Space gibi genel kısayol olmadan):** pencere içinde ⌘N → tek satırlık "Görev / Söz / Not" girişi, doğal tarih ("cuma", "yarın") ayrıştırma.
2. **Onay anı:** satır içi klavye (↑↓ gez, Return onayla, Delete reddet), onaylanınca kısa teşekkür animasyonu, "5 saniye içinde geri al" şeridi.
3. **Rapor:** dönem karşılaştırması ("geçen haftaya göre +2 iş"), müşteriye giden PDF'te marka rengi ve logo, rapor şablonu seçimi (kısa/ayrıntılı).
4. **İlk gün:** Claude Code/Codex kurulu değilse ilk açılışta yönlendirme; boş markada "ilk adım" kartları (Marka Bilgileri'ni doldur, ilk görevi ekle).
5. **Arama:** ⌘K paletine görev, dosya ve iş kaydı arama sonuçları; son açılanlar.
6. **Menü çubuğu ve widget:** menü çubuğu özeti genişlet (bugün teslimleri); App Intents/Widget Xcode'da (kurulu) yapılabilir.
7. **Cihaz üstü özet:** rapor özetini `FoundationModels` ile yerelde yazmak (macOS 26, kullanılabilirlik doğrulanacak).
8. **Erişilebilirlik turu:** VoiceOver ve Tam Klavye Erişimi gerçek pencerede; Artırılmış Kontrast.
9. **Sürükle-bırak:** dosyayı ekran üstüne bırakınca ekle; görevi markalar arası taşıma (yalıtım kuralına dikkat: taşıma yok, kopya yok).

## Dokunulmayanlar
Yayın, imzalama, güncelleme altyapısı, ödeme. (Kurucu: sonra.)

## Zamanlayıcı ve çentik (3 Eki, yapıldı)
Görev satırında oynat/durdur (çalışırken canlı süre), sağ tık menüsü, menü çubuğunda canlı süre (sayaç çalışırken kendiliğinden görünür), çentikli MacBook'ta
çentikten sarkan siyah "ada" (görev adı, süre, durdur). Çekirdek `startTimer/stopTimer/runningTimer` zaten vardı; sayaç uygulama kapansa da sürer.
Gerçek Dinamik Ada yalnız iPhone'dadır; çentik penceresi resmî API değil, AppKit paneli (çentiksiz ekranda gösterilmez). Çentiğin yanında gerçek görünümü
ve menü çubuğu etiketi bu makinede doğrulanamadı (yalnız panelin kendi penceresi yakalandı).

## Terminalden asistana geçiş (3 Eki, kurucu kararı)
Kurucu terminal mantığından vazgeçti; sağ panel artık Cursor tarzı **Asistan** (`AIChatPanel`): marka başına kalıcı sohbet, araç olayı kartları ("Görevleri okudu"),
öneri kartı ("2 görev önerdi · İncele" onay sayfasını açar), hazır sorular (Ne yapmalıyım? · Bu haftayı özetle · Gecikenleri toparla · Müşteriye e-posta taslağı ·
Eksik bilgileri bul), yazma alanı (↩ gönder). Motor `ChatEngine` olduğu gibi kullanılır: sağlayıcı izni marka bazlıdır (panel bağlı değilse "Yapay zekâyı bağla", izin
yoksa onaylı "izin ver" gösterir), yapay zekâ veri değiştirmez, önerir; öneriler onay sayfasına düşer.
"Görev ekle" yeni karta döndü (başlık, tür, tarih çipleri, öncelik) ve üstünde "Yapay zekâya sor: Ne yapmalıyım?" var; ⌘K paletinde de aynı komut.
**Doğrulanmayan:** gerçek bir yapay zekâ yanıtı (anahtar/Codex girişi yok; sohbet ekranı geliştirme örnek kancasıyla `MARKA_SOHBET_ORNEK=1` çizildi).
Terminal kodu (`TerminalPanel`, `TerminalSession`, yalıtım) çekirdekte ölü kod olarak duruyor; arayüzden kaldırıldı, silinmedi.
