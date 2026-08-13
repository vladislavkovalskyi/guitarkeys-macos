import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Гриф с текущей аппликатурой. По струнам можно бить мышью — проводка через
/// несколько струн играется как настоящий бой. Струны, по которым только что
/// ударили, физически колеблются: стоячая волна с узлом на прижатом ладу.
struct FretboardView: View {
    @Environment(AppState.self) private var state

    @UIState private var lastPluckedString: Int?
    @UIState private var hoveredString: Int?

    var body: some View {
        let voicing = state.currentVoicing
        let pulses = state.stringPulse
        let isIdle = pulses.compactMap { $0 }.allSatisfy { Date().timeIntervalSince($0) > 1.4 }

        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 45.0, paused: isIdle)) { timeline in
                Canvas { context, size in
                    draw(context: &context, size: size, voicing: voicing,
                         pulses: pulses, now: timeline.date)
                }
            }
            .contentShape(Rectangle())
            .gesture(strumGesture(size: proxy.size))
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let geometry = FretboardGeometry(size: proxy.size)
                    hoveredString = geometry?.stringIndex(at: location)
                case .ended:
                    hoveredString = nil
                }
            }
            #if os(macOS)
            // Курсор подсказывает, что по струнам можно бить.
            .onHover { inside in
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            #endif
        }
        .frame(minHeight: 148, maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.panelCorner, style: .continuous))
        .overlay(alignment: .topLeading) {
            Text(state.currentChord.name)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .allowsHitTesting(false)
        }
        .accessibilityLabel("Гриф, аккорд \(state.currentChord.name). Щёлкните по струне, чтобы дёрнуть её")
    }

    /// Проводка мышью: каждая новая струна под курсором звучит один раз.
    private func strumGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let geometry = FretboardGeometry(size: size),
                      let index = geometry.stringIndex(at: value.location),
                      index != lastPluckedString else { return }
                lastPluckedString = index
                state.pluck(string: index)
            }
            .onEnded { _ in lastPluckedString = nil }
    }

    /// Первый лад отображаемого окна.
    private func windowStart(_ voicing: Voicing) -> Int {
        let low = voicing.minFret
        let high = voicing.maxFret
        if low == 0 || high <= FretboardGeometry.visibleFrets { return 0 }
        return max(0, min(low - 1, high - FretboardGeometry.visibleFrets))
    }

    private func draw(context: inout GraphicsContext, size: CGSize, voicing: Voicing,
                      pulses: [Date?], now: Date) {
        guard let geometry = FretboardGeometry(size: size) else { return }
        let start = windowStart(voicing)
        let board = geometry.board
        let fretWidth = geometry.fretWidth
        let stringSpacing = geometry.stringSpacing
        let visibleFrets = FretboardGeometry.visibleFrets

        // Полотно грифа.
        context.fill(
            Path(roundedRect: board, cornerRadius: 6, style: .continuous),
            with: .linearGradient(
                Gradient(colors: [Color(red: 0.16, green: 0.11, blue: 0.09).opacity(0.85),
                                  Color(red: 0.10, green: 0.07, blue: 0.06).opacity(0.85)]),
                startPoint: CGPoint(x: board.minX, y: board.minY),
                endPoint: CGPoint(x: board.maxX, y: board.maxY)
            )
        )

        // Ладовые метки.
        for index in 0..<visibleFrets {
            let fret = start + index + 1
            guard [3, 5, 7, 9, 15, 17, 19, 21].contains(fret % 24) || fret % 12 == 0 else { continue }
            let x = board.minX + (CGFloat(index) + 0.5) * fretWidth
            let isDouble = fret % 12 == 0
            let radius: CGFloat = 4
            let centers: [CGPoint] = isDouble
                ? [CGPoint(x: x, y: board.midY - stringSpacing),
                   CGPoint(x: x, y: board.midY + stringSpacing)]
                : [CGPoint(x: x, y: board.midY)]
            for center in centers {
                context.fill(
                    Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                           width: radius * 2, height: radius * 2)),
                    with: .color(.white.opacity(0.10))
                )
            }
        }

        // Лады.
        for index in 0...visibleFrets {
            let x = board.minX + CGFloat(index) * fretWidth
            var path = Path()
            path.move(to: CGPoint(x: x, y: board.minY))
            path.addLine(to: CGPoint(x: x, y: board.maxY))
            let isNut = index == 0 && start == 0
            context.stroke(path,
                           with: .color(isNut ? .white.opacity(0.85) : .white.opacity(0.22)),
                           lineWidth: isNut ? 4 : 1.5)
        }

        // Номер лада, если окно смещено к грифу.
        if start > 0 {
            context.draw(
                Text("\(start + 1)").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary),
                at: CGPoint(x: board.minX - 10, y: board.minY - 8)
            )
        }

        // Струны: снизу 6-я (низкое E), сверху 1-я — как в табулатуре.
        for string in 0..<FretboardGeometry.stringCount {
            let y = geometry.y(ofString: string)
            let fret = voicing.frets[string]
            let isMuted = fret == nil
            let isHovered = hoveredString == string && !isMuted

            let intensity = pulseIntensity(pulses[string], now: now)
            let thickness = 2.6 - CGFloat(string) * 0.28

            // Узел стоячей волны — у прижатого лада, а не всегда у порожка.
            let nodeX: CGFloat
            if let fret, fret > start {
                nodeX = min(board.maxX, geometry.x(ofFret: fret, from: start))
            } else {
                nodeX = board.minX
            }

            var path = Path()
            path.move(to: CGPoint(x: geometry.stringStartX, y: y))

            if intensity > 0.01 && !isMuted {
                // Стоячая волна: пучность посередине свободной части струны.
                let freeStart = nodeX
                let freeEnd = board.maxX
                let oscillation = sin(now.timeIntervalSinceReferenceDate * (26 + Double(string) * 5))
                let amplitude = CGFloat(intensity) * (stringSpacing * 0.34) * CGFloat(oscillation)

                path.addLine(to: CGPoint(x: freeStart, y: y))
                let steps = 48
                for step in 1...steps {
                    let t = CGFloat(step) / CGFloat(steps)
                    let x = freeStart + (freeEnd - freeStart) * t
                    let envelope = sin(Double(t) * .pi)
                    path.addLine(to: CGPoint(x: x, y: y + amplitude * CGFloat(envelope)))
                }
            } else {
                path.addLine(to: CGPoint(x: board.maxX, y: y))
            }

            let base = Color(red: 0.78, green: 0.74, blue: 0.66)
            let color = isMuted
                ? Color.white.opacity(0.12)
                : base.mix(with: Theme.accent, by: Double(max(intensity, isHovered ? 0.45 : 0)))

            let glow = max(Double(intensity), isHovered ? 0.35 : 0)
            context.stroke(path,
                           with: .color(color.opacity(isMuted ? 1 : 0.55 + 0.45 * glow)),
                           lineWidth: thickness + CGFloat(intensity) * 0.8 + (isHovered ? 0.7 : 0))

            // Клавиша струны и название открытой ноты.
            if let keyCode = state.preferences.stringKey(forStringIndex: string) {
                context.draw(
                    Text(KeyCodes.label(for: keyCode))
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(isMuted ? Color.white.opacity(0.20)
                                                 : Theme.accent.opacity(isHovered ? 1 : 0.65)),
                    at: CGPoint(x: FretboardGeometry.keyLabelX, y: y)
                )
            }

            let openName = Pitch.name(Pitch.standardTuning[string] % 12)
            context.draw(
                Text(openName)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(isMuted ? Color.white.opacity(0.25) : Color.white.opacity(0.55)),
                at: CGPoint(x: FretboardGeometry.noteLabelX, y: y)
            )

            // Открытая струна или глушение.
            let markerX = FretboardGeometry.markerX
            if isMuted {
                var cross = Path()
                let r: CGFloat = 4
                cross.move(to: CGPoint(x: markerX - r, y: y - r))
                cross.addLine(to: CGPoint(x: markerX + r, y: y + r))
                cross.move(to: CGPoint(x: markerX + r, y: y - r))
                cross.addLine(to: CGPoint(x: markerX - r, y: y + r))
                context.stroke(cross, with: .color(.white.opacity(0.30)), lineWidth: 1.6)
            } else if fret == 0 {
                let r: CGFloat = 4.5
                context.stroke(
                    Path(ellipseIn: CGRect(x: markerX - r, y: y - r, width: r * 2, height: r * 2)),
                    with: .color(.white.opacity(0.55)), lineWidth: 1.6
                )
            }
        }

        // Баррэ — сплошная полоса поперёк струн.
        if let barre = voicing.barreFret, barre > start, barre - start <= visibleFrets {
            let x = geometry.x(ofFret: barre, from: start) - fretWidth * 0.5
            let strings = voicing.frets.enumerated().filter { $0.element == barre }.map(\.offset)
            if let low = strings.min(), let high = strings.max() {
                let yTop = geometry.y(ofString: high)
                let yBottom = geometry.y(ofString: low)
                let rect = CGRect(x: x - 8, y: min(yTop, yBottom) - 8,
                                  width: 16, height: abs(yBottom - yTop) + 16)
                context.fill(Path(roundedRect: rect, cornerRadius: 8, style: .continuous),
                             with: .color(Theme.accent.opacity(0.85)))
            }
        }

        // Прижатые пальцы.
        for string in 0..<FretboardGeometry.stringCount {
            guard let fret = voicing.frets[string], fret > start,
                  fret - start <= visibleFrets else { continue }
            let y = geometry.y(ofString: string)
            let x = geometry.x(ofFret: fret, from: start) - fretWidth * 0.5
            let r: CGFloat = 9
            let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
            context.fill(Path(ellipseIn: rect), with: .color(Theme.accent))
            context.fill(
                Path(ellipseIn: rect.insetBy(dx: 3, dy: 3)),
                with: .radialGradient(
                    Gradient(colors: [.white.opacity(0.5), .clear]),
                    center: CGPoint(x: x - 2, y: y - 3), startRadius: 0, endRadius: r
                )
            )
        }
    }

    /// Насколько ярко светится струна: экспоненциальный спад после удара.
    private func pulseIntensity(_ date: Date?, now: Date) -> Float {
        guard let date else { return 0 }
        let elapsed = now.timeIntervalSince(date)
        guard elapsed >= 0, elapsed < 1.6 else { return 0 }
        return Float(exp(-elapsed / 0.42))
    }
}
