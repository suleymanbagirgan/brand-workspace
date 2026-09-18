---
stepsCompleted: [validate-prerequisites, design-epics, create-stories, final-validation]
inputDocuments:
  - prds/prd-marka-calisma-alani-2026-09-17/prd.md
  - architecture/architecture-marka-calisma-alani-2026-09-17/ARCHITECTURE-SPINE.md
---

# Marka Çalışma Alanı - Epik Dağılımı

Her epik, derlenebilir ve kullanılabilir bir ürün dilimi olarak teslim edildi. Durum sütunundaki "Bitti" etiketi yalnızca testle veya canlı doğrulamayla kanıtlanan maddelere verildi.

## Epik A — Markalar, kaynaklar, görevler, Genel Bakış (FR-1…FR-6)

| Hikâye | Kabul | Durum / kanıt |
|---|---|---|
| A1 Marka ekleme, düzenleme, arşivleme | Boş ad ve aynı ad (TR harf duyarsız) reddedilir | Bitti — `MarkaTests` |
| A2 Kişiler, projeler, 7 tür marka kaydı | Kayıt kaynağa bağlanabilir; başka markanın kaynağı reddedilir | Bitti — `Store+Brands`, arayüz |
| A3 Kaynak ekleme (dosya, not, görüşme, talep, bağlantı) | İçerik adresli saklama; kaynak güncellemesi tetikleyiciyle reddedilir; FTS araması | Bitti — `KaynakTests` |
| A4 Görevler ve tek sayaç | Aynı anda tek sayaç (benzersiz indeks); görev bitince sayaç durur | Bitti — `GorevTests` |
| A5 joi-todo aktarımı | Kaynak salt okunur; tekrar çalıştırmada kopya yok; status esas alınır | Bitti — `AktarimTests` + gerçek veriyle kuru çalıştırma |
| A6 Genel Bakış | Sayılar SQL'den gelir, kayda açılır, AI metni içermez | Bitti — `DurumTests` |

## Epik B — Çalışma kaydı ve bilgi hafızası (FR-7…FR-11)

| Hikâye | Kabul | Durum / kanıt |
|---|---|---|
| B1 Yedi soruluk çalışma kaydı | Doğrulama için "ne yapıldı" dolu olmalı ve en az bir bağlantı gerekir; düzenleme taslağa düşürür | Bitti — `CalismaKaydiTests` |
| B2 AI önerisini uygulama ve geri alma | Kullanıcı sonradan düzenlediyse geri alma engellenir; çıktı silinmez, arşivlenir | Bitti — `OneriTests` |
| B3 Bilgi sayfası, sürüm, iddia | AI iddiası kaynaksız veya başka markadan olamaz; öneri onaysız güncel sayılmaz; önceki sürüme dönülebilir | Bitti — `BilgiTests` |
| B4 Çelişki/eskime işaretleri ve denetim | Sayfa durumu değişir, sağlık denetiminde görünür | Bitti — `BilgiTests` |
| B5 Kaynaktan derleme | Geçersiz sayfa önerisi reddedilir, geçerli olan öneri olarak girer | Doğrulama katmanı bitti (`AITests`); canlı model çağrısı test edilmedi |

## Epik C — AI Masası, sağlayıcılar, terminal (FR-12…FR-15)

| Hikâye | Kabul | Durum / kanıt |
|---|---|---|
| C1 Durum kartı ve sonraki adım kuralı | Kayıtlardan hesaplanır | Bitti — `DurumTests`, görsel denetim |
| C2 Marka kapsamlı sohbet ve araç kartları | Başka marka kimliği reddedilir; izinsiz sağlayıcıya oturum açılmaz | Bitti — `AITests` |
| C3 Anthropic Messages API | SSE akışı, araç döngüsü, fallbacks, maliyet, geçmiş | Kayıtlı SSE ile test edildi; canlı anahtar yok |
| C4 Codex App Server | Akış, dinamik araçlar, onay, devam ettirme | Canlı doğrulandı (`MarkaDogrula codex`) |
| C5 Terminal | PTY, marka klasörü, BAGLAM.md, klasörden içe alma | Derleniyor ve çiziliyor; etkileşimli kullanım ekran kilitli olduğu için elle denenmedi |

## Epik D — Raporlar (FR-16…FR-18)

| Hikâye | Kabul | Durum / kanıt |
|---|---|---|
| D1 Kaynaklı taslak | Yalnızca doğrulanmış kayıtlar girer; kaydı olmayan tamamlanmış işler uyarıya düşer | Bitti — `RaporTests` |
| D2 Düzenleme, sürüm, onay | Kaynaksız madde veya başka marka referansı kaydedilemez | Bitti — `RaporTests` |
| D3 PDF ve paylaşım geçmişi | %PDF üretilir; taslak filigranlıdır | Bitti — `RaporTests` |
| D4 AI özet | Yalnızca geçerli madde referanslı cümleler kalır | Doğrulama bitti; canlı çağrı yok |
| D5 Planlı gönderim | Plan taslak üretir, göndermez, durdurulabilir | Bitti — `RaporTests` |

## Epik E — İlk açılış, aktarım, yedekleme, beta paketi (FR-19)

| Hikâye | Kabul | Durum / kanıt |
|---|---|---|
| E1 İlk açılış akışı | Marka → ilk kaynak → Masa | Arayüzde var; elle tıklama testi yapılmadı |
| E2 Yedekleme ve geri yükleme | Geri yükleme öncesi yedek alınır; gelecek sürümden yedek reddedilir | Bitti — `YedekTests` |
| E3 Marka dışa aktarımı | JSON + orijinal dosyalar | Bitti — `YedekTests` |
| E4 .app paketi, simge, TR/EN | Ad-hoc imzalı paket; 687/687 çeviri | Bitti — `scripts/build-app.sh`, `scripts/l10n.py check` |
| E5 Beta ölçümleri ve değerlendirme planı | Yerel ölçüm, içerik içermez | Bitti — `AITests.betaOlcumleri`, `docs/degerlendirme-plani.md` |
