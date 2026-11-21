import AppKit
import SwiftUI

/// Owns the status item, the popover and the tool windows.
@MainActor
final class StatusBarController: NSObject, WindowPresenting {
    private let model: AppModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let iconView = StatusItemIconView(frame: .zero)
    private let popover = NSPopover()
    private let windows: WindowCoordinator

    init(model: AppModel) {
        self.model = model
        self.windows = WindowCoordinator(model: model)
        super.init()
        model.presenter = self

        configureStatusItem()
        configurePopover()
        observeDocument()
    }

    // MARK: Setup

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        // Fire on mouse-up so the click feels like a standard button; right clicks open the menu.
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityLabel("Pagedrop")

        // The icon itself is drawn by `StatusItemIconView`. A blank image of the usual size keeps the button
        // laid out like a regular status item, so the overlay covers the whole clickable area.
        let placeholder = NSImage(size: NSSize(width: 18, height: 18))
        placeholder.isTemplate = true
        button.image = placeholder

        iconView.frame = button.bounds
        iconView.autoresizingMask = [.width, .height]
        iconView.onDrop = { [weak self] url in self?.model.open(url) ?? false }
        button.addSubview(iconView)
    }

    private func configurePopover() {
        let host = NSHostingController(rootView: PopoverRootView().environment(model))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true
    }

    /// Keeps the icon in sync with whether a document is loaded.
    private func observeDocument() {
        withObservationTracking {
            iconView.state = model.session.isLoaded ? .hasDocument : .idle
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeDocument() }
        }
    }

    // MARK: Clicks

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showMenu() {
        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Open PDF…", action: #selector(openDocument), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = LaunchAtLogin.shared.isEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Pagedrop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Attaching the menu only for this click keeps left clicks going to the popover.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openDocument() {
        model.chooseDocument()
    }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLogin.shared.setEnabled(!LaunchAtLogin.shared.isEnabled)
    }

    // MARK: WindowPresenting

    func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate()
        popover.contentViewController?.view.window?.makeKey()
    }

    func closePopover() {
        popover.performClose(nil)
    }

    /// A transient popover closes as soon as a panel takes focus; pinning it avoids that.
    func setPopoverPinned(_ pinned: Bool) {
        popover.behavior = pinned ? .applicationDefined : .transient
    }

    func showPageEditor(mode: PageEditorMode) {
        closePopover()
        windows.showPageEditor(mode: mode)
    }

    func showAnnotator() {
        closePopover()
        windows.showAnnotator()
    }

    func closeToolWindows() {
        windows.closeAll()
    }
}
