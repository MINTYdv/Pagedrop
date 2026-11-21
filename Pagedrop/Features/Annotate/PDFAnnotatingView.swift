import AppKit
import PagedropCore
import PDFKit
import SwiftUI

/// Bridges the AppKit annotation canvas into SwiftUI.
struct PDFAnnotatingView: NSViewRepresentable {
    let document: PDFDocument?
    let tool: AnnotationTool
    let model: AnnotationModel

    func makeNSView(context: Context) -> AnnotationCanvasView {
        let canvas = AnnotationCanvasView(model: model)
        canvas.pdfView.document = document
        return canvas
    }

    func updateNSView(_ canvas: AnnotationCanvasView, context: Context) {
        if canvas.pdfView.document !== document {
            canvas.pdfView.document = document
        }
        canvas.tool = tool
    }
}

/// A `PDFView` with a transparent input layer on top.
///
/// `PDFView` doesn't receive mouse events itself (its internal document view does), so subclassing
/// it to draw ink isn't possible. The overlay sits above it, takes over the mouse while the pen or
/// note tool is active, and lets every event through (by hit-testing to `nil`) while the user is
/// selecting text.
@MainActor
final class AnnotationCanvasView: NSView {
    let pdfView = PDFView()
    private let overlay: InputOverlayView
    private let model: AnnotationModel

    var tool: AnnotationTool = .select {
        didSet {
            overlay.tool = tool
            window?.invalidateCursorRects(for: overlay)
        }
    }

    init(model: AnnotationModel) {
        self.model = model
        self.overlay = InputOverlayView(pdfView: pdfView, model: model)
        super.init(frame: .zero)

        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .underPageBackgroundColor
        pdfView.frame = bounds
        pdfView.autoresizingMask = [.width, .height]
        addSubview(pdfView)

        overlay.frame = bounds
        overlay.autoresizingMask = [.width, .height]
        addSubview(overlay)

        model.attach(pdfView)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(selectionChanged),
            name: .PDFViewSelectionChanged,
            object: pdfView
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func selectionChanged(_ notification: Notification) {
        let hasText = !(pdfView.currentSelection?.string ?? "").isEmpty
        model.selectionChanged(hasSelection: hasText)
    }
}

/// Captures the pen and note tools.
@MainActor
final class InputOverlayView: NSView {
    private struct Stroke {
        let page: PDFPage
        var points: [CGPoint]
        var preview: PDFAnnotation?
    }

    var tool: AnnotationTool = .select
    private let pdfView: PDFView
    private let model: AnnotationModel
    private var stroke: Stroke?

    init(pdfView: PDFView, model: AnnotationModel) {
        self.pdfView = pdfView
        self.model = model
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        tool == .select ? nil : super.hitTest(point)
    }

    override func resetCursorRects() {
        switch tool {
        case .select: break
        case .pen: addCursorRect(bounds, cursor: .crosshair)
        case .note: addCursorRect(bounds, cursor: .iBeam)
        }
    }

    /// Scrolling keeps working while a drawing tool is active.
    override func scrollWheel(with event: NSEvent) {
        pdfView.documentView?.enclosingScrollView?.scrollWheel(with: event)
    }

    // MARK: Pen

    override func mouseDown(with event: NSEvent) {
        guard tool == .pen, let (page, point) = pagePoint(for: event) else { return }
        stroke = Stroke(page: page, points: [point])
    }

    override func mouseDragged(with event: NSEvent) {
        guard tool == .pen, var current = stroke else { return }
        let location = pdfView.convert(convert(event.locationInWindow, from: nil), from: self)
        current.points.append(pdfView.convert(location, to: current.page))

        // Redraw the whole stroke as one annotation; strokes are short, so this stays cheap.
        if let preview = current.preview { current.page.removeAnnotation(preview) }
        if let ink = AnnotationFactory.ink(through: current.points) {
            current.page.addAnnotation(ink)
            current.preview = ink
        }
        pdfView.annotationsChanged(on: current.page)
        stroke = current
    }

    override func mouseUp(with event: NSEvent) {
        switch tool {
        case .pen:
            finishStroke()
        case .note:
            placeNote(for: event)
        case .select:
            break
        }
    }

    private func finishStroke() {
        guard let finished = stroke else { return }
        stroke = nil
        if let preview = finished.preview { finished.page.removeAnnotation(preview) }
        guard let ink = AnnotationFactory.ink(through: finished.points) else { return }
        model.add(PlacedAnnotation(page: finished.page, annotation: ink))
    }

    // MARK: Note

    private func placeNote(for event: NSEvent) {
        guard let (page, point) = pagePoint(for: event),
              let text = TextPrompt.ask(title: "Add a note", confirm: "Add")
        else { return }
        model.add(PlacedAnnotation(page: page, annotation: AnnotationFactory.note(text, at: point)))
    }

    // MARK: Coordinates

    /// The page under the event and the event's location in that page's coordinate space.
    private func pagePoint(for event: NSEvent) -> (PDFPage, CGPoint)? {
        let location = pdfView.convert(convert(event.locationInWindow, from: nil), from: self)
        guard let page = pdfView.page(for: location, nearest: true) else { return nil }
        return (page, pdfView.convert(location, to: page))
    }
}
