import SwiftUI

/// Плашка «записано» с прослушиванием. Одна на обе платформы.
struct RecordingNotice: View {
    let url: URL
    @Environment(AppState.self) private var state

    var body: some View {
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
                    .truncationMode(.middle)
            }

            Button(state.isPlayingBack ? "Стоп" : "Прослушать") {
                state.togglePlayback()
            }
            .buttonStyle(.glass)
            .controlSize(.small)

            #if os(macOS)
            Button("Показать") { state.revealLastRecording() }
                .buttonStyle(.glass)
                .controlSize(.small)
            #endif

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
    }
}
