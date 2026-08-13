import Foundation
#if os(iOS)
import UIKit
#endif

/// Тактильный отклик. На телефоне он заменяет ощущение хода клавиши: без него
/// удар по стеклу не читается как взятие аккорда. На маке вызовы пустые.
enum Haptics {
    #if os(iOS)
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    #endif

    /// Подготовить движок заранее — иначе первый отклик приходит с задержкой.
    static func prepare() {
        #if os(iOS)
        light.prepare()
        medium.prepare()
        #endif
    }

    /// Взятие аккорда или удар.
    static func strike(_ strength: Double = 0.8) {
        #if os(iOS)
        medium.impactOccurred(intensity: strength)
        medium.prepare()
        #endif
    }

    /// Щипок отдельной струны — легче удара.
    static func pluck() {
        #if os(iOS)
        light.impactOccurred(intensity: 0.55)
        light.prepare()
        #endif
    }
}
