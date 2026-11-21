import CoreGraphics
import Foundation
import PDFKit

enum TestPDF {
    /// Builds an in-memory PDF. Page `n` (starting at 1) is `100 + 10 * n` points wide and 100 points high,
    /// so pages can be told apart after being removed or moved. Each page has a 20-point black square in its
    /// bottom-left corner.
    static func make(pageCount: Int) -> PDFDocument {
        let data = NSMutableData()
        let context = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: nil, nil)!

        for number in 1...pageCount {
            var box = CGRect(x: 0, y: 0, width: 100 + 10 * number, height: 100)
            let pageInfo = [kCGPDFContextMediaBox as String: Data(bytes: &box, count: MemoryLayout<CGRect>.size)] as CFDictionary
            context.beginPDFPage(pageInfo)
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
            context.endPDFPage()
        }
        context.closePDF()
        return PDFDocument(data: data as Data)!
    }

    /// The original page numbers of `document`'s pages, in order.
    static func pageNumbers(of document: PDFDocument) -> [Int] {
        (0..<document.pageCount).map { index in
            Int(document.page(at: index)!.bounds(for: .mediaBox).width) / 10 - 10
        }
    }

    /// Reads one pixel of a rendered image as a grayscale value from 0 to 255.
    /// `y` counts from the top row, as in a screenshot.
    static func gray(in image: CGImage, x: Int, y: Int) -> Int {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        // Draw the single requested pixel into a 1x1 context.
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return Int(pixel[0])
    }
}
