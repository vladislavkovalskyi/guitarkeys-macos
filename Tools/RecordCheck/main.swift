import AVFoundation
import Foundation

// Проверка записи: играем полторы секунды, пишем в файл, читаем обратно и убеждаемся,
// что там действительно звук нужной длины, а не пустышка с заголовком.

let engine = AudioEngine()
engine.volume = 0.55
engine.humanize = 0.6
engine.model = .acoustic
engine.start()

guard engine.isRunning else { print("✗ движок не запустился"); exit(1) }

var failures = 0
func check(_ condition: Bool, _ message: String) {
    print(condition ? "  ✓ \(message)" : "  ✗ \(message)")
    if !condition { failures += 1 }
}

let url: URL
do {
    url = try engine.startRecording()
} catch {
    print("✗ запись не началась: \(error.localizedDescription)")
    exit(1)
}
check(engine.isRecording, "запись пошла: \(url.lastPathComponent)")

let am = ChordLibrary.voicing(for: Chord(root: 9, quality: .minor))
engine.strum(voicing: am, direction: .down, articulation: .normalDown)
Thread.sleep(forTimeInterval: 0.5)
engine.strum(voicing: am, direction: .up, articulation: .normalUp)
Thread.sleep(forTimeInterval: 0.5)
engine.strum(voicing: am, direction: .down, articulation: .normalDown)
Thread.sleep(forTimeInterval: 0.5)

let level = engine.recordingLevel
let duration = engine.recordedDuration
check(level > 0.001, String(format: "индикатор уровня живой: пик %.3f", level))
check(duration > 1.2 && duration < 1.9, String(format: "длительность считается: %.2f с", duration))

let saved = engine.stopRecording()
engine.stop()

check(saved != nil, "запись остановлена и файл отдан")
check(!engine.isRecording, "состояние записи сброшено")

guard let saved else { exit(1) }

let attributes = try? FileManager.default.attributesOfItem(atPath: saved.path)
let size = (attributes?[.size] as? Int) ?? 0
check(size > 4000, "файл не пустой: \(size) байт")

// Главная проверка: файл читается обратно и в нём есть сигнал.
do {
    let file = try AVAudioFile(forReading: saved)
    let frames = AVAudioFrameCount(file.length)
    let readDuration = Double(file.length) / file.fileFormat.sampleRate
    check(abs(readDuration - duration) < 0.35,
          String(format: "длина файла совпадает с записанной: %.2f с", readDuration))

    guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else {
        check(false, "буфер для чтения не создался"); exit(1)
    }
    try file.read(into: buffer)

    var peak: Float = 0
    var sum: Double = 0
    if let channels = buffer.floatChannelData {
        for channel in 0..<Int(buffer.format.channelCount) {
            let samples = channels[channel]
            for frame in 0..<Int(buffer.frameLength) {
                let value = samples[frame]
                peak = max(peak, abs(value))
                sum += Double(value) * Double(value)
            }
        }
    }
    let rms = (sum / Double(max(1, buffer.frameLength) * 2)).squareRoot()
    check(peak > 0.02, String(format: "в файле есть звук: пик %.3f", peak))
    check(rms > 0.002, String(format: "энергия сигнала: %.4f", rms))
    check(peak <= 1.0, "записанное не клиппит")
    print("  · формат: \(file.fileFormat)")
} catch {
    check(false, "файл не читается: \(error.localizedDescription)")
}

try? FileManager.default.removeItem(at: saved)
print(failures == 0 ? "\nЗапись работает.\n" : "\nПровалено: \(failures)\n")
exit(failures == 0 ? 0 : 1)
