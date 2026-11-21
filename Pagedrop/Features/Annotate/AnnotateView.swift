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
            toolButton("Select text", systemImage: "character.cursor.ibeam", tool: .select)
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
            Menu {
                Button("Save As…") { _ = model.save(asCopy: true) }
            } label: {
                Text("Save")
            } primaryAction: {
                _ = model.save()
            }
        }
    }

    private func toolButton(_ title: String, systemImage: String, tool: AnnotationTool) -> some View {
        Toggle(isOn: Binding(
            get: { model.tool == tool },
            set: { if $0 { model.tool = tool } }
        )) {
            Label(title, systemImage: systemImage)
        }
        .toggleStyle(.button)
        .help(title)
    }
}
