import DexKit
import SwiftUI

struct ContentView: View {
    @Bindable var store: TaskStore
    @Binding var isCreating: Bool

    /// Pre-fills the parent when the sheet is opened from "Add Subtask".
    @State private var newTaskParent: String?

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store, isCreating: $isCreating, newTaskParent: $newTaskParent)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 460)
        } detail: {
            Group {
                if let task = store.selectedTask {
                    TaskDetailView(store: store, task: task, newTaskParent: $newTaskParent, isCreating: $isCreating)
                        // Rebuild the editing state when a different task is picked,
                        // so a half-typed edit cannot leak onto the next task.
                        .id(task.id)
                } else {
                    EmptyDetail(store: store, isCreating: $isCreating)
                }
            }
            .frame(minWidth: 420)
        }
        .sheet(isPresented: $isCreating) {
            NewTaskSheet(store: store, parentID: newTaskParent)
        }
        .onChange(of: isCreating) { _, presented in
            if !presented { newTaskParent = nil }
        }
        .alert(
            "dex reported a problem",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.dismissError() } }
            )
        ) {
            Button("OK", role: .cancel) { store.dismissError() }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

/// Shown when nothing is selected, and when dex itself cannot be found.
private struct EmptyDetail: View {
    let store: TaskStore
    @Binding var isCreating: Bool

    var body: some View {
        VStack(spacing: 14) {
            if store.isBootstrapping {
                ProgressView()
            } else if store.resolvedBinary == nil {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 34))
                    .foregroundStyle(.orange)
                Text("Could not find the dex executable")
                    .font(.title3.weight(.medium))
                Text("Set the path to dex in Settings.")
                    .foregroundStyle(.secondary)
                SettingsLink { Text("Open Settings…") }
            } else {
                Image(systemName: "checklist")
                    .font(.system(size: 38))
                    .foregroundStyle(.tertiary)
                Text("Select a task")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                Button("New Task") { isCreating = true }
                    .keyboardShortcut("n")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
