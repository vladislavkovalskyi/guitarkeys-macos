import AVFoundation
import Foundation

/// Инструмент: набор физических параметров, а не пресет эквалайзера.
/// Разница между нейлоном, сталью и звукоснимателем слышна прежде всего в том,
/// как быстро гаснут обертоны и где струну задевают.
struct GuitarModel: Codable, Hashable, Sendable, Identifiable {

    enum Kind: String, Codable, CaseIterable, Sendable, Identifiable {
        case classical, acoustic, electric

        var id: String { rawValue }

        var title: String {
            switch self {
            case .classical: return "Классика"
            case .acoustic:  return "Акустика"
            case .electric:  return "Электро"
            }
        }

        var subtitle: String {
            switch self {
            case .classical: return "нейлон, мягкая атака"
            case .acoustic:  return "сталь, звонкий корпус"
            case .electric:  return "звукосниматель, длинный сустейн"
            }
        }
    }

    var kind: Kind

    /// Яркость звукоизвлечения: сколько высоких обертонов переживает петлю.
    var brightness: Double
    /// Время затухания басовой струны, секунды.
    var sustain: Double
    /// Насколько короче звучат высокие струны (0 — так же, 1 — вдвое короче).
    var trebleFalloff: Double
    /// Где струну задевают: 0.05 — у бриджа (резко), 0.30 — ближе к грифу (мягко).
    var pickPosition: Double
    /// Вклад корпуса: 0 — почти цельнокорпусная электрогитара, 1 — гулкая дека.
    var body: Double
    /// Реверберация помещения.
    var reverb: Double
    /// Перегруз лампового типа. Осмыслен только для электрогитары.
    var drive: Double

    var id: String { kind.rawValue }

    // MARK: Пресеты

    static let classical = GuitarModel(
        kind: .classical, brightness: 0.30, sustain: 2.8, trebleFalloff: 0.45,
        pickPosition: 0.24, body: 0.85, reverb: 0.18, drive: 0
    )

    static let acoustic = GuitarModel(
        kind: .acoustic, brightness: 0.60, sustain: 3.8, trebleFalloff: 0.35,
        pickPosition: 0.13, body: 1.0, reverb: 0.14, drive: 0
    )

    static let electric = GuitarModel(
        kind: .electric, brightness: 0.70, sustain: 5.2, trebleFalloff: 0.18,
        pickPosition: 0.10, body: 0.30, reverb: 0.08, drive: 0.22
    )

    static let presets: [GuitarModel] = [.classical, .acoustic, .electric]

    static func preset(_ kind: Kind) -> GuitarModel {
        switch kind {
        case .classical: return .classical
        case .acoustic:  return .acoustic
        case .electric:  return .electric
        }
    }

    /// Сустейн конкретной струны: тонкие струны гаснут быстрее толстых.
    /// `string` — 0 для низкой ми, 5 для высокой.
    func sustain(forString string: Int) -> Double {
        let position = Double(max(0, min(5, string))) / 5.0
        return sustain * (1 - trebleFalloff * pow(position, 1.15))
    }

    // MARK: Корпус

    struct EQBand {
        var type: AVAudioUnitEQFilterType
        var frequency: Float
        var bandwidth: Float
        var gain: Float
    }

    /// Резонанс корпуса и характер съёма. Четыре полосы — ровно столько, сколько
    /// нужно, чтобы отличить нейлон от стали, а деку от звукоснимателя.
    var eqBands: [EQBand] {
        let body = Float(self.body)
        switch kind {
        case .classical:
            return [
                EQBand(type: .highPass, frequency: 68, bandwidth: 0.5, gain: 0),
                EQBand(type: .parametric, frequency: 180, bandwidth: 1.1, gain: 3.0 * body),
                EQBand(type: .parametric, frequency: 1100, bandwidth: 1.5, gain: -1.5),
                EQBand(type: .highShelf, frequency: 3800, bandwidth: 0.6, gain: -4.5),
            ]
        case .acoustic:
            return [
                EQBand(type: .highPass, frequency: 72, bandwidth: 0.5, gain: 0),
                EQBand(type: .parametric, frequency: 210, bandwidth: 1.2, gain: 2.6 * body),
                EQBand(type: .parametric, frequency: 900, bandwidth: 1.4, gain: -2.0),
                EQBand(type: .parametric, frequency: 3200, bandwidth: 1.5, gain: 2.6),
            ]
        case .electric:
            return [
                EQBand(type: .highPass, frequency: 110, bandwidth: 0.5, gain: 0),
                EQBand(type: .parametric, frequency: 240, bandwidth: 1.0, gain: 1.5 * body),
                EQBand(type: .parametric, frequency: 1400, bandwidth: 1.1, gain: 3.0),
                EQBand(type: .lowPass, frequency: 5200, bandwidth: 0.5, gain: 0),
            ]
        }
    }
}
