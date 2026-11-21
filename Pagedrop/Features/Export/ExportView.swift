import PagedropCore
import SwiftUI

struct ExportView: View {
    @Environment(AppModel.self) private var appModel
    @State private var model: ExportModel
    let onBack: () -> Void

    init(session: DocumentSession, onBack: @escaping () -> Void) {
        _model = State(initialValue: ExportModel(session: session))
        self.onBack = onBack
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            Form {
                Picker("Format", selection: $model.format) {
                    ForEach(ImageFormat.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("Resolution", selection: $model.dpi) {
                    ForEach(ExportModel.resolutions, id: \.self) { Text("\(Int($0)) dpi").tag($0) }
                }

                if model.format == .jpeg {
                    LabeledContent("Quality") {
                        Slider(value: $model.jpegQuality, in: 0.1...1)
                            .frame(width: 150)
                    }
                }

                Picker("Pages", selection: $model.scope) {
                    Text("All").tag(PageScope.all)
                    Text("Some").tag(PageScope.custom)
                }
                .pickerStyle(.segmented)

                if model.scope == .custom {
                    TextField("Which pages", text: $model.pageRangeText, prompt: Text("For example 1-3, 5"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                    if model.pageIndexes == nil {
                        Text("Enter page numbers like 1-3, 5.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                LabeledContent("Save in") {
                    Button(model.folder?.lastPathComponent ?? "Choose…") { chooseFolder() }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .disabled(model.isExporting)

            footer
                .padding([.horizontal, .bottom], 16)
        }
    }

    private var header: some View {
        HStack {
            Button(action: onBack) {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)

            Spacer()
            Text("Export as images").font(.headline)
            Spacer()

            // Keeps the title centered.
            Label("Back", systemImage: "chevron.left").hidden()
        }
        .padding(14)
    }

    @ViewBuilder
    private var footer: some View {
        switch model.phase {
        case .idle:
            Button("Export") { model.start() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(!model.canExport)

        case .exporting(let completed, let total):
            HStack(spacing: 12) {
                ProgressView(value: Double(completed), total: Double(max(total, 1)))
                Text("\(completed) of \(total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("Cancel") { model.cancel() }
            }

        case .finished(let count, _):
            HStack {
                Label(count == 1 ? "1 image saved" : "\(count) images saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Spacer()
                Button("Show") { model.revealInFinder() }
                Button("Done") { model.dismissResult() }
            }

        case .failed(let message):
            HStack(alignment: .top) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
                Spacer()
                Button("OK") { model.dismissResult() }
            }
        }
    }

    private func chooseFolder() {
        let folder = appModel.pinningPopover {
            FilePanels.chooseFolder(message: "Choose where to save the images.")
        }
        if let folder { model.folder = folder }
    }
}
