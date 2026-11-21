import Foundation
import PDFKit

/// Pure page-level edits. Every function returns a new document and leaves its input untouched.
public enum PDFDocumentEditor {
    /// Returns a copy of `document` without the pages at `indexes` (zero-based).
    public static func removingPages(at indexes: IndexSet, from document: PDFDocument) throws -> PDFDocument {
        let range = 0..<document.pageCount
        guard indexes.allSatisfy(range.contains) else { throw PDFError.invalidPageIndexes }
        guard indexes.count < document.pageCount else { throw PDFError.cannotRemoveAllPages }

        let kept = range.filter { !indexes.contains($0) }
        return try reordering(document, order: kept)
    }

    /// Returns a document whose page `n` is the page `order[n]` of the input.
    ///
    /// Indexes may be omitted (those pages are dropped) but never repeated.
    public static func reordering(_ document: PDFDocument, order: [Int]) throws -> PDFDocument {
        guard !order.isEmpty,
              Set(order).count == order.count,
              order.allSatisfy({ (0..<document.pageCount).contains($0) })
        else { throw PDFError.invalidPageOrder }

        let result = PDFDocument()
        for (position, original) in order.enumerated() {
            guard let page = document.page(at: original)?.copy() as? PDFPage else {
                throw PDFError.invalidPageOrder
            }
            result.insert(page, at: position)
        }
        return result
    }
}

/// Pure helpers to compute page orders, kept separate from PDFKit so they are trivial to test.
public enum PageOrder {
    /// Moves the elements at `offsets` so they end up just before the element
    /// that was at `destination`. Mirrors the semantics of SwiftUI's `move(fromOffsets:toOffset:)`.
    public static func moving(_ order: [Int], fromOffsets offsets: IndexSet, toOffset destination: Int) -> [Int] {
        let moved = offsets.map { order[$0] }
        let before = offsets.filter { $0 < destination }.count
        var result = order
        for index in offsets.reversed() { result.remove(at: index) }
        result.insert(contentsOf: moved, at: destination - before)
        return result
    }

    /// Parses text such as `"1-3, 5, 8-"` into zero-based page indexes, sorted and without duplicates.
    /// An open-ended range (`"8-"`) runs to the last page.
    public static func parse(_ text: String, pageCount: Int) throws -> [Int] {
        let parts = text
            .split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { throw PDFError.invalidPageRange(text) }

        var pages = Set<Int>()
        for part in parts {
            let bounds = part.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            let lower: Int
            let upper: Int
            switch bounds.count {
            case 1:
                guard let page = Int(bounds[0]) else { throw PDFError.invalidPageRange(text) }
                (lower, upper) = (page, page)
            case 2:
                guard let start = Int(bounds[0]) else { throw PDFError.invalidPageRange(text) }
                if bounds[1].isEmpty {
                    (lower, upper) = (start, pageCount)
                } else if let end = Int(bounds[1]) {
                    (lower, upper) = (start, end)
                } else {
                    throw PDFError.invalidPageRange(text)
                }
            default:
                throw PDFError.invalidPageRange(text)
            }
            guard lower >= 1, upper >= lower, upper <= pageCount else { throw PDFError.invalidPageRange(text) }
            pages.formUnion((lower - 1)..<upper)
        }
        return pages.sorted()
    }
}
