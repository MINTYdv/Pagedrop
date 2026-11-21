import PDFKit
import SwiftUI

/// Renders and caches small page previews.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()

    func image(for page: PDFPage, width: CGFloat, key: String) -> NSImage {
        let cacheKey = "\(key)-\(Int(width))" as NSString
        if let cached = cache.object(forKey: cacheKey) { return cached }

        let bounds = page.bounds(for: .cropBox)
        let aspect = page.rotation % 180 == 0 ? bounds.height / bounds.width : bounds.width / bounds.height
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let size = CGSize(width: width * scale, height: width * aspect * scale)
        let image = page.thumbnail(of: size, for: .cropBox)
        cache.setObject(image, forKey: cacheKey)
        return image
    }
}

/// A page preview with a hairline border, sized by width.
struct PageThumbnailView: View {
    let page: PDFPage?
    let width: CGFloat
    /// Distinguishes documents so cached previews never leak between files or edits.
    let cacheKey: String

    var body: some View {
        Group {
            if let page {
                Image(nsImage: ThumbnailCache.shared.image(for: page, width: width, key: cacheKey))
                    .resizable()
                    .scaledToFit()
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        .frame(width: width)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
    }
}
