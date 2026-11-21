import AppKit
import SwiftUI

/// Owns the status item, the popover and the tool windows.
@MainActor
final class StatusBarController: NSObject, WindowPresenting {
    /// Wider than a square item so the icon reads as a drop tray and is easy to hit while dragging.
    private static let itemWidth: CGFloat = 44

    private let model: AppModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: StatusBarController.itemWidth)
    private let iconView = StatusItemIconView(frame: .zero)
    private let popover = NSPopover()
    private let windows: WindowCoordinator
    private let dropPanel = DropPanel()

    /// Where the current PDF drag is hovering. The drop panel stays up while either is true.
    private var isDragOverIcon = false
    private var isDragOverPanel = false
    private var hidePanelTask: Task<Void, Never>?

    init(model: AppModel) {
        self.model = model
        self.windows = WindowCoordinator(model: model)
        super.init()
        model.presenter = self

        configureStatusItem()
        configurePopover()
        configureDropPanel()
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

        // The icon itself is drawn by `StatusItemIconView`. A blank image gives the button its usual height.
        button.image = NSImage(size: NSSize(width: Self.itemWidth - 4, height: 18))
        iconView.frame = button.bounds.insetBy(dx: 2, dy: 0)
        iconView.autoresizingMask = [.width, .height]
        iconView.onDrop = { [weak self] url in self?.model.open(url) ?? false }
        button.addSubview(iconView)

        // Drags over a status item are delivered to its window, which forwards them to its delegate.
        button.window?.registerForDraggedTypes([.fileURL])
        button.window?.delegate = self
    }

    private func configureDropPanel() {
        dropPanel.onDragEntered = { [weak self] sender in
            guard let self else { return [] }
            isDragOverPanel = true
            hidePanelTask?.cancel()
            return iconView.dragEntered(sender)
        }
        dropPanel.onDragExited = { [weak self] in
            self?.isDragOverPanel = false
            self?.hideDropPanelIfIdle()
        }
        dropPanel.onDrop = { [weak self] sender in
            self?.finishDrop(sender) ?? false
        }
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

// MARK: - Drop target

/// The status bar window forwards dragging-destination calls to its delegate (the window was registered
/// for file URLs in `configureStatusItem()`). The icon gives feedback and a larger panel opens below it.
extension StatusBarController: NSWindowDelegate, NSDraggingDestination {
    func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let operation = iconView.dragEntered(sender)
        guard !operation.isEmpty else { return [] }
        isDragOverIcon = true
        hidePanelTask?.cancel()
        if let anchor = statusItem.button?.window?.frame {
            dropPanel.show(below: anchor)
        }
        return operation
    }

    func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        isDragOverIcon ? .copy : []
    }

    func draggingExited(_ sender: (any NSDraggingInfo)?) {
        isDragOverIcon = false
        hideDropPanelIfIdle()
    }

    func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        iconView.canAcceptDrop(sender)
    }

    func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        finishDrop(sender)
    }

    private func finishDrop(_ sender: any NSDraggingInfo) -> Bool {
        isDragOverIcon = false
        isDragOverPanel = false
        hidePanelTask?.cancel()
        dropPanel.hide()
        return iconView.performDrop(sender)
    }

    /// Hides the panel shortly after the drag leaves both targets. The delay lets the cursor travel
    /// from the icon down to the panel without it disappearing on the way.
    private func hideDropPanelIfIdle() {
        hidePanelTask?.cancel()
        hidePanelTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, !Task.isCancelled, !isDragOverIcon, !isDragOverPanel else { return }
            dropPanel.hide()
            iconView.dragExited()
        }
    }
}
