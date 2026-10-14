#!/bin/bash
# Собирает Мурку в build/Murka.app. Нужны Xcode Command Line Tools: xcode-select --install
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Murka.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -parse-as-library Sources/Murka.swift -o "$APP/Contents/MacOS/Murka"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "Готово: $APP"
echo "Запуск:  open $APP"
