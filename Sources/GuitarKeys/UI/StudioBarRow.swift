import SwiftUI

/// Такт в студии. Показывается либо строкой боя, либо табулатурой на шесть струн.
struct StudioBarRow: View {
    let index: Int
    let bar: Bar
    let brush: StudioBrush
    let brushVelocity: Double
    let brushFret: Int
    let compact: Bool

    @Environment(AppState.self) private var state
    @UIState private var isDropTarget = false

    private var chordName: String { state.song.chord(inBar: index)?.name ?? "—" }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            header

            VStack(spacing: 3) {
                if bar.view == .strum {
                    strumLane
                } else {
                    tabLanes
                }
            }

            if !compact { actionsMenu }
        }
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isDropTarget ? Theme.accent : .clear, lineWidth: 2)
                }
        }
        // Перетаскиваем такт целиком — вместе с аккордом и рисунком.
        .dropDestination(for: String.self) { items, _ in
            guard let identifier = items.first, let dragged = UUID(uuidString: identifier) else { return false }
            state.moveBar(dragged, before: bar.id)
            return true
        } isTargeted: { isDropTarget = $0 }
        .contextMenu {
            Button("Продублировать") { state.duplicateBar(at: index) }
            Button("Очистить") { state.clearBar(at: index) }
            Button("Удалить такт", role: .destructive) { state.removeBar(at: index) }
        }
    }

    // MARK: Заголовок такта

    private var header: some View {
        VStack(spacing: 4) {
            Menu {
                Section("Ступень тональности") {
                    ForEach(0..<7, id: \.self) { degree in
                        let triad = state.song.key.chord(degree: degree, seventh: false)
                        let seventh = state.song.key.chord(degree: degree, seventh: true)
                        Button(triad.name) {
                            state.setBarChord(bar: index, source: .degree(index: degree, seventh: false))
                        }
                        Button(seventh.name) {
                            state.setBarChord(bar: index, source: .degree(index: degree, seventh: true))
                        }
                    }
                }
            } label: {
                VStack(spacing: 1) {
                    Text(chordName)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("такт \(index + 1)")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
                .frame(width: compact ? 56 : 68, height: 36)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10, style: .continuous))

            // Переключатель вида: бой или табулатура.
            HStack(spacing: 2) {
                ForEach(BarView.allCases) { view in
                    let selected = bar.view == view
                    Button {
                        state.setBarView(bar: index, view: view)
                    } label: {
                        Image(systemName: view.symbolName)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(selected ? Color.black.opacity(0.8) : .secondary)
                            .frame(width: compact ? 25 : 31, height: 20)
                            .background {
                                if selected {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Theme.accent)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .help(view.title)
                }
            }
            .padding(2)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary)
            }
        }
        // Тянуть такт можно за его шапку: ячейки заняты рисованием.
        .draggable(bar.id.uuidString) {
            Text(chordName)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.accent, in: .rect(cornerRadius: 10, style: .continuous))
                .foregroundStyle(.black)
        }
    }

    private var actionsMenu: some View {
        Menu {
            Button("Продублировать") { state.duplicateBar(at: index) }
            Button("Очистить") { state.clearBar(at: index) }
            Divider()
            Button("Удалить такт", role: .destructive) { state.removeBar(at: index) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 36)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: Бой

    private var strumLane: some View {
        HStack(spacing: 4) {
            ForEach(0..<Bar.slotCount, id: \.self) { slot in
                StrumSlotCell(bar: index,
                              slot: slot,
                              event: bar.strumEvent(at: slot) ?? bar.slots[slot].first,
                              brush: brush,
                              brushVelocity: brushVelocity,
                              isPlaying: isPlayhead(slot))
            }
        }
    }

    // MARK: Табулатура

    private var tabLanes: some View {
        // Сверху первая струна — как в табулатуре.
        VStack(spacing: 2) {
            ForEach((0..<6).reversed(), id: \.self) { string in
                HStack(spacing: 4) {
                    Text(Pitch.name(Pitch.standardTuning[string] % 12))
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .frame(width: 14, alignment: .trailing)

                    ForEach(0..<Bar.slotCount, id: \.self) { slot in
                        TabSlotCell(bar: index,
                                    slot: slot,
                                    string: string,
                                    event: bar.note(string: string, at: slot),
                                    brush: brush,
                                    brushVelocity: brushVelocity,
                                    brushFret: brushFret,
                                    isPlaying: isPlayhead(slot))
                    }
                }
            }
        }
    }

    private func isPlayhead(_ slot: Int) -> Bool {
        state.player.currentSlot == index * Bar.slotCount + slot
    }
}

// MARK: - Ячейка боя

private struct StrumSlotCell: View {
    let bar: Int
    let slot: Int
    let event: StepEvent?
    let brush: StudioBrush
    let brushVelocity: Double
    let isPlaying: Bool

    @Environment(AppState.self) private var state
    @UIState private var isDragging = false
    @UIState private var dragStartVelocity: Double = 1

    private var isDownbeat: Bool { slot % 2 == 0 }

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(isDownbeat ? 0.07 : 0.035))

            // Столбик силы: высота заливки читается как громкость удара.
            if let event {
                GeometryReader { proxy in
                    let height = proxy.size.height * min(1, event.velocity / 1.4)
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(event.isMuted ? Theme.mutedAccent : Theme.accent)
                            .frame(height: max(12, height))
                    }
                }
            }

            if let event {
                VStack(spacing: 1) {
                    Image(systemName: event.symbolName)
                        .font(.system(size: event.isStrum ? 12 : 7, weight: .semibold))
                    if !event.caption.isEmpty {
                        Text(event.caption)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                    }
                }
                .foregroundStyle(Color.black.opacity(0.82))
                .padding(.bottom, 4)
            }

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isPlaying ? Theme.accent : Color.white.opacity(isDownbeat ? 0.14 : 0.07),
                              lineWidth: isPlaying ? 2 : 1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 42)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .scaleEffect(isPlaying ? 1.06 : 1)
        .animation(.easeOut(duration: 0.08), value: isPlaying)
        .animation(.snappy(duration: 0.16), value: event)
        .gesture(gesture)
        .help(event.map { "Сила \(Int($0.velocity * 100))%" } ?? "")
    }

    /// Тап ставит событие, вертикальная тяга правит его силу.
    private var gesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let event else { return }
                if !isDragging {
                    guard abs(value.translation.height) > 6 else { return }
                    isDragging = true
                    dragStartVelocity = event.velocity
                }
                let delta = -value.translation.height / 60
                state.setVelocity(bar: bar, slot: slot, eventID: event.id,
                                  velocity: dragStartVelocity + delta)
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
            // В режиме боя нота без выбранной струны бессмысленна — переключаем на табы.
            state.setBarView(bar: bar, view: .tab)
        }
        Haptics.pluck()
    }
}

// MARK: - Ячейка табулатуры

private struct TabSlotCell: View {
    let bar: Int
    let slot: Int
    let string: Int
    let event: StepEvent?
    let brush: StudioBrush
    let brushVelocity: Double
    let brushFret: Int
    let isPlaying: Bool

    @Environment(AppState.self) private var state
    @UIState private var isDragging = false
    @UIState private var dragStartFret: Int = 0

    private var isDownbeat: Bool { slot % 2 == 0 }

    private var fret: Int? {
        if case .note(_, let fret) = event?.kind { return fret }
        return nil
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(fret != nil ? AnyShapeStyle(Theme.accent)
                                  : AnyShapeStyle(Color.white.opacity(isDownbeat ? 0.06 : 0.03)))

            // Струна нарисована сквозь пустые ячейки — сетка читается как табулатура.
            if fret == nil {
                Rectangle()
                    .fill(Color.white.opacity(0.16))
                    .frame(height: 1)
            }

            if let fret {
                Text("\(fret)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.85))
                    .opacity(0.45 + 0.55 * min(1, (event?.velocity ?? 1) / 1.4))
            }

            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(isPlaying ? Theme.accent.opacity(0.9) : .clear, lineWidth: 1.5)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 20)
        .animation(.snappy(duration: 0.14), value: fret)
        .gesture(gesture)
        .help(fret.map { "Струна \(6 - string), лад \($0)" } ?? "Струна \(6 - string)")
    }

    /// Тап ставит лад кисти, вертикальная тяга перебирает лады — удобно снимать табы.
    private var gesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let current = fret else { return }
                if !isDragging {
                    guard abs(value.translation.height) > 6 else { return }
                    isDragging = true
                    dragStartFret = current
                }
                let steps = Int((-value.translation.height / 14).rounded())
                let target = max(0, min(24, dragStartFret + steps))
                if target != current {
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
        case .pluck(let brushString) where brushString == string:
            state.toggleSlot(bar: bar, slot: slot,
                             event: .pluck(string: string, velocity: brushVelocity))
        default:
            // Повторный тап по той же ноте снимает её.
            if fret == brushFret {
                state.clearNote(bar: bar, slot: slot, string: string)
            } else {
                state.setNote(bar: bar, slot: slot, string: string,
                              fret: brushFret, velocity: brushVelocity)
            }
        }
        Haptics.pluck()
    }
}
