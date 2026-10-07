#!/bin/zsh
# Yerel pre-commit sızıntı kancasını kurur (Camp H3-11). Kanca dosyası DEPOYA GİRMEZ (.git/hooks izlenmez).
# Kullanım: scripts/kancalar-kur.sh [hedef-depo]     (varsayılan: bu depo). Hedef verilirse yalnız oraya kurar (deneme için).
# Kanca staged EKLENEN satırlarda e-posta, kişisel yol, uzun API anahtarı arar; bulursa commit'i engeller (çıkış 1, dosya:satır).
# Desen tek kaynaktan gelir: scripts/sizinti-desenleri.sh (gelistir-kapisi.sh ile aynı).
KOK="$(cd "$(dirname "$0")/.." && pwd)"
HEDEF="${1:-$KOK}"
GIT_DIR=$(git -C "$HEDEF" rev-parse --absolute-git-dir 2>/dev/null) || { echo "git deposu değil: $HEDEF"; exit 1; }
[ -f "$KOK/scripts/sizinti-desenleri.sh" ] || { echo "desen dosyası yok"; exit 1; }
mkdir -p "$GIT_DIR/hooks"
KANCA="$GIT_DIR/hooks/pre-commit"
if [ -f "$KANCA" ] && ! grep -q 'MARKA-SIZINTI-KANCASI' "$KANCA"; then
  echo "Var olan pre-commit kancası bizim değil; üzerine yazılmadı: $KANCA"; exit 1
fi
cat > "$KANCA" <<KANCA_SON
#!/bin/zsh
# MARKA-SIZINTI-KANCASI (scripts/kancalar-kur.sh üretti; elle düzenleme)
source "$KOK/scripts/sizinti-desenleri.sh" || { echo "pre-commit: desen dosyası okunamadı"; exit 1; }
bulgu=\$(git diff --cached -U0 --no-color --diff-filter=ACM | awk '
  /^\+\+\+ b\// { dosya=substr(\$0,7); next }
  /^@@ / { split(\$3,a,","); satir=substr(a[1],2)+0; next }
  /^\+/ && !/^\+\+\+/ { print dosya ":" satir ":" substr(\$0,2); satir++ }
' | grep -vE '^scripts/(sizinti-desenleri|gelistir-kapisi)\.sh:' | grep -iE "\$SIZINTI_DESEN" | grep -viE "\$SAHTE_YOL")
if [ -n "\$bulgu" ]; then
  echo "pre-commit: COMMIT ENGELLENDİ — olası sızıntı (e-posta / kişisel yol / API anahtarı), dosya:satır:"
  echo "\$bulgu" | cut -d: -f1,2 | sed 's/^/  /'
  echo "Düzelt (uydurma ad/@example.test kullan) ve yeniden dene."
  exit 1
fi
exit 0
KANCA_SON
chmod +x "$KANCA"
echo "Kuruldu: $KANCA"
