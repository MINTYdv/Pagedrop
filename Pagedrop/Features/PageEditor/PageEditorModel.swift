import CoreTransferable
import Observation
import PagedropCore
import PDFKit
import UniformTypeIdentifiers

enum PageEditorMode {
    case remove
    case reorder

    /// A short line shown under the window title.
    var hint: String {
        switch self {
        case .remove: "Select the pages to remove"
        case .reorder: "Drag pages into a new order"
        }
    }
}

extension UTType {
    /// Declared as an exported type in `project.yml`.
    static let pagedropPage = UTType(exportedAs: "dev.murte.Pagedrop.page")
}

/// What travels with a dragged thumbnail: the page's index in the original document.
struct PageDragItem: Codable, Transferable {
    let originalIndex: Int

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .pagedropPage)
    }
}

/// Working state of the page editor. The shared document and the file stay untouched until the user saves.
@MainActor
@Observable
final class PageEditorModel {
    let mode: PageEditorMode
    private let session: DocumentSession
    /// The document as it was when the editor opened. Thumbnails always come from it.
    let source: PDFDocument?
    /// Namespaces this editor's cached thumbnails so they can never be mistaken for another document's.
    let thumbnailKey = UUID().uuidString

    /// Original indexes of the pages that remain, in their current order.
    private(set) var order: [Int]
    var selection: Set<Int> = []

    init(session: DocumentSession, mode: PageEditorMode) {
        self.session = session
        self.mode = mode
        self.source = session.document
        self.order = Array(0..<session.pageCount)
    }

    var hasChanges: Bool { order != Array(0..<(source?.pageCount ?? 0)) }
    var canRemove: Bool { !selection.isEmpty && selection.count < order.count }

    func toggleSelection(_ index: Int) {
        if selection.contains(index) { selection.remove(index) } else { selection.insert(index) }
    }

    func removeSelected() {
        guard canRemove else { return }
        order.removeAll { selection.contains($0) }
        selection.removeAll()
    }

    func reset() {
        order = Array(0..<(source?.pageCount ?? 0))
        selection.removeAll()
    }

    /// Drops the dragged page where `target` currently is.
    func move(_ dragged: Int, onto target: Int) {
        guard dragged != target,
              let from = order.firstIndex(of: dragged),
              let to = order.firstIndex(of: target) else { return }
        // Moving right lands after the target; moving left lands before it.
        let destination = to > from ? to + 1 : to
        order = PageOrder.moving(order, fromOffsets: IndexSet(integer: from), toOffset: destination)
    }

    func moveToStart(_ index: Int) {
        guard let from = order.firstIndex(of: index) else { return }
        order = PageOrder.moving(order, fromOffsets: IndexSet(integer: from), toOffset: 0)
    }

    func moveToEnd(_ index: Int) {
        guard let from = order.firstIndex(of: index) else { return }
        order = PageOrder.moving(order, fromOffsets: IndexSet(integer: from), toOffset: order.count)
    }

    /// A new document with the edits applied. Nothing is written or replaced yet.
    func editedDocument() throws -> PDFDocument {
        guard let source else { throw PDFError.unreadable }
        return try PDFDocumentEditor.reordering(source, order: order)
    }
}
