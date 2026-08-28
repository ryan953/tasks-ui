import DexKit
import SwiftUI

struct SidebarView: View {
    @Bindable var store: TaskStore
    @Binding var isCreating: Bool
    @Binding var newTaskParent: String?

    @State private var confirmingDelete: DexTask?

    var body: some View {
        List(store.outline, children: \.outlineChildren, selection: $store.selection) { node in
            TaskRow(task: node.task, state: store.index.state(of: node.task), progress: node.progress)
                .tag(node.task.id)
                .contextMenu { menu(for: node.task) }
        }
        .listStyle(.sidebar)
        .searchable(text: $store.query, placement: .sidebar, prompt: "Search tasks")
        .overlay { emptyOverlay }
        .safeAreaInset(edge: .bottom) { statusBar }
        .toolbar { toolbarItems }
        .confirmationDialog(
            "Delete “\(confirmingDelete?.description ?? "")”?",
            isPresented: Binding(
                get: { confirmingDelete != nil },
                set: { if !$0 { confirmingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let task = confirmingDelete {
                    Task { await store.delete(task.id) }
                }
                confirmingDelete = nil
            }
            Button("Cancel", role: .cancel) { confirmingDelete = nil }
        } message: {
            Text(deleteWarning)
        }
    }

    private var deleteWarning: String {
        let children = confirmingDelete?.children.count ?? 0
        return children > 0
            ? "This also deletes \(children) subtask\(children == 1 ? "" : "s"). This cannot be undone."
            : "This cannot be undone."
    }

    @ViewBuilder
    private var emptyOverlay: some View {
        if store.outline.isEmpty && !store.isLoading && !store.isBootstrapping {
            ContentUnavailableView {
                Label(store.query.isEmpty ? "No tasks" : "No matches", systemImage: "tray")
            } description: {
                Text(store.query.isEmpty
                    ? "Create a task to get started."
                    : "No task matches “\(store.query)”.")
            } actions: {
                if store.query.isEmpty {
                    Button("New Task") { isCreating = true }
                } else {
                    Button("Clear Search") { store.query = "" }
                }
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 6) {
            if store.isLoading {
                ProgressView().controlSize(.small)
            }
            Text("\(store.counts.done) of \(store.counts.total) done")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Toggle("Show completed", isOn: $store.showCompleted)
                .toggleStyle(.checkbox)
                .font(.caption)
                .disabled(store.filter != .all)
                .help(store.filter == .all
                    ? "Hide finished tasks from the list"
                    : "Clear the status filter to use this")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem {
            Menu {
                Picker("Show", selection: $store.filter) {
                    ForEach(StatusFilter.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
                Divider()
                Picker("Sort by", selection: $store.sort) {
                    ForEach(SortField.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Filter", systemImage: store.filter == .all
                    ? "line.3.horizontal.decrease.circle"
                    : "line.3.horizontal.decrease.circle.fill")
            }
            .help("Filter and sort")
        }
        ToolbarItem {
            Button {
                Task { await store.reload() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Reload from dex (⌘R)")
        }
        ToolbarItem {
            Button {
                newTaskParent = nil
                isCreating = true
            } label: {
                Label("New Task", systemImage: "plus")
            }
            .help("New task (⌘N)")
        }
    }

    @ViewBuilder
    private func menu(for task: DexTask) -> some View {
        if task.completed {
            Button("Reopen") { Task { await store.reopen(task.id) } }
        } else {
            Button("Mark as Done…") { store.selection = task.id }
        }
        Button("Add Subtask…") {
            newTaskParent = task.id
            isCreating = true
        }
        Divider()
        Button("Copy Task ID") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(task.id, forType: .string)
        }
        Divider()
        Button("Delete…", role: .destructive) { confirmingDelete = task }
    }
}

struct TaskRow: View {
    let task: DexTask
    let state: TaskState
    let progress: (done: Int, total: Int)

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: state.symbol)
                .foregroundStyle(tint)
                .font(.system(size: 12))
                .help(state.rawValue.capitalized)

            Text(task.description.isEmpty ? "Untitled" : task.description)
                .lineLimit(1)
                .truncationMode(.tail)
                .strikethrough(task.completed, color: .secondary)
                .foregroundStyle(task.completed ? .secondary : .primary)

            Spacer(minLength: 4)

            if progress.total > 0 {
                Text("\(progress.done)/\(progress.total)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .help("Completed subtasks")
            }
            PriorityBadge(priority: task.priority)
        }
        .padding(.vertical, 1)
    }

    private var tint: Color {
        switch state {
        case .completed: .green
        case .blocked: .orange
        case .ready: .secondary
        }
    }
}

struct PriorityBadge: View {
    let priority: Int

    var body: some View {
        Text("P\(priority)")
            .font(.caption2.weight(.medium).monospacedDigit())
            .foregroundStyle(tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(tint.opacity(0.13), in: Capsule())
            .help("Priority \(priority) — lower runs first")
    }

    /// dex treats a lower number as more urgent.
    private var tint: Color {
        switch priority {
        case ..<2: .red
        case 2: .orange
        case 3: .yellow
        default: .secondary
        }
    }
}
