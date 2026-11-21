import AppKit
import Observation
import PagedropCore

enum PageScope: Hashable {
    case all
    case custom
}

@MainActor
@Observable
final class ExportModel {
    enum Phase: Equatable {
        case idle
        case exporting(completed: Int, total: Int)
        case finished(count: Int, folder: URL)
        case failed(String)
    }

    private let session: DocumentSession

    var format: ImageFormat = .png
    var dpi: Double = 150
    var jpegQuality: Double = 0.85
    var scope: PageScope = .all
    var pageRangeText = ""
    var folder: URL?
    private(set) var phase: Phase = .idle

    @ObservationIgnored
    private var exportTask: Task<Void, Never>?

    static let resolutions: [Double] = [72, 150, 300]

    init(session: DocumentSession) {
        self.session = session
    }

    var isExporting: Bool {
        if case .exporting = phase { true } else { false }
    }

    /// The indexes to export, or `nil` while the page list typed by the user is invalid.
    var pageIndexes: [Int]? {
        switch scope {
        case .all:
            return Array(0..<session.pageCount)
        case .custom:
            return try? PageOrder.parse(pageRangeText, pageCount: session.pageCount)
        }
    }

    var canExport: Bool {
        folder != nil && pageIndexes != nil && !isExporting
    }

    func start() {
        guard let document = session.document, let folder, let pageIndexes else { return }

        // `dataRepresentation()` captures the current state, including edits that aren't saved yet.
        guard let data = document.dataRepresentation() else {
            phase = .failed(PDFError.unreadable.localizedDescription)
            return
        }
        let options = ImageExportOptions(format: format, dpi: dpi, jpegQuality: jpegQuality)
        let baseName = session.displayName
        phase = .exporting(completed: 0, total: pageIndexes.count)

        exportTask = Task {
            do {
                let files = try await PDFImageExporter.export(
                    pdfData: data,
                    baseName: baseName,
                    pageIndexes: pageIndexes,
                    options: options,
                    to: folder
                ) { [weak self] completed, total in
                    self?.phase = .exporting(completed: completed, total: total)
                }
                phase = .finished(count: files.count, folder: folder)
            } catch is CancellationError {
                phase = .idle
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        exportTask?.cancel()
    }

    func revealInFinder() {
        guard case .finished(_, let folder) = phase else { return }
        NSWorkspace.shared.open(folder)
    }

    func dismissResult() {
        phase = .idle
    }
}
