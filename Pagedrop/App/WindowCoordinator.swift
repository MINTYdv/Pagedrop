import AppKit
import SwiftUI

/// Creates and reuses the larger windows used by the page editor and the annotation tool.
///
/// Plain `NSWindow`s hosting SwiftUI are used instead of SwiftUI `Window` scenes: the windows are
/// opened from AppKit code (the status item) where there is no SwiftUI environment to call `openWindow` from.
@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var pageEditorWindow: NSWindow?
    private var annotatorWindow: NSWindow?
    private var annotationModel: AnnotationModel?

    init(model: AppModel) {
        self.model = model
    }

    func showPageEditor(mode: PageEditorMode) {
        let editor = PageEditorModel(session: model.session, mode: mode)
        let view = PageEditorView(model: editor)
            .environment(model)
        let window = pageEditorWindow ?? makeWindow(size: NSSize(width: 760, height: 560), minSize: NSSize(width: 480, height: 360))
        install(view, in: window)
        window.title = model.session.displayName
        window.subtitle = mode.hint
        pageEditorWindow = window
        present(window)
    }

    func showAnnotator() {
        let annotation = AnnotationModel(app: model)
        annotationModel = annotation
        let view = AnnotateView(model: annotation).environment(model)
        let window = annotatorWindow ?? makeWindow(size: NSSize(width: 900, height: 700), minSize: NSSize(width: 560, height: 420))
        install(view, in: window)
        window.title = model.session.displayName
        window.subtitle = "Annotate"
        window.delegate = self
        annotatorWindow = window
        present(window)
    }

    func closeAll() {
        annotationModel?.discardChanges()
        pageEditorWindow?.close()
        annotatorWindow?.close()
    }

    // MARK: NSWindowDelegate

    /// Offers to save annotations before the annotation window closes.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === annotatorWindow, let annotation = annotationModel, annotation.hasUnsavedChanges else { return true }

        let alert = NSAlert()
        alert.messageText = "Do you want to save your changes?"
        alert.informativeText = "Your annotations will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return annotation.save()
        case .alertSecondButtonReturn:
            annotation.discardChanges()
            return true
        default:
            return false
        }
    }

    // MARK: Helpers

    private func makeWindow(size: NSSize, minSize: NSSize) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = minSize
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    /// Hosts `view` without letting its intrinsic size resize the window the user may have adjusted.
    private func install(_ view: some View, in window: NSWindow) {
        let host = NSHostingController(rootView: view)
        host.sizingOptions = []
        let size = window.contentRect(forFrameRect: window.frame).size
        window.contentViewController = host
        window.setContentSize(size)
    }

    private func present(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
