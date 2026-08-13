import Foundation

// Офлайн-проверка синтезатора: строй, затухание, отсутствие клиппинга и NaN.
// Собирается вместе с исходниками Audio/ и Music/ — см. Tools/check.sh

let sampleRate: Double = 48000

/// Оценка основного тона методом YIN. Обычная автокорреляция здесь ошибается на октаву:
/// у затухающей струны корреляция на двойном периоде не ниже, чем на истинном.
func estimateFrequency(_ samples: [Float], sampleRate: Double) -> Double {
    let minLag = max(2, Int(sampleRate / 1200))
    let maxLag = min(Int(sampleRate / 60), samples.count / 2)
    guard maxLag > minLag else { return 0 }

    let window = samples.count - maxLag
    guard window > maxLag else { return 0 }

    // Функция разности.
    var difference = [Double](repeating: 0, count: maxLag + 1)
    for lag in 1...maxLag {
        var sum: Double = 0
        for i in 0..<window {
            let delta = Double(samples[i]) - Double(samples[i + lag])
            sum += delta * delta
        }
        difference[lag] = sum
    }

    // Кумулятивная нормализация: убирает предпочтение больших периодов.
    var normalized = [Double](repeating: 1, count: maxLag + 1)
    var running: Double = 0
    for lag in 1...maxLag {
        running += difference[lag]
        normalized[lag] = running > 0 ? difference[lag] * Double(lag) / running : 1
    }

    // Первый провал ниже порога — истинный период, а не его кратное.
    let threshold = 0.15
    var best = -1
    var lag = minLag
    while lag <= maxLag {
        if normalized[lag] < threshold {
            while lag + 1 <= maxLag && normalized[lag + 1] < normalized[lag] { lag += 1 }
            best = lag
            break
        }
        lag += 1
    }
    if best < 0 {
        best = (minLag...maxLag).min { normalized[$0] < normalized[$1] } ?? minLag
    }

    // Параболическая интерполяция вокруг минимума — субсэмпловая точность периода.
    var period = Double(best)
    if best > 1 && best < maxLag {
        let y0 = normalized[best - 1], y1 = normalized[best], y2 = normalized[best + 1]
        let denom = 2 * (2 * y1 - y2 - y0)
        if denom != 0 { period = Double(best) + (y2 - y0) / denom }
    }
    return period > 0 ? sampleRate / period : 0
}

func cents(_ measured: Double, _ target: Double) -> Double {
    guard measured > 0, target > 0 else { return .infinity }
    return 1200 * log2(measured / target)
}

func render(_ synth: GuitarSynth, frames: Int) -> [Float] {
    let left = UnsafeMutablePointer<Float>.allocate(capacity: frames)
    let right = UnsafeMutablePointer<Float>.allocate(capacity: frames)
    defer { left.deallocate(); right.deallocate() }
    left.initialize(repeating: 0, count: frames)
    right.initialize(repeating: 0, count: frames)

    // Рендерим блоками по 512 — как настоящий аудиопоток.
    var offset = 0
    let block = 512
    while offset < frames {
        let n = min(block, frames - offset)
        synth.render(left: left + offset, right: right + offset, frames: n)
        offset += n
    }
    return Array(UnsafeBufferPointer(start: left, count: frames))
}

var failures = 0
func check(_ condition: Bool, _ message: String) {
    if condition {
        print("  ✓ \(message)")
    } else {
        print("  ✗ \(message)")
        failures += 1
    }
}

// MARK: 1. Строй открытых струн

print("Строй открытых струн (допуск ±6 центов):")
for (index, midi) in Pitch.standardTuning.enumerated() {
    let synth = GuitarSynth(sampleRate: sampleRate)
    synth.gain = 1.0
    let target = Pitch.frequency(midi: Double(midi))

    var event = StringEvent()
    event.atSample = 0
    event.string = Int32(index)
    event.frequency = Float(target)
    event.velocity = 0.9
    event.brightness = 0.55
    event.sustain = 4.0
    event.kind = .pluck
    synth.queue.push(event)

    // Пропускаем атаку и анализируем установившийся участок.
    _ = render(synth, frames: Int(sampleRate * 0.15))
    let steady = render(synth, frames: Int(sampleRate * 0.25))

    let measured = estimateFrequency(steady, sampleRate: sampleRate)
    let deviation = cents(measured, target)
    let name = Pitch.name(midi % 12)
    check(abs(deviation) < 6,
          String(format: "струна %d (%@): цель %.2f Гц, измерено %.2f Гц, отклонение %+.2f цента",
                 6 - index, name, target, measured, deviation))
}

// MARK: 2. Строй прижатых нот по всему грифу

print("\nПрижатые ноты (струна 1, лады 1…12):")
var maxDeviation = 0.0
for fret in 1...12 {
    let synth = GuitarSynth(sampleRate: sampleRate)
    synth.gain = 1.0
    let midi = Pitch.standardTuning[5] + fret
    let target = Pitch.frequency(midi: Double(midi))

    var event = StringEvent()
    event.string = 5
    event.frequency = Float(target)
    event.velocity = 0.9
    event.brightness = 0.55
    event.sustain = 4.0
    event.kind = .pluck
    synth.queue.push(event)

    _ = render(synth, frames: Int(sampleRate * 0.10))
    let steady = render(synth, frames: Int(sampleRate * 0.2))
    let deviation = cents(estimateFrequency(steady, sampleRate: sampleRate), target)
    maxDeviation = max(maxDeviation, abs(deviation))
}
check(maxDeviation < 6, String(format: "наибольшее отклонение по грифу: %.2f цента", maxDeviation))

// MARK: 3. Затухание и глушение

print("\nОгибающая:")
do {
    let synth = GuitarSynth(sampleRate: sampleRate)
    synth.gain = 1.0
    var event = StringEvent()
    event.string = 0
    event.frequency = Float(Pitch.frequency(midi: 40))
    event.velocity = 0.9
    event.sustain = 3.5
    event.brightness = 0.55
    event.kind = .pluck
    synth.queue.push(event)

    func peak(_ buffer: [Float]) -> Float { buffer.reduce(0) { max($0, abs($1)) } }
    let attack = peak(render(synth, frames: Int(sampleRate * 0.05)))
    let after1s = peak(render(synth, frames: Int(sampleRate * 0.95)))

    check(attack > 0.05, String(format: "щипок даёт сигнал: пик %.3f", attack))
    check(after1s < attack, String(format: "звук затухает: через 1 с пик %.3f", after1s))
    check(after1s > 0.0005, "струна ещё звучит через секунду (сустейн не обрывается)")

    // Глушение должно убить звук быстро. Сравниваем уровень до и через 0.4 с после —
    // пик по всему окну мерил бы громкость в его начале и ничего бы не показал.
    var damp = StringEvent()
    damp.string = 0
    damp.sustain = 0.12
    damp.kind = .damp
    synth.queue.push(damp)
    let beforeDamp = peak(render(synth, frames: Int(sampleRate * 0.01)))
    _ = render(synth, frames: Int(sampleRate * 0.4))
    let afterDamp = peak(render(synth, frames: Int(sampleRate * 0.05)))
    check(afterDamp < beforeDamp * 0.02,
          String(format: "глушение гасит струну за 0.4 с: %.5f → %.5f", beforeDamp, afterDamp))
}

// MARK: 4. Полный аккорд: без клиппинга и NaN

print("\nАккорд целиком:")
do {
    let synth = GuitarSynth(sampleRate: sampleRate)
    synth.gain = 0.5
    let voicing = ChordLibrary.voicing(for: Chord(root: 4, quality: .minor))  // Em, все шесть струн
    let step = UInt64(sampleRate * 0.017)

    for (position, string) in voicing.soundingStrings.enumerated() {
        guard let midi = voicing.midiNote(string: string) else { continue }
        var event = StringEvent()
        event.atSample = step * UInt64(position)
        event.string = Int32(string)
        event.frequency = Float(Pitch.frequency(midi: Double(midi)))
        event.velocity = 0.95
        event.brightness = 0.58
        event.sustain = 3.6
        event.kind = .pluck
        synth.queue.push(event)
    }

    let buffer = render(synth, frames: Int(sampleRate * 2.0))
    let hasNaN = buffer.contains { !$0.isFinite }
    let peak = buffer.reduce(0) { max($0, abs($1)) }
    var rms = 0.0
    for s in buffer { rms += Double(s) * Double(s) }
    rms = (rms / Double(buffer.count)).squareRoot()

    check(!hasNaN, "нет NaN и бесконечностей")
    check(peak <= 1.0, String(format: "нет клиппинга: пик %.3f", peak))
    check(peak > 0.2, String(format: "аккорд звучит громко: пик %.3f", peak))
    check(rms > 0.01, String(format: "средняя энергия: %.4f", rms))
}

// MARK: 5. Точность планирования во времени

print("\nПланирование событий:")
do {
    let synth = GuitarSynth(sampleRate: sampleRate)
    synth.gain = 1.0
    let delaySamples = UInt64(sampleRate * 0.05)
    var event = StringEvent()
    event.atSample = delaySamples
    event.string = 3
    event.frequency = Float(Pitch.frequency(midi: 55))
    event.velocity = 0.9
    event.sustain = 3.0
    event.brightness = 0.55
    event.kind = .pluck
    synth.queue.push(event)

    let buffer = render(synth, frames: Int(sampleRate * 0.2))
    let onset = buffer.firstIndex { abs($0) > 0.01 } ?? -1
    let errorSamples = abs(onset - Int(delaySamples))
    check(onset >= 0 && errorSamples <= 2,
          "удар начинается в запланированном сэмпле (\(onset) против \(delaySamples))")
}

// MARK: 6. Аппликатуры: правильные ли ноты

print("\nАппликатуры аккордов:")
do {
    var wrong: [String] = []
    for root in 0..<12 {
        for quality in ChordQuality.allCases {
            let chord = Chord(root: root, quality: quality)
            let voicing = ChordLibrary.voicing(for: chord)
            let allowed = chord.pitchClasses
            let sounding = Set(voicing.soundingStrings.compactMap { voicing.midiNote(string: $0) }.map { $0 % 12 })
            let required = Set(quality.essentialIntervals.map { (root + $0) % 12 })

            if !sounding.isSubset(of: allowed) {
                wrong.append("\(chord.name): чужие ноты \(sounding.subtracting(allowed).sorted())")
            } else if !required.isSubset(of: sounding) {
                wrong.append("\(chord.name): не хватает \(required.subtracting(sounding).sorted())")
            } else if voicing.soundingStrings.count < 3 && quality != .power {
                wrong.append("\(chord.name): звучит меньше трёх струн")
            }
        }
    }
    check(wrong.isEmpty, "все \(12 * ChordQuality.allCases.count) аккордов состоят из верных ступеней")
    for problem in wrong.prefix(12) { print("      · \(problem)") }
    if wrong.count > 12 { print("      · …ещё \(wrong.count - 12)") }
}

// MARK: 7. Удобство аппликатур

print("\nУдобство аппликатур:")
do {
    var tooHigh: [String] = []
    var tooWide: [String] = []
    for root in 0..<12 {
        for quality in ChordQuality.allCases {
            let chord = Chord(root: root, quality: quality)
            let voicing = ChordLibrary.voicing(for: chord)
            if voicing.maxFret > 15 { tooHigh.append("\(chord.name) → \(voicing.maxFret) лад") }
            let pressed = voicing.frets.compactMap { $0 }.filter { $0 > 0 }
            if let low = pressed.min(), let high = pressed.max(), high - low > 3 {
                tooWide.append("\(chord.name) → растяжка \(high - low)")
            }
        }
    }
    check(tooHigh.isEmpty, "ни один аккорд не уходит выше 15 лада")
    for problem in tooHigh.prefix(6) { print("      · \(problem)") }
    check(tooWide.isEmpty, "растяжка левой руки не больше 3 ладов")
    for problem in tooWide.prefix(6) { print("      · \(problem)") }
}

// MARK: 8. Модели гитар

print("\nМодели гитар:")
for model in GuitarModel.presets {
    var worst = 0.0
    for (stringIndex, midi) in [(0, 40), (3, 55), (5, 64)] {
        let synth = GuitarSynth(sampleRate: sampleRate)
        synth.gain = 1.0
        let target = Pitch.frequency(midi: Double(midi))

        var event = StringEvent()
        event.string = Int32(stringIndex)
        event.frequency = Float(target)
        event.velocity = 0.9
        event.brightness = Float(model.brightness)
        event.pickPosition = Float(model.pickPosition)
        event.sustain = Float(model.sustain(forString: stringIndex))
        event.kind = .pluck
        synth.queue.push(event)

        _ = render(synth, frames: Int(sampleRate * 0.10))
        let steady = render(synth, frames: Int(sampleRate * 0.25))
        worst = max(worst, abs(cents(estimateFrequency(steady, sampleRate: sampleRate), target)))
    }
    check(worst < 6, String(format: "%@ строит: отклонение до %.2f цента", model.kind.title, worst))

    // Тонкие струны обязаны гаснуть быстрее толстых — иначе это не гитара.
    let sustains = (0..<6).map { model.sustain(forString: $0) }
    let monotonic = zip(sustains, sustains.dropFirst()).allSatisfy { $0 >= $1 }
    check(monotonic, String(format: "%@: сустейн падает от баса к верхам (%.1f → %.1f с)",
                            model.kind.title, sustains.first ?? 0, sustains.last ?? 0))
}

// MARK: 9. Быстрые повторные удары

print("\nБыстрый ритм (нахлёст ударов):")
do {
    let synth = GuitarSynth(sampleRate: sampleRate)
    synth.gain = 0.5
    synth.drive = 0.22
    let voicing = ChordLibrary.voicing(for: Chord(root: 4, quality: .minor))
    let model = GuitarModel.electric

    // Шестнадцатые в темпе 140 — быстрее человек по струнам не бьёт.
    var stroke = 0
    while stroke < 16 {
        let strokeStart = UInt64(Double(stroke) * 0.107 * sampleRate)
        for (position, string) in voicing.soundingStrings.enumerated() {
            guard let midi = voicing.midiNote(string: string) else { continue }
            var event = StringEvent()
            event.atSample = strokeStart + UInt64(Double(position) * 0.014 * sampleRate)
            event.string = Int32(string)
            event.frequency = Float(Pitch.frequency(midi: Double(midi)))
            event.velocity = 0.95
            event.brightness = Float(model.brightness)
            event.pickPosition = Float(model.pickPosition)
            event.sustain = Float(model.sustain(forString: string))
            event.kind = .pluck
            synth.queue.push(event)
        }
        stroke += 1
        // Очередь конечна: подкачиваем её порциями, как это делает главный поток.
        if stroke % 4 == 0 { _ = render(synth, frames: Int(sampleRate * 0.428)) }
    }
    let tail = render(synth, frames: Int(sampleRate * 1.0))

    let hasNaN = tail.contains { !$0.isFinite }
    let peak = tail.reduce(0) { max($0, abs($1)) }
    check(!hasNaN, "повторные удары не разносят модель в NaN")
    check(peak <= 1.0, String(format: "перегруз держится в пределах шкалы: пик %.3f", peak))
}

// MARK: 10. Перестановка аккордов

print("\nПерестановка аккордов:")
do {
    var pads = Preferences.defaultPads
    let keysBefore = pads.map(\.keyCode)
    let chordsBefore = pads.map(\.source)

    // Тянем первый аккорд на четвёртое место.
    pads.moveChord(from: pads[0].id, to: pads[3].id)

    check(pads.map(\.keyCode) == keysBefore, "клавиши остались на своих местах")
    check(pads[3].source == chordsBefore[0], "перетащенный аккорд встал на новое место")
    check(pads[0].source == chordsBefore[1] && pads[2].source == chordsBefore[3],
          "соседи сдвинулись на одну позицию")
    check(Set(pads.map(\.source)) == Set(chordsBefore), "ни один аккорд не потерялся")

    // Перетаскивание на себя ничего не меняет.
    var same = Preferences.defaultPads
    let snapshot = same.map(\.source)
    same.moveChord(from: same[2].id, to: same[2].id)
    check(same.map(\.source) == snapshot, "бросок на самого себя ничего не ломает")

    // Между рядами тоже работает: сетка — это один список.
    var across = Preferences.defaultPads
    let firstOfSecondRow = across[7].source
    across.moveChord(from: across[7].id, to: across[0].id)
    check(across[0].source == firstOfSecondRow, "аккорд переезжает между рядами")
}

// MARK: 11. Струны по одной

print("\nКлавиши струн:")
do {
    let prefs = Preferences()

    // Гитарная нумерация обратна внутренней: клавиша «1» — тонкая ми (индекс 5).
    check(prefs.stringIndex(for: KeyCodes.one) == 5, "клавиша 1 → первая струна (высокая ми)")
    check(prefs.stringIndex(for: KeyCodes.six) == 0, "клавиша 6 → шестая струна (низкая ми)")
    check(prefs.stringIndex(for: KeyCodes.three) == 3, "клавиша 3 → третья струна (соль)")
    check(prefs.stringIndex(for: KeyCodes.a) == nil, "чужая клавиша струну не дёргает")

    let roundTrip = (0..<6).allSatisfy { index in
        guard let code = prefs.stringKey(forStringIndex: index) else { return false }
        return prefs.stringIndex(for: code) == index
    }
    check(roundTrip, "клавиша и струна ссылаются друг на друга без сбоя нумерации")

    // Ноты под клавишами должны идти именно так, как на гитаре.
    let names = (1...6).compactMap { number -> String? in
        guard let index = prefs.stringIndex(for: prefs.stringKeys[number - 1]) else { return nil }
        return Pitch.name(Pitch.standardTuning[index] % 12)
    }
    check(names == ["E", "B", "G", "D", "A", "E"],
          "открытые ноты клавиш 1…6: \(names.joined(separator: " "))")
}

print("\nПопадание мышью по грифу:")
do {
    let size = CGSize(width: 900, height: 200)
    guard let geometry = FretboardGeometry(size: size) else {
        check(false, "геометрия грифа не построилась")
        exit(1)
    }

    let centersHit = (0..<6).allSatisfy { index in
        let point = CGPoint(x: geometry.board.midX, y: geometry.y(ofString: index))
        return geometry.stringIndex(at: point) == index
    }
    check(centersHit, "щелчок точно по струне попадает в неё")

    check(geometry.stringIndex(at: CGPoint(x: 5, y: geometry.y(ofString: 3))) == nil,
          "щелчок левее грифа струну не задевает")
    check(geometry.stringIndex(at: CGPoint(x: geometry.board.midX, y: 0)) == nil,
          "щелчок выше грифа струну не задевает")
    check(geometry.stringIndex(at: CGPoint(x: geometry.board.midX, y: size.height)) == nil,
          "щелчок ниже грифа струну не задевает")

    // Струну можно задеть и левее порожка — там она тоже натянута.
    check(geometry.stringIndex(at: CGPoint(x: geometry.stringStartX + 2,
                                           y: geometry.y(ofString: 2))) == 2,
          "струна ловится и до порожка")

    // Проводка сверху вниз обязана задеть все шесть — это и есть бой мышью.
    var touched: [Int] = []
    var y = geometry.y(ofString: 5)
    while y <= geometry.y(ofString: 0) {
        if let index = geometry.stringIndex(at: CGPoint(x: geometry.board.midX, y: y)),
           index != touched.last {
            touched.append(index)
        }
        y += 0.5
    }
    check(touched == [5, 4, 3, 2, 1, 0],
          "проводка сверху вниз задевает все струны по порядку: \(touched)")
}

print("")
if failures == 0 {
    print("Все проверки пройдены.")
} else {
    print("Провалено проверок: \(failures)")
    exit(1)
}
