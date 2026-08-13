import Foundation

/// Готовый ритмический рисунок на один такт.
///
/// Набивать «восьмёрку» руками по восьми ячейкам — работа, которую должна делать
/// программа. Рисунок применяется к такту или ко всему проекту одним нажатием,
/// а сетка при необходимости перестраивается под него.
struct RhythmPattern: Identifiable, Hashable, Sendable {
    var name: String
    var subtitle: String
    var beatsPerBar: Int
    var division: Division
    var slots: [[StepEvent]]

    var id: String { name }

    /// Группа для меню.
    enum Family: String, CaseIterable, Identifiable, Sendable {
        case strumming, picking, waltz

        var id: String { rawValue }
        var title: String {
            switch self {
            case .strumming: return "Бой"
            case .picking:   return "Перебор"
            case .waltz:     return "Трёхдольные"
            }
        }
    }

    var family: Family {
        if beatsPerBar == 3 { return .waltz }
        return slots.flatMap { $0 }.contains { $0.isStrum } ? .strumming : .picking
    }
}

enum RhythmLibrary {

    // Короткие помощники, чтобы рисунок читался как ритм, а не как таблица.
    private static let d = StepEvent.strum(.down)
    private static func d(_ velocity: Double) -> StepEvent { .strum(.down, velocity: velocity) }
    private static let u = StepEvent.strum(.up, velocity: 0.8)
    private static let x = StepEvent.strum(.down, muted: true, velocity: 0.8)
    private static let xu = StepEvent.strum(.up, muted: true, velocity: 0.75)
    private static func s(_ string: Int, _ velocity: Double = 0.9) -> StepEvent {
        .pluck(string: string, velocity: velocity)
    }

    static let all: [RhythmPattern] = [

        // MARK: Бой

        RhythmPattern(
            name: "Восьмёрка",
            subtitle: "вниз-вверх на каждую восьмую",
            beatsPerBar: 4, division: .eighth,
            slots: [[d(1.0)], [u], [d(0.85)], [u], [d(0.95)], [u], [d(0.85)], [u]]
        ),

        RhythmPattern(
            name: "Восьмёрка с глушением",
            subtitle: "та же, но слабые доли приглушены",
            beatsPerBar: 4, division: .eighth,
            slots: [[d(1.0)], [xu], [d(0.85)], [u], [x], [xu], [d(0.9)], [u]]
        ),

        RhythmPattern(
            name: "Шестёрка",
            subtitle: "вниз, вниз-вверх, вверх-вниз-вверх",
            beatsPerBar: 4, division: .eighth,
            slots: [[d(1.0)], [], [d(0.85)], [u], [], [u], [d(0.9)], [u]]
        ),

        RhythmPattern(
            name: "Четвёрка",
            subtitle: "ровные удары вниз по долям",
            beatsPerBar: 4, division: .eighth,
            slots: [[d(1.0)], [], [d(0.85)], [], [d(0.95)], [], [d(0.85)], []]
        ),

        RhythmPattern(
            name: "Галоп",
            subtitle: "шестнадцатыми, с оттяжкой",
            beatsPerBar: 4, division: .sixteenth,
            slots: [[d(1.0)], [], [u], [u], [d(0.9)], [], [u], [u],
                    [d(0.95)], [], [u], [u], [d(0.9)], [], [u], [u]]
        ),

        RhythmPattern(
            name: "Офбит",
            subtitle: "акцент на слабую долю, как в регги",
            beatsPerBar: 4, division: .eighth,
            slots: [[x], [d(1.0)], [x], [d(0.95)], [x], [d(1.0)], [x], [d(0.95)]]
        ),

        // MARK: Перебор

        RhythmPattern(
            name: "Перебор четвёркой",
            subtitle: "бас и три струны вверх",
            beatsPerBar: 4, division: .eighth,
            slots: [[s(1, 1.0)], [], [s(3)], [], [s(4)], [], [s(5)], []]
        ),

        RhythmPattern(
            name: "Перебор шестёркой",
            subtitle: "бас, вверх и обратно",
            beatsPerBar: 4, division: .eighth,
            slots: [[s(1, 1.0)], [], [s(3)], [s(4)], [s(5)], [s(4)], [s(3)], []]
        ),

        RhythmPattern(
            name: "Восьмёрка перебором",
            subtitle: "ровная россыпь по струнам",
            beatsPerBar: 4, division: .eighth,
            slots: [[s(1, 1.0)], [s(3)], [s(4)], [s(5)], [s(4)], [s(3)], [s(2)], [s(3)]]
        ),

        // MARK: Трёхдольные

        RhythmPattern(
            name: "Вальс",
            subtitle: "бас и два удара вверх",
            beatsPerBar: 3, division: .eighth,
            slots: [[d(1.0)], [], [u], [], [u], []]
        ),

        RhythmPattern(
            name: "Вальс перебором",
            subtitle: "бас и раскладка по струнам",
            beatsPerBar: 3, division: .eighth,
            slots: [[s(1, 1.0)], [], [s(3)], [s(4)], [s(5)], [s(4)]]
        ),
    ]

    static func patterns(in family: RhythmPattern.Family) -> [RhythmPattern] {
        all.filter { $0.family == family }
    }
}
