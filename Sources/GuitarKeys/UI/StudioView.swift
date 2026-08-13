import SwiftUI

/// Чем рисуем по сетке.
enum StudioBrush: Hashable {
    case strum(direction: StrumDirection, muted: Bool)
    case pluck(string: Int)
    /// Нота табулатуры: струну задаёт строка, лад — степпер.
    case note
    case eraser

    var isNote: Bool { self == .note }
}

/// Творческая студия: проект собирается из тактов, в каждом восемь восьмых.
/// Такт показывается либо строкой боя, либо табулатурой на шесть струн.
struct StudioView: View {
    @Environment(AppState.self) private var state

    @UIState private var brush: StudioBrush = .strum(direction: .down, muted: false)
    @UIState private var brushVelocity: Double = 1.0
    @UIState private var brushFret: Int = 0

    let compact: Bool

    var body: some View {
        VStack(spacing: compact ? 8 : 12) {
            transport
            brushBar

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(state.song.bars.enumerated()), id: \.element.id) { index, bar in
                        StudioBarRow(index: index,
                                     bar: bar,
                                     brush: brush,
                                     brushVelocity: brushVelocity,
                                     brushFret: brushFret,
                                     compact: compact)
                    }

                    Button {
                        state.addBar()
                    } label: {
                        Label("Добавить такт", systemImage: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                    }
                    .buttonStyle(.glass)
                }
                .padding(.bottom, 8)
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
            .help("Повторять по кругу")

            stepper(value: Int(state.song.bpm), caption: "темп",
                    minus: { state.song.bpm = max(40, state.song.bpm - 2) },
                    plus: { state.song.bpm = min(220, state.song.bpm + 2) })

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

    private func stepper(value: Int, caption: String,
                         minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack(spacing: 3) {
            Button(action: minus) {
                Image(systemName: "minus").font(.system(size: 9, weight: .bold))
                    .frame(width: 20, height: 28)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()

            VStack(spacing: 0) {
                Text("\(value)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.accent)
                Text(caption).font(.system(size: 8)).foregroundStyle(.tertiary)
            }
            .frame(minWidth: 30)

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
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    brushChip(.strum(direction: .down, muted: false), symbol: "arrow.down")
                    brushChip(.strum(direction: .up, muted: false), symbol: "arrow.up")
                    brushChip(.strum(direction: .down, muted: true), symbol: "arrow.down.to.line")
                    brushChip(.strum(direction: .up, muted: true), symbol: "arrow.up.to.line")

                    divider

                    ForEach(1...6, id: \.self) { number in
                        brushChip(.pluck(string: 6 - number), symbol: nil, label: "\(number)")
                    }

                    divider

                    brushChip(.note, symbol: "number", label: "лад")
                    brushChip(.eraser, symbol: "eraser")
                }
                .padding(.vertical, 2)
            }

            HStack(spacing: 12) {
                if brush.isNote {
                    stepper(value: brushFret, caption: "лад",
                            minus: { brushFret = max(0, brushFret - 1) },
                            plus: { brushFret = min(24, brushFret + 1) })
                }

                HStack(spacing: 8) {
                    Image(systemName: "speaker.wave.2")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Slider(value: $brushVelocity, in: 0.25...1.4)
                        .controlSize(.small)
                        .tint(Theme.accent)
                        .frame(maxWidth: 190)
                    Text("\(Int(brushVelocity * 100))%")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }

                if !compact {
                    Text("сила удара · тяните по ячейке вверх-вниз")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 20)
    }

    private func brushChip(_ value: StudioBrush, symbol: String?, label: String? = nil) -> some View {
        let selected = brush == value
        let muted: Bool = {
            if case .strum(_, let isMuted) = value { return isMuted }
            return false
        }()

        return Button {
            brush = value
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
    }
}
