import SwiftUI

/// Выбор инструмента и правка его тембра.
struct GuitarPickerView: View {
    @Environment(AppState.self) private var state
    @Namespace private var glass

    private var model: GuitarModel { state.guitar }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 8) {
                    ForEach(GuitarModel.Kind.allCases) { kind in
                        card(kind)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Тембр").sectionLabel()

                slider("Яркость", symbol: "sun.max",
                       binding: value(\.brightness), range: 0...1,
                       hint: "мягко ↔ звонко")

                slider("Сустейн", symbol: "waveform.path",
                       binding: value(\.sustain), range: 1.2...6.5,
                       format: { String(format: "%.1f с", $0) },
                       hint: "как долго тянется струна")

                slider("Медиатор", symbol: "hand.point.up.left",
                       binding: value(\.pickPosition), range: 0.05...0.35,
                       hint: "у бриджа ↔ у грифа")

                slider("Корпус", symbol: "circle.circle",
                       binding: value(\.body), range: 0...1,
                       hint: "гулкость деки")

                slider("Помещение", symbol: "wave.3.right",
                       binding: value(\.reverb), range: 0...0.5)

                if model.kind == .electric {
                    slider("Перегруз", symbol: "bolt",
                           binding: value(\.drive), range: 0...1)
                }
            }

            Divider().opacity(0.4)

            HStack {
                Text(model.kind.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Вернуть заводской") { state.resetGuitar() }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private func card(_ kind: GuitarModel.Kind) -> some View {
        let selected = model.kind == kind
        return Button {
            state.selectGuitar(kind)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "guitars.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selected ? Color.black.opacity(0.8) : Theme.accent)
                Text(kind.title)
                    .font(.system(size: 11, weight: selected ? .semibold : .medium, design: .rounded))
                    .foregroundStyle(selected ? Color.black.opacity(0.8) : .primary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 62)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()   // прямоугольное кольцо фокуса ломает форму карточки
        .glassEffect(selected ? .regular.tint(Theme.accent.opacity(0.9)).interactive()
                              : .regular.interactive(),
                     in: .rect(cornerRadius: 16, style: .continuous))
        .glassEffectID(kind.rawValue, in: glass)
        .help(kind.subtitle)
    }

    /// Слайдер правит копию инструмента и сразу отдаёт её движку.
    private func value(_ keyPath: WritableKeyPath<GuitarModel, Double>) -> Binding<Double> {
        Binding(
            get: { state.guitar[keyPath: keyPath] },
            set: { newValue in
                var updated = state.guitar
                updated[keyPath: keyPath] = newValue
                state.updateGuitar(updated)
            }
        )
    }

    private func slider(_ title: String,
                        symbol: String,
                        binding: Binding<Double>,
                        range: ClosedRange<Double>,
                        format: ((Double) -> String)? = nil,
                        hint: String? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 11, weight: .medium))
                if let hint {
                    Text(hint).font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }
            .frame(width: 92, alignment: .leading)
            Slider(value: binding, in: range)
                .controlSize(.small)
                .tint(Theme.accent)
            Text(format?(binding.wrappedValue)
                 ?? "\(Int((binding.wrappedValue - range.lowerBound) / (range.upperBound - range.lowerBound) * 100))%")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }
}
