import AppKit
import Observation
import PDFKit
import UniformTypeIdentifiers

/// What the app asks of the AppKit side (status item, popover, windows).
/// `StatusBarController` is the only implementation; views only ever see this protocol.
@MainActor
protocol WindowPresenting: AnyObject {
    func showPopover()
    func closePopover()
    func setPopoverPinned(_ pinned: Bool)
    func showPageEditor(mode: PageEditorMode)
    func showAnnotator()
    func closeToolWindows()
}

struct AppAlert {
    let title: String
    let message: String
}

/// Root of the app's state. Owns the loaded document and mediates between SwiftUI and AppKit.
@MainActor
@Observable
final class AppModel {
    let session = DocumentSession()
    var alert: AppAlert?

    @ObservationIgnored
    weak var presenter: (any WindowPresenting)?

    /// Loads a PDF and brings the popover forward. Returns whether it worked.
    @discardableResult
    func open(_ url: URL) -> Bool {
        do {
            try session.load(from: url)
            presenter?.closeToolWindows()
            presenter?.showPopover()
            return true
        } catch {
            present(error, title: "Can't open this file")
            return false
        }
    }

    func chooseDocument() {
        guard let url = pinningPopover({ FilePanels.chooseDocument() }) else { return }
        open(url)
    }

    func closeDocument() {
        presenter?.closeToolWindows()
        session.close()
    }

    func present(_ error: Error, title: String) {
        alert = AppAlert(title: title, message: error.localizedDescription)
        presenter?.showPopover()
    }

    /// Runs a modal panel without the transient popover closing underneath it.
    func pinningPopover<T>(_ body: () -> T) -> T {
        presenter?.setPopoverPinned(true)
        defer { presenter?.setPopoverPinned(false) }
        return body()
    }

    /// Asks where to save a copy, then saves there. Returns `false` if the user cancelled.
    func saveDocumentAs(_ edited: PDFDocument? = nil) throws -> Bool {
        guard let url = pinningPopover({ FilePanels.chooseSaveLocation(suggestedName: session.displayName) }) else {
            return false
        }
        try session.save(edited, to: url)
        return true
    }
}

extension URL {
    var isPDF: Bool {
        UTType(filenameExtension: pathExtension)?.conforms(to: .pdf) ?? false
    }
}
