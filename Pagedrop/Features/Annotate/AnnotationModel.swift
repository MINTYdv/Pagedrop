import Observation
import PagedropCore
import PDFKit

enum AnnotationTool: Hashable {
    case select
    case pen
    case note
}

/// State and actions of the annotation window.
@MainActor
@Observable
final class AnnotationModel {
    private let app: AppModel

    var tool: AnnotationTool = .select
    private(set) var hasSelection = false
    /// Whether a text note is being typed on the page.
    var isEditingNote = false
    /// Annotations added since the last save, oldest first.
    private(set) var history: [PlacedAnnotation] = []

    let saveFeedback = SaveFeedback()

    @ObservationIgnored
    private weak var pdfView: PDFView?
    /// Set by the canvas: commits the text note being typed, if any, so it isn't lost by saving or undoing.
    @ObservationIgnored
    var finishPendingEdit: (@MainActor () -> Void)?

    init(app: AppModel) {
        self.app = app
    }

    var document: PDFDocument? { app.session.document }
    var canUndo: Bool { !history.isEmpty }
    var hasUnsavedChanges: Bool { !history.isEmpty }
    /// Whether the Save button has anything to do: committed annotations, or a note still being typed.
    var canSave: Bool { hasUnsavedChanges || isEditingNote }

    func attach(_ pdfView: PDFView) {
        self.pdfView = pdfView
    }

    func selectionChanged(hasSelection: Bool) {
        self.hasSelection = hasSelection
    }

    // MARK: Editing

    func highlightSelection() {
        finishPendingEdit?()
        guard let pdfView, let selection = pdfView.currentSelection else { return }
        for placed in AnnotationFactory.highlights(for: selection) { add(placed) }
        pdfView.clearSelection()
    }

    func add(_ placed: PlacedAnnotation) {
        placed.page.addAnnotation(placed.annotation)
        pdfView?.annotationsChanged(on: placed.page)
        history.append(placed)
    }

    func undo() {
        finishPendingEdit?()
        guard let last = history.popLast() else { return }
        remove(last)
    }

    /// Removes everything added since the last save.
    func discardChanges() {
        finishPendingEdit?()
        while let last = history.popLast() { remove(last) }
    }

    private func remove(_ placed: PlacedAnnotation) {
        placed.page.removeAnnotation(placed.annotation)
        pdfView?.annotationsChanged(on: placed.page)
    }

    // MARK: Saving

    /// Saves over the original file, or asks for a new location when that isn't possible.
    /// Returns whether the document was saved; failures are reported to the user.
    func save(asCopy: Bool = false) -> Bool {
        finishPendingEdit?()
        do {
            if asCopy {
                guard try app.saveDocumentAs() else { return false }
            } else {
                do {
                    try app.session.save()
                } catch {
                    guard try app.saveDocumentAs() else { return false }
                }
            }
            history.removeAll()
            return true
        } catch {
            ErrorAlert.show(error, title: "Can't save")
            return false
        }
    }

    /// The toolbar's save: the same as `save(asCopy:)`, with the button showing progress and confirmation.
    func saveWithFeedback(asCopy: Bool = false) async {
        guard asCopy || canSave else { return }
        await saveFeedback.perform { save(asCopy: asCopy) }
    }
}
