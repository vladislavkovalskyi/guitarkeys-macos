import Foundation

/// Подбор аппликатуры для аккорда: сначала открытые формы, затем подвижные (баррэ).
enum ChordLibrary {

    // MARK: Открытые формы

    /// Проверенные открытые аппликатуры. Ключ — основной тон + вид аккорда.
    private static let openShapes: [Chord: [Int?]] = [
        // C
        Chord(root: 0, quality: .major): [nil, 3, 2, 0, 1, 0],
        Chord(root: 0, quality: .maj7):  [nil, 3, 2, 0, 0, 0],
        Chord(root: 0, quality: .dom7):  [nil, 3, 2, 3, 1, 0],
        // D
        Chord(root: 2, quality: .major): [nil, nil, 0, 2, 3, 2],
        Chord(root: 2, quality: .minor): [nil, nil, 0, 2, 3, 1],
        Chord(root: 2, quality: .dom7):  [nil, nil, 0, 2, 1, 2],
        Chord(root: 2, quality: .min7):  [nil, nil, 0, 2, 1, 1],
        Chord(root: 2, quality: .maj7):  [nil, nil, 0, 2, 2, 2],
        Chord(root: 2, quality: .sus2):  [nil, nil, 0, 2, 3, 0],
        Chord(root: 2, quality: .sus4):  [nil, nil, 0, 2, 3, 3],
        // E
        Chord(root: 4, quality: .major): [0, 2, 2, 1, 0, 0],
        Chord(root: 4, quality: .minor): [0, 2, 2, 0, 0, 0],
        Chord(root: 4, quality: .dom7):  [0, 2, 0, 1, 0, 0],
        Chord(root: 4, quality: .min7):  [0, 2, 0, 0, 0, 0],
        Chord(root: 4, quality: .maj7):  [0, 2, 1, 1, 0, 0],
        Chord(root: 4, quality: .sus4):  [0, 2, 2, 2, 0, 0],
        // G
        Chord(root: 7, quality: .major): [3, 2, 0, 0, 0, 3],
        Chord(root: 7, quality: .dom7):  [3, 2, 0, 0, 0, 1],
        Chord(root: 7, quality: .maj7):  [3, 2, 0, 0, 0, 2],
        Chord(root: 7, quality: .sus4):  [3, 3, 0, 0, 1, 3],
        // A
        Chord(root: 9, quality: .major): [nil, 0, 2, 2, 2, 0],
        Chord(root: 9, quality: .minor): [nil, 0, 2, 2, 1, 0],
        Chord(root: 9, quality: .dom7):  [nil, 0, 2, 0, 2, 0],
        Chord(root: 9, quality: .min7):  [nil, 0, 2, 0, 1, 0],
        Chord(root: 9, quality: .maj7):  [nil, 0, 2, 1, 2, 0],
        Chord(root: 9, quality: .sus2):  [nil, 0, 2, 2, 0, 0],
        Chord(root: 9, quality: .sus4):  [nil, 0, 2, 2, 3, 0],
        // B
        Chord(root: 11, quality: .dom7): [nil, 2, 1, 2, 0, 2],
    ]

    // MARK: Подвижные формы

    /// Форма с основным тоном на 6-й струне («E-shape»). Смещения ладов от лада основного тона.
    private static func eShape(_ quality: ChordQuality) -> [Int?]? {
        switch quality {
        case .major: return [0, 2, 2, 1, 0, 0]
        case .minor: return [0, 2, 2, 0, 0, 0]
        case .dom7:  return [0, 2, 0, 1, 0, 0]
        case .min7:  return [0, 2, 0, 0, 0, 0]
        case .maj7:  return [0, 2, 1, 1, 0, 0]
        case .sus4:  return [0, 2, 2, 2, 0, 0]
        case .power: return [0, 2, 2, nil, nil, nil]
        case .sus2, .dim, .m7b5: return nil // берём форму от 5-й струны
        }
    }

    /// Форма с основным тоном на 5-й струне («A-shape»).
    private static func aShape(_ quality: ChordQuality) -> [Int?]? {
        switch quality {
        case .major: return [nil, 0, 2, 2, 2, 0]
        case .minor: return [nil, 0, 2, 2, 1, 0]
        case .dom7:  return [nil, 0, 2, 0, 2, 0]
        case .min7:  return [nil, 0, 2, 0, 1, 0]
        case .maj7:  return [nil, 0, 2, 1, 2, 0]
        case .sus2:  return [nil, 0, 2, 2, 0, 0]
        case .sus4:  return [nil, 0, 2, 2, 3, 0]
        case .dim:   return [nil, 0, 1, 2, 1, nil]
        case .m7b5:  return [nil, 0, 1, 0, 1, nil]
        case .power: return [nil, 0, 2, 2, nil, nil]
        }
    }

    /// Форма с основным тоном на 4-й струне («D-shape»). Нужна там, где формы от нижних
    /// струн уводят руку за 12-й лад.
    private static func dShape(_ quality: ChordQuality) -> [Int?]? {
        switch quality {
        case .sus2:  return [nil, nil, 0, 2, 3, 0]
        case .dim:   return [nil, nil, 0, 1, 3, 1]
        case .m7b5:  return [nil, nil, 0, 1, 1, 1]
        default: return nil
        }
    }

    /// Лад основного тона для формы от 6-й струны (открытая E = 0).
    private static func rootFretOnSixth(_ root: Int) -> Int { ((root - 4) % 12 + 12) % 12 }
    /// Лад основного тона для формы от 5-й струны (открытая A = 0).
    private static func rootFretOnFifth(_ root: Int) -> Int { ((root - 9) % 12 + 12) % 12 }
    /// Лад основного тона для формы от 4-й струны (открытая D = 0).
    private static func rootFretOnFourth(_ root: Int) -> Int { ((root - 2) % 12 + 12) % 12 }

    private static func shifted(_ shape: [Int?], by fret: Int) -> [Int?] {
        shape.map { $0.map { $0 + fret } }
    }

    // MARK: Резолвер

    private static var cache: [Chord: Voicing] = [:]
    private static let cacheLock = NSLock()

    /// Аппликатура аккорда: открытая форма, если она есть, иначе ближайшее баррэ.
    static func voicing(for chord: Chord) -> Voicing {
        cacheLock.lock()
        if let hit = cache[chord] { cacheLock.unlock(); return hit }
        cacheLock.unlock()

        let result = compute(chord)

        cacheLock.lock()
        cache[chord] = result
        cacheLock.unlock()
        return result
    }

    private static func compute(_ chord: Chord) -> Voicing {
        if let open = openShapes[chord] {
            return Voicing(open)
        }

        var candidates: [[Int?]] = []
        if let shape = eShape(chord.quality) {
            candidates.append(shifted(shape, by: rootFretOnSixth(chord.root)))
        }
        if let shape = aShape(chord.quality) {
            candidates.append(shifted(shape, by: rootFretOnFifth(chord.root)))
        }
        if let shape = dShape(chord.quality) {
            candidates.append(shifted(shape, by: rootFretOnFourth(chord.root)))
        }

        // Чем ниже самый дальний лад, тем удобнее рука и полнее звук.
        if let best = candidates.min(by: { maxFret($0) < maxFret($1) }) {
            return Voicing(best)
        }
        // Страховка: квинта от 6-й струны.
        return Voicing(shifted([0, 2, 2, nil, nil, nil], by: rootFretOnSixth(chord.root)))
    }

    private static func maxFret(_ frets: [Int?]) -> Int {
        frets.compactMap { $0 }.max() ?? 0
    }

    /// Все аккорды, для которых есть готовая открытая форма (для подсказок в интерфейсе).
    static var openChordCatalog: [Chord] { openShapes.keys.sorted { $0.name < $1.name } }
}
