import Foundation

/// Чем рисуем по сетке студии.
enum StudioBrush: Hashable, Sendable {
    case strum(direction: StrumDirection, muted: Bool)
    /// Струна аппликатуры — перебор по аккорду.
    case pluck(string: Int)
    /// Нота табулатуры: струну задаёт строка, лад — степпер.
    case note
    case eraser

    var isNote: Bool { self == .note }

    var title: String {
        switch self {
        case .strum(let direction, let muted):
            let side = direction == .down ? "вниз" : "вверх"
            return muted ? "глушёный \(side)" : "удар \(side)"
        case .pluck(let string): return "струна \(6 - string)"
        case .note: return "лад"
        case .eraser: return "ластик"
        }
    }
}
