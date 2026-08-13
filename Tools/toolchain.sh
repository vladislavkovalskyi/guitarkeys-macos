# Выбор компилятора и SDK для сборки под macOS.
#
# Компилятор и SDK обязаны быть из одного комплекта: SDK, собранный более новым
# Swift, старый компилятор просто откажется читать. На этой машине Command Line
# Tools несут Swift 6.4, а Xcode — 6.3.3, поэтому пары нельзя перемешивать.
# Предпочитаем CLT: он самосогласован и не требует принятия лицензии Xcode.
#
# Сборка под iOS живёт в build-ios.sh и берёт связку из Xcode — там iOS SDK и
# компилятор тоже из одного комплекта.
#
# Подключается через `source`.

CLT=/Library/Developer/CommandLineTools

if [ -x "$CLT/usr/bin/swiftc" ] && [ -d "$CLT/SDKs/MacOSX.sdk" ]; then
    SWIFTC="$CLT/usr/bin/swiftc"
    SDK="$CLT/SDKs/MacOSX.sdk"
    PLUGINS="$CLT/usr/lib/swift/host/plugins"
else
    SWIFTC="$(xcrun -f swiftc)"
    SDK="$(xcrun --show-sdk-path)"
    PLUGINS="$(xcode-select -p)/usr/lib/swift/host/plugins"
fi

TARGET="arm64-apple-macos26.0"
