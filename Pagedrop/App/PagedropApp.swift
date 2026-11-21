import SwiftUI

@main
struct PagedropApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Pagedrop lives in the menu bar and opens its own windows on demand,
        // so SwiftUI has no window scene to manage. `Settings` is the lightest scene that keeps `App` happy.
        Settings { EmptyView() }
    }
}
