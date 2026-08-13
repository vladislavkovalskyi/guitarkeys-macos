#!/bin/bash
# Играет короткую пьесу вживую через колонки.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
source Tools/toolchain.sh
"$SWIFTC" -sdk "$SDK" -target "$TARGET" -swift-version 5 -O \
  -module-name Play -o build/play \
  Sources/GuitarKeys/Audio/GuitarSynth.swift \
  Sources/GuitarKeys/Audio/EventQueue.swift \
  Sources/GuitarKeys/Audio/GuitarModel.swift \
  Sources/GuitarKeys/Audio/AudioEngine.swift \
  Sources/GuitarKeys/Music/Chord.swift \
  Sources/GuitarKeys/Music/ChordLibrary.swift \
  Tools/Play/main.swift
exec build/play
