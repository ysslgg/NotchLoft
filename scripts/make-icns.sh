#!/usr/bin/env bash
# Génère Resources/AppIcon.icns (sips + iconutil) à partir du script Swift.
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
swift scripts/make-icon.swift "$TMP/icon.png"
SET="$TMP/AppIcon.iconset"; mkdir -p "$SET"
for s in 16 32 128 256 512; do
    sips -z $s $s "$TMP/icon.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$TMP/icon.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
cp "$TMP/icon.png" Resources/AppIcon-1024.png
rm -rf "$TMP"
echo "✓ Resources/AppIcon.icns"
