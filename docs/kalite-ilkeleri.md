# Kalite ilkeleri (geliştirme ekibi için tek kaynak)

Bu belge ajanların okuma listesidir; yetki ya da yapılandırma değiştirmez. Bağlayıcı kurallar `CLAUDE.md`'dedir.

## 1. Önce yazmadan çözebilir miyim
- Yazmadan önce depoda aynı işi yapan bir şey var mı bak. Varsa onu kullan, çoğaltma.
- Yeni bağımlılık son seçenektir. Önce platformun kendi kitaplıkları, sonra mevcut kod, en son dış paket.
- En küçük değişiklik kazanır: istenen davranışı veren en az satır, hedefli ekleme, kapsam dışına taşmama.

## 2. Sade yanıt
- Rapor, yaptığın değişikliği ve kanıtını söyler: dosya, satır, test adı, komut çıktısı.
- Kanıtı olmayan cümle yazma. Doğrulayamadığını "doğrulanamadı" diye ayır.
- Ölçülmemiş fayda ya da yapmadığımız bir şey için vaat yazma (`docs/bilinen-sinirlar.md`).

## 3. Tasarım dili token'ları
- Ekran kodu yazı, yarıçap ve simge boyutunu `Sources/MarkaApp/Design.swift` içindeki `Design.Font`,
  `Design.Radius` ve `Design.Icon` üzerinden alır. Sabit boyutlu `.font(.system(size:))` ve sayısal köşe yarıçapı yazılmaz.
- Boşluk ve renk de aynı yerden gelir. Yeni değer gerekiyorsa önce token eklenir, sonra kullanılır.
- Eşik tabanı `scripts/tasarim-esikleri.txt` dosyasındadır ve yalnız düşürülür. Ölçüm `scripts/tasarim-denetimi.py` ile alınır.
- Yeni ekranın açık ve koyu görünümü çizimle bakılır. Göz kararı denetim sayılmaz.

## 4. Kapı ve haritalar
- Bitti demeden önce `scripts/gelistir-kapisi.sh` bayraksız koşar ve `KAPI: GEÇTİ` vermelidir.
- Bozulamaz kuralların hangi testle korunduğu `docs/kural-test-haritasi.md` içindedir; yeni kural testsiz kalmaz.
- Asistan davranışı değişirse `docs/altin-istem.md` içindeki senaryolar koşar.
- Her yeni `L("…")` anahtarı için `scripts/l10n.py` denetimi temiz kalmalıdır.
