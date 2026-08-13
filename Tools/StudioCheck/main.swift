import AVFoundation
import Foundation

// Проверка студии: раскладка проекта в события и сведение во все форматы файлов.

var failures = 0
func check(_ condition: Bool, _ message: String) {
    print(condition ? "  ✓ \(message)" : "  ✗ \(message)")
    if !condition { failures += 1 }
}

let sampleRate: Double = 48000
var song = Song()
song.name = "Проверка"
song.bpm = 120
song.humanize = 0.5

print("Раскладка проекта:")
let events = SongRenderer.events(for: song, model: .acoustic, sampleRate: sampleRate)
check(!events.isEmpty, "события построены: \(events.count) щипков")

let sorted = zip(events, events.dropFirst()).allSatisfy { $0.atSample <= $1.atSample }
check(sorted, "события идут по возрастанию времени")

// Четыре такта по восемь восьмых при 120 ударах — ровно 8 секунд.
let expected = song.duration
check(abs(expected - 8.0) < 0.001, String(format: "длительность проекта: %.2f с", expected))

let lastSample = Double(events.last?.atSample ?? 0) / sampleRate
check(lastSample < expected + 0.1, String(format: "последнее событие внутри проекта: %.2f с", lastSample))

// На сетку темпа ложится начало удара. Струны внутри удара намеренно разнесены —
// это и есть бой, поэтому события сначала группируются по ударам.
let slot = song.slotDuration
let plucks = events.filter { $0.kind == .pluck }.map { Double($0.atSample) / sampleRate }.sorted()

var strokes: [[Double]] = []
for time in plucks {
    if let last = strokes.last?.last, time - last < 0.06 {
        strokes[strokes.count - 1].append(time)
    } else {
        strokes.append([time])
    }
}

let onGrid = strokes.allSatisfy { stroke in
    guard let start = stroke.first else { return false }
    let position = start / slot
    return abs(position - position.rounded()) * slot < 0.02   // не больше 20 мс от доли
}
check(onGrid, "начала ударов ложатся на сетку восьмых (\(strokes.count) ударов)")

// Внутри удара струны обязаны идти вразбежку, иначе это рояль, а не гитара.
let spread = strokes.filter { $0.count > 2 }.map { ($0.last ?? 0) - ($0.first ?? 0) }
let averageSpread = spread.isEmpty ? 0 : spread.reduce(0, +) / Double(spread.count)
check(averageSpread > 0.02 && averageSpread < 0.2,
      String(format: "струны в ударе разнесены: в среднем %.0f мс", averageSpread * 1000))

print("\nСведение в файл:")
let folder = FileManager.default.temporaryDirectory.appendingPathComponent("gk-export-test")
try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

for format in AudioFileFormat.allCases {
    let url = folder.appendingPathComponent("test.\(format.fileExtension)")
    try? FileManager.default.removeItem(at: url)
    do {
        let start = Date()
        _ = try SongExporter.export(song: song, model: .acoustic, to: url,
                                    format: format, sampleRate: sampleRate)
        let elapsed = Date().timeIntervalSince(start)

        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        let file = try AVAudioFile(forReading: url)
        let duration = Double(file.length) / file.fileFormat.sampleRate

        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)) else {
            check(false, "\(format.title): буфер не создался"); continue
        }
        try file.read(into: buffer)
        var peak: Float = 0
        if let channels = buffer.floatChannelData {
            for channel in 0..<Int(buffer.format.channelCount) {
                for frame in 0..<Int(buffer.frameLength) {
                    peak = max(peak, abs(channels[channel][frame]))
                }
            }
        }

        let expectedLength = song.duration + GuitarModel.acoustic.sustain + 1.0
        let lengthOK = abs(duration - expectedLength) < 0.5
        check(lengthOK && peak > 0.05 && size > 2000,
              String(format: "%@: %.2f с, пик %.3f, %d КБ, свелось за %.2f с",
                     format.title, duration, peak, size / 1024, elapsed))
        check(elapsed < song.duration,
              String(format: "%@ сводится быстрее реального времени", format.title))
    } catch {
        check(false, "\(format.title): \(error.localizedDescription)")
    }
}

print("\nТабулатура:")
do {
    var tabSong = Song()
    tabSong.bpm = 120
    // Такт из четырёх нот по табам: 5-я струна лады 0,2,3 и 4-я струна лад 2.
    var bar = Bar(chord: .degree(index: 0, seventh: false), view: .tab)
    bar.slots[0] = [.note(string: 1, fret: 0)]
    bar.slots[2] = [.note(string: 1, fret: 2)]
    bar.slots[4] = [.note(string: 1, fret: 3)]
    bar.slots[6] = [.note(string: 2, fret: 2)]
    tabSong.bars = [bar]

    let tabEvents = SongRenderer.events(for: tabSong, model: .acoustic, sampleRate: sampleRate)
        .filter { $0.kind == .pluck }
    check(tabEvents.count == 4, "четыре ноты табулатуры дают четыре щипка: \(tabEvents.count)")

    // Ноты обязаны звучать ровно теми высотами, что записаны в табах.
    let expectedMidi = [45 + 0, 45 + 2, 45 + 3, 50 + 2]
    let expectedHz = expectedMidi.map { Pitch.frequency(midi: Double($0)) }
    let actualHz = tabEvents.sorted { $0.atSample < $1.atSample }.map { Double($0.frequency) }
    let pitchOK = zip(expectedHz, actualHz).allSatisfy { abs(1200 * log2($1 / $0)) < 5 }
    check(pitchOK, "высоты совпадают с ладами: " + actualHz.map { String(format: "%.1f", $0) }.joined(separator: " "))

    // Табулатура не зависит от аккорда такта.
    var other = tabSong
    other.bars[0].chord = .fixed(Chord(root: 7, quality: .major))
    let otherEvents = SongRenderer.events(for: other, model: .acoustic, sampleRate: sampleRate)
        .filter { $0.kind == .pluck }
        .sorted { $0.atSample < $1.atSample }
        .map { Double($0.frequency) }
    let independent = zip(actualHz, otherEvents).allSatisfy { abs(1200 * log2($1 / $0)) < 8 }
    check(independent, "смена аккорда такта не трогает ноты табулатуры")
}

print("\nПеребор по аккорду:")
do {
    var arp = Song()
    arp.bpm = 120
    arp.key = MusicalKey(tonic: 9, scale: .minor)
    // Am по аппликатуре x02210: струны 5,4,3 дают A, E, A.
    var bar = Bar(chord: .fixed(Chord(root: 9, quality: .minor)), view: .tab)
    bar.slots[0] = [.pluck(string: 1)]
    bar.slots[2] = [.pluck(string: 2)]
    bar.slots[4] = [.pluck(string: 3)]
    bar.slots[6] = [.pluck(string: 0)]   // шестая струна в Am заглушена
    arp.bars = [bar]

    let picked = SongRenderer.events(for: arp, model: .acoustic, sampleRate: sampleRate)
        .filter { $0.kind == .pluck }
        .sorted { $0.atSample < $1.atSample }

    check(picked.count == 3, "заглушённая в аккорде струна молчит: \(picked.count) ноты из 4 поставленных")

    let amVoicing = ChordLibrary.voicing(for: Chord(root: 9, quality: .minor))
    let expected = [1, 2, 3].compactMap { amVoicing.midiNote(string: $0) }.map { Pitch.frequency(midi: Double($0)) }
    let actual = picked.map { Double($0.frequency) }
    let matches = zip(expected, actual).allSatisfy { abs(1200 * log2($1 / $0)) < 8 }
    check(matches, "перебор звучит нотами аккорда: " + actual.map { String(format: "%.1f", $0) }.joined(separator: " "))

    // Сменили аккорд — перебор обязан поехать за ним.
    var moved = arp
    moved.bars[0].chord = .fixed(Chord(root: 0, quality: .major))
    let movedHz = SongRenderer.events(for: moved, model: .acoustic, sampleRate: sampleRate)
        .filter { $0.kind == .pluck }
        .sorted { $0.atSample < $1.atSample }
        .map { Double($0.frequency) }
    let cVoicing = ChordLibrary.voicing(for: Chord(root: 0, quality: .major))
    let cExpected = [1, 2, 3].compactMap { cVoicing.midiNote(string: $0) }.map { Pitch.frequency(midi: Double($0)) }
    let followed = zip(cExpected, movedHz).allSatisfy { abs(1200 * log2($1 / $0)) < 8 }
    check(followed, "смена аккорда меняет ноты перебора: " + movedHz.map { String(format: "%.1f", $0) }.joined(separator: " "))
}

print("\nСила удара:")
do {
    var loud = Song()
    loud.bars = [Bar(chord: .degree(index: 0, seventh: false),
                     slots: [[.strum(.down, velocity: 1.4)], [], [], [], [], [], [], []])]
    var quiet = loud
    quiet.bars[0].slots[0] = [.strum(.down, velocity: 0.3)]

    func peakVelocity(_ song: Song) -> Float {
        SongRenderer.events(for: song, model: .acoustic, sampleRate: sampleRate)
            .filter { $0.kind == .pluck }
            .reduce(0) { max($0, $1.velocity) }
    }
    let loudPeak = peakVelocity(loud)
    let quietPeak = peakVelocity(quiet)
    check(loudPeak > quietPeak * 1.8,
          String(format: "громкий удар сильнее тихого: %.2f против %.2f", loudPeak, quietPeak))
}

print("\nНастраиваемая сетка:")
do {
    var grid = Song()
    grid.bpm = 120
    check(grid.slotsPerBar == 8, "4/4 восьмыми — восемь делений в такте: \(grid.slotsPerBar)")
    check(abs(grid.duration - 8.0) < 0.001, String(format: "длительность: %.2f с", grid.duration))

    // Шестнадцатые: делений вдвое больше, а звучит такт столько же.
    grid.division = .sixteenth
    grid.normalizeBars()
    check(grid.slotsPerBar == 16, "шестнадцатыми — шестнадцать делений: \(grid.slotsPerBar)")
    check(grid.bars.allSatisfy { $0.slotCount == 16 }, "такты подогнаны под новую сетку")
    check(abs(grid.duration - 8.0) < 0.001,
          String(format: "такт звучит столько же: %.2f с", grid.duration))

    // Вальс: три доли в такте.
    var waltz = Song()
    waltz.beatsPerBar = 3
    waltz.normalizeBars()
    check(waltz.slotsPerBar == 6, "3/4 восьмыми — шесть делений: \(waltz.slotsPerBar)")
    check(waltz.bars.allSatisfy { $0.slotCount == 6 }, "такты вальса укоротились")

    // Триоли.
    var triplet = Song()
    triplet.division = .triplet
    triplet.normalizeBars()
    check(triplet.slotsPerBar == 12, "триолями — двенадцать делений: \(triplet.slotsPerBar)")

    // Сжатие такта не должно ломать раскладку.
    let shrunk = SongRenderer.events(for: waltz, model: .acoustic, sampleRate: sampleRate)
    check(!shrunk.isEmpty, "укороченный такт всё ещё играется: \(shrunk.count) щипков")

    // Такты разной длины считаются накопительно, а не как индекс × длина.
    var mixed = Song()
    mixed.bars[0].resize(to: 4)
    let mixedEvents = SongRenderer.events(for: mixed, model: .acoustic, sampleRate: sampleRate)
        .sorted { $0.atSample < $1.atSample }
    let secondBarStart = Double(mixed.bars[0].slotCount) * mixed.slotDuration
    let firstOfSecondBar = mixedEvents.first { Double($0.atSample) / sampleRate > secondBarStart - 0.01 }
    check(firstOfSecondBar != nil, "такты разной длины идут подряд без разрывов")
}

print("\nГотовые бои:")
do {
    check(RhythmLibrary.all.count >= 10, "в библиотеке \(RhythmLibrary.all.count) рисунков")

    // Каждый рисунок обязан ложиться в свою сетку и звучать.
    var broken: [String] = []
    for pattern in RhythmLibrary.all {
        var test = Song()
        test.beatsPerBar = pattern.beatsPerBar
        test.division = pattern.division
        test.normalizeBars()
        guard pattern.slots.count == test.slotsPerBar else {
            broken.append("\(pattern.name): \(pattern.slots.count) долей вместо \(test.slotsPerBar)")
            continue
        }
        test.bars = [Bar(chord: .degree(index: 0, seventh: false), slots: pattern.slots)]
        let sound = SongRenderer.events(for: test, model: .acoustic, sampleRate: sampleRate)
            .filter { $0.kind == .pluck }
        if sound.isEmpty { broken.append("\(pattern.name): не звучит") }
    }
    check(broken.isEmpty, "все рисунки укладываются в сетку и звучат")
    for problem in broken.prefix(5) { print("      · \(problem)") }

    // «Восьмёрка» — восемь движений руки за такт.
    if let eight = RhythmLibrary.all.first(where: { $0.name == "Восьмёрка" }) {
        let strokes = eight.slots.flatMap { $0 }.filter { $0.isStrum }.count
        check(strokes == 8, "в «Восьмёрке» восемь ударов: \(strokes)")
        let downs = eight.slots.flatMap { $0 }.filter {
            if case .strum(let direction, _) = $0.kind { return direction == .down }
            return false
        }.count
        check(downs == 4, "чередование вниз-вверх: \(downs) вниз из 8")
    }
}

print("\nСохранение проекта:")
do {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("test.guitarkeys")
    let encoder = JSONEncoder()
    let data = try encoder.encode(song)
    try data.write(to: url)
    let restored = try JSONDecoder().decode(Song.self, from: Data(contentsOf: url))
    check(restored == song, "проект сохраняется и читается без потерь")
    check(restored.bars.count == song.bars.count, "такты на месте: \(restored.bars.count)")
    try? FileManager.default.removeItem(at: url)
}

try? FileManager.default.removeItem(at: folder)
print(failures == 0 ? "\nСтудия работает.\n" : "\nПровалено: \(failures)\n")
exit(failures == 0 ? 0 : 1)
