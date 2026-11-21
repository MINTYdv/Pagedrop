import AppKit
import SwiftUI

/// A small gear menu with the app-wide options.
struct SettingsMenu: View {
    private let launchAtLogin = LaunchAtLogin.shared

    var body: some View {
        Menu {
            Toggle("Launch at Login", isOn: Binding(
                get: { launchAtLogin.isEnabled },
                set: { launchAtLogin.setEnabled($0) }
            ))
            Divider()
            Button("Quit Pagedrop") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "gearshape")
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Settings")
    }
}
