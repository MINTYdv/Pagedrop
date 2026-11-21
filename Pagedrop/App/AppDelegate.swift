import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController(model: model)
    }

    /// Called when a PDF is opened with "Open With" or dropped on the app icon in Finder.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: \.isPDF) else { return }
        model.open(url)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
