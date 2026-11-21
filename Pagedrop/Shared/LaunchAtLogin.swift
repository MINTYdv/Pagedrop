import Observation
import ServiceManagement

/// Wraps `SMAppService` so the app can start at login.
@MainActor
@Observable
final class LaunchAtLogin {
    static let shared = LaunchAtLogin()

    private(set) var isEnabled: Bool

    private init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Registration can fail for unsigned development builds; the toggle then simply reflects reality.
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
