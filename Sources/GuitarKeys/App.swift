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
            CommandGroup(replacing: .appInfo) {
                Button(L.t("menu.about")) { state.showsAbout = true }
            }
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .undoRedo) {
                Button(L.t("menu.undo")) { state.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!state.canUndo)
                Button(L.t("menu.redo")) { state.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!state.canRedo)
            }
            CommandGroup(replacing: .pasteboard) {}

            CommandMenu(L.t("menu.game")) {
                Button(L.t("menu.strumDown")) { state.strum(direction: .down, muted: false) }
                Button(L.t("menu.strumUp")) { state.strum(direction: .up, muted: false) }
                Divider()
                Button(L.t("menu.keyUp")) { state.transpose(by: 1) }
                Button(L.t("menu.keyDown")) { state.transpose(by: -1) }
                Divider()
                Button(state.isRecording ? L.t("menu.recordStop") : L.t("menu.record")) {
                    state.toggleRecording()
                }
                .keyboardShortcut("r", modifiers: .command)
                Button(L.t("play.recordingsFolder")) { state.openRecordingsFolder() }
                Divider()
                Button(L.t("menu.resetBindings")) { state.resetBindings() }
            }

            CommandMenu(L.t("menu.studio")) {
                Button(L.t("menu.playStop")) { state.toggleSongPlayback() }
                    .keyboardShortcut(.return, modifiers: [])
                Button(state.metronome ? L.t("menu.metronomeOff") : L.t("menu.metronomeOn")) {
                    state.metronome.toggle()
                }
                .keyboardShortcut("m", modifiers: .command)
                Divider()
                Button(L.t("menu.selectAll")) { state.selectAllBars() }
                    .keyboardShortcut("a", modifiers: .command)
                Button(L.t("menu.deselect")) { state.clearSelection() }
                Button(L.t("menu.duplicate")) { state.duplicateSelectedBars() }
                    .keyboardShortcut("d", modifiers: .command)
                Button(L.t("menu.clearBars")) { state.clearSelectedBars() }
                    .keyboardShortcut(.delete, modifiers: [])
                Button(L.t("menu.deleteBars")) { state.removeSelectedBars() }
                    .keyboardShortcut(.delete, modifiers: .command)
                Divider()
                Button(L.t("studio.save")) { state.saveSongProject() }
                    .keyboardShortcut("s", modifiers: .command)
                Menu(L.t("studio.exportSection")) {
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
