import AppKit
import UniformTypeIdentifiers

/// Thin wrappers around the standard open and save panels.
/// URLs returned by these panels carry sandbox access for as long as the app runs.
@MainActor
enum FilePanels {
    static func chooseDocument() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        return run(panel)
    }

    static func chooseFolder(message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = message
        return run(panel)
    }

    static func chooseSaveLocation(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = suggestedName + ".pdf"
        panel.canCreateDirectories = true
        return run(panel)
    }

    private static func run(_ panel: NSSavePanel) -> URL? {
        NSApp.activate()
        return panel.runModal() == .OK ? panel.url : nil
    }
}
