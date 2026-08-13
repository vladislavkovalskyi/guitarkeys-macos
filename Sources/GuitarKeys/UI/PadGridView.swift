import SwiftUI

struct PadGridView: View {
    @Environment(AppState.self) private var state
    @Namespace private var glassNamespace

    private let columns = 7

    var body: some View {
        let pads = state.preferences.pads
        let rows = stride(from: 0, to: pads.count, by: columns).map {
            Array(pads[$0..<min($0 + columns, pads.count)])
        }

        GlassEffectContainer(spacing: 14) {
            VStack(spacing: 10) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 10) {
                        ForEach(row) { pad in
                            PadView(pad: pad, namespace: glassNamespace)
                        }
                    }
                }
            }
        }
    }
}

private struct PadView: View {
    let pad: Pad
    let namespace: Namespace.ID

    @Environment(AppState.self) private var state
    @UIState private var isHovering = false
    @UIState private var isDropTarget = false

    private var isHeld: Bool { state.isPadHeld(pad.id) }
    private var isAwaitingKey: Bool { state.bindingTarget == .pad(pad.id) }
    private var chord: Chord { pad.chord(in: state.preferences.key) }
    private var hasKey: Bool { pad.keyCode != 0xFFFF }

    var body: some View {
        VStack(spacing: 6) {
            Text(hasKey ? KeyCodes.label(for: pad.keyCode) : "—")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(isHeld ? Color.black.opacity(0.75) : .secondary)
                .frame(width: 20, height: 20)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHeld ? Theme.accent : Color.white.opacity(0.10))
                }

            Text(chord.name)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(pad.caption(in: state.preferences.key))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 92)
        .glassEffect(
            glassStyle,
            in: .rect(cornerRadius: Theme.padCorner, style: .continuous)
        )
        .glassEffectID(pad.id, in: namespace)
        .focusEffectDisabled()   // перетаскивание делает пэд фокусируемым, кольцо тут лишнее
        .overlay {
            if isAwaitingKey {
                RoundedRectangle(cornerRadius: Theme.padCorner, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: 2)
                    .overlay {
                        Text("нажмите\nклавишу")
                            .multilineTextAlignment(.center)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .padding(4)
                            .background(.black.opacity(0.55), in: .rect(cornerRadius: 6))
                    }
            }
        }
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: Theme.padCorner, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.9), lineWidth: 2.5)
            }
        }
        .scaleEffect(isHeld ? 1.05 : (isDropTarget ? 1.04 : (isHovering ? 1.02 : 1.0)))
        .animation(.spring(response: 0.24, dampingFraction: 0.62), value: isHeld)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .animation(.spring(response: 0.26, dampingFraction: 0.7), value: isDropTarget)
        .onHover { isHovering = $0 }
        .onTapGesture { state.tap(pad: pad) }
        // Перетаскивание меняет порядок аккордов; клавиши остаются на своих местах.
        .draggable(pad.id.uuidString) {
            Text(chord.name)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Theme.accent, in: .rect(cornerRadius: 12, style: .continuous))
                .foregroundStyle(.black)
        }
        .dropDestination(for: String.self) { items, _ in
            guard let identifier = items.first, let dragged = UUID(uuidString: identifier) else { return false }
            state.movePad(dragged, before: pad.id)
            return true
        } isTargeted: { targeted in
            isDropTarget = targeted
        }
        .contextMenu {
            Button("Настроить аккорд…") { state.inspectorPad = pad }
            Button("Назначить клавишу") { state.bindingTarget = .pad(pad.id) }
        }
        .help("\(chord.name) — \(chord.quality.displayName)")
        .accessibilityLabel("\(chord.name), клавиша \(hasKey ? KeyCodes.label(for: pad.keyCode) : "не назначена")")
    }

    private var glassStyle: Glass {
        if isHeld {
            return .regular.tint(Theme.chordColor(root: chord.root, saturation: 0.7).opacity(0.85)).interactive()
        }
        if isHovering {
            return .regular.tint(Color.white.opacity(0.10)).interactive()
        }
        return .regular.interactive()
    }
}
