# Tasarım geliştirme: 20 tespit (2026-10-04)

Kaynak: çizim aracıyla üretilen açık ve koyu ekranlar (Bugün, Özet, Stüdyo sekmeleri) ve önceki gerçek pencere yakalamaları. Çizim aracı açılır menü, bağlantı ve onay kutusunu çizemez; o parçalar gerçek pencerede ayrıca denetlenmeli.

## Yapıldı (13)
1. Özet kutucukları satırı doldurmuyordu (sağda boşluk) → dört eşit sütun, Bugün ile aynı düzen
2. Stüdyo kutucuğu "Çalışan önerisi bekliyor" kırpılmaya yakındı → "Bekleyen öneri"
3. Stüdyo içeriği Özet'ten dar kalıyordu (980) → 1100
4. Yetenek satırında sağda teknik ad (`seo-denetimi`) gürültüydü → yalnız ipucu olarak kaldı
5. Ekip satırı kalabalıktı ve "Kıdemli" iki kez geçiyordu → "unvan · bölüm · bağlı" tek satır, kıdem ayrı hap
6. Özet'te "Akış" (20 pt) ile "Sıradaki teslimler" (12 pt) başlıkları tutarsızdı → ikisi 15 pt yarı kalın
7. Bugün satırlarında marka adı 11 pt soluk metindi → küçük marka avatarı + 12 pt orta kalınlık
8. Bugün'de "İncele" sade metindi (tıklanabilir görünmüyordu) → vurgu rengi
9. Şirket formu çok uzundu → Ad/Slogan ve Web/Kuruluş yan yana (iki sütun)
10. Organizasyon şemasında yalnız dikey çizgi vardı → her düğüme yatay dirsek çizgisi
11. Araç çubuğu kalabalık ve sağda `»` taşma düğmesi görünüyordu → "Yerel" etiketi yalnız kilit simgesi (ipucu kaldı)
12. Görev satırında atanan rozeti ("C") belirsizdi → ipucu ve VoiceOver etiketi ("Sorumlu: …")
13. Stüdyo satırları tıklanabilir olduğunu belli etmiyordu → üzerine gelince hafif zemin

## Bekliyor (7)
14. Özet kahraman kartı marka adını tekrar ediyor (araç çubuğunda da var): kart sadeleşebilir
15. Bugün'de "Ara (⌘F)" kutusu sağda kopuk duruyor: başlıkla aynı hizaya alınabilir
16. Stüdyo listelerinde klavyeyle gezinme ve odak halkası denetlenmedi
17. Bugün'deki "Onay bekliyor" listesi, aynı sayıyı veren kutucukla yinelenen bilgi
18. Gerçek pencerede: asistan paneli malzemesi ve araç çubuğu taşması (ekran gerekir)
19. 11 pt yardımcı metinlerin kontrastı (özellikle koyu mod) ölçülmedi
20. Üzerine gelince zemin yalnız Stüdyo'da var; Bugün ve Özet satırlarına da yayılmalı
