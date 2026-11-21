import PagedropCore
import PDFKit
import Testing

@Suite("Page editing")
struct PageEditingTests {
    @Test("Removing pages keeps the others in order")
    func removesPages() throws {
        let document = TestPDF.make(pageCount: 5)

        let result = try PDFDocumentEditor.removingPages(at: [1, 3], from: document)

        #expect(TestPDF.pageNumbers(of: result) == [1, 3, 5])
    }

    @Test("Removing pages leaves the original document untouched")
    func removalDoesNotMutateInput() throws {
        let document = TestPDF.make(pageCount: 3)

        _ = try PDFDocumentEditor.removingPages(at: [0], from: document)

        #expect(TestPDF.pageNumbers(of: document) == [1, 2, 3])
    }

    @Test("Removing a page that doesn't exist throws")
    func rejectsOutOfRangeRemoval() {
        let document = TestPDF.make(pageCount: 3)

        #expect(throws: PDFError.invalidPageIndexes) {
            try PDFDocumentEditor.removingPages(at: [3], from: document)
        }
    }

    @Test("Removing every page throws")
    func rejectsEmptyResult() {
        let document = TestPDF.make(pageCount: 2)

        #expect(throws: PDFError.cannotRemoveAllPages) {
            try PDFDocumentEditor.removingPages(at: [0, 1], from: document)
        }
    }

    @Test("Reordering follows the requested order")
    func reordersPages() throws {
        let document = TestPDF.make(pageCount: 4)

        let result = try PDFDocumentEditor.reordering(document, order: [3, 0, 2, 1])

        #expect(TestPDF.pageNumbers(of: result) == [4, 1, 3, 2])
    }

    @Test("Reordering rejects repeated or missing indexes")
    func rejectsInvalidOrder() {
        let document = TestPDF.make(pageCount: 3)

        #expect(throws: PDFError.invalidPageOrder) {
            try PDFDocumentEditor.reordering(document, order: [0, 0, 1])
        }
        #expect(throws: PDFError.invalidPageOrder) {
            try PDFDocumentEditor.reordering(document, order: [0, 5])
        }
        #expect(throws: PDFError.invalidPageOrder) {
            try PDFDocumentEditor.reordering(document, order: [])
        }
    }

    @Test("Moving offsets follows SwiftUI semantics", arguments: [
        ([0, 1, 2, 3], IndexSet(integer: 0), 3, [1, 2, 0, 3]),
        ([0, 1, 2, 3], IndexSet(integer: 3), 0, [3, 0, 1, 2]),
        ([0, 1, 2, 3], IndexSet(integer: 1), 4, [0, 2, 3, 1]),
        ([0, 1, 2, 3], IndexSet([0, 1]), 4, [2, 3, 0, 1]),
        ([0, 1, 2, 3], IndexSet(integer: 2), 2, [0, 1, 2, 3]),
    ])
    func movesOffsets(order: [Int], offsets: IndexSet, destination: Int, expected: [Int]) {
        #expect(PageOrder.moving(order, fromOffsets: offsets, toOffset: destination) == expected)
    }

    @Test("Page ranges are parsed into sorted, unique indexes", arguments: [
        ("1-3, 5", [0, 1, 2, 4]),
        ("5,1", [0, 4]),
        ("2-", [1, 2, 3, 4, 5, 6, 7, 8, 9]),
        ("3-3", [2]),
        ("1-2, 2-4", [0, 1, 2, 3]),
    ])
    func parsesRanges(text: String, expected: [Int]) throws {
        #expect(try PageOrder.parse(text, pageCount: 10) == expected)
    }

    @Test("Invalid page ranges throw", arguments: ["", "abc", "0", "11", "4-2", "1-2-3", "-3"])
    func rejectsInvalidRanges(text: String) {
        #expect(throws: PDFError.invalidPageRange(text)) {
            try PageOrder.parse(text, pageCount: 10)
        }
    }

    @Test("A document survives a round trip through a file")
    func writesAndReadsBack() throws {
        let document = try PDFDocumentEditor.reordering(TestPDF.make(pageCount: 3), order: [2, 1, 0])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pagedrop-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }

        try PDFFile.write(document, to: url)
        let loaded = try PDFFile.read(from: url)

        #expect(TestPDF.pageNumbers(of: loaded) == [3, 2, 1])
    }

    @Test("Reading something that isn't a PDF throws")
    func rejectsNonPDF() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pagedrop-\(UUID().uuidString).pdf")
        try Data("not a pdf".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: PDFError.unreadable) {
            try PDFFile.read(from: url)
        }
    }
}
