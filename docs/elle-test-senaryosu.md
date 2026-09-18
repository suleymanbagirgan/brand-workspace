# Elle test senaryosu — 0.2.1 arayüzü (U9 denetim düzeltmeleriyle)

**Kim uygular:** Kurucu, teknik olmayan bir danışman gözüyle. **Süre:** 20-25 dakika.
**Kapsam:** 0.2.1 akışı — tek adımlı ilk açılış, Bugün, onay bandı ve onay sayfası (öneriler + klasördeki yeni dosyalar), terminal oturumunun marka geçişinde yaşaması, Akış, Yapılacaklar, Rapor, Ayarlar (2 sekme). AI hesabı gerekmez; terminal adımında JSON dosyasını elle yazarsın.
**Nasıl işaretlenir:** Her adımın sonuna ✓ (beklendiği gibi) / ✗ (farklı — ne gördüğünü bir cümleyle yaz) / ? (anlamadım) koy. "?" da kusurdur: metin ya da akış anlaşılmıyordur.

Ekran ve düğme adları koddaki metinlerle birebir aynıdır. Tırnak içindeki adı ekranda arayın. Adımlar henüz tıklanarak denenmedi (README "Bilinen sınırlar"); yalnız terminal oturumunun yaşaması ekran dışı bir pencerede kodla sınandı (`MARKA_TERMINAL_PROVA`). İlk elle uygulama bu senaryonun kendisidir.

---

## 0. Hazırlık (2 dk) — gerçek veriye dokunmadan

Terminal'den ayrı bir deneme veri alanıyla aç (gerçek kopyan açık kalabilir):

```sh
mkdir -p ~/Desktop/marka-test
MARKA_WORKSPACE=~/Desktop/marka-test/ws MARKA_FOLDERS=~/Desktop/marka-test/klasor \
  "dist/Marka Çalışma Alanı.app/Contents/MacOS/MarkaCalismaAlani"
```

> Deneme kopyası kendi tercihlerini ve kendi Keychain kaydını kullanır; gerçek kopyanın API anahtarı burada görünmez. Finder'dan çift tıklamak deneme kopyasını açmaz.

| # | Adım | Beklenen sonuç |
|---|---|---|
| 0.1 | Komutu çalıştır. | Pencerenin tamamında **ilk açılış**: "Marka Çalışma Alanı" başlığı, tek cümle, "İlk markanın adı" alanı ve "Başla". Başka adım yok. |
| 0.2 | Alana `Deneme Mobilya` yaz, Enter'a bas. | Pencere ana görünüme geçer: solda "Bugün", "Markalar" altında "Deneme Mobilya" (seçili), sağda marka ekranı ve **Akış** sekmesi. |

## 1. Marka ekranı ve Akış (4 dk)

| # | Adım | Beklenen sonuç |
|---|---|---|
| 1.1 | Marka ekranına bak. | Üstte marka adı; sağda "Terminal" ve "···". Altında "Akış · Yapılacaklar · Rapor" sekmeleri. Onay bandı yok. Akış boş: "Henüz bir şey yok" ve Claude'dan `oneriler/` klasörüne yazmasını isteyebileceğini, dosyayı sürükleyebileceğini söyleyen tek paragraf. |
| 1.2 | "Not ekle"ye bas. Başlık: `18 Eylül görüşmesi`, not: `40 sandalye için teklif istendi. Karar genel müdürde.` "Ekle". | Not alanı kapanır; Akış'ta "Bugün" altında "Not · 18 Eylül görüşmesi" satırı ve saat. "Not ekle" açıkken düğmenin adı "Vazgeç" olur; Esc de kapatır. Sürükle ipucu artık görünmez (yalnız boş durumda). |
| 1.3 | Masaüstünden bir PDF'i Akış'ın üstüne sürükle-bırak. | Sürüklerken kenar vurgulanır; bırakınca "Dosya" satırı çıkar. |
| 1.4 | Finder'da `~/Desktop/marka-test/klasor/Deneme Mobilya/` klasörüne herhangi bir dosya kopyala; birkaç saniye bekle. | Akış'ta **satır çıkmaz**; sekmelerin üstünde "1 onay bekliyor · İncele" bandı belirir, kenar çubuğunda markanın yanında "1". |
| 1.5 | "İncele". | Onay sayfası: "Onay bekliyor", altında tek cümle "Onayladıkların eklenir; Akış'tan geri alabilirsin." "Dosyalar" grubunda dosyanın klasöre göre yolu, işaretli. "Seçilenleri onayla (1)" → sayfa kapanır, bant kalkar, dosya Akış'ta "Dosya" satırı olur. |
| 1.6 | "Not" satırına tıkla. | Sağda ayrıntı paneli: üst satırda "Not · tarih" ve sağda küçük "Kapat"; başlık, metin; metnin hemen altında "Arşivle". |
| 1.7 | "Kapat"a bas; satırı yeniden aç, Esc'ye bas; yeniden aç, listenin boş yerine tıkla. | Üç yol da paneli kapatır. Çalışmayanı ✗ olarak not et. |

## 2. Terminal oturumu yaşar (5 dk) — **kurucunun asıl çalışma biçimi**

İkinci bir marka gerekir: kenar çubuğunun altındaki "+ Marka"ya bas; alanda yer tutucu "Marka adı — ↩", sağında "Ekle". `İkinci Marka` yaz, "Ekle" (ya da Enter). Sonra "Deneme Mobilya"yı seç.

| # | Adım | Beklenen sonuç |
|---|---|---|
| 2.1 | Başlıktaki "Terminal"e bas (ya da ⌘J). | Altta marka klasöründe açılmış bir kabuk; başlıkta "Terminal · Deneme Mobilya" ve "Yana al". "Terminal" düğmesi açıkken hafif gri zeminli (seçili). İlk satırda soluk "Codex için: …" ipucu olabilir. |
| 2.2 | Kabuğa yaz: `export DENEME=ayni-oturum` Enter; sonra `sleep 600` Enter (çalışan bir komut; Claude oturumunun yerine). | Komut çalışır, istem dönmez. |
| 2.3 | ⌘J ile terminali gizle; 5 saniye bekle; ⌘J ile yeniden aç. | **Aynı ekran**: önceki satırlar yerinde, `sleep` hâlâ sürüyor. Kabuk yeniden başlamadı. |
| 2.4 | "Yana al". | Terminal sağa geçer; aynı satırlar, `sleep` sürüyor. "Alta al" ile geri al: yine aynı. |
| 2.5 | Kenar çubuğunda "İkinci Marka"yı seç. | Terminal paneli "Terminal · İkinci Marka" olur ve **boş, yeni** bir kabuk açılır (her markanın kendi oturumu). |
| 2.6 | "Bugün"e (⌘0) geç, sonra "Deneme Mobilya"ya dön. | Deneme Mobilya terminalinde `sleep` hâlâ sürüyor. Ctrl-C ile durdur; `echo $DENEME` → `ayni-oturum`. |
| 2.7 | Ayarlar › Genel › "Marka yalıtımı" kutusunu kaldır; marka ekranına dön. | Kabuk yeniden başlamaz; terminal başlığında tek satır: "Bu oturum yalıtımlı başladı; ayar değişikliği kabuktan çıkınca açılan yeni oturumda geçerli." Kutuyu yeniden işaretle → satır kalkar. |
| 2.8 | Kabukta `exit` yaz. | Başlıkta "Kabuk kapandı." ve "Yeni oturum". "Yeni oturum" → temiz bir kabuk açılır. |
| 2.9 | Terminalde `sleep 600` başlat; uygulamadan çık (⌘Q). | Tek soru: "N terminalde çalışan oturum var; kapatılsın mı?" (İkinci Marka'nınki de sayılır). "Vazgeç" → uygulama açık kalır, oturum sürer. Yeniden ⌘Q → "Kapat" → uygulama kapanır. Uygulamayı 0'daki komutla yeniden aç. |
| 2.10 | İkinci Marka'da terminali aç; "···" › "Arşivle…" → "Arşivle". | Marka listeden kalkar; o markanın kabuğu sonlanır (Deneme Mobilya'nınki açıksa sürer). |

## 3. Terminalden öneri ve onay (4 dk)

| # | Adım | Beklenen sonuç |
|---|---|---|
| 3.1 | Deneme Mobilya terminalinde yapıştır ve Enter: `mkdir -p oneriler && printf '%s' '{"surum":1,"gorevler":[{"baslik":"Teklifi hazırla","sonTarih":"2026-09-25"},{"baslik":"Numune gönder"}],"kayitlar":[{"tur":"soz","baslik":"Cuma teklif gönderilecek"}]}' > oneriler/2026-09-18-deneme.json` | En çok birkaç saniye içinde "3 onay bekliyor · İncele" bandı; kenar çubuğunda "3". (Dosya reddedilirse "Öneri dosyası okunamadı" uyarısı nedenini söyler; mesajı not et.) |
| 3.2 | "İncele". | Onay sayfası: tek görünür cümle, dosya yolu ya da açıklama paragrafı **yok**. "Yapılacaklar" grubunda üç satır, hepsi işaretli; başlıklar düzeltilebilir, son tarih görünür. "Öncelik" yazmaz. Altta "Tümünü reddet…", "Vazgeç", birincil "Seçilenleri onayla (3)". |
| 3.3 | Sözün kutusunu kaldır; "Seçilenleri onayla (2)". | Sayfa kapanır; **bant "1 onay bekliyor" olarak kalır** (söz reddedilmedi, bekliyor). Akış'ta iki "Öneri onaylandı" satırı. |
| 3.4 | "İncele" → yalnız söz görünür. "Tümünü reddet…" → onay sorusu "1 öneri reddedilsin mi?" → "Tümünü reddet". | Bant kalkar; söz eklenmedi. |
| 3.5 | "Öneri onaylandı · Numune gönder" satırına tıkla. | Panelde "Yeni görev · Onaylandı", başlık, "Ne zaman onaylandı?", "Sonucu göster" ve hemen altında "Geri al". "Nereden geldi?" ya da "Ne önerildi?" satırı yok. |
| 3.6 | "Geri al". | Görev kaldırılır; satır Akış'tan kalkar, panelde "Bu öğe silinmiş ya da geri alınmış olabilir." yazar. |

## 4. Yapılacaklar (3 dk)

| # | Adım | Beklenen sonuç |
|---|---|---|
| 4.1 | "Yapılacaklar" sekmesi (⌘2). | Tek liste: "Teklifi hazırla · Görev · 25 Eyl". Üstte solda iki seçenek "Görev | Söz" (Görev seçili), yanında "Yeni görev — ↩" alanı. Boş sütunlarda "—" yok. Listenin altında açıklama cümlesi yok. |
| 4.2 | `Müşteriyi ara` yaz, Enter. Sonra "Söz"e bas, `Katalog gönderilecek` yaz, Enter. | İki satır eklenir: biri "Görev", biri "Söz". Seçim "Söz"de kalır. |
| 4.3 | "Müşteriyi ara" satırına tıkla; panelde başlığı değiştir, Enter. "Durum" menüsünden "Sürüyor". | Değişiklik anında kaydedilir; satırın tür sütunu "Görev · Sürüyor". Alanların üzerine gelince hafif zemin. Panelin altında "Sil…" ve "İptal et". |
| 4.4 | "Müşteriyi ara" satırındaki kutuya bas. | Satır 1,5 saniye üstü çizili kalır, sonra listeden çıkar. Akış'ta "Görev · Bitti" satırı. |
| 4.5 | "Katalog gönderilecek" satırını aç; panelde "Sil…" → "Silinsin mi?" → "Sil". | Satır ve panel gider. (Sağ tık menüsü artık yok; tek yer panel.) |

## 5. İş kaydı ve Rapor (4 dk)

| # | Adım | Beklenen sonuç |
|---|---|---|
| 5.1 | Kabukta yapıştır ve Enter: `printf '%s' '{"surum":1,"calismaKayitlari":[{"baslik":"Teklif hazırlandı","neIstendi":"40 sandalye teklifi","neYapildi":"Fiyat listesi hazırlandı"}]}' > oneriler/2026-09-18-is.json` → bant → "İncele" → "Seçilenleri onayla". | Onay sayfasında satırın altında "“Doğrulanmadı” olarak eklenir; doğrulamayı Akış'ta sen yaparsın." Akış'ta "İş kaydı · Teklif hazırlandı" satırı ve sağda soluk "Doğrulanmadı" — satırda düğme **yok**. |
| 5.2 | Satıra tıkla. | Panel: sorular ve hemen altında "Düzenle" ile birincil "Doğrula" (etkin değil) ve "Doğrulamak için en az bir dosya ya da görev bağlanmalı." |
| 5.3 | "Düzenle". | Düz satırlı düzenleyici (sistem formu değil): solda sorular ("Ne kararlaştırıldı?" dahil), sağda alanlar; "Görev" metin menüsü. "Hangi dosyalar kullanıldı?" altında 1.2'deki notu işaretle → "Kaydet". Panelde "Doğrula". |
| 5.4 | "Rapor" sekmesi (⌘3). | Başlık satırı tam genişlik: solda "Bu hafta · yalnız doğrulanmış iş kayıtlarından", sağ kenarda "···" ve tek birincil düğme **"Hazır, PDF al"**. Uyarılar tek satırda. Belgede "Taslak". |
| 5.5 | "Hazır, PDF al" → Masaüstüne kaydet. | PDF'te TASLAK filigranı yok. Belgedeki durum "Hazır · 1. sürüm"; birincil düğme artık "PDF". (Kaydetme panelinde "Vazgeç" dersen rapor taslak kalır.) |
| 5.6 | "···" menüsü; "Geçmiş"i aç. | Menüde yalnız "Düzenle" ve "E-posta taslağı…". "Geçmiş": "1. sürüm · Hazır", "PDF dışa aktarıldı"; varsa "Diğer raporlar". "Onayla" kelimesi rapor ekranında yok. |
| 5.7 | Bir maddeye tıkla. | Akış sekmesine geçilir ve dayanağı olan iş kaydı sağ panelde açılır. |

## 6. Bugün, arama, Bilgiler, Ayarlar (3 dk)

| # | Adım | Beklenen sonuç |
|---|---|---|
| 6.1 | Kenar çubuğunda "Bugün" (⌘0). | Dört bölüm: "Onay bekliyor" (sayı kenar çubuğuyla aynı), "Geciken", "Bu hafta yapılan", "Karar bekleniyor". Boş bölümde tek satır, hepsi aynı biçimde. |
| 6.2 | ⌘F, `teklif` yaz. | "Arama sonuçları · N": marka · tür · başlık. Satıra tıkla → marka açılır, kayıt sağ panelde. |
| 6.3 | Marka ekranında "···" → "Bilgiler ve AI izinleri…". | "Profil", "AI izinleri" (cümle: "Uygulama içindeki rapor özeti yalnız izin verdiğin sağlayıcıyı kullanır. Terminal bu izne bağlı değildir."), "Kişiler · Ekle", "Projeler · Ekle"; terminalden hedef/teklif/sözleşme/önemli tarih geldiyse salt okunur "Hedef, teklif ve tarihler". Profil satırının üzerine gelince hafif zemin; tıkla → yerinde düzenleme. Proje düzenleyicisinde alan adı "Amaç". |
| 6.4 | ⌘, (Ayarlar) › "Veri". | "Yedekler"de her satırda "Geri yükle…" üzerine gelmeden görünür; "İçe aktarım" metni "eski görev listesi" der (teknik ad yok). Genel › Codex metninde "belirteç" yok. |
| 6.5 | "Tanı bilgisini kopyala"; bir metin düzenleyiciye yapıştır. | Sürüm (0.2.1), macOS, kayıt sayıları, beta ölçümleri. Marka adı, not metni ya da dosya yolu **yok**. |
| 6.6 | Ayarlar › Veri › "Arşivlenmiş markalar": 2.10'da arşivlenen markada "Arşivden çıkar" (hep görünür). | Marka kenar çubuğuna geri gelir; verisi yerinde. |

## Bitiş

Uygulamadan çık. Deneme verisini silmek için `~/Desktop/marka-test` klasörünü çöpe at. ✗ ve ? işaretli adımları, ne gördüğünle birlikte bildir.
