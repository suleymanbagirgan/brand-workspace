#!/bin/zsh
# Sürüm numarasını tek kaynaktan (Sources/MarkaCore/Version.swift) okur ve yazdırır.
# Kullanım: scripts/version.sh          → 0.2.0
#           scripts/version.sh --build  → artan build numarası (git commit sayısı)
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" == "--build" ]]; then
  git rev-list --count HEAD 2>/dev/null || { echo "HATA: git commit sayısı okunamadı (build numarası)" >&2; exit 1; }
  exit 0
fi
V="$(sed -nE 's/.*MarkaCoreVersion.*string = "([^"]*)".*/\1/p' Sources/MarkaCore/Version.swift)"
if [[ ! "$V" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  echo "HATA: Sources/MarkaCore/Version.swift içinde X.Y.Z biçiminde sürüm bulunamadı (okunan: '$V')" >&2
  exit 1
fi
echo "$V"
