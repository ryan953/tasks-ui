import DexKit
import SwiftUI

/// Dependencies and hierarchy: what blocks this task, what it blocks, its subtasks.
///
/// Blocker changes apply immediately rather than joining the Save/Revert draft —
/// adding a link is a single discrete act, and `dex` mirrors it onto the other task,
/// so batching it with text edits would hide that side effect.
struct RelationsView: View {
    @Bindable var store: TaskStore
    let task: DexTask

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            blockedBySection
            if !task.blocks.isEmpty { blocksSection }
            if !task.children.isEmpty { subtasksSection }
        }
    }

    private var blockedBySection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                SectionLabel("Blocked by")
                AddRelationButton(
                    store: store,
                    // Nothing already linked, and nothing that would close a loop.
                    excluding: store.index.ineligibleRelations(for: task).union(task.blockedBy)
                ) { id in
                    Task { await store.apply(TaskEdit(addBlockers: [id]), to: task.id) }
                }
                Spacer()
            }
            if task.blockedBy.isEmpty {
                Text("Nothing is blocking this task.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.index.tasks(ids: task.blockedBy)) { blocker in
                    RelationRow(store: store, task: blocker) {
                        Button {
                            Task { await store.apply(TaskEdit(removeBlockers: [blocker.id]), to: task.id) }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove this dependency")
                    }
                }
            }
        }
    }

    private var blocksSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel("Blocks")
            ForEach(store.index.tasks(ids: task.blocks)) { blocked in
                RelationRow(store: store, task: blocked) {
                    // Removed from the other task, where the dependency was declared.
                    Button {
                        Task { await store.apply(TaskEdit(removeBlockers: [task.id]), to: blocked.id) }
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Stop blocking this task")
                }
            }
        }
    }

    private var subtasksSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel("Subtasks")
            ForEach(store.index.tasks(ids: task.children)) { child in
                RelationRow(store: store, task: child) { EmptyView() }
            }
        }
    }
}

/// One linked task. Clicking it moves the selection there.
private struct RelationRow<Trailing: View>: View {
    static func tint(for state: TaskState) -> Color {
        switch state {
        case .completed: .green
        case .inProgress: .blue
        case .blocked: .orange
        case .ready: .secondary
        }
    }

    let store: TaskStore
    let task: DexTask
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            Button {
                store.selection = task.id
            } label: {
                HStack(spacing: 7) {
                    let state = store.index.state(of: task)
                    Image(systemName: state.symbol)
                        .foregroundStyle(Self.tint(for: state))
                        .font(.caption)
                    Text(task.name)
                        .lineLimit(1)
                        .strikethrough(task.completed, color: .secondary)
                    Text(task.id)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Go to \(task.id)")

            trailing
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// "+" that opens a searchable task list.
struct AddRelationButton: View {
    let store: TaskStore
    let excluding: Set<String>
    let onPick: (String) -> Void

    @State private var isShowing = false

    var body: some View {
        Button {
            isShowing = true
        } label: {
            Image(systemName: "plus.circle")
        }
        .buttonStyle(.plain)
        .help("Add a blocking task")
        .popover(isPresented: $isShowing, arrowEdge: .bottom) {
            TaskSearchList(store: store, excluding: excluding) { id in
                isShowing = false
                onPick(id)
            }
        }
    }
}

/// Choose a parent, or clear it.
///
/// A popover with its own search field rather than a plain `Picker`: a real store
/// holds hundreds of tasks, which makes a pop-up menu unusable.
struct TaskPicker: View {
    let store: TaskStore
    let title: String
    let excluding: Set<String>
    @Binding var selection: String

    @State private var isShowing = false

    var body: some View {
        Button {
            isShowing = true
        } label: {
            HStack(spacing: 6) {
                Text(label)
                    .lineLimit(1)
                    .foregroundStyle(selection.isEmpty ? .secondary : .primary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 200, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .popover(isPresented: $isShowing, arrowEdge: .bottom) {
            TaskSearchList(
                store: store,
                excluding: excluding,
                clearTitle: title,
                onClear: {
                    selection = ""
                    isShowing = false
                }
            ) { id in
                selection = id
                isShowing = false
            }
        }
    }

    private var label: String {
        guard !selection.isEmpty else { return title }
        return store.index[selection]?.name ?? selection
    }
}

/// Searchable, scrollable task list used by the pickers.
struct TaskSearchList: View {
    let store: TaskStore
    let excluding: Set<String>
    var clearTitle: String?
    var onClear: (() -> Void)?
    let onPick: (String) -> Void

    @State private var query = ""

    private var matches: [DexTask] {
        let index = store.index
        return
            index
            .sorted(index.tasks.filter { !excluding.contains($0.id) }, by: .priority)
            .filter { index.matches($0, query: query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search tasks", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(9)

            Divider()

            if matches.isEmpty {
                Text("No tasks available")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(20)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if let clearTitle, let onClear {
                            PickerRow(title: clearTitle, subtitle: nil, muted: true, action: onClear)
                            Divider()
                        }
                        ForEach(matches) { task in
                            PickerRow(
                                title: task.name,
                                subtitle: "\(task.id) · P\(task.priority)",
                                muted: false
                            ) {
                                onPick(task.id)
                            }
                        }
                    }
                }
                .frame(height: 260)
            }
        }
        .frame(width: 340)
    }
}

private struct PickerRow: View {
    let title: String
    let subtitle: String?
    let muted: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .lineLimit(1)
                    .foregroundStyle(muted ? .secondary : .primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(isHovering ? Color.accentColor.opacity(0.15) : .clear)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
