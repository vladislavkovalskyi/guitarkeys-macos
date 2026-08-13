import Foundation

// Проверка живого аудиотракта: запускается настоящий AVAudioEngine и берётся аккорд.
// Убеждаемся, что CoreAudio действительно тянет граф, а не молчит из-за ошибки в связях.

let engine = AudioEngine()
engine.volume = 0.5
engine.start()

guard engine.isRunning else {
    print("✗ аудиодвижок не запустился")
    exit(1)
}
print("✓ движок запущен, частота дискретизации \(Int(engine.outputSampleRate)) Гц")

let before = engine.renderedSampleCount
Thread.sleep(forTimeInterval: 0.4)
let after = engine.renderedSampleCount
let rendered = after - before
let expected = UInt64(engine.outputSampleRate * 0.4)

if rendered > expected / 2 {
    print("✓ CoreAudio тянет граф: \(rendered) сэмплов за 0.4 с (ожидалось ≈\(expected))")
} else {
    print("✗ граф не рендерится: \(rendered) сэмплов за 0.4 с")
    exit(1)
}

let am = ChordLibrary.voicing(for: Chord(root: 9, quality: .minor))

// Три инструмента подряд — разницу должно быть слышно.
for model in GuitarModel.presets {
    print("▸ \(model.kind.title): \(model.kind.subtitle)")
    engine.model = model
    engine.strum(voicing: am, direction: .down, articulation: .normalDown)
    Thread.sleep(forTimeInterval: 0.55)
    engine.strum(voicing: am, direction: .up, articulation: .normalUp)
    Thread.sleep(forTimeInterval: 0.55)
    engine.strum(voicing: am, direction: .down, articulation: .mutedDown)
    Thread.sleep(forTimeInterval: 0.5)
    engine.dampAll()
    Thread.sleep(forTimeInterval: 0.35)
}

// Один и тот же бой без «живой руки» и с ней.
engine.model = .acoustic
for (label, humanize) in [("механически ровно", 0.0), ("живая рука", 0.85)] {
    print("▸ бой, \(label)")
    engine.humanize = humanize
    for _ in 0..<6 {
        engine.strum(voicing: am, direction: .down, articulation: .normalDown)
        Thread.sleep(forTimeInterval: 0.24)
        engine.strum(voicing: am, direction: .up, articulation: .normalUp)
        Thread.sleep(forTimeInterval: 0.24)
    }
    engine.dampAll()
    Thread.sleep(forTimeInterval: 0.4)
}

engine.stop()
print("✓ аудиотракт работает")
