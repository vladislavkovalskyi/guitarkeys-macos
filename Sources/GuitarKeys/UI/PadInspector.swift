import SwiftUI

/// Настройка одной клавиши: ступень лада или конкретный аккорд.
struct PadInspector: View {
    let pad: Pad
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @UIState private var followsKey: Bool
    @UIState private var degree: Int
    @UIState private var seventh: Bool
    @UIState private var root: Int
    @UIState private var quality: ChordQuality

    init(pad: Pad) {
        self.pad = pad
        switch pad.source {
        case .degree(let index, let isSeventh):
            _followsKey = State(initialValue: true)
            _degree = State(initialValue: index)
            _seventh = State(initialValue: isSeventh)
            _root = State(initialValue: 0)
            _quality = State(initialValue: .major)
        case .fixed(let chord):
            _followsKey = State(initialValue: false)
            _degree = State(initialValue: 0)
            _seventh = State(initialValue: false)
            _root = State(initialValue: chord.root)
            _quality = State(initialValue: chord.quality)
        }
    }

    private var resultingChord: Chord {
        followsKey
            ? state.preferences.key.chord(degree: degree, seventh: seventh)
            : Chord(root: root, quality: quality)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(resultingChord.name)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accent)
                Text(resultingChord.quality.displayName)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    state.bindingTarget = .pad(pad.id)
                    dismiss()
                } label: {
                    Text(pad.keyCode == 0xFFFF ? "назначить" : KeyCodes.label(for: pad.keyCode))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .frame(minWidth: 40)
                }
                .buttonStyle(.glass)
                .help("Назначить клавишу")
            }

            Picker("", selection: $followsKey) {
                Text("Ступень лада").tag(true)
                Text("Свой аккорд").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if followsKey {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Ступень").sectionLabel()
                    HStack(spacing: 5) {
                        ForEach(0..<7, id: \.self) { index in
                            let chord = state.preferences.key.chord(degree: index, seventh: seventh)
                            chip(title: state.preferences.key.scale.romanNumerals[index],
                                 subtitle: chord.name,
                                 selected: degree == index) { degree = index }
                        }
                    }
                    Toggle("Септаккорд", isOn: $seventh)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .font(.system(size: 12))
                }
                Text("Такая клавиша следует за тональностью: сменили тональность — сменился аккорд.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Основной тон").sectionLabel()
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 6),
                              spacing: 5) {
                        ForEach(0..<12, id: \.self) { pitch in
                            chip(title: Pitch.name(pitch), subtitle: nil, selected: root == pitch) {
                                root = pitch
                            }
                        }
                    }

                    Text("Вид аккорда").sectionLabel()
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 5),
                              spacing: 5) {
                        ForEach(ChordQuality.allCases, id: \.self) { item in
                            chip(title: item.suffix.isEmpty ? "maj" : item.suffix,
                                 subtitle: nil,
                                 selected: quality == item) { quality = item }
                        }
                    }
                }
            }

            MiniFretboard(voicing: ChordLibrary.voicing(for: resultingChord))
                .frame(height: 74)

            HStack {
                Button("Прослушать") {
                    state.updatePad(pad, source: currentSource)
                    state.strum(direction: .down, muted: false)
                }
                .buttonStyle(.glass)
                Spacer()
                Button("Готово") {
                    state.updatePad(pad, source: currentSource)
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 420)
        .onChange(of: currentSource) { _, newValue in
            state.updatePad(pad, source: newValue)
        }
    }

    private var currentSource: PadSource {
        followsKey ? .degree(index: degree, seventh: seventh) : .fixed(Chord(root: root, quality: quality))
    }

    @ViewBuilder
    private func chip(title: String, subtitle: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 9))
                        .opacity(0.7)
                }
            }
            .foregroundStyle(selected ? Color.black.opacity(0.82) : Color.primary)
            .frame(maxWidth: .infinity)
            .frame(height: subtitle == nil ? 26 : 34)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.quaternary))
            }
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }
}

/// Компактная схема аккорда для инспектора.
private struct MiniFretboard: View {
    let voicing: Voicing

    var body: some View {
        Canvas { context, size in
            let start = voicing.minFret == 0 || voicing.maxFret <= 5 ? 0 : max(0, voicing.minFret - 1)
            let cols = 5
            let left: CGFloat = 26, right: CGFloat = 10, top: CGFloat = 8, bottom: CGFloat = 8
            let board = CGRect(x: left, y: top,
                               width: size.width - left - right,
                               height: size.height - top - bottom)
            guard board.width > 10, board.height > 10 else { return }
            let fw = board.width / CGFloat(cols)
            let sp = board.height / 5

            for i in 0...cols {
                let x = board.minX + CGFloat(i) * fw
                var p = Path()
                p.move(to: CGPoint(x: x, y: board.minY))
                p.addLine(to: CGPoint(x: x, y: board.maxY))
                context.stroke(p, with: .color(.white.opacity(i == 0 && start == 0 ? 0.7 : 0.18)),
                               lineWidth: i == 0 && start == 0 ? 3 : 1)
            }

            for s in 0..<6 {
                let y = board.maxY - CGFloat(s) * sp
                var p = Path()
                p.move(to: CGPoint(x: board.minX, y: y))
                p.addLine(to: CGPoint(x: board.maxX, y: y))
                let muted = voicing.frets[s] == nil
                context.stroke(p, with: .color(.white.opacity(muted ? 0.10 : 0.38)), lineWidth: 1)

                if muted {
                    var cross = Path()
                    let r: CGFloat = 3, x = board.minX - 12
                    cross.move(to: CGPoint(x: x - r, y: y - r)); cross.addLine(to: CGPoint(x: x + r, y: y + r))
                    cross.move(to: CGPoint(x: x + r, y: y - r)); cross.addLine(to: CGPoint(x: x - r, y: y + r))
                    context.stroke(cross, with: .color(.white.opacity(0.28)), lineWidth: 1.3)
                } else if voicing.frets[s] == 0 {
                    let r: CGFloat = 3.5, x = board.minX - 12
                    context.stroke(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                   with: .color(.white.opacity(0.5)), lineWidth: 1.3)
                }
            }

            for s in 0..<6 {
                guard let fret = voicing.frets[s], fret > start, fret - start <= cols else { continue }
                let y = board.maxY - CGFloat(s) * sp
                let x = board.minX + (CGFloat(fret - start) - 0.5) * fw
                let r: CGFloat = 6
                context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                             with: .color(Theme.accent))
            }

            if start > 0 {
                context.draw(Text("\(start + 1)").font(.system(size: 9)).foregroundStyle(.secondary),
                             at: CGPoint(x: board.minX + 6, y: board.minY - 2))
            }
        }
    }
}
