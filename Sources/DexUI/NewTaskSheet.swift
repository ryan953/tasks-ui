import DexKit
import SwiftUI

struct NewTaskSheet: View {
    @Bindable var store: TaskStore
    let parentID: String?

    @Environment(\.dismiss) private var dismiss
    @State private var description = ""
    @State private var context = ""
    @State private var priority = 1
    @State private var parent = ""
    @State private var blockedBy: [String] = []
    @State private var isSaving = false
    @FocusState private var descriptionFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(parentID == nil ? "New Task" : "New Subtask")
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    field("Description") {
                        TextField("What needs doing?", text: $description, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...3)
                            .focused($descriptionFocused)
                    }

                    field("Context") {
                        TextEditor(text: $context)
                            .font(.system(.body, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .padding(7)
                            .frame(height: 150)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(nsColor: .separatorColor))
                            )
                            .overlay(alignment: .topLeading) {
                                if context.isEmpty {
                                    Text("Requirements, approach, done criteria…")
                                        .foregroundStyle(.tertiary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 15)
                                        .allowsHitTesting(false)
                                }
                            }
                    }

                    HStack(alignment: .top, spacing: 24) {
                        field("Priority") {
                            Stepper(value: $priority, in: 1...9) {
                                Text("P\(priority)").monospacedDigit()
                            }
                            .frame(width: 110)
                        }
                        field("Parent") {
                            TaskPicker(store: store, title: "No parent", excluding: [], selection: $parent)
                        }
                    }

                    field("Blocked by") {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                AddRelationButton(store: store, excluding: Set(blockedBy)) { id in
                                    blockedBy.append(id)
                                }
                                Text(blockedBy.isEmpty ? "Nothing yet" : "\(blockedBy.count) selected")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(store.index.tasks(ids: blockedBy)) { blocker in
                                HStack(spacing: 7) {
                                    Text(blocker.description).lineLimit(1)
                                    Text(blocker.id)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.tertiary)
                                    Spacer()
                                    Button {
                                        blockedBy.removeAll { $0 == blocker.id }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                }
                .padding(20)
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.escape)
                Button("Create Task") { create() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid || isSaving)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 560, height: 620)
        .onAppear {
            parent = parentID ?? ""
            descriptionFocused = true
        }
    }

    private var isValid: Bool {
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(label)
            content()
        }
    }

    private func create() {
        guard isValid else { return }
        isSaving = true
        let task = NewTask(
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            // dex requires a context; an empty string is accepted and keeps the
            // field optional for the user.
            context: context,
            priority: priority,
            parentID: parent.isEmpty ? nil : parent,
            blockedBy: blockedBy
        )
        Task {
            let id = await store.create(task)
            isSaving = false
            if id != nil { dismiss() }
        }
    }
}

/// Asks for the result text `dex complete` records against the task.
struct CompleteSheet: View {
    let task: DexTask
    let onComplete: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var result = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Mark as Done")
                .font(.title3.weight(.semibold))
            Text(task.description)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Result")
                TextEditor(text: $result)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(7)
                    .frame(height: 140)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor))
                    )
                    .focused($focused)
                    .overlay(alignment: .topLeading) {
                        if result.isEmpty {
                            Text("What was done, decisions taken, follow-ups…")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 15)
                                .allowsHitTesting(false)
                        }
                    }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.escape)
                Button("Mark as Done") {
                    onComplete(result.isEmpty ? "Done" : result)
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear { focused = true }
    }
}
