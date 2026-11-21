import Foundation

/// Errors thrown by the Core layer. Messages are written to be shown to people as-is.
public enum PDFError: LocalizedError, Equatable {
    case unreadable
    case passwordProtected
    case writeFailed
    case invalidPageIndexes
    case invalidPageOrder
    case invalidPageRange(String)
    case cannotRemoveAllPages
    case renderFailed(pageNumber: Int)
    case encodingFailed(pageNumber: Int)

    public var errorDescription: String? {
        switch self {
        case .unreadable:
            "This file can't be opened as a PDF."
        case .passwordProtected:
            "This PDF is protected by a password."
        case .writeFailed:
            "The file couldn't be saved."
        case .invalidPageIndexes:
            "Some of the selected pages don't exist."
        case .invalidPageOrder:
            "The new page order isn't valid."
        case .invalidPageRange(let text):
            "“\(text)” isn't a valid list of pages."
        case .cannotRemoveAllPages:
            "A document needs at least one page."
        case .renderFailed(let pageNumber):
            "Page \(pageNumber) couldn't be drawn."
        case .encodingFailed(let pageNumber):
            "Page \(pageNumber) couldn't be saved as an image."
        }
    }
}
