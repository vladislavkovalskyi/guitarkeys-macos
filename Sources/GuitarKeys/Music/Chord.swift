import Foundation

// MARK: - Pitch

enum Pitch {
    /// Стандартный строй, от 6-й струны (низкое E2) к 1-й (высокое E4), в MIDI-нотах.
    static let standardTuning: [Int] = [40, 45, 50, 55, 59, 64]

    static let sharpNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    static let flatNames  = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]

    static func name(_ pitchClass: Int, flats: Bool = false) -> String {
        let pc = ((pitchClass % 12) + 12) % 12
        return flats ? flatNames[pc] : sharpNames[pc]
    }

    /// Частота ноты равномерно темперированного строя (A4 = 440 Гц).
    static func frequency(midi: Double) -> Double {
        440.0 * pow(2.0, (midi - 69.0) / 12.0)
    }
}

// MARK: - Аккорд

enum ChordQuality: String, Codable, CaseIterable, Hashable, Sendable {
    case major, minor, dom7, min7, maj7, sus2, sus4, dim, m7b5, power

    /// Суффикс в имени аккорда: C, Cm, C7, Cm7, Cmaj7…
    var suffix: String {
        switch self {
        case .major: return ""
        case .minor: return "m"
        case .dom7:  return "7"
        case .min7:  return "m7"
        case .maj7:  return "maj7"
        case .sus2:  return "sus2"
        case .sus4:  return "sus4"
        case .dim:   return "dim"
        case .m7b5:  return "m7b5"
        case .power: return "5"
        }
    }

    var displayName: String {
        switch self {
        case .major: return "мажор"
        case .minor: return "минор"
        case .dom7:  return "септаккорд"
        case .min7:  return "мин. септ"
        case .maj7:  return "большой септ"
        case .sus2:  return "sus2"
        case .sus4:  return "sus4"
        case .dim:   return "уменьшённый"
        case .m7b5:  return "полууменьш."
        case .power: return "квинта"
        }
    }

    /// Интервалы от основного тона в полутонах.
    var intervals: [Int] {
        switch self {
        case .major: return [0, 4, 7]
        case .minor: return [0, 3, 7]
        case .dom7:  return [0, 4, 7, 10]
        case .min7:  return [0, 3, 7, 10]
        case .maj7:  return [0, 4, 7, 11]
        case .sus2:  return [0, 2, 7]
        case .sus4:  return [0, 5, 7]
        case .dim:   return [0, 3, 6]
        case .m7b5:  return [0, 3, 6, 10]
        case .power: return [0, 7]
        }
    }
}

struct Chord: Codable, Hashable, Sendable {
    /// Основной тон как класс высоты: 0 = C … 11 = B.
    var root: Int
    var quality: ChordQuality

    var name: String { Pitch.name(root) + quality.suffix }

    func transposed(by semitones: Int) -> Chord {
        Chord(root: ((root + semitones) % 12 + 12) % 12, quality: quality)
    }

    /// Классы высоты, входящие в аккорд.
    var pitchClasses: Set<Int> {
        Set(quality.intervals.map { ((root + $0) % 12 + 12) % 12 })
    }
}

// MARK: - Аппликатура

/// Позиции на грифе для шести струн: 6-я … 1-я. `nil` — струна глушится.
struct Voicing: Hashable, Sendable {
    var frets: [Int?]

    init(_ frets: [Int?]) {
        precondition(frets.count == 6)
        self.frets = frets
    }

    /// MIDI-нота, звучащая на струне, или nil если струна заглушена.
    func midiNote(string: Int) -> Int? {
        guard let fret = frets[string] else { return nil }
        return Pitch.standardTuning[string] + fret
    }

    var soundingStrings: [Int] {
        (0..<6).filter { frets[$0] != nil }
    }

    /// Наименьший прижатый лад (для отрисовки окна грифа); 0 — только открытые.
    var minFret: Int {
        frets.compactMap { $0 }.filter { $0 > 0 }.min() ?? 0
    }

    var maxFret: Int {
        frets.compactMap { $0 }.max() ?? 0
    }

    /// Форма-баррэ прижимает несколько струн на одном ладу.
    var barreFret: Int? {
        let pressed = frets.compactMap { $0 }.filter { $0 > 0 }
        guard let low = pressed.min(), low > 0 else { return nil }
        let onLow = frets.enumerated().filter { $0.element == low }
        guard onLow.count >= 3 else { return nil }
        // Баррэ имеет смысл только если это самый низкий лад аккорда.
        let indices = onLow.map(\.offset)
        guard let first = indices.min(), let last = indices.max(), last - first >= 2 else { return nil }
        return low
    }
}

// MARK: - Тональность

enum ScaleType: String, Codable, CaseIterable, Sendable {
    case major, minor

    var displayName: String { self == .major ? "мажор" : "минор" }

    /// Ступени лада в полутонах от тоники.
    var degrees: [Int] {
        self == .major ? [0, 2, 4, 5, 7, 9, 11] : [0, 2, 3, 5, 7, 8, 10]
    }

    /// Трезвучия ступеней лада.
    var triadQualities: [ChordQuality] {
        self == .major
            ? [.major, .minor, .minor, .major, .major, .minor, .dim]
            : [.minor, .dim, .major, .minor, .minor, .major, .major]
    }

    /// Септаккорды ступеней лада.
    var seventhQualities: [ChordQuality] {
        self == .major
            ? [.maj7, .min7, .min7, .maj7, .dom7, .min7, .m7b5]
            : [.min7, .m7b5, .maj7, .min7, .min7, .maj7, .dom7]
    }

    static let romanMajor = ["I", "ii", "iii", "IV", "V", "vi", "vii°"]
    static let romanMinor = ["i", "ii°", "III", "iv", "v", "VI", "VII"]

    var romanNumerals: [String] { self == .major ? Self.romanMajor : Self.romanMinor }
}

struct MusicalKey: Codable, Hashable, Sendable {
    var tonic: Int = 0
    var scale: ScaleType = .major

    var name: String { Pitch.name(tonic) + " " + scale.displayName }

    /// Аккорд ступени лада (индекс 0…6).
    func chord(degree: Int, seventh: Bool) -> Chord {
        let i = ((degree % 7) + 7) % 7
        let root = (tonic + scale.degrees[i]) % 12
        let quality = seventh ? scale.seventhQualities[i] : scale.triadQualities[i]
        return Chord(root: root, quality: quality)
    }

    func roman(degree: Int, seventh: Bool) -> String {
        let i = ((degree % 7) + 7) % 7
        return scale.romanNumerals[i] + (seventh ? "7" : "")
    }
}
