import Foundation
import PDFKit

/// Reads and writes PDF files.
public enum PDFFile {
    /// Loads a PDF fully into memory, so the original file is never held open
    /// and can safely be overwritten later.
    public static func read(from url: URL) throws -> PDFDocument {
        guard let data = try? Data(contentsOf: url), let document = PDFDocument(data: data) else {
            throw PDFError.unreadable
        }
        guard !document.isLocked else { throw PDFError.passwordProtected }
        guard document.pageCount > 0 else { throw PDFError.unreadable }
        return document
    }

    /// Writes the document to `url`.
    ///
    /// The write is deliberately non-atomic: an atomic write creates a temporary file
    /// next to the destination, which the App Sandbox only allows for folders the user
    /// has explicitly granted. Writing in place only needs access to the file itself.
    public static func write(_ document: PDFDocument, to url: URL) throws {
        guard let data = document.dataRepresentation() else { throw PDFError.writeFailed }
        do {
            try data.write(to: url, options: [])
        } catch {
            throw PDFError.writeFailed
        }
    }
}
