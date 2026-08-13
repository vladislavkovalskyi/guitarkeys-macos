import Foundation

/// Раскладка удара на события отдельных струн.
///
/// Вынесена из движка, потому что нужна дважды: живой игре и офлайн-сведению
/// проекта в файл. Логика «живой руки» должна быть ровно одна, иначе экспорт
/// звучал бы иначе, чем то, что слышал автор.
enum StrumScheduler {

    /// События одного удара по аккорду.
    /// - Parameters:
    ///   - origin: момент начала удара в сэмплах.
    ///   - humanize: 0 — механическая ровность, 1 — заметно неровная рука.
    static func strum(voicing: Voicing,
                      direction: StrumDirection,
                      articulation: StrumArticulation,
                      model: GuitarModel,
                      humanize: Double,
                      sampleRate: Double,
                      origin: UInt64) -> [StringEvent] {

        let sounding = voicing.soundingStrings
        guard !sounding.isEmpty else { return [] }

        let human = Float(max(0, min(1, humanize)))
        var order: [Int] = direction == .down ? sounding : sounding.reversed()

        // Движение вверх начинается с тонких струн и часто не достаёт до басов.
        if direction == .up && human > 0 && order.count > 3 {
            if Float.random(in: 0...1) < 0.40 * human {
                order.removeLast()
                if order.count > 3 && Float.random(in: 0...1) < 0.30 * human {
                    order.removeLast()
                }
            }
        }

        // Сила и скорость всего движения гуляют от удара к удару.
        let strokeGain = 1 + Float.random(in: -0.11...0.11) * human
        let spreadMs = articulation.spreadMs * (1 + Double.random(in: -0.22...0.22) * Double(human))

        var events: [StringEvent] = []
        events.reserveCapacity(order.count)

        for (position, stringIndex) in order.enumerated() {
            guard let midi = voicing.midiNote(string: stringIndex) else { continue }

            var velocity = articulation.velocity * strokeGain
            if direction == .up {
                // Медиатор входит в струны под углом: первые задеты полнее последних.
                let depth = Float(position) / Float(max(1, order.count - 1))
                velocity *= 0.55 + 0.45 * (1 - depth)
            }
            velocity *= 1 + Float.random(in: -0.19...0.19) * human

            // Живая гитара не строит идеально: палец давит на лад каждый раз чуть иначе.
            let detuneCents = Float.random(in: -3.0...3.0) * human
            let frequency = Float(Pitch.frequency(midi: Double(midi))) * pow(2, detuneCents / 1200)

            // Дрожание руки во времени — главное, что отличает игру от секвенсора.
            let jitterMs = Double.random(in: -2.2...2.2) * Double(human)
            let offsetMs = max(0, Double(position) * spreadMs + jitterMs)

            var event = StringEvent()
            event.atSample = origin &+ UInt64(offsetMs * sampleRate / 1000)
            event.string = Int32(stringIndex)
            event.frequency = frequency
            event.velocity = min(1, max(0.04, velocity))
            event.brightness = brightness(articulation: articulation, model: model, human: human)
            event.pickPosition = pickPosition(model: model, human: human)
            event.sustain = sustain(string: stringIndex, articulation: articulation,
                                    model: model, human: human)
            event.kind = .pluck
            events.append(event)
        }
        return events
    }

    /// Событие щипка одной струны.
    static func pluck(string: Int,
                      voicing: Voicing,
                      articulation: StrumArticulation,
                      model: GuitarModel,
                      humanize: Double,
                      origin: UInt64) -> StringEvent? {
        guard let midi = voicing.midiNote(string: string) else { return nil }
        let human = Float(max(0, min(1, humanize)))
        let detuneCents = Float.random(in: -3.0...3.0) * human

        var event = StringEvent()
        event.atSample = origin
        event.string = Int32(string)
        event.frequency = Float(Pitch.frequency(midi: Double(midi))) * pow(2, detuneCents / 1200)
        event.velocity = min(1, articulation.velocity * (1 + Float.random(in: -0.15...0.15) * human))
        event.brightness = brightness(articulation: articulation, model: model, human: human)
        event.pickPosition = pickPosition(model: model, human: human)
        event.sustain = sustain(string: string, articulation: articulation, model: model, human: human)
        event.kind = .pluck
        return event
    }

    /// Нота по табулатуре: конкретный лад на конкретной струне, независимо от аккорда.
    static func note(string: Int,
                     fret: Int,
                     articulation: StrumArticulation,
                     model: GuitarModel,
                     humanize: Double,
                     origin: UInt64) -> StringEvent? {
        guard Pitch.standardTuning.indices.contains(string), fret >= 0, fret <= 24 else { return nil }
        let midi = Pitch.standardTuning[string] + fret
        let human = Float(max(0, min(1, humanize)))
        let detuneCents = Float.random(in: -3.0...3.0) * human

        var event = StringEvent()
        event.atSample = origin
        event.string = Int32(string)
        event.frequency = Float(Pitch.frequency(midi: Double(midi))) * pow(2, detuneCents / 1200)
        event.velocity = min(1, max(0.04, articulation.velocity * (1 + Float.random(in: -0.15...0.15) * human)))
        event.brightness = brightness(articulation: articulation, model: model, human: human)
        event.pickPosition = pickPosition(model: model, human: human)
        event.sustain = sustain(string: string, articulation: articulation, model: model, human: human)
        event.kind = .pluck
        return event
    }

    /// Приглушить все струны.
    static func damp(release: Float, origin: UInt64) -> [StringEvent] {
        (0..<GuitarSynth.stringCount).map { string in
            var event = StringEvent()
            event.atSample = origin
            event.string = Int32(string)
            event.sustain = release
            event.kind = .damp
            return event
        }
    }

    // MARK: Разброс параметров

    private static func brightness(articulation: StrumArticulation,
                                   model: GuitarModel, human: Float) -> Float {
        let jitter = Float.random(in: -0.09...0.09) * human
        return max(0, min(1, Float(model.brightness) + articulation.brightnessOffset + jitter))
    }

    private static func pickPosition(model: GuitarModel, human: Float) -> Float {
        // Рука не попадает дважды в одну точку струны.
        let jitter = Float.random(in: -0.035...0.035) * human
        return max(0.04, min(0.42, Float(model.pickPosition) + jitter))
    }

    private static func sustain(string: Int, articulation: StrumArticulation,
                                model: GuitarModel, human: Float) -> Float {
        let base = Float(model.sustain(forString: string)) * articulation.sustainScale
        return max(0.03, base * (1 + Float.random(in: -0.10...0.10) * human))
    }
}
