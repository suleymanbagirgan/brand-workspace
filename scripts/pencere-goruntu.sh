#!/bin/zsh
# Gerçek uygulama penceresinin görüntüsünü alır (ImageRenderer'ın çizemediği araç çubuğu, sistem malzemesi, terminal ve menüler dahil).
# Kullanım: scripts/pencere-goruntu.sh <bölüm> <çıktı.png> [light|dark] [panel|onay|-] [board|gantt|calendar]   (panel: ilk kaydın ayrıntı panelini aç)
#   bölüm: flow | todo | files | info | finance | report   (açılış bölümü)
# Önkoşul: `scripts/build-app.sh` çalışmış olmalı; çalıştıran uygulamaya (Terminal) macOS Ayarlar › Gizlilik › Ekran Kaydı izni verilmiş olmalı.
# Güvenlik: geçici veri alanı ve örnek veri kullanır (gerçek veriye dokunmaz), yalnız KENDİ başlattığı işlemin penceresini (PID ile) yakalar,
# tam ekran görüntüsü almaz.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TAB=${1:?bölüm}; OUT=${2:?çıktı}; MODE=${3:-light}
WORK=$(mktemp -d)
# Deneme kopyasının tercih alanı (yol özetli) da silinir; yoksa her çalıştırma ~/Library/Preferences'ta bir plist bırakır.
cleanup() { rm -rf "$WORK"; rm -f "$HOME"/Library/Preferences/com.markacalismaalani.app.deneme.*.plist 2>/dev/null; }
trap cleanup EXIT
swiftc -O "$ROOT/scripts/pencere-id.swift" -o "$WORK/pencere-id"
mkdir -p "$WORK/ws" "$WORK/folders"
(cd "$ROOT" && swift run MarkaDogrula demo "$WORK/ws" >/dev/null 2>&1)
MARKA_WORKSPACE="$WORK/ws" MARKA_FOLDERS="$WORK/folders" MARKA_SEKME=$TAB MARKA_GORUNUM=$MODE MARKA_MOD=${5:-} MARKA_PARCA=${5:-} MARKA_PANEL=$([ "$4" = "panel" ] && echo 1 || { [ "$4" = "onay" ] && echo onay || echo 0; }) \
  "$HOME/Applications/Workspace AI.app/Contents/MacOS/MarkaCalismaAlani" >/dev/null 2>&1 &
PID=$!
sleep 5
ID=$("$WORK/pencere-id" $PID)
if [ -n "$ID" ]; then screencapture -x -o -l "$ID" "$OUT"; echo "yakalandı: $OUT"; else echo "pencere bulunamadı (Ekran Kaydı izni?)"; fi
kill $PID 2>/dev/null; sleep 1; kill -9 $PID 2>/dev/null; true
