#!/bin/zsh
# Çizim kararlılığı (H2-07): aynı koddan iki MARKA_SNAPSHOT koşusunun PNG'leri bire bir aynı mı?
# Kullanım: scripts/cizim-kararliligi.sh [uygulama-ikilisi]   (varsayılan: ~/Applications/Workspace AI.app)
# YALNIZ geçici veri alanı kurar (mktemp); gerçek veriye ve çalışan uygulamaya dokunmaz. Sonda geçici her şeyi siler.
# Çıkış: 0 KARARLI, 1 KARARSIZ, 2 kurulum hatası. Not: ImageRenderer Menu/Link/Toggle/TextField/kaydırma/odak çizmez; bu bozuk sayılmaz.
cd "$(dirname "$0")/.."
BIN=${1:-"$HOME/Applications/Workspace AI.app/Contents/MacOS/MarkaCalismaAlani"}
[ -x "$BIN" ] || { echo "ikili yok: $BIN (scripts/build-app.sh)" >&2; exit 2; }
T=$(mktemp -d "${TMPDIR:-/tmp}/cizim-kararliligi.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT
DOGRULA=.build/debug/MarkaDogrula
[ -x "$DOGRULA" ] || swift build --product MarkaDogrula >/dev/null 2>&1 || { echo "MarkaDogrula derlenemedi" >&2; exit 2; }
mkdir -p "$T/tohum" "$T/tohum-klasor"
"$DOGRULA" demo "$T/tohum" >/dev/null 2>&1 || { echo "örnek veri kurulamadı" >&2; exit 2; }
for k in 1 2; do
  # Yollar iki koşuda AYNI olmalı: Ayarlar › Veri ekranı veri alanı yolunu yazar.
  rm -rf "$T/ws" "$T/kl"; cp -R "$T/tohum" "$T/ws"; cp -R "$T/tohum-klasor" "$T/kl"
  MARKA_WORKSPACE="$T/ws" MARKA_FOLDERS="$T/kl" MARKA_SNAPSHOT="$T/png$k" "$BIN" >"$T/cikti$k.txt" 2>&1 &
  PID=$!
  # En çok 180 sn bekle; takılırsa süreci kapat (artık süreç bırakma).
  for _ in {1..180}; do kill -0 $PID 2>/dev/null || break; sleep 1; done
  kill $PID 2>/dev/null; wait $PID 2>/dev/null
done
N=$(ls "$T/png1" 2>/dev/null | wc -l | tr -d ' ')
[ "$N" -gt 0 ] || { echo "PNG üretilmedi" >&2; exit 2; }
AYNI=0; FARK=()
for f in "$T"/png1/*.png; do
  b=${f:t}
  if cmp -s "$f" "$T/png2/$b"; then AYNI=$((AYNI+1)); else FARK+=("$b"); fi
done
echo "$N PNG: $AYNI bire bir aynı, ${#FARK[@]} farklı (ikinci koşuda $(ls "$T/png2" | wc -l | tr -d ' ') dosya)"
if [ ${#FARK[@]} -eq 0 ] && [ "$N" = "$(ls "$T/png2" | wc -l | tr -d ' ')" ]; then echo "KARARLI"; exit 0; fi
for b in $FARK; do echo "  fark: $b"; done
# Fark çıkan çiftler inceleme için .build altına kopyalanır (geçici veri yine silinir).
rm -rf .build/cizim-kararliligi; mkdir -p .build/cizim-kararliligi
for b in $FARK; do cp "$T/png1/$b" ".build/cizim-kararliligi/1-$b"; cp "$T/png2/$b" ".build/cizim-kararliligi/2-$b"; done
echo "KARARSIZ"; exit 1
