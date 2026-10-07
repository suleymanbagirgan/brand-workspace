#!/bin/zsh
# MarkaCore satır kapsamı (Camp H3-08). Ayrı derleme klasörü (.build/kapsam): ana .build'e dokunmaz.
# Kullanım: scripts/kapsam.sh        Çıktı: "MarkaCore satır kapsamı: %NN,N" ya da "doğrulanamadı: <neden>" (çıkış 2).
# Kapsam yalnız MarkaCore'dur; MarkaApp (SwiftUI) testsizdir ve ölçümün DIŞINDADIR.
cd "$(dirname "$0")/.." || exit 1
KOK="$PWD"; export LC_ALL=C
SC=.build/kapsam
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
L=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
COV=$(xcrun --find llvm-cov 2>/dev/null); PROF=$(xcrun --find llvm-profdata 2>/dev/null)
if [ -z "$COV" ] || [ -z "$PROF" ]; then echo "doğrulanamadı: llvm-cov/llvm-profdata bulunamadı"; exit 2; fi

GUNLUK=$(mktemp -t kapsam)
if [ -d "$F/Testing.framework" ] && ! xcode-select -p 2>/dev/null | grep -q Xcode.app; then
  swift test --enable-code-coverage --scratch-path "$SC" -Xswiftc -F$F -Xlinker -F$F -Xlinker -rpath -Xlinker $F -Xlinker -rpath -Xlinker $L >"$GUNLUK" 2>&1
else
  swift test --enable-code-coverage --scratch-path "$SC" >"$GUNLUK" 2>&1
fi
kod=$?
if [ $kod -ne 0 ]; then echo "doğrulanamadı: swift test çıkış $kod (günlük: $GUNLUK)"; tail -5 "$GUNLUK"; exit 2; fi

PROFDATA=$(find "$SC" -name default.profdata -path '*codecov*' 2>/dev/null | head -1)
BIN=$(find "$SC" -name 'MarkaCalismaAlaniPackageTests.xctest' -maxdepth 4 2>/dev/null | head -1)
[ -n "$BIN" ] && BIN="$BIN/Contents/MacOS/MarkaCalismaAlaniPackageTests"
if [ -z "$PROFDATA" ] || [ ! -f "$BIN" ]; then echo "doğrulanamadı: profdata/test ikilisi bulunamadı ($SC)"; exit 2; fi

RAPOR=$("$COV" report "$BIN" -instr-profile="$PROFDATA" -ignore-filename-regex='(\.build|Tests|MarkaApp|MarkaDogrula)/' 2>/dev/null)
echo "$RAPOR" | grep 'Sources/MarkaCore' >/dev/null || RAPOR=$("$COV" report "$BIN" -instr-profile="$PROFDATA" 2>/dev/null | grep -E 'Filename|Sources/MarkaCore|TOTAL')
# Sütunlar (llvm-cov report): Ad Regions Missed Cover Functions Missed Exec Lines Missed Cover [Branches...]; Lines = 3. '%' sütunundan geriye sayılır.
SATIRLAR=$(echo "$RAPOR" | grep 'Sources/MarkaCore' | sed "s#$KOK/##")
TOP=$(echo "$SATIRLAR" | awk '{ k=0; for(i=1;i<=NF;i++) if ($i ~ /%$/) c[++k]=i; L=$(c[3]-2); M=$(c[3]-1); T+=L; K+=M } END { printf "%d %d", T, K }')
TOPLAM=$(echo "$TOP" | awk '{ if ($1>0) printf "%.1f", ($1-$2)*100/$1; else print "0" }')
echo "MarkaCore satır kapsamı: %$TOPLAM (satır: $(echo $TOP | awk '{print $1}'), kaçan: $(echo $TOP | awk '{print $2}'); MarkaApp/MarkaDogrula dışarıda)"
echo "Kapsamı en düşük 5 dosya (satır %, kaçan/toplam):"
echo "$SATIRLAR" | awk '{ for(i=1;i<=NF;i++) if ($i ~ /%$/) c[++k]=i; if ($(c[3]-2)>0) printf "%s %s %d/%d\n", $(c[3]), $1, $(c[3]-1), $(c[3]-2); k=0 }' | sort -n | head -5
