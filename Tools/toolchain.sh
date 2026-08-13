# Выбор компилятора и SDK.
# Установленный Xcode перехватывает xcrun и до принятия лицензии отказывается
# работать — в этом случае откатываемся на Command Line Tools, которым лицензия
# не нужна. Скрипт подключается через `source`.
CLT=/Library/Developer/CommandLineTools

if xcrun --show-sdk-path >/dev/null 2>&1; then
    SWIFTC="$(xcrun -f swiftc)"
    SDK="$(xcrun --show-sdk-path)"
    PLUGINS="$(xcode-select -p)/usr/lib/swift/host/plugins"
else
    SWIFTC="$CLT/usr/bin/swiftc"
    SDK="$CLT/SDKs/MacOSX.sdk"
    PLUGINS="$CLT/usr/lib/swift/host/plugins"
fi

[ -d "$PLUGINS" ] || PLUGINS="$CLT/usr/lib/swift/host/plugins"
TARGET="arm64-apple-macos26.0"
