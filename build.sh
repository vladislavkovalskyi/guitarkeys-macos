#!/bin/bash
# Сборка GuitarKeys.app. Xcode не нужен — достаточно Command Line Tools.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="GuitarKeys"
BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
source Tools/toolchain.sh

CONFIG="${1:-release}"
if [ "$CONFIG" = "debug" ]; then
    OPT_FLAGS=(-Onone -g)
else
    OPT_FLAGS=(-O -whole-module-optimization)
fi

echo "▸ Компиляция ($CONFIG)"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

"$SWIFTC" \
    -sdk "$SDK" \
    -target "$TARGET" \
    -swift-version 5 \
    -parse-as-library \
    -module-name "$APP_NAME" \
    -plugin-path "$PLUGINS" \
    "${OPT_FLAGS[@]}" \
    -o "$APP_DIR/Contents/MacOS/$APP_NAME" \
    $(find Sources -name '*.swift')

echo "▸ Иконка"
ICONSET="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
"$SWIFTC" -sdk "$SDK" -target "$TARGET" -swift-version 5 -O \
    -module-name MakeIcon -o "$BUILD_DIR/make-icon" Tools/MakeIcon/main.swift
"$BUILD_DIR/make-icon" "$BUILD_DIR/icon-1024.png"

for spec in "16:16x16" "32:16x16@2x" "32:32x32" "64:32x32@2x" \
            "128:128x128" "256:128x128@2x" "256:256x256" "512:256x256@2x" \
            "512:512x512" "1024:512x512@2x"; do
    px="${spec%%:*}"
    name="${spec##*:}"
    sips -z "$px" "$px" "$BUILD_DIR/icon-1024.png" --out "$ICONSET/icon_$name.png" >/dev/null 2>&1
done
iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/AppIcon.icns"

echo "▸ Бандл"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

echo "▸ Подпись (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP_DIR" 2>/dev/null

echo "✓ Готово: $APP_DIR"
