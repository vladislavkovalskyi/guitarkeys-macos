import Foundation

// Небольшая пьеса для GuitarKeys: интро перебором на классике, бой на акустике,
// повтор на электрогитаре. Играется вживую, через колонки.

let engine = AudioEngine()
engine.volume = 0.55
engine.humanize = 0.72
engine.model = .classical
engine.start()

guard engine.isRunning else {
    print("не удалось запустить звук")
    exit(1)
}

let bpm = 92.0
let beat = 60.0 / bpm
let eighth = beat / 2

let started = Date()
var cursor = 0.0

/// Ждём по абсолютному времени, иначе задержки накапливаются и темп уплывает.
func wait(until offset: Double) {
    let delta = started.addingTimeInterval(offset).timeIntervalSinceNow
    if delta > 0 { Thread.sleep(forTimeInterval: delta) }
}

struct Strike {
    var direction: StrumDirection?
    var muted = false
    var velocity: Float = 1.0

    static let rest = Strike(direction: nil)
    static func down(_ v: Float) -> Strike { Strike(direction: .down, velocity: v) }
    static func up(_ v: Float) -> Strike { Strike(direction: .up, velocity: v) }
    static func chuk(_ v: Float) -> Strike { Strike(direction: .down, muted: true, velocity: v) }
    static func chukUp(_ v: Float) -> Strike { Strike(direction: .up, muted: true, velocity: v) }
}

func chord(_ root: Int, _ quality: ChordQuality) -> (name: String, voicing: Voicing) {
    let c = Chord(root: root, quality: quality)
    return (c.name, ChordLibrary.voicing(for: c))
}

let Am    = chord(9, .minor)
let F     = chord(5, .major)
let Fmaj7 = chord(5, .maj7)
let C     = chord(0, .major)
let G     = chord(7, .major)

func play(_ bar: (name: String, voicing: Voicing), pattern: [Strike], spread: Double) {
    // Гитарист приподнимает пальцы перед сменой аккорда — хвост предыдущего гаснет.
    engine.dampAll(release: 0.30)

    for (index, strike) in pattern.enumerated() {
        guard let direction = strike.direction else { continue }
        wait(until: cursor + Double(index) * eighth)

        var articulation: StrumArticulation
        switch (direction, strike.muted) {
        case (.down, false): articulation = .normalDown
        case (.up, false):   articulation = .normalUp
        case (.down, true):  articulation = .mutedDown
        case (.up, true):    articulation = .mutedUp
        }
        articulation.velocity *= strike.velocity
        articulation.spreadMs = direction == .down ? spread : spread * 0.65
        if strike.muted { articulation.spreadMs *= 0.55 }

        engine.strum(voicing: bar.voicing, direction: direction, articulation: articulation)
    }
    cursor += 4 * beat
}

func arpeggio(_ bar: (name: String, voicing: Voicing), order: [Int]) {
    engine.dampAll(release: 0.40)
    let strings = bar.voicing.soundingStrings
    for (index, position) in order.enumerated() {
        wait(until: cursor + Double(index) * eighth)
        let string = strings[min(position, strings.count - 1)]
        var articulation = StrumArticulation.normalDown
        articulation.velocity = index == 0 ? 0.75 : 0.55
        engine.pluck(string: string, voicing: bar.voicing, articulation: articulation)
    }
    cursor += 4 * beat
}

let verse: [Strike] = [.down(1.0), .rest, .down(0.80), .up(0.70),
                       .rest, .up(0.70), .down(0.88), .up(0.72)]

let chorus: [Strike] = [.down(1.0), .up(0.60), .down(0.85), .up(0.72),
                        .chuk(0.72), .up(0.70), .down(0.92), .up(0.76)]

let electric: [Strike] = [.down(1.0), .chukUp(0.55), .chuk(0.65), .up(0.72),
                          .rest, .up(0.74), .down(0.95), .chukUp(0.60)]

func announce(_ title: String, _ chords: String) {
    print("  \(title.padding(toLength: 22, withPad: " ", startingAt: 0))\(chords)")
}

print("\n♪  «Тёплый ветер» — 92 удара в минуту, ля минор\n")

announce("интро · классика", "Am  Fmaj7")
arpeggio(Am, order: [0, 2, 3, 4, 3, 2, 3, 4])
arpeggio(Fmaj7, order: [0, 2, 3, 4, 3, 2, 3, 4])

engine.model = .acoustic
announce("куплет · акустика", "Am  F  C  G")
for bar in [Am, F, C, G] { play(bar, pattern: verse, spread: 17) }

announce("припев · акустика", "F  C  G  Am")
for bar in [F, C, G, Am] { play(bar, pattern: chorus, spread: 15) }

engine.model = .electric
announce("проигрыш · электро", "Am  F  C  G")
for bar in [Am, F, C, G] { play(bar, pattern: electric, spread: 10) }

announce("кода · электро", "F  G  Am")
play(F, pattern: chorus, spread: 12)
play(G, pattern: chorus, spread: 12)

// Последний аккорд оставляем звенеть.
wait(until: cursor)
engine.dampAll(release: 0.25)
var final = StrumArticulation.normalDown
final.velocity = 1.0
final.sustainScale = 1.6
final.spreadMs = 26
engine.strum(voicing: Am.voicing, direction: .down, articulation: final)

wait(until: cursor + 4.5)
engine.stop()
print("\n♪  всё\n")
