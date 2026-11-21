import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

public enum ImageFormat: String, CaseIterable, Identifiable, Sendable {
    case png
    case jpeg

    public var id: Self { self }

    public var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        }
    }

    public var contentType: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        }
    }

    public var displayName: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        }
    }
}

public struct ImageExportOptions: Sendable, Equatable {
    public var format: ImageFormat
    /// Output resolution in dots per inch. A PDF point is 1/72 inch, so 72 DPI renders at the page's natural size.
    public var dpi: Double
    /// Compression quality from 0 to 1. Ignored for PNG.
    public var jpegQuality: Double

    public init(format: ImageFormat = .png, dpi: Double = 150, jpegQuality: Double = 0.85) {
        self.format = format
        self.dpi = dpi
        self.jpegQuality = jpegQuality
    }
}

/// Renders PDF pages to bitmaps.
public enum PDFPageRenderer {
    /// Draws `page` on an opaque white background at the requested resolution.
    public static func render(_ page: PDFPage, dpi: Double, pageNumber: Int = 1) throws -> CGImage {
        let box = PDFDisplayBox.cropBox
        let bounds = page.bounds(for: box)
        // `bounds(for:)` ignores the page's own rotation, but `draw(with:to:)` applies it.
        let isSideways = page.rotation % 180 != 0
        let pointSize = isSideways ? CGSize(width: bounds.height, height: bounds.width) : bounds.size

        let scale = dpi / 72
        let width = max(1, Int((pointSize.width * scale).rounded()))
        let height = max(1, Int((pointSize.height * scale).rounded()))

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw PDFError.renderFailed(pageNumber: pageNumber) }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: CGFloat(width) / pointSize.width, y: CGFloat(height) / pointSize.height)
        page.draw(with: box, to: context)

        guard let image = context.makeImage() else { throw PDFError.renderFailed(pageNumber: pageNumber) }
        return image
    }
}

/// Exports PDF pages as image files.
public enum PDFImageExporter {
    /// `<name>-page-01.png`. The number is zero-padded to at least two digits (more for long documents).
    public static func fileName(base: String, pageNumber: Int, pageCount: Int, format: ImageFormat) -> String {
        let width = max(2, String(pageCount).count)
        let number = String(format: "%0\(width)d", pageNumber)
        return "\(base)-page-\(number).\(format.fileExtension)"
    }

    /// Encodes a rendered page as PNG or JPEG data, tagging it with the resolution it was rendered at.
    public static func encode(_ image: CGImage, options: ImageExportOptions, pageNumber: Int = 1) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, options.format.contentType.identifier as CFString, 1, nil) else {
            throw PDFError.encodingFailed(pageNumber: pageNumber)
        }
        var properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: options.dpi,
            kCGImagePropertyDPIHeight: options.dpi,
        ]
        if options.format == .jpeg {
            properties[kCGImageDestinationLossyCompressionQuality] = min(max(options.jpegQuality, 0), 1)
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw PDFError.encodingFailed(pageNumber: pageNumber) }
        return data as Data
    }

    /// Renders the given pages and writes one image per page into `folder`.
    ///
    /// Runs on the concurrent pool, never on the main actor. It works on its own `PDFDocument`
    /// built from `pdfData`, because PDFKit objects must not be shared between threads.
    ///
    /// - Parameters:
    ///   - pageIndexes: Zero-based indexes of the pages to export.
    ///   - progress: Called on the main actor after each page with `(completed, total)`.
    /// - Returns: The URLs of the written files, in page order.
    @concurrent
    public static func export(
        pdfData: Data,
        baseName: String,
        pageIndexes: [Int],
        options: ImageExportOptions,
        to folder: URL,
        progress: @MainActor @Sendable (_ completed: Int, _ total: Int) -> Void = { _, _ in }
    ) async throws -> [URL] {
        guard let document = PDFDocument(data: pdfData) else { throw PDFError.unreadable }
        var written: [URL] = []

        for (step, index) in pageIndexes.enumerated() {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { throw PDFError.invalidPageIndexes }

            let image = try PDFPageRenderer.render(page, dpi: options.dpi, pageNumber: index + 1)
            let data = try encode(image, options: options, pageNumber: index + 1)
            let name = fileName(base: baseName, pageNumber: index + 1, pageCount: document.pageCount, format: options.format)
            let url = folder.appendingPathComponent(name)
            try data.write(to: url, options: [])
            written.append(url)

            await progress(step + 1, pageIndexes.count)
        }
        return written
    }
}
