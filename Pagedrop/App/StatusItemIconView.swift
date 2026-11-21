import AppKit
import UniformTypeIdentifiers

/// The icon shown in the menu bar, drawn as a small rounded "tray" that lights up while a PDF hovers over it.
///
/// ### Why doesn't this view receive the drag itself?
/// A view registered for dragged types inside a status item never gets `draggingEntered(_:)`: the drag
/// is routed to the status bar window, not to its subviews. `StatusBarController` therefore registers
/// the button's window and acts as its delegate (an `NSWindow` forwards dragging-destination calls to
/// its delegate), then hands each step to this view through `dragEntered(_:)`, `dragExited()` and
/// `performDrop(_:)`.
///
/// ### Why does it draw the icon?
/// SF Symbol effects (`addSymbolEffect`) are only available on `NSImageView`, not on `NSButton`.
/// The button therefore has no image of its own and this view draws the symbol instead. It ignores
/// mouse events (`hitTest(_:)` returns `nil`) so clicks go straight to the button.
@MainActor
final class StatusItemIconView: NSView {
    enum State {
        case idle
        case hasDocument
    }

    /// Called with the dropped PDF. Returns whether the file was accepted.
    var onDrop: ((URL) -> Bool)?

    var state: State = .idle {
        didSet { if !isDragging { showRestingSymbol() } }
    }

    private let imageView = NSImageView()
    private var isDragging = false {
        didSet { needsDisplay = true }
    }
    private var restoreTask: Task<Void, Never>?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        imageView.symbolConfiguration = .init(pointSize: 13, weight: .medium)
        imageView.imageScaling = .scaleNone
        imageView.frame = bounds
        imageView.autoresizingMask = [.width, .height]
        imageView.wantsLayer = true
        addSubview(imageView)

        showRestingSymbol(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: Drawing

    override var wantsUpdateLayer: Bool { true }

    /// Draws the tray. Colors are resolved here so they follow the menu bar's light or dark appearance.
    override func updateLayer() {
        guard let layer else { return }
        let tint: NSColor = isDragging ? .controlAccentColor : .labelColor
        layer.cornerRadius = 5
        layer.borderWidth = 1
        layer.borderColor = tint.withAlphaComponent(isDragging ? 0.9 : 0.35).cgColor
        layer.backgroundColor = tint.withAlphaComponent(isDragging ? 0.25 : 0.08).cgColor
    }

    override func layout() {
        super.layout()
        // Leave a little room above and below so the tray sits inside the menu bar like other items.
        imageView.frame = bounds
    }

    // MARK: Hit testing

    /// Clicks pass through to the status bar button underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // MARK: Drag steps (forwarded by StatusBarController)

    func dragEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard Self.pdfURL(in: sender.draggingPasteboard) != nil else {
            reject()
            return []
        }
        if !isDragging {
            isDragging = true
            restoreTask?.cancel()
            setSymbol("doc.badge.plus", animated: true)
            imageView.addSymbolEffect(.bounce)
        }
        return .copy
    }

    func dragExited() {
        guard isDragging else { return }
        isDragging = false
        showRestingSymbol()
    }

    func canAcceptDrop(_ sender: any NSDraggingInfo) -> Bool {
        Self.pdfURL(in: sender.draggingPasteboard) != nil
    }

    func performDrop(_ sender: any NSDraggingInfo) -> Bool {
        isDragging = false
        guard let url = Self.pdfURL(in: sender.draggingPasteboard), onDrop?(url) == true else {
            reject()
            return false
        }
        showRestingSymbol()
        return true
    }

    // MARK: Feedback

    /// Shakes the icon and briefly shows a "no" symbol.
    private func reject() {
        isDragging = false
        setSymbol("xmark.circle", animated: true)

        let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shake.values = [0, -4, 4, -3, 3, -1, 0]
        shake.duration = 0.4
        imageView.layer?.add(shake, forKey: "shake")

        restoreTask?.cancel()
        restoreTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self?.showRestingSymbol()
        }
    }

    private func showRestingSymbol(animated: Bool = true) {
        let name = switch state {
        case .idle: "doc.on.doc"
        case .hasDocument: "doc.text.fill"
        }
        setSymbol(name, animated: animated)
    }

    private func setSymbol(_ name: String, animated: Bool) {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Pagedrop")
        if animated {
            imageView.setSymbolImage(image ?? NSImage(), contentTransition: .replace)
        } else {
            imageView.image = image
        }
    }

    // MARK: Pasteboard

    /// The first dragged file that is a PDF. Only the extension is checked, since the sandbox may not
    /// let us look inside a file before the drop completes; the document is validated when loaded.
    private static func pdfURL(in pasteboard: NSPasteboard) -> URL? {
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
        return urls?.first(where: \.isPDF)
    }
}
