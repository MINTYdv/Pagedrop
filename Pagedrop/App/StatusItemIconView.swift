import AppKit
import UniformTypeIdentifiers

/// The icon shown in the menu bar. It is also the drop target for PDF files.
///
/// ### Why a separate view?
/// `NSStatusBarButton` can't be subclassed, and its window belongs to the system, so we can't
/// register it for dragged types directly. Instead this view is added as a subview that fills the
/// button and registers for `.fileURL` itself. AppKit finds drag destinations by hit-testing the
/// window's view hierarchy, which is why `hitTest(_:)` must return this view: returning `nil`
/// (the usual trick for click-through overlays) would make the drop disappear too.
///
/// Clicks still reach the button because this view doesn't handle mouse events: the default
/// `NSResponder` implementation forwards them along the responder chain to the superview, which is
/// the button, so its normal tracking and action dispatch keep working.
///
/// ### Why does it draw the icon?
/// SF Symbol effects (`addSymbolEffect`) are only available on `NSImageView`, not on `NSButton`.
/// The button therefore has no image of its own and this view draws the symbol instead.
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
    private var isDragging = false
    private var restoreTask: Task<Void, Never>?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        imageView.symbolConfiguration = .init(pointSize: 14, weight: .regular)
        imageView.imageScaling = .scaleNone
        imageView.frame = bounds
        imageView.autoresizingMask = [.width, .height]
        imageView.wantsLayer = true
        addSubview(imageView)

        registerForDraggedTypes([.fileURL])
        showRestingSymbol(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: Hit testing

    /// The image view must not steal hits: this view has to be the deepest hit view so it is found as the drag destination.
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    // MARK: Drag destination

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard Self.pdfURL(in: sender.draggingPasteboard) != nil else {
            reject()
            return []
        }
        isDragging = true
        restoreTask?.cancel()
        setSymbol("doc.badge.plus", animated: true)
        imageView.addSymbolEffect(.bounce)
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        isDragging = false
        showRestingSymbol()
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        Self.pdfURL(in: sender.draggingPasteboard) != nil
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
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
