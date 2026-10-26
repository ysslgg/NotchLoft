#!/usr/bin/env bash
# Compile l'adaptateur MediaRemote, l'app Swift et assemble NotchLoft.app.
# UNIVERSAL=1 ./build.sh  -> binaire arm64 + x86_64
set -euo pipefail
cd "$(dirname "$0")"

ROOT="$PWD"
ADAPTER_DIR="$ROOT/.build-adapter/src"
APP="$ROOT/dist/NotchLoft.app"

echo "▸ Adaptateur MediaRemote"
if [ ! -d "$ADAPTER_DIR" ]; then
    git clone --depth 1 https://github.com/ungive/mediaremote-adapter.git "$ADAPTER_DIR"
fi
cmake -S "$ADAPTER_DIR" -B "$ADAPTER_DIR/build" -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build "$ADAPTER_DIR/build" >/dev/null

echo "▸ Compilation Swift"
ARCHS=()
if [ "${UNIVERSAL:-0}" = "1" ]; then ARCHS=(--arch arm64 --arch x86_64); fi
swift build -c release ${ARCHS[@]+"${ARCHS[@]}"}
BIN_DIR="$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)"

echo "▸ Assemblage de l'app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/NotchLoft" "$APP/Contents/MacOS/NotchLoft"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ADAPTER_DIR/bin/mediaremote-adapter.pl" "$APP/Contents/Resources/"
cp -R "$ADAPTER_DIR/build/MediaRemoteAdapter.framework" "$APP/Contents/Frameworks/"
for lp in "$ROOT"/Resources/*.lproj; do
    [ -d "$lp" ] && cp -R "$lp" "$APP/Contents/Resources/"
done
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

echo "▸ Signature ad hoc"
codesign --force --deep --sign - "$APP"

echo "✓ $APP"
lipo -info "$APP/Contents/MacOS/NotchLoft"
