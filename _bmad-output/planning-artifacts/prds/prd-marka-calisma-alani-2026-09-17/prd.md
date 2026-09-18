---
title: Marka Çalışma Alanı
created: 2026-09-17
updated: 2026-09-17
status: final
---

# PRD: Marka Çalışma Alanı
*Geçici ad — onaylanacak.*

## 0. Belgenin Amacı
Bu PRD; ürün sahibi (danışman), geliştirme ajanları ve sonraki BMAD iş akışları (mimari, epikler) içindir. Sözlük (§3) terimleri bağlayıcıdır. Özellikler §4'te FR'lerle iç içe verilir. Tahmine dayanan her şey `[VARSAYIM]` etiketiyle işaretlidir ve §9'da toplanır. Mimari kararlar `architecture/.../ARCHITECTURE-SPINE.md` içindedir.

## 1. Vizyon
Birden fazla markaya danışmanlık yapan kişi, bir markaya döndüğünde neyin konuşulduğunu, neyin söz verildiğini, neyin yapıldığını ve sıradaki adımı hatırlamak için dağınık notlara, sohbet geçmişlerine ve e-postalara dağılır. Marka Çalışma Alanı bu bağlamı tek bir yerel Mac uygulamasında toplar.

Ürünün omurgası tek bir döngüdür: **Marka bağlamı → AI ile çalışma → doğrulanmış iş kaydı → güncel bilgi hafızası → müşteri raporu.** Her halka bir öncekinin doğrulanmış çıktısını kullanır. Sohbet geçmişi veya "tamamlandı" işareti tek başına müşteriye giden bir iddiaya dönüşmez.

Uygulama AI hesabı olmadan da çalışır: markalar, kaynaklar, görevler, süre, çalışma kaydı, bilgi sayfaları ve rapor taslağı yerel verilerden üretilir. AI; kullanıcının kendi Anthropic API anahtarı veya kendi Codex (ChatGPT) oturumu ile, yalnızca izin verilen markalar için devreye girer.

## 2. Hedef Kullanıcı

### 2.1 Yapılacak İşler (JTBD)
- 3–8 markaya aynı anda hizmet veren solo danışman olarak, bir markaya geçtiğimde 30 saniye içinde kaldığım yeri görmek istiyorum.
- AI ile iş yaparken hangi kaynağın kullanıldığını ve neyin değiştiğini görmek; yanlış markanın bilgisinin karışmadığından emin olmak istiyorum.
- Hafta sonunda müşteriye, her cümlesinin arkasında gerçek bir kayıt olan bir rapor göndermek; raporu sıfırdan yazmamak istiyorum.
- Müşteriye verdiğim sözleri ve müşteriden beklediğim kararları unutmamak istiyorum.

### 2.2 Kullanıcı Olmayanlar (v1)
- 10+ kişilik ajanslar (çok kullanıcılı yetki, ortak veri tabanı yok).
- Satış hunisi / fatura yönetimi arayanlar (CRM veya muhasebe değil).
- iOS / web kullanıcıları.

### 2.3 Ana Kullanıcı Yolculukları

- **UJ-1. Danışman sabah Örnek Yangın'a döner.**
  - **Persona + bağlam:** Dört markaya danışman; dün başka markayla uğraştı.
  - **Giriş:** Uygulama açılır; son seçili marka Örnek Yangın, sekme Masa.
  - **Yol:** Durum kartı: son temas (kaynak), açık sözler (teklif cuma), bekleyen müşteri kararları, taslak çıktılar, önerilen sonraki adım ("teklifi kontrol et") — hepsi kayıtlara tıklanabilir.
  - **Doruk:** Her satırın arkasındaki kaydı tek tıkla açar; hiçbir şey tahmin değildir, AI önerisi ayrı etiketlidir.
  - **Sonuç:** "Teklifi tamamla" yazarak AI oturumu başlatır.
  - **Kenar durum:** Markada hiç kayıt yoksa kart boş durum gösterir ve ilk kaynağı eklemeyi önerir.

- **UJ-2. Danışman AI ile teklifi tamamlar.**
  - **Giriş:** Masa, marka bağlamlı oturum; sağlayıcı markanın izin verdiği sağlayıcı.
  - **Yol:** Mesaj yazar → yanıt akışla gelir → araç kartları görünür (hangi kaynak okundu) → AI bir çıktı dosyası ve çalışma kaydı önerir → izin kartında "Onayla / Reddet".
  - **Doruk:** Onaylayınca çıktı dosyası markanın kaynaklarına "iş çıktısı" olarak, çalışma kaydı "taslak" olarak eklenir; kullanıcı kaydı doğrular.
  - **Sonuç:** Görev tamamlanır; bilgi hafızası için güncelleme önerisi oluşur.
  - **Kenar durum:** API hatası/iptal → mesaj "yarım kaldı" etiketiyle saklanır, hiçbir öneri uygulanmaz.

- **UJ-3. Danışman cuma haftalık raporu hazırlar.** Raporlar → "Haftalık taslak" → yalnızca doğrulanmış çalışma kayıtları, tamamlanan görevler, çıktılar, açık konular, bekleyen kararlar, süre ve sıradaki adımlar; her maddenin yanında kaynak bağlantısı. Düzenler, onaylar, PDF alır; paylaşım geçmişine işlenir.

- **UJ-4. Yeni kullanıcı ilk markasını kurar.** İlk açılış → kısa tanıtım → marka adı/sektör → (isteğe bağlı) joi-todo içe aktarımı → ilk kaynak → Masa.

- **UJ-5. Sabah genel bakış.** Genel Bakış: geciken görevler, bu hafta teslimler, son temas, yanıt bekleyen konular, bu hafta yapılanlar; her sayı listeye açılır.

## 3. Sözlük
- **Marka** — Danışmanlık verilen müşteri. Diğer tüm kayıtlar tam olarak bir markaya aittir (Tüm Markalar oturumu hariç).
- **Kaynak** — Değiştirilemeyen ham kayıt: dosya, not, görüşme notu, müşteri talebi, iş çıktısı, bağlantı. İçeriği ve özet değeri (sha256) oluşturulduktan sonra değişmez; yalnızca arşivlenebilir.
- **Marka Kaydı** — Markanın yapılandırılmış maddesi: hedef, talep, söz, bekleyen karar, teklif, sözleşme, önemli tarih. İsteğe bağlı olarak bir Kaynağa bağlanır.
- **Görev** — Yapılacak iş: proje, sorumlu, öncelik, son tarih, durum, harcanan süre.
- **Süre Kaydı** — Bir göreve harcanan zaman aralığı.
- **Çalışma Kaydı** — Önemli bir işin doğrulanabilir kaydı: ne istendi, hangi kaynaklar kullanıldı, ne yapıldı, hangi çıktılar üretildi, hangi karar alındı, kim onayladı, müşteriye ne bildirildi. Durumu: taslak → doğrulandı (veya geri çekildi). Raporlar yalnızca doğrulanmış olanları kullanır.
- **Bilgi Sayfası** — Markaya ait derlenmiş bilgi (kişi, hedef, proje, karar, tercih, süreç, genel). Sürümleri vardır.
- **Sayfa Sürümü** — Bilgi Sayfasının bir hâli; durumu önerildi / onaylandı / reddedildi.
- **İddia** — Sayfa Sürümündeki tek önemli bilgi cümlesi; bir Kaynağa (ve tarihine) bağlanır; durumu güncel / çelişkili / eskimiş olabilir.
- **Bilgi Kuralları** — Markaya özel, AI'ın bilgi sayfalarını nasıl derleyeceğini belirleyen açık metin.
- **AI Oturumu** — Tek bir Marka (veya açıkça seçilmiş Tüm Markalar) kapsamında, tek sağlayıcıyla yürütülen sohbet.
- **AI Önerisi** — AI'ın veri değiştirmek için ürettiği, kullanıcı onayı bekleyen değişiklik (görev, çalışma kaydı, bilgi sürümü, çıktı dosyası).
- **Denetim Olayı** — Her veri değişikliğinin önce/sonra hâli; AI değişikliklerinin geri alınmasını sağlar.
- **Rapor** — Bir marka ve dönem (haftalık/aylık) için taslak; **Rapor Sürümü**ne sahiptir; her **Rapor Maddesi** kayıt referansları taşır.
- **Paylaşım Kaydı** — Bir Rapor Sürümünün PDF olarak dışa aktarıldığı veya paylaşıldığı olay.
- **Marka Klasörü** — Terminal ve Codex'in çalıştığı, yalnızca o markanın bağlam anlık görüntüsünü içeren disk klasörü.

## 4. Özellikler

### 4.1 Markalar ve Marka Çalışma Alanı
**Açıklama:** Kullanıcı marka ekler/düzenler/arşivler. Profil: logo, kısa tanım, sektör, kişiler, projeler ve Marka Kayıtları. Teklif ve sözleşme dosyaları Kaynak olarak saklanır; AI özeti ayrı bir Bilgi Sayfası sürümüdür ve kaynağa bağlanır. Realizes UJ-1, UJ-4.

#### FR-1: Marka yönetimi
Kullanıcı sınırsız marka ekleyebilir, düzenleyebilir, arşivleyebilir.
**Sonuçlar:** Marka adı boş olamaz; aynı adla ikinci marka eklenemez (büyük/küçük harf duyarsız, Türkçe yerel); arşivlenen marka kenar çubuğundan kalkar ama verisi silinmez.

#### FR-2: Kişiler, projeler, Marka Kayıtları
Kullanıcı markaya kişi, proje ve yedi türde Marka Kaydı ekler.
**Sonuçlar:** Her Marka Kaydı türü, durumu ve (varsa) tarihi ile listelenir; söz ve bekleyen karar Masa ve Genel Bakış'ta görünür.

#### FR-3: Kaynak ekleme
Kullanıcı dosya (sürükle-bırak), not, görüşme notu, müşteri talebi ve bağlantı ekler.
**Sonuçlar:** Dosya içerik adresli olarak kopyalanır (orijinal korunur); sha256 saklanır; kaynak satırının içerik alanlarının güncellenmesi veri tabanı tetikleyicisiyle reddedilir; metin/markdown/PDF metni aranabilir.

### 4.2 Görevler ve Süre
#### FR-4: Görevler
Görev: marka, proje, sorumlu, öncelik (0–3), son tarih, durum (yapılacak, sürüyor, bekliyor, bitti, iptal), harcanan süre.
**Sonuçlar:** Aynı anda yalnızca bir süre sayacı çalışır (benzersiz kısmi indeks); görev bitince çalışan sayaç kapanır.

#### FR-5: Eski veriyi içe aktarma
Kullanıcı joi-todo verisini (tasks.json, events.jsonl, config.json) salt okunur olarak içe aktarır; projeleri markalara eşler.
**Sonuçlar:** Kaynak dosyalar değiştirilmez; aynı içe aktarım iki kez çalışınca kopya oluşmaz; `status` alanı `done` ile çelişirse `status` esas alınır ve rapora sayılır; süreler `stop` olaylarından, kalan fark tek "içe aktarılan toplam" kaydı olarak aktarılır.

### 4.3 Genel Bakış
#### FR-6: Bugün ilgilenilecekler
Tüm markalar için: geciken görevler, 7 gün içinde teslimler, son müşteri teması, yanıt bekleyen konular (açık talepler + bekleyen kararlar), bu hafta doğrulanan işler.
**Sonuçlar:** Her sayı, onu oluşturan kayıt listesini açar; sayılar yalnızca SQL sorgularından gelir; AI metni bu ekranda yer almaz.

### 4.4 Çalışma Kaydı
#### FR-7: Doğrulanmış çalışma kaydı
Kullanıcı veya AI (öneri olarak) Çalışma Kaydı oluşturur; yedi soru alanı; girdi kaynakları ve çıktı kaynakları bağlanır.
**Sonuçlar:** "Doğrulandı" durumuna geçmek için en az "ne yapıldı" dolu ve en az bir kaynak veya görev bağlı olmalı; doğrulayan ve zaman damgası kaydedilir; doğrulanmış kayıt düzenlenirse yeniden taslağa düşer; geri çekilen kayıt raporlara girmez.

#### FR-8: Geri alınabilir AI değişiklikleri
AI Önerisi uygulanınca Denetim Olayı yazılır; kullanıcı uygulanan öneriyi geri alabilir.
**Sonuçlar:** Geri alma, oluşturulan kaydı siler veya önceki hâline döndürür; geri alınan öneri "geri alındı" durumunu alır.

### 4.5 Bilgi Hafızası
#### FR-9: Üç katman
Ham Kaynaklar (değişmez), Bilgi Sayfaları + Sürümler + İddialar (derlenmiş), Bilgi Kuralları (açık metin, düzenlenebilir).
#### FR-10: Kaynaktan derleme
AI, yeni kaynak için kurallar + kaynak metni + mevcut sayfa dizinini kullanarak sayfa sürümü önerileri üretir.
**Sonuçlar:** AI sürümü "önerildi" olarak girer, onaysız güncel sayılmaz; her AI iddiası aynı markadan geçerli bir kaynak kimliği taşımak zorundadır, taşımayan iddia reddedilir; çelişki ve eskimiş işaretleri açıklamasıyla gösterilir.
#### FR-11: Düzeltme, onay, geri dönüş, arama
Kullanıcı sürümü düzenler (yeni sürüm), onaylar, reddeder, önceki sürüme döner; kaynaklar ve onaylı sayfalar FTS5 ile aranır.
**Sonuçlar:** Sohbet mesajı doğrudan iddia kaynağı olamaz; önce "not" kaynağı olarak kaydedilmelidir.

### 4.6 AI Masası
#### FR-12: Durum kartı
Seçili markanın son temas, açık sözler, bekleyen kararlar, taslak çıktılar ve kural tabanlı sonraki adım.
**Sonuçlar:** Kart AI olmadan hesaplanır ve her satır kayda bağlıdır.
#### FR-13: Marka bağlamlı sohbet
Akışlı yanıt; araç kullanımı, oluşturulan dosyalar, öneriler ve izin istekleri kart olarak görünür; oturum geçmişi saklanır.
**Sonuçlar:** Oturumun markası sonradan değişmez; araçlar yalnızca oturum markasının kayıtlarını döndürür (başka marka kimliği istenirse hata); Tüm Markalar kapsamı yalnızca açık onayla başlar; markanın izin vermediği sağlayıcıya istek gönderilmez.
#### FR-14: Sağlayıcılar
Anthropic Messages API (kullanıcı anahtarı, Keychain) ve Codex App Server (kullanıcının kurulu codex'i, kendi ChatGPT oturumu).
**Sonuçlar:** Her yanıt için token ve tahmini maliyet "tahmini" etiketiyle gösterilir; Codex onay istekleri kullanıcıya sorulur.
#### FR-15: Terminal
Gerçek PTY terminali; Marka Klasöründe açılır; `MARKA_ADI`, `MARKA_KLASORU` ortam değişkenleri.
**Sonuçlar:** Terminal veri tabanına yazmaz; klasöre bırakılan dosyalar kullanıcı onayıyla iş çıktısı kaynağı olur.

### 4.7 Raporlar
#### FR-16: Kaynaklı rapor taslağı
Haftalık/aylık; bölümler: yapılan işler, teslim edilen çıktılar, açık konular, müşteri kararı bekleyenler, harcanan süre, sıradaki adımlar.
**Sonuçlar:** "Yapılan işler" yalnızca doğrulanmış çalışma kayıtlarından gelir; doğrulanmış kaydı olmayan tamamlanan görevler ayrı uyarı listesinde gösterilir ve rapora girmez; her maddede en az bir referans; AI özet cümlesi yalnızca geçerli madde referansıyla kabul edilir.
#### FR-17: Düzenleme, onay, sürüm, PDF, paylaşım geçmişi
**Sonuçlar:** Her kaydetme yeni sürüm; onaylanmamış sürüm PDF'e "TASLAK" filigranıyla çıkar; PDF dışa aktarımı Paylaşım Kaydı yazar.
#### FR-18: Planlı gönderim (kontrollü)
Kullanıcı alıcı, sıklık, kapsam ayarlar; plan durdurulabilir; her çalıştırma kaydedilir.
**Sonuçlar (beta):** Plan zamanı gelince taslak üretir ve kullanıcıya bildirir; e-posta yalnızca kullanıcının Mail'de gönder tuşuna basmasıyla çıkar. Otomatik SMTP gönderimi yoktur. [NON-GOAL for MVP]

### 4.8 Güvenilirlik
#### FR-19: Yedekleme, geri yükleme, dışa aktarma
**Sonuçlar:** Günlük otomatik yedek (son 14); elle yedek; geri yükleme öncesi mevcut veri yedeklenir; şema sürümü uyumsuz yedek reddedilir; marka bazlı JSON + dosya dışa aktarımı.

## 5. Hedef Dışı
- CRM satış hunisi, faturalama, ekip yetkilendirmesi, bulut senkronizasyonu.
- Claude.ai tüketici aboneliğine bağlanma (Anthropic desteklemiyor).
- Terminalin bir "abonelik entegrasyonu" gibi sunulması.
- Otomatik müşteri e-postası (beta).

## 6. MVP Kapsamı
### 6.1 Kapsamda
A–E dilimleri (bkz. epics.md).
### 6.2 Kapsam dışı
- App Store sürümü (sandbox, terminal ve CLI ile çelişir).
- Otomatik güncelleme (Sparkle) — dağıtım kimliği gelince.
- Uygulama aboneliğine dahil AI kredisi — ayrı değerlendirme.

## 7. Başarı Ölçütleri
**Birincil**
- **SM-1**: İlk kurulum süresi — ilk açılıştan ilk markanın Masa'sında ≥1 kaynak görünene kadar geçen süre; hedef medyan < 10 dk. FR-1, FR-3.
- **SM-2**: Rapor hazırlama süresi — "taslak oluştur"dan "onayla"ya; hedef medyan < 15 dk. FR-16, FR-17.
**İkincil**
- **SM-3**: Kaynak hatası oranı — onaylı rapor maddelerinden kullanıcının "yanlış kaynak" işaretlediği oran; hedef < %5. FR-10, FR-16.
- **SM-4**: Tekrar kullanım — 2. haftada ≥3 gün uygulamayı açan beta kullanıcısı oranı. 
**Karşı ölçüt**
- **SM-C1**: AI önerisi kabul oranı — yüksek olması hedef değildir; kör onay riski. SM-2'yi dengeler.

## 8. Açık Sorular
1. Fiyat ve talep kanıtlanmadı; beta görüşmeleriyle ölçülecek.
2. Uygulama içi AI kredisi için Anthropic ticari koşulları ayrıca incelenmeli.
3. Codex App Server protokolü "experimental" — sürüm değişimlerine karşı uyumluluk testi gerekir.

## 9. Varsayımlar Dizini
- §2.1 — Hedef kullanıcı 3–8 marka yönetir. [VARSAYIM]
- §4.7 — Müşteriler PDF raporu kabul eder. [VARSAYIM]
- §7 — SM hedef değerleri beta öncesi tahmindir. [VARSAYIM]
