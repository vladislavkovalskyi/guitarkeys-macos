import SwiftUI

/// Таймлайн проекта: сплошная лента слева направо, такты идут подряд.
/// Слева закреплены подписи дорожек, справа — прокручиваемая сетка,
/// поверх которой бежит курсор воспроизведения.
struct StudioTimeline: View {
    @Environment(AppState.self) private var state

    let brush: StudioBrush
    let brushVelocity: Double
    let brushFret: Int
    /// Ширина одного деления — она же зум.
    let cellWidth: CGFloat
    let showsTabs: Bool
    let compact: Bool

    private var song: Song { state.song }
    private let gutter: CGFloat = 34

    /// Высоты дорожек считаются от доступного места, иначе под таймлайном
    /// остаётся пустое поле, а на весь экран — половина окна.
    var body: some View {
        GeometryReader { proxy in
            let rest = max(150, proxy.size.height - 16 - 34 - 14)
            let strumHeight = showsTabs ? max(44, rest * 0.34) : rest
            let tabHeight = showsTabs ? max(18, (rest - strumHeight - 10) / 6) : 0

            HStack(alignment: .top, spacing: 6) {
                trackLabels(strumHeight: strumHeight, tabHeight: tabHeight)

                ScrollView(.horizontal, showsIndicators: true) {
                    ZStack(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 4) {
                            ruler
                            chordTrack
                            strumTrack(height: strumHeight)
                            if showsTabs { tabTracks(height: tabHeight) }
                        }
                        playhead(height: proxy.size.height)
                    }
                    .padding(.trailing, 24)
                }
            }
        }
    }

    // MARK: Подписи дорожек

    private func trackLabels(strumHeight: CGFloat, tabHeight: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            label("такт", height: 16)
            label("аккорд", height: 34)
            label("бой", height: strumHeight)
            if showsTabs {
                VStack(spacing: 2) {
                    ForEach((0..<6).reversed(), id: \.self) { string in
                        label(Pitch.name(Pitch.standardTuning[string] % 12), height: tabHeight)
                    }
                }
            }
        }
        .frame(width: gutter, alignment: .trailing)
    }

    private func label(_ text: String, height: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .medium, design: .rounded))
            .foregroundStyle(.tertiary)
            .frame(height: height, alignment: .center)
    }

    // MARK: Линейка

    private var ruler: some View {
        HStack(spacing: 0) {
            ForEach(Array(song.bars.enumerated()), id: \.element.id) { index, bar in
                HStack(spacing: 0) {
                    Text("\(index + 1)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(width: cellWidth, alignment: .leading)
                    ForEach(1..<max(1, bar.slotCount), id: \.self) { slot in
                        // Точками отмечены сильные доли — по ним считается ритм.
                        Text(song.isDownbeat(slot) ? "·" : "")
                            .font(.system(size: 9))
                            .foregroundStyle(.quaternary)
                            .frame(width: cellWidth)
                    }
                }
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.18)).frame(width: 1)
                }
            }
        }
        .frame(height: 16)
    }

    // MARK: Аккорды

    private var chordTrack: some View {
        HStack(spacing: 2) {
            ForEach(Array(song.bars.enumerated()), id: \.element.id) { index, bar in
                ChordClip(index: index, bar: bar,
                          width: cellWidth * CGFloat(bar.slotCount) - 2)
            }
        }
        .frame(height: 34)
                .contentShape(Rectangle())
    }

    // MARK: Бой

    private func strumTrack(height: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(song.bars.enumerated()), id: \.element.id) { index, bar in
                ForEach(0..<bar.slotCount, id: \.self) { slot in
                    StrumCell(bar: index, slot: slot,
                              event: bar.strumEvent(at: slot) ?? bar.slots[slot].first(where: { $0.string == nil }),
                              isDownbeat: song.isDownbeat(slot),
                              isBarStart: slot == 0,
                              brush: brush,
                              brushVelocity: brushVelocity,
                              isPlaying: isPlayhead(bar: index, slot: slot))
                        .frame(width: cellWidth)
                }
            }
        }
        .frame(height: height)
    }

    // MARK: Табулатура

    private func tabTracks(height: CGFloat) -> some View {
        VStack(spacing: 2) {
            ForEach((0..<6).reversed(), id: \.self) { string in
                HStack(spacing: 0) {
                    ForEach(Array(song.bars.enumerated()), id: \.element.id) { index, bar in
                        let voicing = state.song.chord(inBar: index).map { ChordLibrary.voicing(for: $0) }
                        ForEach(0..<bar.slotCount, id: \.self) { slot in
                            TabCell(bar: index, slot: slot, string: string,
                                    event: bar.note(string: string, at: slot),
                                    chordFret: voicing?.frets[string] ?? nil,
                                    isDownbeat: song.isDownbeat(slot),
                                    isBarStart: slot == 0,
                                    brush: brush,
                                    brushVelocity: brushVelocity,
                                    brushFret: brushFret,
                                    isPlaying: isPlayhead(bar: index, slot: slot))
                                .frame(width: cellWidth)
                        }
                    }
                }
                .frame(height: height)
            }
        }
    }

    // MARK: Курсор

    private func playhead(height: CGFloat) -> some View {
        let slot = state.player.currentSlot
        return Group {
            if slot >= 0 {
                Rectangle()
                    .fill(Theme.accent)
                    .frame(width: 2, height: height)
                    .contentShape(Rectangle())
                    .offset(x: CGFloat(slot) * cellWidth)
                    .allowsHitTesting(false)
                    .animation(.linear(duration: 0.05), value: slot)
            }
        }
    }

    private func isPlayhead(bar: Int, slot: Int) -> Bool {
        state.player.currentSlot == song.absoluteSlot(bar: bar, slot: slot)
    }
}

// MARK: - Клип аккорда

private struct ChordClip: View {
    let index: Int
    let bar: Bar
    let width: CGFloat

    @Environment(AppState.self) private var state
    @UIState private var isDropTarget = false

    private var chordName: String { state.song.chord(inBar: index)?.name ?? "—" }

    var body: some View {
        Menu {
            // Ступени тональности идут первыми: ими пользуются чаще всего,
            // и они едут за сменой тональности.
            Section("Ступень тональности") {
                ForEach(0..<7, id: \.self) { degree in
                    let triad = state.song.key.chord(degree: degree, seventh: false)
                    let seventh = state.song.key.chord(degree: degree, seventh: true)
                    Button("\(triad.name)  ·  \(state.song.key.roman(degree: degree, seventh: false))") {
                        state.setBarChord(bar: index, source: .degree(index: degree, seventh: false))
                    }
                    Button("\(seventh.name)  ·  \(state.song.key.roman(degree: degree, seventh: true))") {
                        state.setBarChord(bar: index, source: .degree(index: degree, seventh: true))
                    }
                }
            }

            // Любой из 252 аккордов: сначала тон, внутри — виды по группам.
            Menu("Любой аккорд") {
                ForEach(0..<12, id: \.self) { tone in
                    Menu(Pitch.name(tone)) {
                        ForEach(ChordQuality.Family.allCases) { family in
                            Section(family.title) {
                                ForEach(family.qualities, id: \.self) { quality in
                                    Button(Chord(root: tone, quality: quality).name) {
                                        state.setBarChord(bar: index,
                                                          source: .fixed(Chord(root: tone, quality: quality)))
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Divider()

            Menu("Ритм такта") {
                ForEach(RhythmPattern.Family.allCases) { family in
                    Section(family.title) {
                        ForEach(RhythmLibrary.patterns(in: family)) { pattern in
                            Button(pattern.name) { state.applyPattern(pattern, toBar: index) }
                        }
                    }
                }
            }

            Divider()
            Button("Копировать такт") { state.copyBar(at: index) }
            if state.copiedBar != nil {
                Button("Вставить в этот такт") { state.pasteBar(at: index) }
            }
            Button("Продублировать такт") { state.duplicateBar(at: index) }
            Button("Очистить такт") { state.clearBar(at: index) }
            Button("Удалить такт", role: .destructive) { state.removeBar(at: index) }
        } label: {
            Text(chordName)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: max(30, width), height: 30)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.accent.opacity(0.16))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(isDropTarget ? Theme.accent : Theme.accent.opacity(0.35),
                                              lineWidth: isDropTarget ? 2 : 1)
                        }
                }
        }
        .menuStyle(.borderlessButton)
        // Ширину задаёт такт, поэтому fixedSize здесь нельзя: он сжал бы клип
        // до размера названия аккорда.
        .frame(width: max(30, width))
        // Такт целиком перетаскивается за свой аккорд.
        .draggable(bar.id.uuidString) {
            Text(chordName)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Theme.accent, in: .rect(cornerRadius: 9, style: .continuous))
                .foregroundStyle(.black)
        }
        .dropDestination(for: String.self) { items, _ in
            guard let identifier = items.first, let dragged = UUID(uuidString: identifier) else { return false }
            state.moveBar(dragged, before: bar.id)
            return true
        } isTargeted: { isDropTarget = $0 }
    }
}

// MARK: - Ячейка боя

private struct StrumCell: View {
    let bar: Int
    let slot: Int
    let event: StepEvent?
    let isDownbeat: Bool
    let isBarStart: Bool
    let brush: StudioBrush
    let brushVelocity: Double
    let isPlaying: Bool

    @Environment(AppState.self) private var state
    @UIState private var isDragging = false
    @UIState private var dragStartVelocity: Double = 1

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.white.opacity(isDownbeat ? 0.07 : 0.03))
                .padding(.horizontal, 1)

            if let event {
                // Высота заливки — сила удара: динамика видна с одного взгляда.
                GeometryReader { proxy in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(event.isMuted ? Theme.mutedAccent : Theme.accent)
                            .frame(height: max(10, proxy.size.height * min(1, event.velocity / 1.4)))
                    }
                    .padding(.horizontal, 1)
                }

                Image(systemName: event.symbolName)
                    .font(.system(size: event.isStrum ? 11 : 6, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.82))
                    .padding(.bottom, 5)
            }

            if isBarStart {
                HStack {
                    Rectangle().fill(Color.white.opacity(0.22)).frame(width: 1)
                    Spacer()
                }
            }

            if isPlaying {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: 1.5)
                    .padding(.horizontal, 1)
            }
        }
        .contentShape(Rectangle())
        .animation(.snappy(duration: 0.14), value: event)
        .gesture(gesture)
        .help(event.map { "Сила \(Int($0.velocity * 100))%" } ?? "")
    }

    private var gesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let event else { return }
                if !isDragging {
                    guard abs(value.translation.height) > 6 else { return }
                    isDragging = true
                    dragStartVelocity = event.velocity
                }
                state.setVelocity(bar: bar, slot: slot, eventID: event.id,
                                  velocity: dragStartVelocity - value.translation.height / 60)
            }
            .onEnded { _ in
                defer { isDragging = false }
                guard !isDragging else { return }
                apply()
            }
    }

    private func apply() {
        switch brush {
        case .eraser:
            state.clearSlot(bar: bar, slot: slot)
        case .strum(let direction, let muted):
            state.toggleSlot(bar: bar, slot: slot,
                             event: .strum(direction, muted: muted, velocity: brushVelocity))
        case .pluck(let string):
            state.toggleSlot(bar: bar, slot: slot,
                             event: .pluck(string: string, velocity: brushVelocity))
        case .note:
            state.toggleSlot(bar: bar, slot: slot,
                             event: .strum(.down, velocity: brushVelocity))
        }
        Haptics.pluck()
    }
}

// MARK: - Ячейка табулатуры

private struct TabCell: View {
    let bar: Int
    let slot: Int
    let string: Int
    let event: StepEvent?
    /// Какой лад зажат на этой струне в аккорде такта; nil — струна не звучит.
    let chordFret: Int?
    let isDownbeat: Bool
    let isBarStart: Bool
    let brush: StudioBrush
    let brushVelocity: Double
    let brushFret: Int
    let isPlaying: Bool

    @Environment(AppState.self) private var state
    @UIState private var isDragging = false
    @UIState private var dragStartFret: Int = 0

    private var pinnedFret: Int? {
        if case .note(_, let fret) = event?.kind { return fret }
        return nil
    }

    private var followsChord: Bool {
        if case .pluck = event?.kind { return true }
        return false
    }

    private var soundingFret: Int? { pinnedFret ?? (followsChord ? chordFret : nil) }
    private var isSilent: Bool { followsChord && chordFret == nil }

    var body: some View {
        ZStack {
            if event == nil {
                // Струна тянется сквозь пустые ячейки — сетка читается как табулатура.
                Rectangle().fill(Color.white.opacity(isDownbeat ? 0.22 : 0.12)).frame(height: 1)
            } else {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(fill)
                    .padding(.horizontal, 1)
            }

            if isSilent {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.55))
            } else if let fret = soundingFret {
                Text("\(fret)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.85))
                    .opacity(0.5 + 0.5 * min(1, (event?.velocity ?? 1) / 1.4))
            }

            if isBarStart {
                HStack {
                    Rectangle().fill(Color.white.opacity(0.22)).frame(width: 1)
                    Spacer()
                }
            }

            if isPlaying {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.8), lineWidth: 1)
                    .padding(.horizontal, 1)
            }
        }
        .contentShape(Rectangle())
        .animation(.snappy(duration: 0.12), value: soundingFret)
        .gesture(gesture)
        .help(helpText)
    }

    private var fill: AnyShapeStyle {
        if isSilent { return AnyShapeStyle(Color.white.opacity(0.12)) }
        // Нота из аккорда светлее: видно, что лад следует аккорду, а не приколочен.
        return AnyShapeStyle(followsChord ? Theme.accent.opacity(0.62) : Theme.accent)
    }

    private var helpText: String {
        let number = 6 - string
        if isSilent { return "Струна \(number) в этом аккорде не звучит" }
        if let pinned = pinnedFret { return "Струна \(number), лад \(pinned) — задан вручную" }
        if let chord = chordFret { return "Струна \(number), лад \(chord) — из аккорда" }
        return "Струна \(number)"
    }

    private var gesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let current = soundingFret else { return }
                if !isDragging {
                    guard abs(value.translation.height) > 6 else { return }
                    isDragging = true
                    dragStartFret = current
                }
                let target = max(0, min(24, dragStartFret + Int((-value.translation.height / 14).rounded())))
                if target != pinnedFret {
                    state.setNote(bar: bar, slot: slot, string: string,
                                  fret: target, velocity: event?.velocity ?? brushVelocity)
                }
            }
            .onEnded { _ in
                defer { isDragging = false }
                guard !isDragging else { return }
                apply()
            }
    }

    private func apply() {
        switch brush {
        case .eraser:
            state.clearNote(bar: bar, slot: slot, string: string)
        case .note:
            // Кисть с номером лада прибивает лад намертво, как в табулатуре.
            if pinnedFret == brushFret {
                state.clearNote(bar: bar, slot: slot, string: string)
            } else {
                state.setNote(bar: bar, slot: slot, string: string,
                              fret: brushFret, velocity: brushVelocity)
            }
        default:
            // По умолчанию нота идёт из аккорда и едет за его сменой.
            state.toggleSlot(bar: bar, slot: slot,
                             event: .pluck(string: string, velocity: brushVelocity))
        }
        Haptics.pluck()
    }
}
