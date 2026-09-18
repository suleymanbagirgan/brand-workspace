#!/bin/zsh
# Marka Çalışma Alanı.app paketini üretir (Xcode gerektirmez).
# Kullanım: scripts/build-app.sh [--sign "Developer ID Application: …"]
set -euo pipefail
cd "$(dirname "$0")/.."
SIGN_ID="-"
if [[ "${1:-}" == "--sign" ]]; then SIGN_ID="$2"; fi
# Sürüm tek kaynaktan: Sources/MarkaCore/Version.swift (scripts/version.sh okur ve biçimi denetler).
VERSION="$(scripts/version.sh)"
BUILD="$(scripts/version.sh --build)"
APP="dist/Marka Çalışma Alanı.app"

# Simge
mkdir -p build/icon.iconset
swiftc -O scripts/make-icon.swift -o build/make-icon
build/make-icon build/icon-1024.png
for spec in 16:16x16 32:16x16@2x 32:32x32 64:32x32@2x 128:128x128 256:128x128@2x 256:256x256 512:256x256@2x 512:512x512 1024:512x512@2x; do
  sips -z ${spec%%:*} ${spec%%:*} build/icon-1024.png --out "build/icon.iconset/icon_${spec#*:}.png" >/dev/null
done
iconutil -c icns build/icon.iconset -o Resources/AppIcon.icns

swift build -c release --product MarkaApp
BIN="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/MarkaApp" "$APP/Contents/MacOS/MarkaCalismaAlani"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp -R Resources/tr.lproj Resources/en.lproj "$APP/Contents/Resources/"
for b in "$BIN"/*.bundle(N); do cp -R "$b" "$APP/Contents/Resources/"; done
cp LICENSE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/" 2>/dev/null || true

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.markacalismaalani.app</string>
  <key>CFBundleName</key><string>Marka Çalışma Alanı</string>
  <key>CFBundleDisplayName</key><string>Marka Çalışma Alanı</string>
  <key>CFBundleExecutable</key><string>MarkaCalismaAlani</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD}</string>
  <key>CFBundleDevelopmentRegion</key><string>tr</string>
  <key>CFBundleLocalizations</key><array><string>tr</string><string>en</string></array>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticTermination</key><false/>
  <key>NSHumanReadableCopyright</key><string>Beta ${VERSION}</string>
</dict>
</plist>
PLIST

if [[ "$SIGN_ID" == "-" ]]; then
  codesign --force --deep --sign - "$APP"
else
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_ID" "$APP"
fi
codesign --verify --deep --strict "$APP"
echo "Hazır: $PWD/$APP"
