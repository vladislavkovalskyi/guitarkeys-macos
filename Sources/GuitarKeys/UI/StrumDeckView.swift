import SwiftUI

/// Правая рука: удары вниз/вверх, обычные и глушёные.
struct StrumDeckView: View {
    @Environment(AppState.self) private var state
    @Namespace private var glass

    @UIState private var flash: GuitarAction?

    private let strumActions: [GuitarAction] = [.mutedUp, .strumUp, .strumDown, .mutedDown]

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 10) {
                AutoStrumToggle(namespace: glass)
                    .padding(.trailing, 6)

                ForEach(strumActions) { action in
                    StrumButton(action: action,
                                isFlashing: flash == action,
                                namespace: glass)
                }

                Spacer(minLength: 12)

                RecordButton(namespace: glass)
            }
        }
        .onChange(of: state.strumTick) { _, _ in
            let action: GuitarAction
            switch (state.lastStrum, state.lastStrumMuted) {
            case (.down, false): action = .strumDown
            case (.up, false):   action = .strumUp
            case (.down, true):  action = .mutedDown
            case (.up, true):    action = .mutedUp
            }
            withAnimation(.easeOut(duration: 0.09)) { flash = action }
            withAnimation(.easeOut(duration: 0.42).delay(0.09)) { flash = nil }
        }
    }
}

/// Играть ли удар вниз в момент взятия аккорда. Выключишь — клавиша только зажимает
/// аппликатуру, а ритм полностью за правой рукой: стрелками или по струнам.
private struct AutoStrumToggle: View {
    let namespace: Namespace.ID

    @Environment(AppState.self) private var state
    @UIState private var isHovering = false

    private var isOn: Bool { state.preferences.autoStrumOnPress }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: isOn ? "hand.tap.fill" : "hand.raised.slash")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isOn ? Color.black.opacity(0.78) : .secondary)
                .contentTransition(.symbolEffect(.replace))

            Text(isOn ? "звучит\nпри нажатии" : "молчит\nдо удара")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(isOn ? Color.black.opacity(0.6) : .secondary)
                .lineSpacing(1)
        }
        .frame(width: 96, height: 74)
        .glassEffect(isOn ? .regular.tint(Theme.accent.opacity(0.75)).interactive()
                          : .regular.interactive(),
                     in: .rect(cornerRadius: Theme.padCorner, style: .continuous))
        .glassEffectID("autoStrum", in: namespace)
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.snappy(duration: 0.22), value: isOn)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .onHover { isHovering = $0 }
        .onTapGesture {
            state.preferences.autoStrumOnPress.toggle()
        }
        .help(isOn
              ? "Аккорд звучит сразу при нажатии клавиши. Выключите, чтобы зажимать аккорд молча и играть бой самому"
              : "Клавиша только зажимает аккорд. Ритм — стрелками или по струнам")
        .accessibilityLabel("Удар при нажатии аккорда, \(isOn ? "включено" : "выключено")")
    }
}

/// Запись игры в файл. Кольцо вокруг точки дышит по реальному уровню сигнала —
/// сразу видно, что пишется звук, а не тишина.
private struct RecordButton: View {
    let namespace: Namespace.ID

    @Environment(AppState.self) private var state
    @UIState private var isHovering = false

    private var isRecording: Bool { state.isRecording }

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                if isRecording {
                    Circle()
                        .stroke(Theme.record.opacity(0.5), lineWidth: 2)
                        .frame(width: 26, height: 26)
                        .scaleEffect(1 + state.recordingLevel * 0.5)
                        .opacity(1 - state.recordingLevel * 0.45)
                }
                Image(systemName: isRecording ? "stop.fill" : "record.circle")
                    .font(.system(size: isRecording ? 14 : 18, weight: .semibold))
                    .foregroundStyle(Theme.record)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(isRecording ? state.recordingTimeText : "запись")
                    .font(.system(size: isRecording ? 15 : 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isRecording ? Theme.record : .primary)
                    .contentTransition(.numericText())
                Text(isRecording ? "идёт" : "⌘R")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 74)
        .glassEffect(isRecording ? .regular.tint(Theme.record.opacity(0.28)).interactive()
                                 : .regular.interactive(),
                     in: .rect(cornerRadius: Theme.padCorner, style: .continuous))
        .glassEffectID("record", in: namespace)
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.snappy(duration: 0.25), value: isRecording)
        .animation(.easeOut(duration: 0.12), value: state.recordingLevel)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .onHover { isHovering = $0 }
        .onTapGesture { state.toggleRecording() }
        .contextMenu {
            Button("Папка с записями") { state.openRecordingsFolder() }
            if state.lastRecording != nil {
                Button("Показать последнюю запись") { state.revealLastRecording() }
            }
        }
        .help(isRecording ? "Остановить запись" : "Записать игру в файл")
        .accessibilityLabel(isRecording ? "Идёт запись, \(state.recordingTimeText)" : "Начать запись")
    }
}

private struct StrumButton: View {
    let action: GuitarAction
    let isFlashing: Bool
    let namespace: Namespace.ID

    @Environment(AppState.self) private var state
    @UIState private var isHovering = false

    private var isAwaitingKey: Bool { state.bindingTarget == .action(action) }

    private var keyLabels: String {
        let codes = state.preferences.keyCodes(for: action)
        return codes.isEmpty ? "—" : codes.map { KeyCodes.label(for: $0) }.joined(separator: " ")
    }

    private var isMuted: Bool { action == .mutedDown || action == .mutedUp }

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: action.symbolName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isFlashing ? Color.black.opacity(0.8)
                                            : (isMuted ? Theme.mutedAccent : Theme.accent))

            Text(keyLabels)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(isFlashing ? Color.black.opacity(0.6) : .secondary)

            Text(isMuted ? "глушение" : "открытый")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
                .opacity(isHovering || isFlashing ? 1 : 0.55)
        }
        .frame(width: 96, height: 74)
        .glassEffect(glassStyle, in: .rect(cornerRadius: Theme.padCorner, style: .continuous))
        .glassEffectID(action.rawValue, in: namespace)
        .overlay {
            if isAwaitingKey {
                RoundedRectangle(cornerRadius: Theme.padCorner, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: 2)
            }
        }
        .scaleEffect(isFlashing ? 1.07 : (isHovering ? 1.02 : 1.0))
        .animation(.spring(response: 0.22, dampingFraction: 0.55), value: isFlashing)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .onHover { isHovering = $0 }
        .onTapGesture {
            switch action {
            case .strumDown: state.strum(direction: .down, muted: false)
            case .strumUp:   state.strum(direction: .up, muted: false)
            case .mutedDown: state.strum(direction: .down, muted: true)
            case .mutedUp:   state.strum(direction: .up, muted: true)
            default: break
            }
        }
        .contextMenu {
            Button("Назначить клавишу") { state.bindingTarget = .action(action) }
        }
        .help(action.title)
    }

    private var glassStyle: Glass {
        if isFlashing {
            return .regular.tint((isMuted ? Theme.mutedAccent : Theme.accent).opacity(0.9)).interactive()
        }
        return .regular.interactive()
    }
}
