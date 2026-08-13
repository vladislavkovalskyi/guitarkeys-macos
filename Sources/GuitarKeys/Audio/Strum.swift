import Foundation

/// Направление движения медиатора.
/// Живёт отдельно от движка: этим пользуется и модель проекта, которой
/// незачем тянуть за собой AVFoundation.
enum StrumDirection: String, Codable, Sendable {
    case down   // от низких струн к высоким
    case up     // от высоких к низким

    var symbol: String { self == .down ? "arrow.down" : "arrow.up" }
}

/// Характер удара. Абсолютный тембр задаёт инструмент, здесь — только отклонения от него.
struct StrumArticulation: Sendable {
    var velocity: Float = 0.9
    var brightnessOffset: Float = 0     // резче или мягче обычного
    var sustainScale: Float = 1         // доля штатного затухания
    var spreadMs: Double = 16           // задержка между соседними струнами
    var muted: Bool = false             // глушение ладонью

    static let normalDown = StrumArticulation(velocity: 0.90, brightnessOffset: 0.00, sustainScale: 1.00, spreadMs: 17)
    static let normalUp   = StrumArticulation(velocity: 0.68, brightnessOffset: 0.06, sustainScale: 0.72, spreadMs: 11)
    static let mutedDown  = StrumArticulation(velocity: 0.80, brightnessOffset: -0.18, sustainScale: 0.055, spreadMs: 9, muted: true)
    static let mutedUp    = StrumArticulation(velocity: 0.62, brightnessOffset: -0.14, sustainScale: 0.048, spreadMs: 7, muted: true)
}
