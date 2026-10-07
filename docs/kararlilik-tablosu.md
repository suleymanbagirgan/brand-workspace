# Kararlılık tablosu — 2026-10-05 (bu makinede ölçüldü)

Araç: `scripts/kararsiz-avci.sh N` (varsayılan N=10). `scripts/test.sh` N kez koşar, her `✔/✘ Test <ad>` satırını ayrıştırıp test başına geçme sayısı yazar. Kısmi sonuçlar `.build/kararsiz-avci/` altında saklanır; kesilirse aynı N ile yeniden çalıştırınca kaldığı koşudan sürer (`--sifirla` baştan başlatır).

Yalnız 20/20 dışında kalanlar listelenir:

| test adı | geçme/N | notlar |
|---|---|---|
| (yok) | | 290 testin tamamı 20/20 geçti |

**20 koşu · 290 test · 0 kararsız**

- Koşu başına 10–12 sn, toplam 217 sn (Apple Silicon, tek makine, aynı anda başka derleme yok).
- 20/20 yalnızca "bu makinede 20 koşuda geçti" demektir; kararlılık iddiası değildir. Yük altında (CI, paralel derleme) ya da yavaş makinede zaman sınırlı testler (YogunVeri) farklı davranabilir; bu ölçülmedi.
- Sınır: ayrıştırıcı kalma satırlarını (`✘ Test … failed`) tanır ama gerçek bir kalan testle bu çıktı biçimi bu çalışmada sınanmadı; test adları suite'ler arasında tekrarlanmıyor (kontrol edildi), tekrarlanırsa sayılar birleşir.
- Bilinen geçmiş: öneri geri alma testindeki `at > decidedAt` kararsızlığı `>=` ile daha önce düzeltilmişti; bu koşularda yeniden görülmedi.
