#!/bin/zsh
# Kararsız test avcısı: testleri N kez (varsayılan 10) koşturur, TEST BAŞINA geçme sayısını tablo yazar.
# Kullanım: scripts/kararsiz-avci.sh [N] [--sifirla]
#   Ham koşu çıktıları ve kısmi sonuçlar: .build/kararsiz-avci/ (kesilirse aynı N ile yeniden çalıştır: kalınan yerden devam eder;
#   --sifirla önceki koşuları siler). Çıktı: terminale tablo; docs/kararlilik-tablosu.md'yi YAZMAZ, o belge elle özetlenir.
# "20/20" yalnızca "bu makinede 20 koşuda geçti" demektir; kararlılık iddiası değildir.
cd "$(dirname "$0")/.."
N=10; SIFIRLA=0
for a in "$@"; do
  case "$a" in
    --sifirla) SIFIRLA=1 ;;
    <->) N=$a ;;
    *) echo "kullanım: $0 [N] [--sifirla]" >&2; exit 2 ;;
  esac
done
D=.build/kararsiz-avci
[ $SIFIRLA = 1 ] && rm -rf "$D"
mkdir -p "$D"
T0=$SECONDS
echo "Kararsız test avcısı: $N koşu ($(date '+%Y-%m-%d %H:%M'), bu makinede)"
for i in $(seq 1 $N); do
  if [ -f "$D/kosu-$i.tamam" ]; then echo "koşu $i/$N: önceki sonuçtan (atlandı)"; continue; fi
  s=$SECONDS
  scripts/test.sh > "$D/kosu-$i.txt" 2>&1
  kod=$?
  if ! grep -qE "^[✔✘] Test run with" "$D/kosu-$i.txt"; then
    echo "koşu $i/$N: test çıktısı yok (derleme hatası?) çıkış=$kod; 60 sn sonra yeniden"; sleep 60
    scripts/test.sh > "$D/kosu-$i.txt" 2>&1; kod=$?
    grep -qE "^[✔✘] Test run with" "$D/kosu-$i.txt" || { echo "koşu $i/$N: yine olmadı, duruyorum (devam için yeniden çalıştır)"; exit 1; }
  fi
  e=$((SECONDS - s))
  echo "$e" > "$D/kosu-$i.sure"
  touch "$D/kosu-$i.tamam"
  echo "koşu $i/$N: ${e} sn, çıkış=$kod, $(grep -cE '^✘ Test .* failed' "$D/kosu-$i.txt") kalan test"
done
TOPLAM=$((SECONDS - T0))
python3 - "$N" "$D" "$TOPLAM" <<'PY'
import sys, re, glob, collections
N, D, toplam = int(sys.argv[1]), sys.argv[2], sys.argv[3]
gec = collections.Counter(); kal = collections.Counter(); gor = collections.Counter()
ras = re.compile(r'^([✔✘]) Test (.+?) (passed|failed) after ')
sureler = []
for i in range(1, N + 1):
    for l in open(f"{D}/kosu-{i}.txt", errors="replace"):
        m = ras.match(l)
        if not m: continue
        ad = m.group(2)
        gor[ad] += 1
        if m.group(3) == "passed": gec[ad] += 1
        else: kal[ad] += 1
    sureler.append(int(open(f"{D}/kosu-{i}.sure").read()))
print(f"\n| test | geçme/{N} | kalma |\n|---|---|---|")
bozuk = [a for a in gor if gec[a] != N]
for a in sorted(bozuk): print(f"| {a} | {gec[a]}/{N} | {kal[a]} |")
if not bozuk: print(f"| (hepsi {N}/{N}) | | |")
print(f"\n{N} koşu · {len(gor)} test · {len(bozuk)} kararsız (ya da {N}/{N} dışında)")
print(f"koşu süreleri (sn): {sureler} · toplam {toplam} sn")
PY
