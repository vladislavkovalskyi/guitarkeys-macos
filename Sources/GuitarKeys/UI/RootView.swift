import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var state
    @UIState private var energy: Double = 0

    var body: some View {
        @Bindable var state = state

        ZStack {
            AmbientBackground(root: state.currentChord.root, energy: energy)

            VStack(spacing: 0) {
                HeaderView()

                VStack(spacing: 16) {
                    PadGridView()
                    FretboardView()
                    StrumDeckView()
                    footer
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 20)
                .frame(maxHeight: .infinity)   // запас высоты уходит грифу
            }

            if state.bindingTarget != nil {
                bindingOverlay
            }

            if let notice = state.recordingNotice {
                savedOverlay(notice)
            }
        }
        .frame(minWidth: 860, minHeight: 640)
        .preferredColorScheme(.dark)
        .onChange(of: state.strumTick) { _, _ in
            withAnimation(.easeOut(duration: 0.10)) { energy = 1 }
            withAnimation(.easeOut(duration: 0.85).delay(0.10)) { energy = 0 }
        }
        .sheet(item: $state.inspectorPad) { pad in
            PadInspector(pad: pad)
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            hint("аккорд", "удерживайте клавишу")
            divider
            hint("бой", "↓ ↑ ␣")
            divider
            hint("струны", "1…6 или мышью по грифу")
            divider
            hint("глушение", "← →")
            divider
            hint("тональность", "[ ]")
            Spacer()
            Text(state.currentChord.name)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.accent.opacity(0.85))
        }
        .padding(.horizontal, 4)
        .frame(height: 18)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(width: 1, height: 10)
    }

    private func hint(_ title: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private func savedOverlay(_ url: URL) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.record)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Записано")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Text(url.lastPathComponent)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Button(state.isPlayingBack ? "Стоп" : "Прослушать") {
                    state.togglePlayback()
                }
                .buttonStyle(.glass)
                .controlSize(.small)

                Button("Показать") { state.revealLastRecording() }
                    .buttonStyle(.glass)
                    .controlSize(.small)

                Button {
                    withAnimation(.easeOut(duration: 0.25)) { state.recordingNotice = nil }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .glassEffect(.regular.tint(Theme.record.opacity(0.16)), in: .capsule)
            .padding(.bottom, 40)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: state.recordingNotice)
    }

    private var bindingOverlay: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                Image(systemName: "keyboard")
                    .foregroundStyle(Theme.accent)
                Text("Нажмите клавишу")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text("Esc — отмена")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .glassEffect(.regular.tint(Theme.accent.opacity(0.22)), in: .capsule)
            .padding(.bottom, 40)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: state.bindingTarget)
        .allowsHitTesting(false)
    }
}
