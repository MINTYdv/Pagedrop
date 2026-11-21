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
        didSet { overlay.tool = tool }
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
        model.finishPendingEdit = { [weak overlay] in overlay?.commitEditor() }
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

/// Captures the pen and note tools. Notes are typed straight onto the page in a small text field.
@MainActor
final class InputOverlayView: NSView, NSTextFieldDelegate {
    private struct Stroke {
        let page: PDFPage
        var points: [CGPoint]
        var preview: PDFAnnotation?
    }

    /// A note being typed: the field on screen and where the note's top-left corner lands on its page.
    private struct NoteEditor {
        let field: NSTextField
        let page: PDFPage
        let anchor: CGPoint
        let scale: CGFloat
    }

    var tool: AnnotationTool = .select {
        didSet {
            guard tool != oldValue else { return }
            if tool != .note { commitEditor() }
            window?.invalidateCursorRects(for: self)
        }
    }
    private let pdfView: PDFView
    private let model: AnnotationModel
    private var stroke: Stroke?
    private var editor: NoteEditor?

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

    /// The first click in the window counts: it shouldn't only activate it.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Cursor

    private var toolCursor: NSCursor? {
        switch tool {
        case .select: nil
        case .pen: .crosshair
        case .note: .iBeam
        }
    }

    override func resetCursorRects() {
        if let toolCursor { addCursorRect(bounds, cursor: toolCursor) }
    }

    // The PDF view underneath sets its own cursor, so the overlay also claims it with a tracking area.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.cursorUpdate, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func cursorUpdate(with event: NSEvent) {
        if let toolCursor { toolCursor.set() } else { super.cursorUpdate(with: event) }
    }

    /// Scrolling keeps working while a drawing tool is active.
    override func scrollWheel(with event: NSEvent) {
        commitEditor()
        pdfView.documentView?.enclosingScrollView?.scrollWheel(with: event)
    }

    // MARK: Pen

    override func mouseDown(with event: NSEvent) {
        // A click away from the note being typed finishes it.
        if editor != nil {
            commitEditor()
            return
        }
        switch tool {
        case .pen:
            guard let (page, point) = pagePoint(for: event) else { return }
            stroke = Stroke(page: page, points: [point])
        case .note:
            beginNote(for: event)
        case .select:
            break
        }
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
        if tool == .pen { finishStroke() }
    }

    private func finishStroke() {
        guard let finished = stroke else { return }
        stroke = nil
        if let preview = finished.preview { finished.page.removeAnnotation(preview) }
        guard let ink = AnnotationFactory.ink(through: finished.points) else { return }
        model.add(PlacedAnnotation(page: finished.page, annotation: ink))
    }

    // MARK: Note

    /// Puts an editable text field on the page where the click happened.
    private func beginNote(for event: NSEvent) {
        guard let (page, _) = pagePoint(for: event) else { return }
        let click = convert(event.locationInWindow, from: nil)
        let scale = pdfView.scaleFactor

        // Keep the whole box on screen when clicking near the right edge.
        let maxWidth = (AnnotationFactory.noteMaxWidth + 12) * scale
        let topLeft = CGPoint(x: max(0, min(click.x, bounds.width - maxWidth)), y: click.y)

        let field = NSTextField()
        field.font = .systemFont(ofSize: AnnotationFactory.noteFont.pointSize * scale)
        field.textColor = .black
        field.isBordered = false
        field.drawsBackground = true
        field.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.35)
        field.focusRingType = .none
        field.usesSingleLineMode = false
        field.lineBreakMode = .byWordWrapping
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.delegate = self
        field.wantsLayer = true
        field.layer?.borderColor = NSColor.controlAccentColor.cgColor
        field.layer?.borderWidth = 1

        let anchor = pdfView.convert(pdfView.convert(topLeft, from: self), to: page)
        editor = NoteEditor(field: field, page: page, anchor: anchor, scale: scale)
        model.isEditingNote = true
        addSubview(field)
        resizeEditor(to: "")
        window?.makeFirstResponder(field)
    }

    /// Grows the field with its text, keeping the top-left corner where the click was.
    private func resizeEditor(to text: String) {
        guard let editor else { return }
        let size = AnnotationFactory.noteSize(for: text)
        let topLeft = pdfView.convert(pdfView.convert(editor.anchor, from: editor.page), to: self)
        let width = max(size.width, 48) * editor.scale
        let height = size.height * editor.scale
        editor.field.frame = NSRect(x: topLeft.x, y: topLeft.y - height, width: width, height: height)
    }

    /// Turns what was typed into a note on the page. Empty text adds nothing.
    func commitEditor() {
        guard let editor else { return }
        let text = (editor.field.currentEditor()?.string ?? editor.field.stringValue)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        closeEditor()
        guard !text.isEmpty else { return }
        model.add(PlacedAnnotation(page: editor.page, annotation: AnnotationFactory.note(text, at: editor.anchor)))
    }

    private func cancelEditor() {
        closeEditor()
    }

    private func closeEditor() {
        guard let editor else { return }
        self.editor = nil
        model.isEditingNote = false
        editor.field.delegate = nil
        window?.makeFirstResponder(self)
        editor.field.removeFromSuperview()
    }

    // MARK: NSTextFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, field === editor?.field else { return }
        resizeEditor(to: field.currentEditor()?.string ?? field.stringValue)
    }

    /// Clicking elsewhere (or switching windows) finishes the note.
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, field === editor?.field else { return }
        commitEditor()
    }

    /// Return finishes the note, Escape throws it away. Option-Return starts a new line.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            commitEditor()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            cancelEditor()
            return true
        default:
            return false
        }
    }

    // MARK: Coordinates

    /// The page under the event and the event's location in that page's coordinate space.
    private func pagePoint(for event: NSEvent) -> (PDFPage, CGPoint)? {
        let location = pdfView.convert(convert(event.locationInWindow, from: nil), from: self)
        guard let page = pdfView.page(for: location, nearest: true) else { return nil }
        return (page, pdfView.convert(location, to: page))
    }
}
