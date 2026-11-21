import PagedropCore
import PDFKit
import SwiftUI

struct PageEditorView: View {
    @Environment(AppModel.self) private var appModel
    @State var model: PageEditorModel
    let onFinish: () -> Void

    init(model: PageEditorModel, onFinish: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onFinish = onFinish
    }

    private let columns = [GridItem(.adaptive(minimum: 130, maximum: 170), spacing: 20)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 24) {
                ForEach(Array(model.order.enumerated()), id: \.element) { position, original in
                    PageCell(model: model, original: original, position: position)
                }
            }
            .padding(24)
            .animation(.snappy, value: model.order)
        }
        .background(.background)
        .toolbar { toolbar }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            if model.mode == .remove {
                Button("Remove", systemImage: "trash") { model.removeSelected() }
                    .disabled(!model.canRemove)
                    .help("Remove the selected pages")
            }
            Button("Undo All", systemImage: "arrow.uturn.backward") { model.reset() }
                .disabled(!model.hasChanges && model.selection.isEmpty)
                .help("Put everything back")
        }

        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Save As…") { save(asCopy: true) }
            } label: {
                Text("Save")
            } primaryAction: {
                save(asCopy: false)
            }
            .disabled(!model.hasChanges)
        }
    }

    private func save(asCopy: Bool) {
        do {
            let edited = try model.editedDocument()
            if asCopy {
                guard try appModel.saveDocumentAs(edited) else { return }
            } else {
                do {
                    try appModel.session.save(edited)
                } catch {
                    // The original may not be writable (read-only location, no sandbox access): offer a copy instead.
                    guard try appModel.saveDocumentAs(edited) else { return }
                }
            }
            onFinish()
        } catch {
            ErrorAlert.show(error, title: "Can't save")
        }
    }
}

private struct PageCell: View {
    let model: PageEditorModel
    let original: Int
    let position: Int

    var body: some View {
        let isSelected = model.selection.contains(original)

        VStack(spacing: 8) {
            PageThumbnailView(
                page: model.source?.page(at: original),
                width: 120,
                cacheKey: "editor-\(model.thumbnailKey)-\(original)"
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 3).strokeBorder(Color.accentColor, lineWidth: 3)
                }
            }
            .overlay(alignment: .topTrailing) {
                if model.mode == .remove {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(isSelected ? .white : .secondary, isSelected ? Color.accentColor : .clear)
                        .font(.title3)
                        .padding(4)
                }
            }

            Text("\(position + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contentShape(.rect)
        .onTapGesture {
            if model.mode == .remove { model.toggleSelection(original) }
        }
        .modifier(ReorderModifier(model: model, original: original))
        .accessibilityLabel("Page \(position + 1)")
    }
}

/// Drag and drop is only active when reordering, so it can't interfere with selecting pages.
private struct ReorderModifier: ViewModifier {
    let model: PageEditorModel
    let original: Int

    func body(content: Content) -> some View {
        if model.mode == .reorder {
            content
                .draggable(PageDragItem(originalIndex: original))
                .dropDestination(for: PageDragItem.self) { items, _ in
                    guard let dragged = items.first else { return false }
                    model.move(dragged.originalIndex, onto: original)
                    return true
                }
                .contextMenu {
                    Button("Move to Start") { model.moveToStart(original) }
                    Button("Move to End") { model.moveToEnd(original) }
                }
        } else {
            content
        }
    }
}
