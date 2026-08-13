import Foundation

/// Модификаторы клавиатуры без привязки к AppKit: логика игры не должна знать
/// про `NSEvent`, иначе её не перенести на iPad с внешней клавиатурой.
struct KeyModifiers: OptionSet, Sendable, Hashable {
    let rawValue: Int

    init(rawValue: Int) { self.rawValue = rawValue }

    static let shift   = KeyModifiers(rawValue: 1 << 0)
    static let control = KeyModifiers(rawValue: 1 << 1)
    static let option  = KeyModifiers(rawValue: 1 << 2)
    static let command = KeyModifiers(rawValue: 1 << 3)

    /// Сочетания с ⌘ и ⌃ принадлежат системе и меню, а не инструменту.
    var isSystemChord: Bool {
        contains(.command) || contains(.control)
    }
}
