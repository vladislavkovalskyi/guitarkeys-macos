#!/bin/bash
# Проверки GuitarKeys.
#   ./Tools/check.sh          — офлайн: строй, огибающая, аппликатуры (без звука)
#   ./Tools/check.sh --audio  — плюс живой AVAudioEngine: прозвучит аккорд Am
set -euo pipefail
cd "$(dirname "$0")/.."

source Tools/toolchain.sh
mkdir -p build

AUDIO_SOURCES=(
    Sources/GuitarKeys/Audio/GuitarSynth.swift
    Sources/GuitarKeys/Audio/EventQueue.swift
    Sources/GuitarKeys/Audio/GuitarModel.swift
    Sources/GuitarKeys/Audio/Strum.swift
    Sources/GuitarKeys/Audio/StrumScheduler.swift
    Sources/GuitarKeys/Music/Chord.swift
    Sources/GuitarKeys/Music/ChordLibrary.swift
    Sources/GuitarKeys/Input/Bindings.swift
    Sources/GuitarKeys/Input/KeyCodes.swift
    Sources/GuitarKeys/UI/FretboardGeometry.swift
    Sources/GuitarKeys/Music/Song.swift
    Sources/GuitarKeys/Audio/AudioFileFormat.swift
)

echo "▸ Синтез и аппликатуры"
"$SWIFTC" -sdk "$SDK" -target "$TARGET" -swift-version 5 -O \
    -module-name TuneCheck -o build/tune-check \
    "${AUDIO_SOURCES[@]}" Tools/TuneCheck/main.swift
build/tune-check

echo
echo "▸ Студия и экспорт"
"$SWIFTC" -sdk "$SDK" -target "$TARGET" -swift-version 5 -O \
    -module-name StudioCheck -o build/studio-check \
    "${AUDIO_SOURCES[@]}" \
    Sources/GuitarKeys/Audio/AudioEngine.swift \
    Sources/GuitarKeys/Audio/SongExporter.swift \
    Tools/StudioCheck/main.swift
build/studio-check

if [ "${1:-}" = "--audio" ]; then
    echo
    echo "▸ Живой аудиотракт"
    "$SWIFTC" -sdk "$SDK" -target "$TARGET" -swift-version 5 -O \
        -module-name AudioCheck -o build/audio-check \
        "${AUDIO_SOURCES[@]}" Sources/GuitarKeys/Audio/AudioEngine.swift \
        Tools/AudioCheck/main.swift
    build/audio-check

    echo
    echo "▸ Запись в файл"
    "$SWIFTC" -sdk "$SDK" -target "$TARGET" -swift-version 5 -O \
        -module-name RecordCheck -o build/record-check \
        "${AUDIO_SOURCES[@]}" Sources/GuitarKeys/Audio/AudioEngine.swift \
        Tools/RecordCheck/main.swift
    build/record-check

fi
