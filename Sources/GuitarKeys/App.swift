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
            CommandGroup(replacing: .undoRedo) {
                Button("Отменить") { state.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!state.canUndo)
                Button("Повторить") { state.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!state.canRedo)
            }
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

            CommandMenu("Студия") {
                Button("Играть или стоп") { state.toggleSongPlayback() }
                    .keyboardShortcut(.return, modifiers: [])
                Button(state.metronome ? "Выключить метроном" : "Включить метроном") {
                    state.metronome.toggle()
                }
                .keyboardShortcut("m", modifiers: .command)
                Divider()
                Button("Выделить все такты") { state.selectAllBars() }
                    .keyboardShortcut("a", modifiers: .command)
                Button("Снять выделение") { state.clearSelection() }
                Button("Продублировать") { state.duplicateSelectedBars() }
                    .keyboardShortcut("d", modifiers: .command)
                Button("Очистить такты") { state.clearSelectedBars() }
                    .keyboardShortcut(.delete, modifiers: [])
                Button("Удалить такты") { state.removeSelectedBars() }
                    .keyboardShortcut(.delete, modifiers: .command)
                Divider()
                Button("Сохранить проект") { state.saveSongProject() }
                    .keyboardShortcut("s", modifiers: .command)
                Menu("Свести в файл") {
                    ForEach(AudioFileFormat.allCases) { format in
                        Button(format.title) { state.exportSong(format: format) }
                    }
                }
            }
        }
        #else
        WindowGroup {
            TouchRootView()
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
