---
description: Otomatik geliştirme turu: ürün yöneticisi sprint seçer → tasarım lideri şartname yazar → arayüz/kodlama ekibi uygular → kalite kapısı doğrular. Konu verilmezse bekleyen işlerden seçilir.
argument-hint: "[konu veya madde numarası]"
---

Bir otomatik geliştirme turu çalıştır. Konu: $ARGUMENTS (boşsa ürün yöneticisi seçer).

**Önemli:** Proje ajanları bu oturuma yüklü olmayabilir. O durumda her ekip üyesi için `general-purpose` ajan aç ve göreve "önce `.claude/agents/<ad>.md` dosyasını oku ve oradaki rolü, kuralları, yasakları uygula" yaz. `model` alanını dosyadaki ile aynı ver.

## Döngü
1. **Ürün yöneticisi** (`urun-yoneticisi`): sprint özetini üret (en çok 3 madde, ölçülebilir kabul ölçütü, kullanıcı kararı bekleyenler ayrı). Kullanıcı kararı gereken maddeye **başlama**.
2. **Tasarım lideri** (`tasarim-lideri`): yalnız arayüz içeren maddeler için şartname. Kanıtı çizimle topla.
3. **Uygulama:** arayüz → `arayuz-gelistirici`; çekirdek/AI/veri → `swift-gelistirici`; testler → `test-muhendisi`. Aynı dosyaya dokunan işleri **paralel çalıştırma**; ayrık dosyalıysa paralel olabilir.
4. **Denetim** (ilgili olanlar): `arayuz-denetci` (ekran), `marka-yalitim-muhafizi` (marka/tenant), `veri-gizliligi-denetcisi` (veri çıkışı), `ai-saglayici-uzmani` (AI), `surum-muhendisi` (paket).
5. **Kalite kapısı** (`kalite-kapisi`; tek komut: `scripts/gelistir-kapisi.sh`, bayraksız): `KAPI: GEÇTİ` olmadan tur bitmez. `KALDI` ise bulguyu ilgili uygulayıcıya geri ver; en çok **2** onarım turu, sonra dur ve kullanıcıya raporla.
6. **Rapor:** ne yapıldı (kanıtla), ne doğrulanamadı, ne kullanıcı kararı bekliyor. Yeni dosyalar için commit **önerilir**, atılmaz.

## Her delegasyona aynen yaz (alt ajanlar CLAUDE.md'yi okumayabilir)
- Gerçek veri alanına (`~/Library/Application Support/MarkaCalismaAlani`) dokunma; uygulama başlatırken **her zaman** `MARKA_WORKSPACE` ve `MARKA_FOLDERS` geçici klasör ver.
- Uygulamayı `open` ile başlatma; ekran görüntüsü yalnız uygulamanın kendi penceresi, tam ekran yok. Başlattığın süreç kalmasın.
- Commit, push, imzalama, yayın, ödeme, harcama yok. API anahtarı arama/Keychain tarama yok.
- Bozulamaz kurallar: marka yalıtımı · ham kaynak değişmez · **AI veri değiştirmez, öneri üretir, kullanıcı onaylar** · her yazma denetim izi · içerik yalnız izinli sağlayıcıya · yapmadığımızı vaat etmeyiz.
- Doğrulamadığını "çalışıyor" diye yazma; ekran kilitli ya da anahtar yoksa "doğrulanamadı" de.

## Durma koşulları
Kullanıcı kararı gerekiyorsa · 2 onarım turundan sonra kapı hâlâ KALDI ise · bozulamaz kural ihlali şüphesi · gerçek veri ihtiyacı. Bunlarda dur ve sor.
