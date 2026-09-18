# cli-todo-for-agentic: README ile kod karşılaştırması ve aktarım yöntemi

İncelenen sürüm: `suleymanbagirgan/cli-todo-for-agentic`, `main` dalı, son commit `d224ce4`. Depo yalnızca okundu, hiçbir değişiklik yapılmadı.
Gerçek veri: `~/Library/Mobile Documents/com~apple~CloudDocs/joi-todo/`. Bu klasör de yalnızca okundu; ölçümler 17 Eylül 2026 tarihli.

## 1. Kodda gerçekten bulunan özellikler

| Özellik | Kanıt | Durum |
|---|---|---|
| Görev ekleme ve düzenleme, `+proje !! @tarih` sözdizimi, TR tarihler (`@bugün`, `@yarın`) | `src/parse.js` | Var |
| Kategori → proje hiyerarşisi, kategori başına kod (`BP-12`) | `src/config.js`, `store.js:nextCode` | Var |
| Durumlar READY / ACTIVE / HOLD / COMPLETE | `store.js:STATUS`, `setStatus` | Var |
| Görev başına sayaç (start/hold/stop), sürenin `timeSpent` alanına eklenmesi | `src/timer.js` | Var |
| 12 saati geçen sayacın otomatik HOLD'a alınması | `timer.js:reconcileStaleActive` | Var; yalnızca uygulama açılınca çalışıyor |
| Atomik yazma (tmp + rename) ve süreçler arası kilit | `src/io.js` | Var |
| Olay günlüğü (`events.jsonl`) | `store.js:logEventUnlocked` | Var |
| Geri alma (`u`, `todo undo`) | `store.js:undoLast` | Kısmi, aşağıya bakın |
| Tam ekran TUI, alt-screen | `bin/todo.js:85`, `src/App.js` | Var |
| Günlük manifesto, kişisel dosyayı güvenli yükleme | `src/manifestos.js`, `App.js:12-17` | Var |
| `list`, `top`, `stats`, `time`, `projects`, `now`, `path`, `clear` komutları | `bin/todo.js` switch | Var |
| `todo agent`: Claude CLI'yı `claude -p` ile çağırma | `bin/todo.js:426-460` | Var |
| iCloud eşitlemesi (symlink) | `bin/todo.js:385-424` | Var |

## 2. README'de olup kodda farklı olanlar

1. **"Data isn't the source of truth; the events are."** Bu doğru değil. Asıl doğruluk kaynağı `tasks.json`. Olay günlüğü yalnızca geri alma, istatistik ve süre raporu için okunuyor. Görev listesi olaylardan yeniden kurulmuyor.
2. **Geri alma "her mutasyonu" kapsamıyor.** `undoLast` yalnızca `add`, `remove`, `toggle`, `clear` ve `edit` olaylarını geri alıyor. Son olay `start`, `stop` veya `status` ise "geri alınamıyor" hatası dönüyor. Sayaç kullanıldıktan sonra `u` tuşu çoğu zaman çalışmıyor.
3. **"Virtualized scroll":** `ink-scroll-view` kullanılıyor, ancak `App.js:525` tüm satırları üretip kaydırma bileşenine veriyor. Gerçek bir sanallaştırma (yalnızca görünen satırları üretme) kodda doğrulanamadı.
4. **Test yok.** `package.json` içindeki `test` betiği bilerek hata veriyor.
5. **Tutarlılık:** Gerçek veride 12 görevde `done` ve `status` alanları çelişiyor (ör. `done:false`, `status:"COMPLETE"`). Kod iki alanı ayrı yollarla güncelliyor (`toggleTask` ile `setStatus`). Geri alma yalnızca birini düzelttiğinde tutarsızlık kalıyor.
6. **Sayaç güvenliği:** Gerçek veride tek bir `personal` görevinde 284.676 sn (yaklaşık 79 saat) süre var. Toplam sürenin tamamı bu görevden geliyor. 12 saat koruması uygulama kapalıyken işlemediği için unutulan sayaç süreye yazılmış.

## 3. Gerçek verinin durumu (ölçüm)

- Toplam 761 görev: 731 COMPLETE, 27 READY, 3 HOLD. Olay satırı sayısı 1.683, bozuk satır yok.
- Projeler: gerçek veride çok sayıda proje kodu (müşteri adları bu belgeden çıkarıldı).
- `nfe` ile `atlas` büyük olasılıkla aynı markanın yazım farkı. Kesin karar kullanıcıya ait.
- Marka projelerinde (BP kategorisi) kayıtlı süre çok az. Süre verisinin büyük kısmı güvenilir değil (bkz. madde 6).

## 4. Aktarım yöntemi (uygulandı)

`Sources/MarkaCore/Import/JoiTodoImporter.swift`. Arayüzden iki yerden açılır: *Ayarlar › İçe aktarım* ve ilk açılış ekranı.

- **Salt okunur:** `tasks.json`, `events.jsonl` ve `config.json` yalnızca okunur. Aktarım sırasında bu üç dosyanın bir kopyası uygulama veri klasörüne (`İçe aktarımlar/`) izlenebilirlik için alınır.
- **Eşleme kullanıcıda:** Her proje için hedef marka adı girilir. Boş bırakılan proje aktarılmaz. Aynı adı birden fazla projeye yazmak projeleri birleştirir. BP kategorisindeki projeler marka olarak önerilir; `nfe` gibi önek benzerlikleri aynı markaya önerilir.
- **Tekrarlanabilir:** Her görev `joi:<id>:<oluşturma zamanı>` anahtarıyla saklanır. Aktarım ikinci kez çalışınca yeni kayıt oluşturmaz.
- **Durum:** `status` alanı `done` alanından yeni olduğu için çelişkide `status` esas alınır. Eşleme şöyle: COMPLETE → Bitti, ACTIVE → Sürüyor, HOLD → Bekliyor, READY → Yapılacak.
- **Tamamlanma tarihi:** `doneAt`, yoksa olay günlüğündeki son tamamlama olayı, o da yoksa oluşturma tarihi kullanılır (tahmin olarak sayılır ve raporlanır).
- **Süre:** `stop` olaylarının her biri ayrı süre kaydı olur. `timeSpent` bunlardan 60 sn'den fazla büyükse fark tek bir "İçe aktarılan toplam süre (ayrıntı yok)" kaydı olarak eklenir. 12 saati aşan görev süreleri önizlemede uyarı olarak gösterilir.
- **Gerçek veriyle kuru çalıştırma (geçici çalışma alanına):** Önerilen eşlemeyle 4 marka ve 348 görev aktarıldı. İkinci çalıştırmada 0 görev aktarıldı, 348 görev atlandı. `tasks.json` bayt bayt aynı kaldı. Komut: `swift run MarkaDogrula joi "<joi-todo klasörü>"`.

**Aktarılmayanlar:** manifestolar, kategori misyonları (`missions`) ve iCloud symlink ayarı. Görev kodları (`BP-12`) görev notuna ve `legacyCode` alanına yazılır.
