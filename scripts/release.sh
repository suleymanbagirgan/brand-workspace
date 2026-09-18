#!/bin/zsh
# Beta paketi: build-app.sh → dist/MarkaCalismaAlani-<sürüm>.dmg (uygulama + /Applications kısayolu), her adım doğrulanır.
#
# Kullanım:
#   scripts/release.sh
#       Ad-hoc imzalı dmg. Başka bir Mac'te Gatekeeper uyarısı verir (docs/beta-kurulum.md).
#   scripts/release.sh --sign "Developer ID Application: Ad Soyad (TAKIMID)" --notarize <keychain-profili>
#       Developer ID imzası (hardened runtime + zaman damgası), notarization ve staple.
#
# Kimlik bilgisi betikte yok. Notarization profili bir kez şu komutla Keychain'e kaydedilir:
#   xcrun notarytool store-credentials <profil> --apple-id <apple-id> --team-id <TAKIMID>
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { print -u2 "\nHATA: $*"; exit 1; }
step() { print "\n==> $*"; }
ok()   { print "    tamam: $*"; }

SIGN_ID=""
PROFILE=""
while (( $# )); do
  case "$1" in
    --sign)     [[ $# -ge 2 && -n "$2" ]] || fail "--sign bir imza kimliği ister (ör. \"Developer ID Application: Ad Soyad (TAKIMID)\")"
                SIGN_ID="$2"; shift 2 ;;
    --notarize) [[ $# -ge 2 && -n "$2" ]] || fail "--notarize bir notarytool keychain profili adı ister"
                PROFILE="$2"; shift 2 ;;
    -h|--help)  sed -n '2,12p' "$0"; exit 0 ;;
    *)          fail "bilinmeyen seçenek: $1 (yardım: scripts/release.sh --help)" ;;
  esac
done
[[ -n "$PROFILE" && -z "$SIGN_ID" ]] && fail "--notarize yalnızca --sign ile kullanılır; Apple ad-hoc imzalı uygulamayı notarize etmez."

VERSION="$(scripts/version.sh)"
BUILD="$(scripts/version.sh --build)"
APP_NAME="Marka Çalışma Alanı.app"
APP="dist/$APP_NAME"
DMG="dist/MarkaCalismaAlani-$VERSION.dmg"
WORK="build/release"
MNT=""

cleanup() {
  if [[ -n "$MNT" ]] && mount | grep -qF " on $MNT "; then
    hdiutil detach "$MNT" -quiet 2>/dev/null || hdiutil detach "$MNT" -force -quiet 2>/dev/null || true
  fi
}
trap cleanup EXIT

print "Marka Çalışma Alanı $VERSION (build $BUILD)"
if [[ -n "$SIGN_ID" ]]; then print "Kip: Developer ID imzası${PROFILE:+ + notarization (profil: $PROFILE)}"
else print "Kip: AD-HOC (Developer ID verilmedi)"; fi

# ---------------------------------------------------------------- ön denetim
step "Ön denetim"
grep -qF "> Beta $VERSION." README.md || fail "README.md 'Beta $VERSION.' içermiyor; sürüm tek kaynaktan (Sources/MarkaCore/Version.swift) gelir, README'yi güncelle."
ok "README sürümü $VERSION ile aynı"
if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
  print "    uyarı: çalışma ağacında commit edilmemiş değişiklik var; build $BUILD bunları tam temsil etmez."
fi
for t in hdiutil codesign spctl ditto shasum; do command -v $t >/dev/null || fail "$t bulunamadı"; done

if [[ -n "$SIGN_ID" ]]; then
  [[ "$SIGN_ID" == "Developer ID Application:"* ]] || \
    fail "Dağıtım için 'Developer ID Application: …' kimliği gerekir (verilen: '$SIGN_ID'). 'Apple Development' veya 'Mac App Distribution' sertifikası başka Mac'lerde Gatekeeper'dan geçmez."
  IDS="$(security find-identity -v -p codesigning 2>&1 || true)"
  if ! print -r -- "$IDS" | grep -qF "\"$SIGN_ID\""; then
    print -u2 "\nBu Mac'teki geçerli imza kimlikleri (security find-identity -v -p codesigning):"
    print -u2 -r -- "$IDS" | sed 's/^/    /' >&2
    fail "'$SIGN_ID' Keychain'de geçerli bir imza kimliği olarak bulunamadı.
  Developer ID Application sertifikası ve özel anahtarı bu Mac'in Keychain'inde olmalı:
  developer.apple.com › Certificates › '+' › Developer ID Application (Account Holder gerekir),
  indirilen .cer dosyasını çift tıkla; başka Mac'te üretildiyse .p12 olarak dışa aktarıp buraya al.
  İmzasız paket için seçeneksiz çalıştır: scripts/release.sh"
  fi
  ok "imza kimliği Keychain'de: $SIGN_ID"
  if [[ -n "$PROFILE" ]]; then
    xcrun --find notarytool >/dev/null 2>&1 || fail "xcrun notarytool bulunamadı (Command Line Tools güncel mi? xcode-select --install)"
    xcrun --find stapler >/dev/null 2>&1 || fail "xcrun stapler bulunamadı (Command Line Tools güncel mi?)"
    xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 || \
      fail "notarytool keychain profili '$PROFILE' bulunamadı ya da Apple'a bağlanılamadı. Önce bir kez:
  xcrun notarytool store-credentials $PROFILE --apple-id <apple-id> --team-id <TAKIMID>
  (uygulamaya özel parola appleid.apple.com'dan alınır; ağ bağlantısını da kontrol et)"
    ok "notarytool profili çalışıyor: $PROFILE"
  else
    print "    uyarı: --notarize verilmedi. Developer ID imzalı ama notarize edilmemiş uygulama macOS 15'te yine engellenir."
  fi
fi

# notarytool'a gönderir, 'Accepted' değilse günlüğü basıp durur.
notarize() {
  local file="$1" json="$WORK/notary-$(basename "$1").json" id status
  xcrun notarytool submit "$file" --keychain-profile "$PROFILE" --wait --output-format json > "$json" || true
  id="$(plutil -extract id raw -o - "$json" 2>/dev/null || true)"
  status="$(plutil -extract status raw -o - "$json" 2>/dev/null || true)"
  if [[ "$status" != "Accepted" ]]; then
    print -u2 "notarytool yanıtı:"; cat "$json" >&2
    [[ -n "$id" ]] && xcrun notarytool log "$id" --keychain-profile "$PROFILE" >&2 || true
    fail "notarization kabul edilmedi ($(basename "$file"): durum '${status:-bilinmiyor}')"
  fi
  ok "notarization kabul edildi: $(basename "$file") (id $id)"
}

# ---------------------------------------------------------------- uygulama
step "Uygulama derleniyor (scripts/build-app.sh)"
if [[ -n "$SIGN_ID" ]]; then scripts/build-app.sh --sign "$SIGN_ID"; else scripts/build-app.sh; fi
rm -rf "$WORK"; mkdir -p "$WORK"

step "Uygulama imzası doğrulanıyor"
codesign --verify --deep --strict --verbose=2 "$APP"
SIG="$(codesign -dv --verbose=2 "$APP" 2>&1)"
print -r -- "$SIG" | grep -E '^(Identifier|Format|Authority|Signature|TeamIdentifier|Timestamp|CodeDirectory)' | sed 's/^/    /'
if [[ -n "$SIGN_ID" ]]; then
  print -r -- "$SIG" | grep -qF "Authority=$SIGN_ID" || fail "uygulama beklenen kimlikle imzalanmamış"
  print -r -- "$SIG" | grep -qE 'flags=.*runtime' || fail "hardened runtime açık değil (notarization için gerekli)"
  print -r -- "$SIG" | grep -q '^Timestamp=' || fail "güvenli zaman damgası yok (notarization için gerekli)"
else
  print -r -- "$SIG" | grep -q 'Signature=adhoc' || fail "ad-hoc imza bekleniyordu"
fi
PLIST_V="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
PLIST_B="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")"
[[ "$PLIST_V" == "$VERSION" && "$PLIST_B" == "$BUILD" ]] || fail "Info.plist sürümü ($PLIST_V/$PLIST_B) kaynakla ($VERSION/$BUILD) uyuşmuyor"
ARCHS="$(lipo -archs "$APP/Contents/MacOS/MarkaCalismaAlani")"
ok "codesign --verify --deep --strict; Info.plist $PLIST_V ($PLIST_B); mimari: $ARCHS"

if [[ -n "$PROFILE" ]]; then
  step "Uygulama notarize ediliyor (birkaç dakika sürebilir)"
  ditto -c -k --keepParent "$APP" "$WORK/app.zip"
  notarize "$WORK/app.zip"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  ok "bilet uygulamaya zımbalandı (çevrimdışı ilk açılış için)"
fi

# ---------------------------------------------------------------- dmg
step "Disk görüntüsü oluşturuluyor: $DMG"
STAGE="$WORK/dmg-root"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP_NAME"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Marka Çalışma Alanı $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" -quiet
ok "oluşturuldu"

if [[ -n "$SIGN_ID" ]]; then
  step "Disk görüntüsü imzalanıyor"
  codesign --force --timestamp --sign "$SIGN_ID" "$DMG"
  codesign --verify --strict --verbose=2 "$DMG"
  ok "dmg imzalı"
  if [[ -n "$PROFILE" ]]; then
    step "Disk görüntüsü notarize ediliyor"
    notarize "$DMG"
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    ok "bilet dmg'ye zımbalandı"
  fi
fi

step "hdiutil verify"
hdiutil verify "$DMG" 2>&1 | tail -n 2 | sed 's/^/    /'
ok "sağlama toplamı geçerli"

step "Disk görüntüsü bağlanıp içerik doğrulanıyor"
MNT="$PWD/$WORK/mnt"
mkdir -p "$MNT"
hdiutil attach "$DMG" -nobrowse -readonly -noautoopen -mountpoint "$MNT" -quiet
[[ -d "$MNT/$APP_NAME" ]] || fail "dmg içinde '$APP_NAME' yok"
[[ -L "$MNT/Applications" && "$(readlink "$MNT/Applications")" == "/Applications" ]] || fail "dmg içinde /Applications kısayolu yok"
codesign --verify --deep --strict --verbose=2 "$MNT/$APP_NAME"
M_V="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$MNT/$APP_NAME/Contents/Info.plist")"
[[ "$M_V" == "$VERSION" ]] || fail "dmg içindeki uygulamanın sürümü $M_V (beklenen $VERSION)"
[[ -x "$MNT/$APP_NAME/Contents/MacOS/MarkaCalismaAlani" ]] || fail "dmg içindeki uygulamanın çalıştırılabilir dosyası yok"
ok "uygulama + Applications kısayolu var; içerideki uygulamanın imzası geçerli; sürüm $M_V"
APP_SPCTL="$(spctl -a -t exec -vv "$MNT/$APP_NAME" 2>&1 || true)"
hdiutil detach "$MNT" -quiet
MNT=""
ok "ayrıldı"

step "Gatekeeper değerlendirmesi (spctl)"
DMG_SPCTL="$(spctl -a -t open --context context:primary-signature -vv "$DMG" 2>&1 || true)"
print "    uygulama: "; print -r -- "$APP_SPCTL" | sed 's/^/      /'
print "    dmg:      "; print -r -- "$DMG_SPCTL" | sed 's/^/      /'
if [[ -n "$PROFILE" ]]; then
  print -r -- "$APP_SPCTL" | grep -q 'accepted' || fail "Gatekeeper uygulamayı kabul etmedi"
  print -r -- "$APP_SPCTL" | grep -q 'Notarized Developer ID' || fail "uygulama 'Notarized Developer ID' olarak görünmüyor"
  print -r -- "$DMG_SPCTL" | grep -q 'accepted' || fail "Gatekeeper dmg'yi kabul etmedi"
  ok "Gatekeeper uygulamayı ve dmg'yi kabul ediyor (Notarized Developer ID)"
else
  print "    (beklenen: ret. Ad-hoc imza Gatekeeper'dan geçmez; notarization yok.)"
fi

# ---------------------------------------------------------------- özet
SIZE="$(du -h "$DMG" | cut -f1 | tr -d ' ')"
SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"
print "\n================================================================"
print "Paket:   $PWD/$DMG"
print "Sürüm:   $VERSION (build $BUILD), mimari: $ARCHS"
print "Boyut:   $SIZE"
print "SHA-256: $SHA"
if [[ -n "$PROFILE" ]]; then
  print "İmza:    Developer ID + notarize + zımbalı. Katılımcı çift tıklayıp açabilir."
elif [[ -n "$SIGN_ID" ]]; then
  print "İmza:    Developer ID imzalı ama NOTARIZE EDİLMEDİ — macOS 15+ açılışı engeller. --notarize <profil> ile tekrar çalıştır."
else
  print "İmza:    İMZASIZ/AD-HOC — katılımcı Gatekeeper uyarısı görecek."
  print "         İlk açılış talimatını katılımcıya gönder: docs/beta-kurulum.md"
fi
print "================================================================"
