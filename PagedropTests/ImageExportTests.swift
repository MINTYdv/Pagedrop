import CoreGraphics
import Foundation
import ImageIO
import PagedropCore
import PDFKit
import Testing

@Suite("Image export")
struct ImageExportTests {
    @Test("File names are zero-padded", arguments: [
        (1, 5, ImageFormat.png, "Report-page-01.png"),
        (12, 20, ImageFormat.jpeg, "Report-page-12.jpg"),
        (7, 150, ImageFormat.png, "Report-page-007.png"),
    ])
    func fileNames(pageNumber: Int, pageCount: Int, format: ImageFormat, expected: String) {
        #expect(PDFImageExporter.fileName(base: "Report", pageNumber: pageNumber, pageCount: pageCount, format: format) == expected)
    }

    @Test("Rendering scales with the resolution", arguments: [(72.0, 110, 100), (144.0, 220, 200), (300.0, 458, 417)])
    func renderSize(dpi: Double, expectedWidth: Int, expectedHeight: Int) throws {
        let page = try #require(TestPDF.make(pageCount: 1).page(at: 0))

        let image = try PDFPageRenderer.render(page, dpi: dpi)

        #expect(image.width == expectedWidth)
        #expect(image.height == expectedHeight)
    }

    @Test("Rendering draws the page on a white background")
    func renderContent() throws {
        let page = try #require(TestPDF.make(pageCount: 1).page(at: 0))

        let image = try PDFPageRenderer.render(page, dpi: 72)

        // The black square is in the bottom-left corner; the top-right corner is blank.
        #expect(TestPDF.gray(in: image, x: 5, y: image.height - 5) < 40)
        #expect(TestPDF.gray(in: image, x: image.width - 5, y: 5) > 215)
    }

    @Test("A rotated page is rendered upright")
    func renderRotatedPage() throws {
        let page = try #require(TestPDF.make(pageCount: 1).page(at: 0))
        page.rotation = 90

        let image = try PDFPageRenderer.render(page, dpi: 72)

        #expect(image.width == 100)
        #expect(image.height == 110)
        // Rotating 90° clockwise carries the bottom-left corner to the top-left.
        #expect(TestPDF.gray(in: image, x: 5, y: 5) < 40)
        #expect(TestPDF.gray(in: image, x: 5, y: image.height - 5) > 215)
    }

    @Test("Encoded images have the requested format", arguments: ImageFormat.allCases)
    func encodedFormat(format: ImageFormat) throws {
        let page = try #require(TestPDF.make(pageCount: 1).page(at: 0))
        let image = try PDFPageRenderer.render(page, dpi: 72)

        let data = try PDFImageExporter.encode(image, options: ImageExportOptions(format: format))

        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let type = try #require(CGImageSourceGetType(source) as String?)
        #expect(type == format.contentType.identifier)
    }

    @Test("Lower JPEG quality produces smaller files")
    func jpegQuality() throws {
        let page = try #require(TestPDF.make(pageCount: 1).page(at: 0))
        let image = try PDFPageRenderer.render(page, dpi: 300)

        let high = try PDFImageExporter.encode(image, options: ImageExportOptions(format: .jpeg, jpegQuality: 1))
        let low = try PDFImageExporter.encode(image, options: ImageExportOptions(format: .jpeg, jpegQuality: 0.1))

        #expect(low.count < high.count)
    }

    @Test("Exporting writes one file per requested page and reports progress")
    func exportsFiles() async throws {
        let document = TestPDF.make(pageCount: 4)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pagedrop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let reports = ProgressLog()
        let files = try await PDFImageExporter.export(
            pdfData: try #require(document.dataRepresentation()),
            baseName: "Doc",
            pageIndexes: [0, 2, 3],
            options: ImageExportOptions(format: .png, dpi: 72),
            to: folder
        ) { completed, total in
            reports.record(completed, of: total)
        }

        #expect(files.map(\.lastPathComponent) == ["Doc-page-01.png", "Doc-page-03.png", "Doc-page-04.png"])
        for file in files {
            #expect(FileManager.default.fileExists(atPath: file.path))
            let source = try #require(CGImageSourceCreateWithURL(file as CFURL, nil))
            #expect(CGImageSourceGetCount(source) == 1)
        }
        let values = await reports.values
        #expect(values == [1, 2, 3])
    }

    @Test("Cancelling stops the export")
    func cancelledExport() async throws {
        let document = TestPDF.make(pageCount: 3)
        let data = try #require(document.dataRepresentation())
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pagedrop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let task = Task {
            try await PDFImageExporter.export(pdfData: data, baseName: "Doc", pageIndexes: [0, 1, 2], options: ImageExportOptions(), to: folder)
        }
        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
    }
}

/// Collects progress reports. The export reports on the main actor, so access is serialized there.
@MainActor
final class ProgressLog {
    private(set) var values: [Int] = []

    func record(_ completed: Int, of total: Int) {
        values.append(completed)
    }
}
