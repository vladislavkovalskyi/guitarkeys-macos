import SwiftUI

struct HeaderView: View {
    @Environment(AppState.self) private var state
    @Namespace private var glass

    var body: some View {
        @Bindable var state = state

        HStack(spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: "guitars.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("GuitarKeys")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }

            Spacer(minLength: 8)

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    keyStepper
                    scalePicker
                }
            }

            Spacer(minLength: 8)

            Button {
                state.showsGuitarPicker.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "guitars.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Text(state.guitar.kind.title)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }
                .padding(.horizontal, 11)
                .frame(height: 28)
            }
            .buttonStyle(.glass)
            .help("Инструмент и тембр")
            .popover(isPresented: $state.showsGuitarPicker, arrowEdge: .bottom) {
                GuitarPickerView()
            }

            Button {
                state.showsSettings.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 28)
            }
            .buttonStyle(.glass)
            .help("Настройки и привязки клавиш")
            .popover(isPresented: $state.showsSettings, arrowEdge: .bottom) {
                SettingsView()
            }
        }
        // Заголовок окна скрыт, поэтому содержимое доходит до самого верха —
        // отступ слева освобождает место под кнопки окна.
        .padding(.leading, 82)
        .padding(.trailing, 20)
        .padding(.vertical, 12)
    }

    private var keyStepper: some View {
        HStack(spacing: 4) {
            Button {
                state.transpose(by: -1)
            } label: {
                Image(systemName: "minus").font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 26)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .help("Понизить тональность (\(hint(for: .transposeDown)))")

            Text(Pitch.name(state.preferences.key.tonic))
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .frame(minWidth: 34)
                .foregroundStyle(Theme.accent)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.22), value: state.preferences.key.tonic)

            Button {
                state.transpose(by: 1)
            } label: {
                Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 26)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .help("Повысить тональность (\(hint(for: .transposeUp)))")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .glassEffect(.regular.interactive(), in: .capsule)
        .glassEffectID("key", in: glass)
    }

    private var scalePicker: some View {
        HStack(spacing: 2) {
            ForEach(ScaleType.allCases, id: \.self) { scale in
                let selected = state.preferences.key.scale == scale
                Button {
                    state.setKey(scale: scale)
                } label: {
                    Text(scale.displayName)
                        .font(.system(size: 11, weight: selected ? .semibold : .regular, design: .rounded))
                        .foregroundStyle(selected ? Color.black.opacity(0.8) : .secondary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background {
                            if selected {
                                Capsule().fill(Theme.accent)
                            }
                        }
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
            }
        }
        .padding(3)
        .glassEffect(.regular.interactive(), in: .capsule)
        .glassEffectID("scale", in: glass)
        .animation(.snappy(duration: 0.2), value: state.preferences.key.scale)
    }

    private func hint(for action: GuitarAction) -> String {
        state.preferences.keyCodes(for: action).map { KeyCodes.label(for: $0) }.joined(separator: " / ")
    }
}
