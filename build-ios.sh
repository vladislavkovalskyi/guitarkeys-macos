#!/bin/bash
# Сборка GuitarKeys под iPhone и iPad.
#   ./build-ios.sh              — для симулятора
#   ./build-ios.sh device       — для настоящего устройства (нужна подпись)
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="GuitarKeys"
DEST="${1:-simulator}"

if [ "$DEST" = "device" ]; then
    SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
    TARGET="arm64-apple-ios26.0"
    BUILD_DIR="build/ios-device"
else
    SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
    TARGET="arm64-apple-ios26.0-simulator"
    BUILD_DIR="build/ios-simulator"
fi

SWIFTC="$(xcrun -f swiftc)"
PLUGINS="$(xcode-select -p)/usr/lib/swift/host/plugins"
APP_DIR="$BUILD_DIR/$APP_NAME.app"

echo "▸ Компиляция ($DEST)"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"

# Бандл iOS плоский: исполняемый файл и Info.plist лежат прямо в .app
"$SWIFTC" \
    -sdk "$SDK" \
    -target "$TARGET" \
    -swift-version 5 \
    -parse-as-library \
    -module-name "$APP_NAME" \
    -plugin-path "$PLUGINS" \
    -O -whole-module-optimization \
    -o "$APP_DIR/$APP_NAME" \
    $(find Sources -name '*.swift')

echo "▸ Бандл"
cp Resources/Info-iOS.plist "$APP_DIR/Info.plist"

echo "▸ Подпись (ad-hoc)"
codesign --force --sign - "$APP_DIR"

echo "✓ Готово: $APP_DIR"
