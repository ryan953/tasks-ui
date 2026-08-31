import DexKit
import SwiftUI

struct TaskDetailView: View {
    @Bindable var store: TaskStore
    let task: DexTask
    @Binding var newTaskParent: String?
    @Binding var isCreating: Bool

    @State private var draft: Draft
    @State private var isCompleting = false
    @State private var isConfirmingDelete = false
    @FocusState private var focus: Field?

    private enum Field { case name, details }

    init(store: TaskStore, task: DexTask, newTaskParent: Binding<String?>, isCreating: Binding<Bool>) {
        self.store = store
        self.task = task
        _newTaskParent = newTaskParent
        _isCreating = isCreating
        _draft = State(initialValue: Draft(task: task))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                Divider()
                detailsEditor
                fields
                RelationsView(store: store, task: task)
                if task.completed { resultSection }
                if let commit = task.metadata?.commit { CommitView(commit: commit) }
                timestamps
            }
            .padding(22)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background)
        .safeAreaInset(edge: .bottom) { if isDirty { saveBar } }
        .toolbar { toolbarItems }
        .sheet(isPresented: $isCompleting) {
            CompleteSheet(task: task) { result, commit in
                Task { await store.complete(task.id, result: result, commit: commit) }
            }
        }
        .confirmationDialog(
            "Delete “\(task.name)”?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { Task { await store.delete(task.id) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                task.children.isEmpty
                    ? "This cannot be undone."
                    : "This also deletes \(task.children.count) subtask\(task.children.count == 1 ? "" : "s"). This cannot be undone."
            )
        }
        // The file watcher can refresh a task while it is open. Adopt the new values
        // only when the user has nothing unsaved, so typing is never overwritten.
        .onChange(of: task) { _, updated in
            if !isDirty { draft = Draft(task: updated) }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Task name", text: $draft.name, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.title2.weight(.semibold))
                .lineLimit(1...4)
                .focused($focus, equals: .name)

            HStack(spacing: 8) {
                StateBadge(state: store.index.state(of: task))
                PriorityBadge(priority: task.priority)
                Text(task.id)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .help("Task ID — click to select, ⌘C to copy")
            }
        }
    }

    // MARK: - Editors

    private var detailsEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Description")
            TextEditor(text: $draft.details)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 140)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color(nsColor: .separatorColor))
                )
                .focused($focus, equals: .details)
                .overlay(alignment: .topLeading) {
                    if draft.details.isEmpty {
                        Text("Requirements, approach, done criteria…")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    private var fields: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Priority")
                Stepper(value: $draft.priority, in: 1...9) {
                    Text("P\(draft.priority)").monospacedDigit()
                }
                .frame(width: 110)
                .help("Lower numbers come first")
            }
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Parent")
                TaskPicker(
                    store: store,
                    title: "No parent",
                    excluding: store.index.ineligibleRelations(for: task),
                    selection: $draft.parentID
                )
            }
            Spacer()
        }
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Result")
            Text(task.result?.isEmpty == false ? task.result! : "No result recorded.")
                .font(.callout)
                .foregroundStyle(task.result?.isEmpty == false ? .primary : .secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 7))
        }
    }

    private var timestamps: some View {
        HStack(spacing: 16) {
            if let created = task.createdAt { Stamp(label: "Created", date: created) }
            if let started = task.startedAt { Stamp(label: "Started", date: started) }
            if let updated = task.updatedAt { Stamp(label: "Updated", date: updated) }
            if let completed = task.completedAt { Stamp(label: "Completed", date: completed) }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: - Saving

    private var isDirty: Bool { draft != Draft(task: task) }

    private var saveBar: some View {
        HStack {
            Text("Unsaved changes")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Revert") { draft = Draft(task: task) }
            Button("Save Changes") { save() }
                .keyboardShortcut("s")
                .buttonStyle(.borderedProminent)
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func save() {
        let edit = draft.edit(from: task)
        guard !edit.isEmpty else { return }
        focus = nil
        Task { await store.apply(edit, to: task.id) }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem {
            Button {
                newTaskParent = task.id
                isCreating = true
            } label: {
                Label("Add Subtask", systemImage: "plus.rectangle.on.rectangle")
            }
            .help("Add a subtask under this task")
        }
        ToolbarItem {
            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .help("Delete this task")
        }
        ToolbarItem {
            if !task.completed, store.index.state(of: task) != .inProgress {
                Button {
                    Task { await store.start(task.id) }
                } label: {
                    Label("Start", systemImage: "play.circle")
                }
                .help("Mark this task as in progress")
            }
        }
        ToolbarItem {
            if task.completed {
                Button {
                    Task { await store.reopen(task.id) }
                } label: {
                    Label("Reopen", systemImage: "arrow.uturn.backward.circle")
                }
                .help("Mark this task as not done")
            } else {
                Button {
                    isCompleting = true
                } label: {
                    Label("Mark as Done", systemImage: "checkmark.circle")
                }
                .keyboardShortcut(.return, modifiers: .command)
                .help("Mark as done (⌘↩)")
            }
        }
    }
}

/// The editable fields, so "what changed" is a value comparison.
private struct Draft: Equatable {
    var name: String
    var details: String
    var priority: Int
    /// Empty means no parent.
    var parentID: String

    init(task: DexTask) {
        name = task.name
        details = task.details ?? ""
        priority = task.priority
        parentID = task.parentID ?? ""
    }

    /// Only the fields that actually changed, because `dex edit` overwrites exactly
    /// the flags it is handed and leaves the rest alone.
    func edit(from task: DexTask) -> TaskEdit {
        var edit = TaskEdit()
        if name != task.name { edit.name = name }
        if details != (task.details ?? "") { edit.details = details }
        if priority != task.priority { edit.priority = priority }
        if parentID != (task.parentID ?? ""), !parentID.isEmpty { edit.parentID = parentID }
        return edit
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(0.6)
    }
}

struct StateBadge: View {
    let state: TaskState

    var body: some View {
        Label(state.label, systemImage: state.symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(tint.opacity(0.13), in: Capsule())
    }

    private var tint: Color {
        switch state {
        case .completed: .green
        case .inProgress: .blue
        case .blocked: .orange
        case .ready: .secondary
        }
    }
}

private struct Stamp: View {
    let label: String
    let date: Date

    var body: some View {
        Text("\(label) \(date.formatted(date: .abbreviated, time: .shortened))")
    }
}

private struct CommitView: View {
    let commit: CommitMetadata

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Commit")
            HStack(spacing: 8) {
                Text(String(commit.sha.prefix(8)))
                    .font(.caption.monospaced())
                if let branch = commit.branch {
                    Text(branch).font(.caption).foregroundStyle(.secondary)
                }
                if let url = commit.url, let link = URL(string: url) {
                    Link("Open", destination: link).font(.caption)
                }
            }
        }
    }
}
