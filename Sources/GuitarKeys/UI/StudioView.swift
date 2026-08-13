import SwiftUI

/// Творческая студия: таймлайн проекта, кисти и транспорт.
/// Сетка настраивается — размер такта и дробление доли задаются в шапке.
struct StudioView: View {
    @Environment(AppState.self) private var state

    let compact: Bool

    var body: some View {
        VStack(spacing: compact ? 8 : 10) {
            transport
            brushBar

            StudioTimeline(brush: state.brush,
                           brushVelocity: state.brushVelocity,
                           brushFret: state.brushFret,
                           cellWidth: state.timelineZoom,
                           showsTabs: state.showsTabs,
                           compact: compact)
                .frame(maxHeight: .infinity, alignment: .top)

            HStack(spacing: 8) {
                Button { state.addBar() } label: {
                    Label("Такт", systemImage: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                }
                .buttonStyle(.glass)

                if !compact { shortcutHints }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Транспорт

    private var transport: some View {
        @Bindable var state = state

        return HStack(spacing: 8) {
            Button {
                state.toggleSongPlayback()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: state.isSongPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                    if !compact {
                        Text(state.isSongPlaying ? "Стоп" : "Играть")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                }
                .padding(.horizontal, compact ? 10 : 14)
                .frame(height: 34)
            }
            .buttonStyle(.glass)
            .tint(Theme.accent)

            Button {
                state.player.loops.toggle()
            } label: {
                Image(systemName: "repeat")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(state.player.loops ? Theme.accent : .secondary)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.glass)
            .help("Повторять по кругу (L)")

            stepper(value: "\(Int(state.song.bpm))", caption: "темп",
                    minus: { state.song.bpm = max(40, state.song.bpm - 1) },
                    plus: { state.song.bpm = min(220, state.song.bpm + 1) })

            // Размер такта и дробление — сетка перестраивается на лету.
            stepper(value: "\(state.song.beatsPerBar)/4", caption: "размер",
                    minus: { state.setBeatsPerBar(state.song.beatsPerBar - 1) },
                    plus: { state.setBeatsPerBar(state.song.beatsPerBar + 1) })

            Menu {
                ForEach(Division.allCases) { division in
                    Button(division.title) { state.setDivision(division) }
                }
            } label: {
                VStack(spacing: 0) {
                    Text(state.song.division.title)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.accent)
                    Text("сетка").font(.system(size: 8)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 8)
                .frame(height: 34)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .glassEffect(.regular.interactive(), in: .capsule)

            if !compact {
                Text(durationLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 6)

            Button { state.saveSongProject() } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.glass)
            .help("Сохранить проект")

            Menu {
                Section("Свести в файл") {
                    ForEach(AudioFileFormat.allCases) { format in
                        Button("\(format.title) — \(format.subtitle)") {
                            state.exportSong(format: format)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    if state.isExporting {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    if !compact {
                        Text(state.isExporting ? "Сведение…" : "Свести")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                }
                .padding(.horizontal, compact ? 8 : 12)
                .frame(height: 34)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .glassEffect(.regular.interactive(), in: .capsule)
            .disabled(state.isExporting)
        }
    }

    private var durationLabel: String {
        let total = state.song.duration
        return String(format: "%d такта · %d:%02d", state.song.bars.count,
                      Int(total) / 60, Int(total) % 60)
    }

    private func stepper(value: String, caption: String,
                         minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack(spacing: 3) {
            Button(action: minus) {
                Image(systemName: "minus").font(.system(size: 9, weight: .bold))
                    .frame(width: 20, height: 28)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()

            VStack(spacing: 0) {
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.accent)
                Text(caption).font(.system(size: 8)).foregroundStyle(.tertiary)
            }
            .frame(minWidth: 32)

            Button(action: plus) {
                Image(systemName: "plus").font(.system(size: 9, weight: .bold))
                    .frame(width: 20, height: 28)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
        }
        .padding(.horizontal, 3)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    // MARK: Кисть

    private var brushBar: some View {
        @Bindable var state = state

        return VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    brushChip(.strum(direction: .down, muted: false), symbol: "arrow.down", hint: "1")
                    brushChip(.strum(direction: .up, muted: false), symbol: "arrow.up", hint: "2")
                    brushChip(.strum(direction: .down, muted: true), symbol: "arrow.down.to.line", hint: "3")
                    brushChip(.strum(direction: .up, muted: true), symbol: "arrow.up.to.line", hint: "4")

                    divider

                    ForEach(1...6, id: \.self) { number in
                        brushChip(.pluck(string: 6 - number), symbol: nil, label: "\(number)")
                    }

                    divider

                    brushChip(.note, symbol: "number", label: "лад", hint: "5")
                    brushChip(.eraser, symbol: "eraser", hint: "6")
                }
                .padding(.vertical, 2)
            }

            HStack(spacing: 10) {
                if state.brush.isNote {
                    stepper(value: "\(state.brushFret)", caption: "лад",
                            minus: { state.brushFret = max(0, state.brushFret - 1) },
                            plus: { state.brushFret = min(24, state.brushFret + 1) })
                }

                HStack(spacing: 7) {
                    Image(systemName: "speaker.wave.2")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Slider(value: $state.brushVelocity, in: 0.25...1.4)
                        .controlSize(.small)
                        .tint(Theme.accent)
                        .frame(maxWidth: 150)
                    Text("\(Int(state.brushVelocity * 100))%")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }

                Toggle("табы", isOn: $state.showsTabs)
                    .toggleStyle(.button)
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .help("Показать табулатуру (T)")

                HStack(spacing: 4) {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Slider(value: $state.timelineZoom, in: 16...64)
                        .controlSize(.small)
                        .tint(Theme.accent)
                        .frame(maxWidth: 90)
                }
                .help("Масштаб таймлайна ([ ])")

                Spacer(minLength: 0)
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 20)
    }

    private func brushChip(_ value: StudioBrush, symbol: String?,
                           label: String? = nil, hint: String? = nil) -> some View {
        let selected = state.brush == value
        let muted: Bool = {
            if case .strum(_, let isMuted) = value { return isMuted }
            return false
        }()

        return Button {
            state.brush = value
        } label: {
            HStack(spacing: 3) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: value == .note ? 9 : 11, weight: .semibold))
                }
                if let label {
                    Text(label)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                }
            }
            .foregroundStyle(selected ? Color.black.opacity(0.82)
                                      : (muted ? Theme.mutedAccent : Theme.accent))
            .frame(width: label == nil ? 36 : 40, height: 30)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(selected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.quaternary))
        }
        .help(hint.map { "\(value.title) (\($0))" } ?? value.title)
    }

    private var shortcutHints: some View {
        HStack(spacing: 10) {
            ForEach(AppState.studioShortcuts.prefix(7), id: \.keys) { shortcut in
                HStack(spacing: 3) {
                    Text(shortcut.keys)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.accent.opacity(0.9))
                    Text(shortcut.action)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}
