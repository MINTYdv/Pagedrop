import SwiftUI

/// The popover's main screen: the loaded document and the actions available for it.
struct ToolsView: View {
    @Environment(AppModel.self) private var model
    let onSelectExport: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            DocumentHeader()
                .padding(16)

            Divider()

            VStack(spacing: 2) {
                ToolRow(title: "Export as images", subtitle: "Save pages as pictures", systemImage: "photo.on.rectangle", action: onSelectExport)
                ToolRow(title: "Remove pages", subtitle: "Delete the ones you don't need", systemImage: "trash", action: { model.presenter?.showPageEditor(mode: .remove) })
                    .disabled(model.session.pageCount < 2)
                ToolRow(title: "Reorder pages", subtitle: "Drag pages into a new order", systemImage: "arrow.up.arrow.down", action: { model.presenter?.showPageEditor(mode: .reorder) })
                    .disabled(model.session.pageCount < 2)
                ToolRow(title: "Annotate", subtitle: "Mark up your document", systemImage: "pencil.tip.crop.circle", action: { model.presenter?.showAnnotator() })
            }
            .padding(8)
        }
    }
}

private struct DocumentHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let session = model.session
        HStack(spacing: 14) {
            PageThumbnailView(
                page: session.document?.page(at: 0),
                width: 44,
                cacheKey: "header-\(session.revision)"
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(session.pageCount == 1 ? "1 page" : "\(session.pageCount) pages")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                model.closeDocument()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Close document")

            SettingsMenu()
        }
    }
}

private struct ToolRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16))
                    .foregroundStyle(.tint)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(.rect)
            .background(isHovering && isEnabled ? Color.primary.opacity(0.08) : .clear, in: .rect(cornerRadius: 8))
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
