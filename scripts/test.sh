#!/bin/zsh
# Testleri çalıştırır. Xcode yoksa Command Line Tools içindeki Swift Testing çerçevesini bağlar.
set -e
cd "$(dirname "$0")/.."
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
L=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
if [ -d "$F/Testing.framework" ] && ! xcode-select -p 2>/dev/null | grep -q Xcode.app; then
  swift test -Xswiftc -F$F -Xlinker -F$F -Xlinker -rpath -Xlinker $F -Xlinker -rpath -Xlinker $L "$@"
else
  swift test "$@"
fi
