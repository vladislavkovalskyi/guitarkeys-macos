import SwiftUI

enum Theme {
    /// Тёплый янтарный акцент — цвет дерева и бронзовых струн.
    static let accent = Color(red: 0.98, green: 0.66, blue: 0.30)
    static let accentDeep = Color(red: 0.86, green: 0.42, blue: 0.16)
    static let mutedAccent = Color(red: 0.55, green: 0.62, blue: 0.78)
    static let record = Color(red: 0.95, green: 0.30, blue: 0.26)

    static let padCorner: CGFloat = 18
    static let panelCorner: CGFloat = 26

    /// Каждой тонике — свой оттенок, чтобы смена тональности читалась боковым зрением.
    static func hue(forRoot root: Int) -> Double {
        // Квинтовый круг мягче ложится на цветовой круг, чем хроматический ряд.
        let circleOfFifths = (root * 7) % 12
        return Double(circleOfFifths) / 12.0
    }

    static func chordColor(root: Int, saturation: Double = 0.55, brightness: Double = 0.95) -> Color {
        Color(hue: hue(forRoot: root), saturation: saturation, brightness: brightness)
    }
}

/// Фон окна: глубокая подложка с мягким свечением в цвете текущего аккорда.
/// Liquid Glass раскрывается только над насыщенным фоном, поэтому он здесь не декорация.
struct AmbientBackground: View {
    var root: Int
    var energy: Double        // 0…1 — насколько недавно был удар

    var body: some View {
        let hue = Theme.hue(forRoot: root)

        ZStack {
            Color(red: 0.055, green: 0.055, blue: 0.070)

            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                    [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                    [0.0, 1.0], [0.5, 1.0], [1.0, 1.0],
                ],
                colors: [
                    Color(hue: hue, saturation: 0.55, brightness: 0.20 + 0.10 * energy),
                    Color(hue: hue + 0.06, saturation: 0.40, brightness: 0.14),
                    Color(hue: hue - 0.05, saturation: 0.50, brightness: 0.19 + 0.08 * energy),
                    Color(hue: hue + 0.02, saturation: 0.35, brightness: 0.12),
                    Color(hue: hue, saturation: 0.60, brightness: 0.26 + 0.14 * energy),
                    Color(hue: hue - 0.03, saturation: 0.30, brightness: 0.11),
                    Color(hue: hue + 0.04, saturation: 0.45, brightness: 0.16 + 0.06 * energy),
                    Color(hue: hue, saturation: 0.35, brightness: 0.10),
                    Color(hue: hue - 0.06, saturation: 0.40, brightness: 0.15),
                ]
            )
            .opacity(0.9)

            // Виньетка собирает внимание к центру.
            RadialGradient(
                colors: [.clear, Color.black.opacity(0.45)],
                center: .center,
                startRadius: 220,
                endRadius: 700
            )
        }
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.55), value: root)
        .animation(.easeOut(duration: 0.35), value: energy)
    }
}

extension View {
    /// Подпись мелким капслоком — язык системных панелей macOS.
    func sectionLabel() -> some View {
        self
            .font(.system(size: 10, weight: .semibold))
            .textCase(.uppercase)
            .kerning(0.8)
            .foregroundStyle(.secondary)
    }
}
