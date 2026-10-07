# Tasarım geliştirme: ikinci tur, 20 tespit (2026-10-04)

Kaynak: çizim aracıyla üretilen Görevler, Finans, Dosyalar, Marka Bilgileri, Rapor ve Onay ekranları (açık/koyu). Çizim aracı açılır menü, bağlantı, onay kutusu ve arama alanını çizemez; o parçalar gerçek pencerede ayrıca denetlenmeli.

## Yapıldı (8)
1. Finans özet kutuları sol yığılıydı (sağda boş) → `TileGrid`: pencereye göre en çok 4 eşit sütun, dar alanda sarılır (asistan paneli açıkken ezilmez)
2. Özet ve Finans kutuları farklı mantıkla dizilmişti → ikisi de aynı `TileGrid`
3. Marka Bilgileri üstteki iki kart sabit genişlikteydi, sağda boşluk → eşit iki sütun
4. "Bağlam doluluğu" tamamlanınca da marka rengindeydi → 8/8 olunca yeşil (tamam sinyali)
5. Rapor hazırlık listesinde "Özet'te doğrula" siyah düz metindi → yalnız uyarı satırlarında vurgu rengi ("senden bir şey bekleniyor")
6. Kenar çubuğunda Stüdyo simgesi marka avatarlarıyla hizasızdı → 30 pt yuvarlak kare simge, seçiliyken vurgu rengi
7. Görevler: "Müşteri yanıtı bekleyen" şeridi ile ilk grup arası ~80 pt boşluk → grup üst boşluğu 22→16, şerit alt boşluğu azaltıldı
8. Bugün satırı vurgusu (önceki tur) ve Stüdyo satırı üstüne gelince zemin (önceki tur) korundu

## Bilerek yapılmadı
- Tüm metin düğmelerine vurgu rengi: `TextButtonStyle` yorumuna göre vurgu yalnız birincil düğme, sayı ve seçili öğe içindir (tek vurgu ilkesi). "Düzenle", "Seçimi kaldır" gibi sakin eylemler siyah kalır.
- Onay sayfasındaki "Son tarih · —": bu bir boş değer değil, tarih seçme denetimi.

## Bekliyor (12)
9. Özet kahraman kartı marka adını tekrar ediyor (araç çubuğunda da var)
10. Bugün'de "Ara (⌘F)" kutusu başlıkla hizasız
11. Bugün'de "Onay bekliyor" listesi aynı sayıyı veren kutucukla yinelenir
12. Stüdyo listelerinde klavye gezintisi ve odak halkası denetlenmedi
13. 11 pt yardımcı metinlerin kontrastı (özellikle koyu mod) ölçülmedi
14. Bugün ve Özet satırlarında üzerine gelince zemin yok (Stüdyo'da var)
15. Dosyalar galerisinde bütün kartlar aynı simge/renkte; tür ayrımı yok
16. Her sekmede 34 pt sayfa başlığı ~120 pt dikey yer tutuyor; kompakt başlık düşünülmeli
17. Finans'ta tahsil edilen satırların başlığı soluk (kontrast), yalnız durum soluk olmalı
18. Onay sayfasında altbilgi eylemleri ("Tümünü reddet…") yıkıcı olduğu hâlde vurgusuz
19. Demo veride dosya adlarında Türkçe karakter eksik ("Musteri Referanslari"): demo verisi düzeltilmeli
20. Gerçek pencerede: asistan paneli malzemesi ve araç çubuğu taşması (ekran gerekir)
