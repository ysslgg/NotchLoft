#!/usr/bin/env bash
# Crée dist/NotchTune.dmg (create-dmg, avec repli sur un DMG simple).
set -euo pipefail
cd "$(dirname "$0")/.."
APP="dist/NotchTune.app"
DMG="dist/NotchTune.dmg"
[ -d "$APP" ] || { echo "Lance d'abord ./build.sh"; exit 1; }
rm -f "$DMG"

TMP="$(mktemp -d)"
swift scripts/make-dmg-background.swift "$TMP/bg.png" 1
swift scripts/make-dmg-background.swift "$TMP/bg@2x.png" 2
tiffutil -cathidpicheck "$TMP/bg.png" "$TMP/bg@2x.png" -out "$TMP/background.tiff"

STAGE="$TMP/stage"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"

if command -v create-dmg >/dev/null && create-dmg \
    --volname "NotchTune" \
    --volicon "Resources/AppIcon.icns" \
    --background "$TMP/background.tiff" \
    --window-pos 200 120 \
    --window-size 660 400 \
    --icon-size 110 \
    --icon "NotchTune.app" 170 200 \
    --hide-extension "NotchTune.app" \
    --app-drop-link 490 200 \
    --no-internet-enable \
    "$DMG" "$STAGE"; then
    echo "✓ $DMG (stylisé)"
else
    echo "⚠︎ create-dmg a échoué : DMG simple"
    rm -f "$DMG"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "NotchTune" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
    echo "✓ $DMG (simple)"
fi
rm -rf "$TMP"
