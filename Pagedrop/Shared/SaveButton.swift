import Observation
import SwiftUI

/// Drives the Save button's feedback: a brief "Saving", then a checkmark that fades back to normal.
@MainActor
@Observable
final class SaveFeedback {
    enum Phase {
        case idle
        case saving
        case saved
    }

    private(set) var phase = Phase.idle
    @ObservationIgnored
    private var resetTask: Task<Void, Never>?

    /// Runs `save` (which reports whether it succeeded) while showing progress, then confirms success.
    func perform(_ save: () -> Bool) async {
        guard phase != .saving else { return }
        resetTask?.cancel()
        phase = .saving
        // Let the progress state reach the screen before the (synchronous) write starts.
        await Task.yield()

        guard save() else {
            phase = .idle
            return
        }
        phase = .saved
        resetTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            phase = .idle
        }
    }
}

/// A toolbar Save button that is disabled when there is nothing to save and confirms when it is done.
/// Its menu offers saving a copy. ⌘S saves.
struct SaveButton: View {
    let feedback: SaveFeedback
    let hasChanges: Bool
    let save: @MainActor () async -> Void
    let saveAs: @MainActor () async -> Void

    private var isDisabled: Bool { feedback.phase == .idle && !hasChanges }

    var body: some View {
        Menu {
            Button("Save As…") { Task { await saveAs() } }
        } label: {
            label
        } primaryAction: {
            Task { await save() }
        }
        .disabled(isDisabled)
        .background {
            // Menu items only receive shortcuts while the menu is open, so ⌘S lives on a hidden button.
            Button("Save") { Task { await save() } }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(isDisabled)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var label: some View {
        switch feedback.phase {
        case .idle:
            Text("Save")
        case .saving:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Saving")
            }
        case .saved:
            // An explicit HStack: a toolbar would show only the icon of a `Label`.
            HStack(spacing: 6) {
                Image(systemName: "checkmark").symbolEffect(.bounce, value: feedback.phase)
                Text("Saved")
            }
        }
    }
}
