import SwiftUI

/// Правая рука на телефоне: четыре крупные площадки под большой палец.
struct TouchStrumBar: View {
    @Environment(AppState.self) private var state
    @Namespace private var glass

    let height: CGFloat

    private let strokes: [(direction: StrumDirection, muted: Bool)] = [
        (.down, false), (.up, false), (.down, true), (.up, true),
    ]

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(Array(strokes.enumerated()), id: \.offset) { index, stroke in
                    StrokePad(direction: stroke.direction,
                              muted: stroke.muted,
                              height: height,
                              identifier: index,
                              namespace: glass)
                }
            }
        }
    }
}

private struct StrokePad: View {
    let direction: StrumDirection
    let muted: Bool
    let height: CGFloat
    let identifier: Int
    let namespace: Namespace.ID

    @Environment(AppState.self) private var state
    @UIState private var isPressed = false

    private var tint: Color { muted ? Theme.mutedAccent : Theme.accent }

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: direction == .down ? "arrow.down" : "arrow.up")
                .font(.system(size: height > 70 ? 24 : 20, weight: .semibold))
                .foregroundStyle(isPressed ? Color.black.opacity(0.8) : tint)

            Text(muted ? "глушение" : "открытый")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(isPressed ? AnyShapeStyle(Color.black.opacity(0.55))
                                          : AnyShapeStyle(.tertiary))
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .glassEffect(isPressed ? .regular.tint(tint.opacity(0.9)).interactive()
                               : .regular.interactive(),
                     in: .rect(cornerRadius: Theme.padCorner, style: .continuous))
        .glassEffectID("stroke\(identifier)", in: namespace)
        .scaleEffect(isPressed ? 1.05 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.55), value: isPressed)
        // Удар происходит в момент касания, а не отпускания: иначе ритм запаздывает.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    isPressed = true
                    Haptics.strike(muted ? 0.6 : 0.95)
                    state.strum(direction: direction, muted: muted)
                }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel(direction == .down ? "Удар вниз" : "Удар вверх")
    }
}
