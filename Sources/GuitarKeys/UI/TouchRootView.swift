import SwiftUI

/// Экран для iPhone и iPad. Раскладка та же, что на маке, но клавиш нет:
/// аккорд держит палец, а бой берётся с грифа или с площадок внизу.
struct TouchRootView: View {
    @Environment(AppState.self) private var state
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @UIState private var energy: Double = 0

    var body: some View {
        @Bindable var state = state

        GeometryReader { proxy in
            // Считаем по реальному размеру, а не только по классу: в ландшафте
            // телефон широкий, но низкий, и раскладку решает именно высота.
            let narrow = proxy.size.width < 700
            let short = proxy.size.height < 520
            let compact = narrow || sizeClass == .compact

            // Узкий экран — меньше колонок; низкий — ниже площадки,
            // иначе четыре ряда аккордов съедают гриф.
            let columns = narrow ? 4 : 7
            let padHeight: CGFloat = short ? 46 : (compact ? 60 : 84)
            let strumHeight: CGFloat = short ? 52 : (compact ? 66 : 86)

            VStack(spacing: compact ? 10 : 14) {
                header(compact: compact)
                if state.screen == .studio {
                    StudioView(compact: compact)
                } else {
                    TouchPadGrid(columns: columns, padHeight: padHeight)
                    FretboardView()
                    TouchStrumBar(height: strumHeight)
                }
            }
            .padding(.horizontal, compact ? 12 : 20)
            .padding(.bottom, compact ? 8 : 16)
            // Размер задаём явно: фон с ignoresSafeArea, лежащий в стопке рядом
            // с содержимым, растягивал бы контейнер за пределы экрана.
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background {
                AmbientBackground(root: state.currentChord.root, energy: energy)
                    .ignoresSafeArea()
            }
            .overlay(alignment: .bottom) {
                if let notice = state.recordingNotice {
                    RecordingNotice(url: notice)
                        .padding(.horizontal, 12)
                        .padding(.bottom, compact ? 96 : 116)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { Haptics.prepare() }
        .onChange(of: scenePhase) { _, phase in
            // На iOS нет applicationWillTerminate: приложение просто уходит в фон.
            // Незакрытый файл записи остался бы битым, поэтому закрываем сами.
            if phase != .active {
                state.stopRecording()
                state.stopPlayback()
            }
        }
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
            screenPicker
            keyStepper(compact: compact)
            if !compact { scaleToggle }

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

    /// Игра или студия — на телефоне только иконки, места на подписи нет.
    private var screenPicker: some View {
        HStack(spacing: 2) {
            ForEach(AppScreen.allCases) { screen in
                let selected = state.screen == screen
                Button {
                    state.screen = screen
                    Haptics.pluck()
                } label: {
                    Image(systemName: screen.symbolName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selected ? Color.black.opacity(0.82) : .secondary)
                        .frame(width: 32, height: 28)
                        .background {
                            if selected { Capsule().fill(Theme.accent) }
                        }
                }
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .accessibilityLabel(screen.title)
            }
        }
        .padding(3)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private func keyStepper(compact: Bool) -> some View {
        // На узком экране слово «мажор» рядом не помещается, поэтому лад пишется
        // прямо в названии тональности: C или Cm, как записывают аккорд.
        let tonic = Pitch.name(state.preferences.key.tonic)
        let title = compact && state.preferences.key.scale == .minor ? tonic + "m" : tonic

        return HStack(spacing: 2) {
            Button { state.transpose(by: -1) } label: {
                Image(systemName: "minus").font(.system(size: 11, weight: .bold))
                    .frame(width: 26, height: 30)
            }
            .contentShape(Rectangle())
            .buttonStyle(.plain)

            Button {
                guard compact else { return }
                state.setKey(scale: state.preferences.key.scale == .major ? .minor : .major)
                Haptics.pluck()
            } label: {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accent)
                    .frame(minWidth: 34)
                    .fixedSize()
                    .contentTransition(.numericText())
            }
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .disabled(!compact)
            .accessibilityLabel(state.preferences.key.name)

            Button { state.transpose(by: 1) } label: {
                Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                    .frame(width: 26, height: 30)
            }
            .contentShape(Rectangle())
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
        .contentShape(Rectangle())
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
