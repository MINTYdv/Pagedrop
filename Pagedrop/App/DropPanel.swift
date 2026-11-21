import AppKit

/// A large drop target that appears under the status item while a PDF is dragged over it.
///
/// A status item is only about 40 × 30 points, so hitting it with a dragged file is fiddly. As soon as
/// the drag touches the icon, this panel slides in right below it and accepts the drop too, giving the
/// user a target that is easy to aim for.
@MainActor
final class DropPanel: NSPanel {
    private static let size = NSSize(width: 240, height: 124)

    private let zone = DropZoneView()

    /// Forwarded drag steps, wired by `StatusBarController`.
    var onDragEntered: ((any NSDraggingInfo) -> NSDragOperation)? {
        get { zone.onDragEntered }
        set { zone.onDragEntered = newValue }
    }
    var onDragExited: (() -> Void)? {
        get { zone.onDragExited }
        set { zone.onDragExited = newValue }
    }
    var onDrop: ((any NSDraggingInfo) -> Bool)? {
        get { zone.onDrop }
        set { zone.onDrop = newValue }
    }

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        animationBehavior = .utilityWindow

        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true
        contentView = background

        zone.frame = background.bounds
        zone.autoresizingMask = [.width, .height]
        background.addSubview(zone)
    }

    /// Shows the panel centered under `anchor`, a rect in screen coordinates.
    func show(below anchor: NSRect) {
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        var origin = NSPoint(x: anchor.midX - Self.size.width / 2, y: anchor.minY - Self.size.height - 6)
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - Self.size.width - 8)
        }
        setFrameOrigin(origin)
        zone.isHighlighted = false
        guard !isVisible else { return }
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            animator().alphaValue = 1
        }
    }

    func hide() {
        guard isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.orderOut(nil) }
        }
    }
}

/// The content of `DropPanel`: a dashed outline with a symbol and a short hint.
@MainActor
private final class DropZoneView: NSView {
    var onDragEntered: ((any NSDraggingInfo) -> NSDragOperation)?
    var onDragExited: (() -> Void)?
    var onDrop: ((any NSDraggingInfo) -> Bool)?

    var isHighlighted = false {
        didSet {
            guard isHighlighted != oldValue else { return }
            needsDisplay = true
            symbol.contentTintColor = isHighlighted ? .controlAccentColor : .secondaryLabelColor
            if isHighlighted { symbol.addSymbolEffect(.bounce) }
        }
    }

    private let symbol = NSImageView()
    private let label = NSTextField(labelWithString: "Drop to open")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        symbol.image = NSImage(systemSymbolName: "arrow.down.doc", accessibilityDescription: nil)
        symbol.symbolConfiguration = .init(pointSize: 30, weight: .regular)
        symbol.contentTintColor = .secondaryLabelColor

        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [symbol, label])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 10, dy: 10), xRadius: 9, yRadius: 9)
        path.lineWidth = 1.5
        path.setLineDash([6, 4], count: 2, phase: 0)
        let tint: NSColor = isHighlighted ? .controlAccentColor : .tertiaryLabelColor
        if isHighlighted {
            tint.withAlphaComponent(0.12).setFill()
            path.fill()
        }
        tint.setStroke()
        path.stroke()
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let operation = onDragEntered?(sender) ?? []
        isHighlighted = !operation.isEmpty
        return operation
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        isHighlighted ? .copy : []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        isHighlighted = false
        onDragExited?()
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        isHighlighted = false
        return onDrop?(sender) ?? false
    }
}
