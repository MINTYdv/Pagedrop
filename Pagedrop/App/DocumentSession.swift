import Foundation
import Observation
import PDFKit
import PagedropCore

/// The document currently loaded in the app, shared by the popover and every tool window.
///
/// `PDFDocument` is a reference type that isn't observable, so views that need to refresh after an
/// in-place change (annotations, for example) watch `revision`.
@MainActor
@Observable
final class DocumentSession {
    private(set) var document: PDFDocument?
    private(set) var fileURL: URL?
    private(set) var revision = 0

    var isLoaded: Bool { document != nil }
    var pageCount: Int { document?.pageCount ?? 0 }
    var displayName: String { fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled" }

    func load(from url: URL) throws {
        document = try PDFFile.read(from: url)
        fileURL = url
        revision += 1
    }

    /// Notes that the document was modified in place, so views can refresh.
    func markChanged() {
        revision += 1
    }

    /// Writes a document to disk and, only if that succeeds, makes it the current one.
    ///
    /// - Parameters:
    ///   - edited: The document to save. Defaults to the current document.
    ///   - url: Where to save. Defaults to the original file.
    func save(_ edited: PDFDocument? = nil, to url: URL? = nil) throws {
        guard let content = edited ?? document, let destination = url ?? fileURL else {
            throw PDFError.writeFailed
        }
        try PDFFile.write(content, to: destination)
        document = content
        fileURL = destination
        revision += 1
    }

    func close() {
        document = nil
        fileURL = nil
        revision += 1
    }
}
