import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        VStack(alignment: .leading, spacing: 18) {
            group("Звук") {
                slider("Громкость", value: $state.volume, range: 0...1, symbol: "speaker.wave.2")
                slider("Разброс боя",
                       value: $state.preferences.strumSpread,
                       range: 5...45,
                       symbol: "timelapse",
                       format: { "\(Int($0)) мс" })
                slider("Живая рука", value: $state.humanize, range: 0...1, symbol: "hand.wave")
            }
            Text("Живая рука делает каждый удар чуть другим: сила, тайминг, строй и\u{00A0}место щипка. На нуле — механически ровно.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, -8)

            group("Игра") {
                Toggle("Удар вниз при нажатии аккорда", isOn: $state.preferences.autoStrumOnPress)
                Toggle("Глушить струны при отпускании", isOn: $state.preferences.muteOnRelease)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.system(size: 12))

            group("Клавиши правой руки") {
                ForEach(state.preferences.actions) { binding in
                    HStack {
                        Image(systemName: binding.action.symbolName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 16)
                        Text(binding.action.title)
                            .font(.system(size: 12))
                        Spacer(minLength: 12)
                        Button {
                            state.bindingTarget = .action(binding.action)
                            state.showsSettings = false
                        } label: {
                            Text(binding.keyCodes.isEmpty
                                 ? "назначить"
                                 : binding.keyCodes.map { KeyCodes.label(for: $0) }.joined(separator: " "))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .frame(minWidth: 44)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                    }
                }
            }

            group("Клавиши струн") {
                HStack(spacing: 5) {
                    ForEach(0..<6, id: \.self) { number in
                        VStack(spacing: 3) {
                            Text("\(number + 1)")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.tertiary)
                            Button {
                                state.bindingTarget = .string(number)
                                state.showsSettings = false
                            } label: {
                                Text(stringKeyLabel(number))
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                        }
                    }
                }
                Text("Струна 1 — самая тонкая. По грифу можно бить и мышью: проводка через несколько струн играется как бой.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().opacity(0.4)

            HStack {
                Text("Правый клик по любой клавише — настроить аккорд.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Сбросить") { state.resetBindings() }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private func stringKeyLabel(_ number: Int) -> String {
        let code = state.preferences.stringKeys[number]
        return code == 0xFFFF ? "—" : KeyCodes.label(for: code)
    }

    @ViewBuilder
    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).sectionLabel()
            content()
        }
    }

    private func slider(_ title: String,
                        value: Binding<Double>,
                        range: ClosedRange<Double>,
                        symbol: String,
                        format: ((Double) -> String)? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Slider(value: value, in: range)
                .controlSize(.small)
                .tint(Theme.accent)
            Text(format?(value.wrappedValue) ?? "\(Int(value.wrappedValue * 100))%")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
        .help(title)
    }
}
