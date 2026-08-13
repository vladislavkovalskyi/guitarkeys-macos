import Foundation

/// Физические коды клавиш macOS. Привязка идёт по позиции клавиши,
/// поэтому раскладка (в том числе русская) на игру не влияет.
enum KeyCodes {
    static let a: UInt16 = 0,  s: UInt16 = 1,  d: UInt16 = 2,  f: UInt16 = 3
    static let h: UInt16 = 4,  g: UInt16 = 5,  z: UInt16 = 6,  x: UInt16 = 7
    static let c: UInt16 = 8,  v: UInt16 = 9,  b: UInt16 = 11, q: UInt16 = 12
    static let w: UInt16 = 13, e: UInt16 = 14, r: UInt16 = 15, y: UInt16 = 16
    static let t: UInt16 = 17, o: UInt16 = 31, u: UInt16 = 32, i: UInt16 = 34
    static let p: UInt16 = 35, l: UInt16 = 37, j: UInt16 = 38, k: UInt16 = 40
    static let n: UInt16 = 45, m: UInt16 = 46
    static let one: UInt16 = 18, two: UInt16 = 19, three: UInt16 = 20
    static let four: UInt16 = 21, five: UInt16 = 23, six: UInt16 = 22
    static let leftBracket: UInt16 = 33, rightBracket: UInt16 = 30
    static let semicolon: UInt16 = 41, quote: UInt16 = 39
    static let comma: UInt16 = 43, period: UInt16 = 47, slash: UInt16 = 44
    static let space: UInt16 = 49, tab: UInt16 = 48, escape: UInt16 = 53
    static let arrowLeft: UInt16 = 123, arrowRight: UInt16 = 124
    static let arrowDown: UInt16 = 125, arrowUp: UInt16 = 126

    private static let labels: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "⏎",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥", 49: "␣", 50: "`",
        51: "⌫", 53: "⎋", 123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    /// Подпись клавиши для интерфейса.
    static func label(for keyCode: UInt16) -> String {
        labels[keyCode] ?? "#\(keyCode)"
    }

    /// Клавиши, которые нельзя занимать под игру.
    static let reserved: Set<UInt16> = [escape, tab]
}
