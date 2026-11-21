import SwiftUI

/// The content of the popover. Shows an empty state until a document is loaded.
struct PopoverRootView: View {
    @Environment(AppModel.self) private var model
    @State private var screen: Screen = .tools

    enum Screen {
        case tools
        case export
    }

    var body: some View {
        @Bindable var model = model

        Group {
            if model.session.isLoaded {
                switch screen {
                case .tools:
                    ToolsView(onSelectExport: { screen = .export })
                case .export:
                    ExportView(session: model.session, onBack: { screen = .tools })
                        .id(model.session.revision)
                }
            } else {
                EmptyStateView()
            }
        }
        .frame(width: 360)
        .background(.regularMaterial)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: \.isPDF) else { return false }
            return model.open(url)
        }
        .alert(
            model.alert?.title ?? "",
            isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } }),
            presenting: model.alert
        ) { _ in
            Button("OK") {}
        } message: { alert in
            Text(alert.message)
        }
        .onChange(of: model.session.isLoaded) { _, isLoaded in
            if !isLoaded { screen = .tools }
        }
    }
}
