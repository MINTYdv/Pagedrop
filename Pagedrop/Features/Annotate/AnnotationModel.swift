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
    /// Annotations added since the last save, oldest first.
    private(set) var history: [PlacedAnnotation] = []

    @ObservationIgnored
    private weak var pdfView: PDFView?

    init(app: AppModel) {
        self.app = app
    }

    var document: PDFDocument? { app.session.document }
    var canUndo: Bool { !history.isEmpty }
    var hasUnsavedChanges: Bool { !history.isEmpty }

    func attach(_ pdfView: PDFView) {
        self.pdfView = pdfView
    }

    func selectionChanged(hasSelection: Bool) {
        self.hasSelection = hasSelection
    }

    // MARK: Editing

    func highlightSelection() {
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
        guard let last = history.popLast() else { return }
        remove(last)
    }

    /// Removes everything added since the last save.
    func discardChanges() {
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
}
