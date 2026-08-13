import CoreGraphics

/// Раскладка грифа: где проходят струны и лады. Вынесена из отрисовки, потому что
/// по ней же считается попадание мыши — рисунок и щипок обязаны совпадать.
struct FretboardGeometry {

    static let visibleFrets = 5
    static let stringCount = 6

    static let leftInset: CGFloat = 74     // место под клавишу, ноту и знак глушения
    static let rightInset: CGFloat = 22
    static let topInset: CGFloat = 34
    static let bottomInset: CGFloat = 20
    /// Насколько струна выступает за порожец влево — там её тоже можно задеть.
    static let stringLeadIn: CGFloat = 14

    static let keyLabelX: CGFloat = 14
    static let noteLabelX: CGFloat = 32
    static let markerX: CGFloat = 48

    let board: CGRect
    let fretWidth: CGFloat
    let stringSpacing: CGFloat

    init?(size: CGSize) {
        let rect = CGRect(x: Self.leftInset,
                          y: Self.topInset,
                          width: size.width - Self.leftInset - Self.rightInset,
                          height: size.height - Self.topInset - Self.bottomInset)
        guard rect.width > 40, rect.height > 20 else { return nil }
        board = rect
        fretWidth = rect.width / CGFloat(Self.visibleFrets)
        stringSpacing = rect.height / CGFloat(Self.stringCount - 1)
    }

    /// Струны идут снизу вверх: 0 — низкая ми, 5 — высокая. Как в табулатуре.
    func y(ofString index: Int) -> CGFloat {
        board.maxY - CGFloat(index) * stringSpacing
    }

    func x(ofFret fret: Int, from windowStart: Int) -> CGFloat {
        board.minX + CGFloat(fret - windowStart) * fretWidth
    }

    /// Левый край струны — она начинается раньше порожка.
    var stringStartX: CGFloat { board.minX - Self.stringLeadIn }

    /// Струна под точкой, или nil если мышь мимо грифа.
    func stringIndex(at point: CGPoint) -> Int? {
        guard point.x >= stringStartX - 8, point.x <= board.maxX + 4 else { return nil }

        let raw = (board.maxY - point.y) / stringSpacing
        let index = Int(raw.rounded())
        guard index >= 0, index < Self.stringCount else { return nil }
        // Дальше половины промежутка считается, что мимо струны не задели.
        guard abs(raw - CGFloat(index)) <= 0.5 else { return nil }
        return index
    }
}
