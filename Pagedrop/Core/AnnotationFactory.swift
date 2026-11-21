import AppKit
import PDFKit

/// A finished annotation together with the page it belongs to.
public struct PlacedAnnotation {
    public let page: PDFPage
    public let annotation: PDFAnnotation

    public init(page: PDFPage, annotation: PDFAnnotation) {
        self.page = page
        self.annotation = annotation
    }
}

/// Builds PDF annotations. Nothing here touches views, so it can run in tests.
public enum AnnotationFactory {
    public static let highlightColor = NSColor.systemYellow.withAlphaComponent(0.5)
    public static let penColor = NSColor.systemRed
    public static let penWidth: CGFloat = 2.5

    /// One highlight per selected line of text.
    public static func highlights(for selection: PDFSelection) -> [PlacedAnnotation] {
        selection.selectionsByLine().flatMap { line in
            line.pages.compactMap { page -> PlacedAnnotation? in
                let bounds = line.bounds(for: page)
                guard !bounds.isEmpty else { return nil }

                let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                annotation.color = highlightColor
                // Quadrilateral points are relative to the annotation's origin.
                annotation.quadrilateralPoints = [
                    CGPoint(x: 0, y: bounds.height),
                    CGPoint(x: bounds.width, y: bounds.height),
                    CGPoint(x: 0, y: 0),
                    CGPoint(x: bounds.width, y: 0),
                ].map { NSValue(point: $0) }
                return PlacedAnnotation(page: page, annotation: annotation)
            }
        }
    }

    /// A freehand stroke through `points`, which are expressed in page coordinates.
    public static func ink(through points: [CGPoint], color: NSColor = penColor, width: CGFloat = penWidth) -> PDFAnnotation? {
        guard let first = points.first else { return nil }

        let path = NSBezierPath()
        path.move(to: first)
        for point in points.dropFirst() { path.line(to: point) }
        if points.count == 1 { path.line(to: CGPoint(x: first.x + 0.01, y: first.y)) }

        let bounds = path.bounds.insetBy(dx: -width, dy: -width)
        let annotation = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
        annotation.color = color
        let border = PDFBorder()
        border.lineWidth = width
        annotation.border = border

        // The ink path is relative to the annotation's origin.
        path.transform(using: AffineTransform(translationByX: -bounds.minX, byY: -bounds.minY))
        annotation.add(path)
        return annotation
    }

    /// The font notes are written in.
    public static var noteFont: NSFont { .systemFont(ofSize: 14) }
    /// Notes wrap their text at this width (not counting the padding around it).
    public static let noteMaxWidth: CGFloat = 240

    /// The size of the box that fits `text`, in page units. Empty text gets the size of a single blank line.
    public static func noteSize(for text: String, font: NSFont = noteFont) -> CGSize {
        let measured = ((text.isEmpty ? " " : text) as NSString).boundingRect(
            with: CGSize(width: noteMaxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return CGSize(width: ceil(measured.width) + 12, height: ceil(measured.height) + 8)
    }

    /// A text note whose top-left corner is at `point` and whose box is sized to fit `text`.
    public static func note(_ text: String, at point: CGPoint, font: NSFont = noteFont) -> PDFAnnotation {
        let size = noteSize(for: text, font: font)
        let bounds = CGRect(origin: CGPoint(x: point.x, y: point.y - size.height), size: size)

        let annotation = PDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
        annotation.contents = text
        annotation.font = font
        annotation.fontColor = .black
        annotation.color = NSColor.systemYellow.withAlphaComponent(0.35)
        annotation.alignment = .left
        let border = PDFBorder()
        border.lineWidth = 0
        annotation.border = border
        return annotation
    }
}
