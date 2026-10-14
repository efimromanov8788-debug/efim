#!/bin/bash
# Скачивает последнюю версию Мурки, кладёт в «Программы» и запускает.
set -euo pipefail

URL="https://github.com/efimromanov8788-debug/claudeai/releases/latest/download/Murka.zip"
DEST="/Applications"
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Скачиваю Мурку…"
curl -fsSL "$URL" -o "$TMP/Murka.zip"

pkill -x Murka 2>/dev/null || true
rm -rf "$DEST/Murka.app"
ditto -x -k "$TMP/Murka.zip" "$DEST"
xattr -dr com.apple.quarantine "$DEST/Murka.app" 2>/dev/null || true

open "$DEST/Murka.app"
echo "Готово! Мурка живёт в $DEST/Murka.app 🐱"
