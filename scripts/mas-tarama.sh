#!/bin/zsh
# MAS (Mac App Store) kipi taraması — sandbox geçişi S2 kanıtı.
#
# Ne yapar:
#   1) MAS kipinde derlenen kaynakta (Sources/MarkaCore + Sources/MarkaApp) `#if !MAS` bölgeleri DIŞINDA şu kalıpların
#      bulunmadığını doğrular: `Process(`, `sandbox-exec`, `/bin/zsh`, `NSTask`, ayrıca `environment["MARKA_` (geliştirme kancası).
#   2) `swift build --product MarkaApp -Xswiftc -DMAS` çalıştırır (ayrı derleme klasörü: .build/mas-kip; normal önbelleği bozmaz).
#
# Sınırlar (dürüst tarama, derleyici değil):
#   - Koşullu derleme metin düzeyinde izlenir: yalnız tam olarak `#if MAS` / `#if !MAS` bilinir; `#else` bunları tersine çevirir.
#     Başka koşullar (`#if DEBUG`, `#elseif …`) "derlenir" sayılır (temkinli: fazla satır taranır, eksik değil).
#   - Yalnız tümüyle yorum olan satırlar (`//`, `///`) atlanır; satır sonu yorumu ve `/* … */` blokları taranır (yanlış pozitif olabilir).
#   - Kalıp metin araması: dolaylı süreç başlatma (posix_spawn, NSWorkspace ile uygulama açma, dlopen…) yakalanmaz.
#   - Sources/MarkaDogrula ve Tests MAS kipinde derlenmez (Codex'e bağlı); taranmaz.
#   - Derlemenin geçmesi uygulamanın sandbox'ta ÇALIŞTIĞINI kanıtlamaz; yalnız MAS kaynağının derlendiğini gösterir.
set -e
cd "$(dirname "$0")/.."

echo "== 1) Kaynak taraması (MAS kipinde derlenen satırlar) =="
python3 - <<'PY'
import pathlib, re, sys
root = pathlib.Path(".")
patterns = ["Process(", "sandbox-exec", "/bin/zsh", "NSTask", 'environment["MARKA_']
files = sorted(list((root / "Sources/MarkaCore").rglob("*.swift")) + list((root / "Sources/MarkaApp").rglob("*.swift")))
hits, scanned, skipped = [], 0, 0
for f in files:
    stack = []  # her öğe: True (MAS'ta derlenir) / False (derlenmez)
    for no, line in enumerate(f.read_text().splitlines(), 1):
        s = line.strip()
        m = re.match(r"#if\s+(!?)\s*MAS\s*$", s)
        if m:
            stack.append(m.group(1) != "!"); continue
        if s.startswith("#if"):
            stack.append(True); continue
        if s.startswith("#elseif"):
            stack[-1] = True; continue
        if s == "#else":
            stack[-1] = not stack[-1]; continue
        if s.startswith("#endif"):
            stack.pop(); continue
        if not all(stack):
            skipped += 1; continue
        if s.startswith("//"):
            continue
        scanned += 1
        for p in patterns:
            if p in line:
                hits.append(f"{f}:{no}: {p}  |  {s[:120]}")
    if stack:
        print(f"HATA: {f} içinde kapanmamış #if"); sys.exit(2)
print(f"Dosya: {len(files)} · taranan kod satırı: {scanned} · MAS'ta derlenmeyen (atlanan) satır: {skipped}")
print("Kalıplar: " + ", ".join(patterns))
if hits:
    print("BULUNDU (MAS kipinde derlenen kaynakta olmamalı):")
    print("\n".join(hits)); sys.exit(1)
print("TEMİZ: kalıpların hiçbiri MAS kipinde derlenen kaynakta yok.")
PY

echo
echo "== 2) MAS kipi derleme: swift build --product MarkaApp -Xswiftc -DMAS =="
LOG=$(mktemp -t mas-derleme)
if swift build --product MarkaApp -Xswiftc -DMAS --scratch-path .build/mas-kip >"$LOG" 2>&1; then
  echo "Hata sayısı: $(grep -c 'error:' "$LOG" || true) · Uyarı satırı: $(grep -c 'warning:' "$LOG" || true)"
  tail -1 "$LOG"
  rm -f "$LOG"
else
  grep 'error:' "$LOG" | sort -u | head -40
  echo "MAS kipi derleme BAŞARISIZ (günlük: $LOG)"; exit 1
fi
