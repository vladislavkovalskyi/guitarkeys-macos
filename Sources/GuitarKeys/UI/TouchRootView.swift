import SwiftUI

/// Экран для iPhone и iPad. Раскладка та же, что на маке, но клавиш нет:
/// аккорд держит палец, а бой берётся с грифа или с площадок внизу.
struct TouchRootView: View {
    @Environment(AppState.self) private var state
    @Environment(\.horizontalSizeClass) private var sizeClass
    @UIState private var energy: Double = 0

    var body: some View {
        @Bindable var state = state

        GeometryReader { proxy in
            // На телефоне в портрете места мало, поэтому всё ужимается.
            let compact = sizeClass == .compact || proxy.size.width < 700
            let columns = compact ? 4 : 7
            let padHeight: CGFloat = compact ? 60 : 84
            let strumHeight: CGFloat = compact ? 66 : 86

            ZStack {
                AmbientBackground(root: state.currentChord.root, energy: energy)

                VStack(spacing: compact ? 10 : 14) {
                    header(compact: compact)
                    TouchPadGrid(columns: columns, padHeight: padHeight)
                    FretboardView()
                    TouchStrumBar(height: strumHeight)
                }
                .padding(.horizontal, compact ? 12 : 20)
                .padding(.bottom, compact ? 8 : 16)

                if let notice = state.recordingNotice {
                    VStack {
                        Spacer()
                        RecordingNotice(url: notice)
                            .padding(.horizontal, 12)
                            .padding(.bottom, compact ? 96 : 116)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { Haptics.prepare() }
        .onChange(of: state.strumTick) { _, _ in
            withAnimation(.easeOut(duration: 0.10)) { energy = 1 }
            withAnimation(.easeOut(duration: 0.85).delay(0.10)) { energy = 0 }
        }
        .sheet(item: $state.inspectorPad) { pad in
            PadInspector(pad: pad)
        }
        .sheet(isPresented: $state.showsSettings) {
            SettingsView()
        }
        .sheet(isPresented: $state.showsGuitarPicker) {
            GuitarPickerView()
        }
    }

    private func header(compact: Bool) -> some View {
        HStack(spacing: 8) {
            keyStepper
            scaleToggle

            Spacer(minLength: 4)

            iconButton(systemName: state.preferences.autoStrumOnPress
                       ? "hand.tap.fill" : "hand.raised.slash",
                       tint: state.preferences.autoStrumOnPress ? Theme.accent : .secondary,
                       label: "Удар при нажатии") {
                state.preferences.autoStrumOnPress.toggle()
                Haptics.pluck()
            }

            iconButton(systemName: state.isRecording ? "stop.fill" : "record.circle",
                       tint: Theme.record,
                       label: "Запись") {
                state.toggleRecording()
                Haptics.strike()
            }

            if !compact {
                Button {
                    state.showsGuitarPicker = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "guitars.fill").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                        Text(state.guitar.kind.title)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 34)
                }
                .buttonStyle(.glass)
            } else {
                iconButton(systemName: "guitars.fill", tint: Theme.accent, label: "Инструмент") {
                    state.showsGuitarPicker = true
                }
            }

            iconButton(systemName: "slider.horizontal.3", tint: .secondary, label: "Настройки") {
                state.showsSettings = true
            }
        }
        .frame(height: 40)
        .overlay(alignment: .center) {
            if state.isRecording {
                Text(state.recordingTimeText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.record)
                    .allowsHitTesting(false)
            }
        }
    }

    private var keyStepper: some View {
        HStack(spacing: 2) {
            Button { state.transpose(by: -1) } label: {
                Image(systemName: "minus").font(.system(size: 11, weight: .bold))
                    .frame(width: 26, height: 30)
            }
            .buttonStyle(.plain)

            Text(Pitch.name(state.preferences.key.tonic))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.accent)
                .frame(minWidth: 30)
                .contentTransition(.numericText())

            Button { state.transpose(by: 1) } label: {
                Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                    .frame(width: 26, height: 30)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private var scaleToggle: some View {
        Button {
            state.setKey(scale: state.preferences.key.scale == .major ? .minor : .major)
        } label: {
            Text(state.preferences.key.scale.displayName)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.8))
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Capsule().fill(Theme.accent))
        }
        .buttonStyle(.plain)
    }

    private func iconButton(systemName: String,
                            tint: Color,
                            label: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 34)
        }
        .buttonStyle(.glass)
        .accessibilityLabel(label)
    }
}
