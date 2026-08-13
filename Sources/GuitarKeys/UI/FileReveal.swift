import Foundation
#if os(macOS)
import AppKit
#endif

/// Показать записанный файл системе. На iOS Finder'а нет, поэтому вызовы пустые —
/// там для этого будет share sheet.
enum FileReveal {
    static func reveal(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        #endif
    }

    static func open(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }
}
