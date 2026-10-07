#!/bin/zsh
# Yolculuk kayıtlarını (E-09) yeniden üretir ve kayıtlı sonuçlarla ARASINDAKİ FARKI yazar (E-26).
#   Tests/Fixtures/yolculuk/*.json  (betik)  →  koşu  →  adım adım sonuç  →  Tests/Fixtures/yolculuk-sonuc/<ad>.json (kayıt)
# Kullanım: scripts/yolculuk-kaydet.sh            yalnız yeniden üretir ve `diff` yazar; depoya DOKUNMAZ. Fark yoksa çıktı boştur (çıkış 0).
#           scripts/yolculuk-kaydet.sh --kabul     farkı kayıt klasörüne yazar. Bilinçli davranış değişikliğinde, kodla AYNI değişiklikte
#                                                  gözden geçirmek için; kapı bunu asla otomatik çağırmaz.
# Çıkış: 0 = fark yok (ya da --kabul uygulandı), 1 = fark var, 2 = koşu hazırlanamadı.
# Koşucu, depo DIŞINDA küçük bir paket olarak derlenir (yalnız MarkaCore'a yol bağımlılığı; depoda dosya/Package.swift değişmez).
cd "$(dirname "$0")/.." || exit 2
DEPO="$PWD"
KABUL=0
for a in "$@"; do
  case "$a" in
    --kabul) KABUL=1 ;;
    *) echo "Bilinmeyen bayrak: $a (yalnız --kabul)" >&2; exit 2 ;;
  esac
done

KOSUCU="${YOLCULUK_KOSUCU:-${TMPDIR:-/tmp}/marka-yolculuk-kosucu}"
KAYIT="$DEPO/Tests/Fixtures/yolculuk-sonuc"
URETIM="$(mktemp -d "${TMPDIR:-/tmp}/yolculuk-uretim.XXXXXX")"
trap 'rm -rf "$URETIM"' EXIT

mkdir -p "$KOSUCU/Sources/yk"
cat > "$KOSUCU/Package.swift" <<PAKET
// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "yk", platforms: [.macOS(.v14)],
  dependencies: [.package(path: "$DEPO")],
  targets: [.executableTarget(name: "yk", dependencies: [.product(name: "MarkaCore", package: "MarkaCalismaAlani")])])
PAKET
cat > "$KOSUCU/Sources/yk/main.swift" <<'KOD'
import Foundation
import MarkaCore
let a = CommandLine.arguments
let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
let cikis = URL(fileURLWithPath: a[2], isDirectory: true)
try FileManager.default.createDirectory(at: cikis, withIntermediateDirectories: true)
for y in try YolculukKosucu.yukleKlasor(URL(fileURLWithPath: a[1])) {
    let s = await YolculukKosucu.kos(y)
    try (try e.encode(s) + Data("\n".utf8)).write(to: cikis.appendingPathComponent("\(y.ad).json"))
}
KOD

( cd "$KOSUCU" && swift build -c debug >"$URETIM/derleme.log" 2>&1 ) || { echo "koşucu derlenemedi:" >&2; tail -20 "$URETIM/derleme.log" >&2; exit 2; }
"$KOSUCU/.build/debug/yk" "$DEPO/Tests/Fixtures/yolculuk" "$URETIM/sonuc" || { echo "yolculuk koşusu çöktü" >&2; exit 2; }

mkdir -p "$KAYIT"
diff -ru "$KAYIT" "$URETIM/sonuc"; fark=$?
if [ $fark -eq 0 ]; then exit 0; fi
if [ "$KABUL" = 1 ]; then
  find "$KAYIT" -name "*.json" -delete && cp "$URETIM/sonuc"/*.json "$KAYIT"/
  echo "KABUL EDİLDİ: $KAYIT güncellendi. Farkı kodla birlikte gözden geçir." >&2
  exit 0
fi
echo "FARK VAR: kayıtlar koddan farklı. Bilinçli ise gözden geçirip: scripts/yolculuk-kaydet.sh --kabul" >&2
exit 1
