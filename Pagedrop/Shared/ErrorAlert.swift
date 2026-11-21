import AppKit

/// A plain alert for failures in windows that don't have the popover on screen.
@MainActor
enum ErrorAlert {
    static func show(_ error: Error, title: String) {
        let alert = NSAlert(error: error)
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        NSApp.activate()
        alert.runModal()
    }
}
