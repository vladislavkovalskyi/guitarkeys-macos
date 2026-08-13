import Foundation

/// Что происходит на доле.
struct StepEvent: Codable, Hashable, Sendable, Identifiable {

    enum Kind: Codable, Hashable, Sendable {
        /// Удар по всему аккорду такта.
        case strum(direction: StrumDirection, muted: Bool)
        /// Щипок струны в аппликатуре аккорда — для перебора.
        case pluck(string: Int)
        /// Конкретный лад на конкретной струне: так переносят табулатуру.
        case note(string: Int, fret: Int)
    }

    var id = UUID()
    var kind: Kind
    /// Сила относительно обычной: 0.25 — еле слышно, 1.4 — акцент.
    var velocity: Double = 1.0

    init(id: UUID = UUID(), kind: Kind, velocity: Double = 1.0) {
        self.id = id
        self.kind = kind
        self.velocity = velocity
    }

    // Идентификатор не участвует в сравнении: две одинаковые доли — это одно и то же.
    static func == (lhs: StepEvent, rhs: StepEvent) -> Bool {
        lhs.kind == rhs.kind && abs(lhs.velocity - rhs.velocity) < 0.001
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
    }

    static func strum(_ direction: StrumDirection, muted: Bool = false, velocity: Double = 1) -> StepEvent {
        StepEvent(kind: .strum(direction: direction, muted: muted), velocity: velocity)
    }

    static func pluck(string: Int, velocity: Double = 1) -> StepEvent {
        StepEvent(kind: .pluck(string: string), velocity: velocity)
    }

    static func note(string: Int, fret: Int, velocity: Double = 1) -> StepEvent {
        StepEvent(kind: .note(string: string, fret: fret), velocity: velocity)
    }

    /// Струна, которой касается событие, если оно про одну струну.
    var string: Int? {
        switch kind {
        case .strum: return nil
        case .pluck(let string): return string
        case .note(let string, _): return string
        }
    }

    var isStrum: Bool {
        if case .strum = kind { return true }
        return false
    }

    var isMuted: Bool {
        if case .strum(_, let muted) = kind { return muted }
        return false
    }

    var symbolName: String {
        switch kind {
        case .strum(let direction, let muted):
            if muted { return direction == .down ? "arrow.down.to.line" : "arrow.up.to.line" }
            return direction == .down ? "arrow.down" : "arrow.up"
        case .pluck: return "circle.fill"
        case .note:  return "number"
        }
    }

    /// Короткая подпись для сетки.
    var caption: String {
        switch kind {
        case .strum: return ""
        case .pluck(let string): return "\(6 - string)"          // гитарная нумерация
        case .note(_, let fret): return "\(fret)"
        }
    }

    /// Совпадают по смыслу, но не обязательно по силе, — чтобы кисть стирала повтор.
    func matchesKind(of other: StepEvent) -> Bool { kind == other.kind }
}

/// Как показывать такт в студии.
enum BarView: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case strum   // одна строка: бой
    case tab     // шесть строк: табулатура

    var id: String { rawValue }
    var title: String { self == .strum ? "Бой" : "Табы" }
    var symbolName: String { self == .strum ? "arrow.up.arrow.down" : "tablecells" }
}

/// Такт: аккорд и восемь восьмых. На каждой доле может быть несколько событий —
/// например, аккорд по табулатуре из нескольких струн сразу.
struct Bar: Codable, Hashable, Identifiable, Sendable {
    static let slotCount = 8

    var id = UUID()
    var chord: PadSource
    var slots: [[StepEvent]]
    var view: BarView = .strum

    init(id: UUID = UUID(), chord: PadSource,
         slots: [[StepEvent]]? = nil, view: BarView = .strum) {
        self.id = id
        self.chord = chord
        self.view = view
        let given = slots ?? Array(repeating: [], count: Bar.slotCount)
        self.slots = given.count == Bar.slotCount
            ? given
            : Array(repeating: [], count: Bar.slotCount)
    }

    var isEmpty: Bool { slots.allSatisfy(\.isEmpty) }

    /// Удар на доле, если он там есть.
    func strumEvent(at slot: Int) -> StepEvent? {
        guard slots.indices.contains(slot) else { return nil }
        return slots[slot].first(where: \.isStrum)
    }

    /// Нота на конкретной струне и доле.
    func note(string: Int, at slot: Int) -> StepEvent? {
        guard slots.indices.contains(slot) else { return nil }
        return slots[slot].first { $0.string == string }
    }
}

/// Проект студии.
struct Song: Codable, Hashable, Sendable {
    var name: String = "Без названия"
    var bpm: Double = 92
    var key: MusicalKey = MusicalKey(tonic: 9, scale: .minor)
    var guitar: GuitarModel.Kind = .acoustic
    var humanize: Double = 0.55
    var bars: [Bar] = Song.starter

    /// Длительность восьмой в секундах.
    var slotDuration: TimeInterval { 60.0 / bpm / 2 }
    var totalSlots: Int { bars.count * Bar.slotCount }
    var duration: TimeInterval { Double(totalSlots) * slotDuration }

    func chord(inBar index: Int) -> Chord? {
        guard bars.indices.contains(index) else { return nil }
        switch bars[index].chord {
        case .degree(let degree, let seventh): return key.chord(degree: degree, seventh: seventh)
        case .fixed(let chord): return chord
        }
    }

    /// Заготовка: четыре такта с боем «вниз — вниз-вверх — вверх-вниз-вверх».
    static var starter: [Bar] {
        let pattern: [[StepEvent]] = [
            [.strum(.down)],
            [],
            [.strum(.down, velocity: 0.85)],
            [.strum(.up, velocity: 0.8)],
            [],
            [.strum(.up, velocity: 0.8)],
            [.strum(.down, velocity: 0.9)],
            [.strum(.up, velocity: 0.8)],
        ]
        // i — VI — III — VII: ходовая последовательность в миноре.
        return [0, 5, 2, 6].map { degree in
            Bar(chord: .degree(index: degree, seventh: false), slots: pattern)
        }
    }
}

/// Хранение проектов: ~/Music/GuitarKeys/Проекты (на iOS — Documents).
enum SongStore {
    static let fileExtension = "guitarkeys"

    static var folder: URL {
        #if os(macOS)
        let base = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GuitarKeys", isDirectory: true)
        #else
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        #endif
        return base.appendingPathComponent("Проекты", isDirectory: true)
    }

    static func url(for song: Song) -> URL {
        let safe = song.name.replacingOccurrences(of: "/", with: "-")
        return folder.appendingPathComponent("\(safe).\(fileExtension)")
    }

    @discardableResult
    static func save(_ song: Song) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let url = url(for: song)
        try encoder.encode(song).write(to: url, options: .atomic)
        return url
    }

    static func load(from url: URL) throws -> Song {
        try JSONDecoder().decode(Song.self, from: Data(contentsOf: url))
    }

    static func list() -> [URL] {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey])
        return (contents ?? [])
            .filter { $0.pathExtension == fileExtension }
            .sorted { left, right in
                let l = (try? left.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let r = (try? right.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return l > r
            }
    }
}
