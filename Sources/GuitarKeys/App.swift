import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct GuitarKeysApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    #endif
    @UIState private var state = AppState()

    var body: some Scene {
        #if os(macOS)
        Window("GuitarKeys", id: "main") {
            RootView()
                .environment(state)
                .onAppear { delegate.state = state }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 900, height: 668)
        .commands {
            // Приложение — инструмент, а не редактор документов.
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .undoRedo) {}
            CommandGroup(replacing: .pasteboard) {}

            CommandMenu("Игра") {
                Button("Удар вниз") { state.strum(direction: .down, muted: false) }
                Button("Удар вверх") { state.strum(direction: .up, muted: false) }
                Divider()
                Button("Тональность выше") { state.transpose(by: 1) }
                Button("Тональность ниже") { state.transpose(by: -1) }
                Divider()
                Button(state.isRecording ? "Остановить запись" : "Записать игру") {
                    state.toggleRecording()
                }
                .keyboardShortcut("r", modifiers: .command)
                Button("Папка с записями") { state.openRecordingsFolder() }
                Divider()
                Button("Сбросить привязки") { state.resetBindings() }
            }
        }
        #else
        WindowGroup {
            RootView()
                .environment(state)
        }
        #endif
    }
}

#if os(macOS)
final class AppDelegate: NSObject, NSApplicationDelegate {
    var state: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { state?.shutdown() }
    }
}
#endif
