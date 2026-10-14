#!/bin/bash
# Собирает Мурку в build/Murka.app (сразу для Apple Silicon и Intel).
# Нужны Xcode Command Line Tools: xcode-select --install
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Murka.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS"

for arch in arm64 x86_64; do
    swiftc -O -parse-as-library -target "$arch-apple-macos12.0" Sources/*.swift -o "build/Murka-$arch"
done
lipo -create build/Murka-arm64 build/Murka-x86_64 -output "$APP/Contents/MacOS/Murka"
rm build/Murka-arm64 build/Murka-x86_64

cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "Готово: $APP"
echo "Запуск:  open $APP"
