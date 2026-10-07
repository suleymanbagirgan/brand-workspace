#!/bin/zsh
# Tek komut kalite kapısı (Camp H1-11). Adımlar sırayla koşar; biri KALDI olsa da kalanlar koşar (tam tablo).
#   1 test · 2 paket · 3 çeviri · 4 MAS taraması · 5 erişilebilirlik taraması · 6 sızıntı grep'i · 7 artık süreç
# Kullanım: scripts/gelistir-kapisi.sh [--hizli]     (--hizli: paketi atlar; test+çeviri+taramalar+sızıntı+süreç)
# Çıkış kodu: 0 = KAPI: GEÇTİ, 1 = KAPI: KALDI. Düzeltme yapmaz, süreç öldürmez, commit etmez.
# Ayrıntı günlükleri: $KAPI_GUNLUK (varsayılan: geçici klasör). Hızlı kipte paket kanıtı yoktur: bitti sayılmaz.
cd "$(dirname "$0")/.." || exit 1

HIZLI=0
for a in "$@"; do
  case "$a" in
    --hizli) HIZLI=1 ;;
    *) echo "Bilinmeyen bayrak: $a (yalnız --hizli)"; exit 2 ;;
  esac
done

GUNLUK="${KAPI_GUNLUK:-$(mktemp -d "${TMPDIR:-/tmp}/gelistir-kapisi.XXXXXX")}"
mkdir -p "$GUNLUK"
KALAN=()
SATIRLAR=()

kayit() {  # ad durum ozet
  SATIRLAR+=("$(printf '%-16s · %-5s · %s' "$1" "$2" "$3")")
  [ "$2" = "KALDI" ] && KALAN+=("$1")
}

# Koşu öncesi süreç kümesi (kullanıcının kendi uygulaması olabilir; farkı "bizim koşunun bıraktığı" sayılır)
# Yalnız uygulama/doğrulama ikilisinin kendisi (komut satırı başında); derleyici ve test yardımcıları sayılmaz.
SUREC_DESEN='^[^ ]*(MacOS/MarkaCalismaAlani|/MarkaApp|/MarkaDogrula)( |$)'
ONCE="$(pgrep -f "$SUREC_DESEN" 2>/dev/null | sort)"

[ "$HIZLI" = 1 ] && echo "HIZLI KİP (paket atlandı)"

# 1) test
scripts/test.sh > "$GUNLUK/test.log" 2>&1; kod=$?
gecen=$(grep -oE "Test run with [0-9]+ tests?" "$GUNLUK/test.log" | tail -1 | grep -oE "[0-9]+")
basarisiz=$(grep -c "✘" "$GUNLUK/test.log")
if [ $kod -eq 0 ] && [ "$basarisiz" -eq 0 ] && [ -n "$gecen" ]; then
  kayit "test" GEÇTİ "${gecen} test, 0 başarısız"
else
  kayit "test" KALDI "çıkış $kod, ✘ satırı $basarisiz, ${gecen:-?} test (günlük: $GUNLUK/test.log)"
fi

# 2) paket
if [ "$HIZLI" = 1 ]; then
  kayit "paket" ATLANDI "--hizli"
else
  scripts/build-app.sh > "$GUNLUK/paket.log" 2>&1; kod=$?
  if [ $kod -eq 0 ]; then kayit "paket" GEÇTİ "build-app çıkış 0"
  else kayit "paket" KALDI "çıkış $kod (günlük: $GUNLUK/paket.log)"; fi
fi

# 3) çeviri
python3 scripts/l10n.py check > "$GUNLUK/l10n.log" 2>&1; kod=$?
l10n=$(head -1 "$GUNLUK/l10n.log")
toplam=0
for alan in "eksik" "fazla" "biçim uyumsuz" "çoğul eksik" "çoğul hatalı"; do
  n=$(echo "$l10n" | grep -oE "${alan}: [0-9]+" | head -1 | grep -oE "[0-9]+$")
  if [ -z "$n" ]; then toplam=-1000; else toplam=$((toplam + n)); fi
done
if [ $kod -eq 0 ] && [ $toplam -eq 0 ]; then kayit "çeviri" GEÇTİ "eksik/fazla/biçim/çoğul = 0"
else kayit "çeviri" KALDI "çıkış $kod, sapma toplamı $toplam (günlük: $GUNLUK/l10n.log)"; fi

# 4) MAS taraması
scripts/mas-tarama.sh > "$GUNLUK/mas.log" 2>&1; kod=$?
if [ $kod -eq 0 ]; then kayit "mas-tarama" GEÇTİ "yasak kalıp 0, MAS derlemesi tamam"
else kayit "mas-tarama" KALDI "çıkış $kod (günlük: $GUNLUK/mas.log)"; fi

# 5) erişilebilirlik taraması (betik hep 0 çıkar; karar BULGU TOPLAMI'ndan)
scripts/erisilebilirlik-tarama.sh > "$GUNLUK/a11y.log" 2>&1; kod=$?
bulgu=$(grep -E "^BULGU TOPLAMI" "$GUNLUK/a11y.log" | grep -oE "[0-9]+" | tail -1)
if [ $kod -eq 0 ] && [ "$bulgu" = "0" ]; then kayit "erişilebilirlik" GEÇTİ "bulgu toplamı 0"
else kayit "erişilebilirlik" KALDI "bulgu toplamı ${bulgu:-okunamadı}, çıkış $kod (günlük: $GUNLUK/a11y.log)"; fi

# 6) sızıntı grep'i — herkese açık depo. Desen kalite-kapisi.md 6. adımın sıkılaştırılmış hâli: gerçek sızıntı biçimleri
#    (uzun anahtar, e-posta, kişisel yol); `apiKey:` gibi kod parametre adları ve uydurma yollar (/Users/x, /Users/ornek) sayılmaz.
#    Gerçek müşteri adı buraya YAZILMAZ (ad listesi depoya girer); ad denetimi kullanıcıdadır.
source scripts/sizinti-desenleri.sh   # SIZINTI_DESEN + SAHTE_YOL: tek kaynak (pre-commit kancası da bunu kullanır)
bulgular=$(grep -rniIE "$SIZINTI_DESEN" Sources Tests docs scripts README.md CLAUDE.md .claude 2>/dev/null \
  | grep -v "^scripts/gelistir-kapisi.sh:" | grep -v "^scripts/sizinti-desenleri.sh:" | grep -vniE "$SAHTE_YOL")
if [ -z "$bulgular" ]; then kayit "sızıntı" GEÇTİ "bulgu 0"
else
  n=$(echo "$bulgular" | wc -l | tr -d ' ')
  echo "$bulgular" | cut -c1-120 | head -10 > "$GUNLUK/sizinti.log"
  kayit "sızıntı" KALDI "bulgu $n (dosya:satır: $GUNLUK/sizinti.log)"
fi

# 6b) tasarım denetimi (E-15): ihlal toplamı scripts/tasarim-esikleri.txt tabanını aşarsa KALDI; eşit/altı GEÇTİ.
#     TASARIM_YOL: yalnız deneme için taranacak klasörü değiştirir (varsayılan Sources/MarkaApp).
t0=$SECONDS
taban=$(grep -E '^toplam:[[:space:]]*[0-9]+' scripts/tasarim-esikleri.txt 2>/dev/null | head -1 | grep -oE '[0-9]+$')
if [ -z "$taban" ]; then
  kayit "tasarım" KALDI "taban okunamadı (scripts/tasarim-esikleri.txt 'toplam: N' satırı)"
else
  python3 scripts/tasarim-denetimi.py --esik "$taban" "${TASARIM_YOL:-Sources/MarkaApp}" > "$GUNLUK/tasarim.log" 2>&1; kod=$?
  olcum=$(grep -E '^toplam:' "$GUNLUK/tasarim.log" | grep -oE '[0-9]+$')
  if [ $kod -eq 0 ]; then kayit "tasarım" GEÇTİ "ihlal ${olcum:-?} ≤ taban $taban ($((SECONDS - t0)) sn)"
  else kayit "tasarım" KALDI "ihlal ${olcum:-?} > taban $taban, çıkış $kod (ayrıntı: python3 scripts/tasarim-denetimi.py --ayrinti; günlük: $GUNLUK/tasarim.log)"; fi
fi

# 6c) yolculuklar (E-26): kayıtlı kullanıcı yolculukları (Tests/Fixtures/yolculuk) AYRI adımda koşar; bozulan yolculuk ve adım adıyla KALDI.
#     Aynı testler adım 1'de de koşar; burada yalnız adıyla görünür olması ve kırılan adımı yazması için süzgeçle yeniden koşulur.
t0=$SECONDS
scripts/test.sh --filter YolculukTests > "$GUNLUK/yolculuk.log" 2>&1; kod=$?
gecen=$(grep -oE "Test run with [0-9]+ tests?" "$GUNLUK/yolculuk.log" | tail -1 | grep -oE "[0-9]+")
basarisiz=$(grep -c "✘" "$GUNLUK/yolculuk.log")
if [ $kod -eq 0 ] && [ "$basarisiz" -eq 0 ] && [ -n "$gecen" ]; then
  kayit "yolculuk" GEÇTİ "${gecen} test, 0 başarısız ($((SECONDS - t0)) sn)"
else
  kirik=$(grep -oE "[a-z0-9-]+: KALDI, adım [0-9]+ «[^»]*»" "$GUNLUK/yolculuk.log" | head -1)
  kayit "yolculuk" KALDI "${kirik:-çıkış $kod, ✘ satırı $basarisiz, ${gecen:-?} test} (günlük: $GUNLUK/yolculuk.log)"
fi

# 7) artık süreç — öldürme yok, yalnız rapor. Koşu boyunca yeni beliren süreç = KALDI.
sleep 2  # çıkmakta olan süreçler için kısa bekleme
SONRA="$(pgrep -f "$SUREC_DESEN" 2>/dev/null | sort)"
YENI="$(comm -13 <(echo "$ONCE") <(echo "$SONRA") | grep -v '^$')"
if [ -z "$YENI" ]; then
  say=$(echo "$SONRA" | grep -vc '^$')
  kayit "artık süreç" GEÇTİ "yeni 0 (koşu öncesinden var olan: $say, kullanıcının kendi uygulaması olabilir)"
else
  ayrinti=$(for p in ${(f)YENI}; do echo -n "PID $p $(ps -o lstart= -p $p 2>/dev/null | tr -s ' ') ; "; done)
  kayit "artık süreç" KALDI "yeni $(echo "$YENI" | wc -l | tr -d ' ') (öldürülmedi): $ayrinti"
fi

echo
echo "ADIM             · DURUM · ÖZET"
for s in "${SATIRLAR[@]}"; do echo "$s"; done
echo
[ "$HIZLI" = 1 ] && echo "HIZLI KİP (paket atlandı)"
if [ ${#KALAN[@]} -eq 0 ]; then
  echo "KAPI: GEÇTİ (çıkış 0)"; exit 0
else
  echo "KAPI: KALDI (${(j:, :)KALAN}) (çıkış 1)"; exit 1
fi
