import SwiftUI

struct AnnotateView: View {
    @Bindable var model: AnnotationModel

    var body: some View {
        PDFAnnotatingView(document: model.document, tool: model.tool, model: model)
            .toolbar { toolbar }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            toolButton("Draw", systemImage: "pencil.tip", tool: .pen)
            toolButton("Add a note", systemImage: "text.bubble", tool: .note)

            Button("Highlight", systemImage: "highlighter") { model.highlightSelection() }
                .disabled(!model.hasSelection)
                .help("Highlight the selected text")

            Button("Undo", systemImage: "arrow.uturn.backward") { model.undo() }
                .disabled(!model.canUndo)
                .help("Undo the last change")
        }

        ToolbarItem(placement: .primaryAction) {
            SaveButton(
                feedback: model.saveFeedback,
                hasChanges: model.canSave,
                save: { await model.saveWithFeedback() },
                saveAs: { await model.saveWithFeedback(asCopy: true) }
            )
        }
    }

    private func toolButton(_ title: String, systemImage: String, tool: AnnotationTool) -> some View {
        Toggle(isOn: Binding(
            get: { model.tool == tool },
            set: { model.tool = $0 ? tool : .select }
        )) {
            Label(title, systemImage: systemImage)
        }
        .toggleStyle(.button)
        .help(title)
    }
}
