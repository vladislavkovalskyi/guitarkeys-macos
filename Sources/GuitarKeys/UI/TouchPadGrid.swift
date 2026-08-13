import SwiftUI

/// Аккорды под палец. В отличие от маковской сетки здесь нет подписей клавиш,
/// зато есть удержание: палец лежит на аккорде, второй бьёт по грифу.
struct TouchPadGrid: View {
    @Environment(AppState.self) private var state
    @Namespace private var glass

    /// Сколько аккордов помещается в ряд: на телефоне меньше, на планшете весь ряд.
    let columns: Int
    let padHeight: CGFloat

    var body: some View {
        let layout = Array(repeating: GridItem(.flexible(), spacing: 8), count: columns)

        GlassEffectContainer(spacing: 12) {
            LazyVGrid(columns: layout, spacing: 8) {
                ForEach(state.preferences.pads) { pad in
                    TouchPad(pad: pad, height: padHeight, namespace: glass)
                }
            }
        }
    }
}

private struct TouchPad: View {
    let pad: Pad
    let height: CGFloat
    let namespace: Namespace.ID

    @Environment(AppState.self) private var state
    @UIState private var isPressed = false

    private var isHeld: Bool { state.isPadHeld(pad.id) }
    private var chord: Chord { pad.chord(in: state.preferences.key) }

    var body: some View {
        VStack(spacing: 3) {
            Text(chord.name)
                .font(.system(size: height > 70 ? 22 : 18, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .foregroundStyle(isHeld ? Color.black.opacity(0.82) : .primary)

            Text(pad.caption(in: state.preferences.key))
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(isHeld ? AnyShapeStyle(Color.black.opacity(0.5))
                                        : AnyShapeStyle(.tertiary))
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .glassEffect(
            isHeld ? .regular.tint(Theme.chordColor(root: chord.root, saturation: 0.7).opacity(0.9)).interactive()
                   : .regular.interactive(),
            in: .rect(cornerRadius: Theme.padCorner, style: .continuous)
        )
        .glassEffectID(pad.id, in: namespace)
        .scaleEffect(isHeld ? 1.04 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.6), value: isHeld)
        // Нажатие и отпускание нужны раздельно, поэтому не Button:
        // палец держит аккорд ровно столько, сколько лежит на пэде.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    isPressed = true
                    Haptics.strike()
                    state.pressPad(pad)
                }
                .onEnded { _ in
                    isPressed = false
                    state.releasePad(pad)
                }
        )
        .contextMenu {
            Button("Настроить аккорд…") { state.inspectorPad = pad }
        }
        .accessibilityLabel(chord.name)
    }
}
