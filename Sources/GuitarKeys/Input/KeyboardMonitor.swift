#if os(macOS)
import AppKit

/// Локальный перехват клавиатуры. Локальный, а не глобальный: приложению не нужен
/// доступ к «Универсальному доступу», а обработанные нажатия не доходят до системы
/// и не вызывают системный звук отказа.
@MainActor
final class KeyboardMonitor {

    /// Возвращает true, если нажатие обработано и дальше его пускать не нужно.
    var onKeyDown: ((UInt16, KeyModifiers) -> Bool)?
    var onKeyUp: ((UInt16) -> Bool)?

    private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }

            let modifiers = KeyModifiers(event.modifierFlags)
            // Сочетания с ⌘/⌃ оставляем системе и меню.
            if modifiers.isSystemChord { return event }
            // Автоповтор при удержании — не музыкальный ритм, игнорируем.
            if event.type == .keyDown && event.isARepeat { return nil }

            let handled: Bool
            switch event.type {
            case .keyDown: handled = self.onKeyDown?(event.keyCode, modifiers) ?? false
            case .keyUp:   handled = self.onKeyUp?(event.keyCode) ?? false
            default:       handled = false
            }
            return handled ? nil : event
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}

extension KeyModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var result: KeyModifiers = []
        if flags.contains(.shift)   { result.insert(.shift) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.option)  { result.insert(.option) }
        if flags.contains(.command) { result.insert(.command) }
        self = result
    }
}
#endif
