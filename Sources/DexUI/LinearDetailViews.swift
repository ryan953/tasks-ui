import LinearKit
import SwiftUI

struct LinearIssueDetailView: View {
    @Bindable var store: LinearStore
    let issue: LinearIssue

    @State private var draft: IssueDraft
    @FocusState private var focus: Field?

    private enum Field { case title, description }

    init(store: LinearStore, issue: LinearIssue) {
        self.store = store
        self.issue = issue
        _draft = State(initialValue: IssueDraft(issue: issue))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                Divider()
                descriptionEditor
                controls
                metadata
            }
            .padding(22)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background)
        .safeAreaInset(edge: .bottom) { if isDirty { saveBar } }
        .toolbar { toolbarItems }
        .task(id: issue.team?.id) {
            if let teamID = issue.team?.id { await store.loadStates(teamID: teamID) }
        }
        .onChange(of: issue) { _, updated in
            if !isDirty { draft = IssueDraft(issue: updated) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Issue title", text: $draft.title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.title2.weight(.semibold))
                .lineLimit(1...4)
                .focused($focus, equals: .title)

            HStack(spacing: 8) {
                Label(issue.state.name, systemImage: issue.state.type.symbol)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(StateTint.color(for: issue.state.type))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(StateTint.color(for: issue.state.type).opacity(0.13), in: Capsule())

                Text(issue.identifier)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                if let team = issue.team {
                    Text(team.name).font(.caption).foregroundStyle(.secondary)
                }
                if let project = issue.projectName {
                    Label(project, systemImage: "square.stack.3d.up")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var descriptionEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Description")
            TextEditor(text: $draft.description)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 160)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(nsColor: .separatorColor)))
                .focused($focus, equals: .description)
                .overlay(alignment: .topLeading) {
                    if draft.description.isEmpty {
                        Text("Markdown, the same as Linear")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    private var controls: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Priority")
                Picker("Priority", selection: $draft.priority) {
                    ForEach(LinearPriority.allCases) { priority in
                        Label(priority.label, systemImage: priority.symbol).tag(priority)
                    }
                }
                .labelsHidden()
                .frame(width: 170)
            }

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Status")
                if states.isEmpty {
                    // Until the team's states arrive there is nothing truthful to
                    // offer, so show the current one rather than an empty menu.
                    Text(issue.state.name)
                        .foregroundStyle(.secondary)
                        .frame(height: 22)
                } else {
                    Picker("Status", selection: $draft.stateID) {
                        ForEach(states) { state in
                            Text(state.name).tag(state.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
            }
            Spacer()
        }
    }

    private var metadata: some View {
        HStack(spacing: 16) {
            if let assignee = issue.assigneeName {
                Label(assignee, systemImage: "person")
            }
            if let updated = issue.updatedAt {
                Text("Updated \(updated.formatted(date: .abbreviated, time: .shortened))")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var states: [LinearState] {
        guard let teamID = issue.team?.id else { return [] }
        return store.statesByTeam[teamID] ?? []
    }

    private var isDirty: Bool { draft != IssueDraft(issue: issue) }

    private var saveBar: some View {
        HStack {
            Text("Unsaved changes").font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button("Revert") { draft = IssueDraft(issue: issue) }
            Button("Save to Linear") { save() }
                .keyboardShortcut("s")
                .buttonStyle(.borderedProminent)
                .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func save() {
        let edit = draft.edit(from: issue)
        guard !edit.isEmpty else { return }
        focus = nil
        Task { await store.apply(edit, to: issue.id) }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem {
            // Everything the app deliberately does not model is one click away.
            if let url = URL(string: issue.url) {
                Link(destination: url) {
                    Label("Open in Linear", systemImage: "arrow.up.forward.square")
                }
                .help("Open \(issue.identifier) on the Linear website")
            }
        }
    }
}

private struct IssueDraft: Equatable {
    var title: String
    var description: String
    var priority: LinearPriority
    var stateID: String

    init(issue: LinearIssue) {
        title = issue.title
        description = issue.description ?? ""
        priority = issue.priority
        stateID = issue.state.id
    }

    /// Only what changed, so an untouched field cannot be overwritten by a stale
    /// value from the form.
    func edit(from issue: LinearIssue) -> LinearIssueEdit {
        var edit = LinearIssueEdit()
        if title != issue.title { edit.title = title }
        if description != (issue.description ?? "") { edit.description = description }
        if priority != issue.priority { edit.priority = priority }
        if stateID != issue.state.id { edit.stateID = stateID }
        return edit
    }
}

struct LinearProjectDetailView: View {
    @Bindable var store: LinearStore
    let project: LinearProject

    @State private var draft: ProjectDraft

    init(store: LinearStore, project: LinearProject) {
        self.store = store
        self.project = project
        _draft = State(initialValue: ProjectDraft(project: project))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Project name", text: $draft.name, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.title2.weight(.semibold))
                        .lineLimit(1...3)

                    HStack(spacing: 8) {
                        if let status = project.statusName {
                            Text(status)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(.quaternary.opacity(0.6), in: Capsule())
                        }
                        if let lead = project.leadName {
                            Label(lead, systemImage: "person").font(.caption).foregroundStyle(.secondary)
                        }
                        if let progress = project.progress {
                            Text("\(Int(progress * 100))% complete")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("Description")
                    TextEditor(text: $draft.description)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 160)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(nsColor: .separatorColor)))
                }

                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("Target date")
                    TextField("YYYY-MM-DD", text: $draft.targetDate)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                }

                // Status, members, milestones and updates stay in Linear; the app
                // covers the fields worth editing in passing and links out for the
                // rest.
                Text("Status, milestones and members are edited in Linear.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(22)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background)
        .safeAreaInset(edge: .bottom) { if isDirty { saveBar } }
        .toolbar {
            ToolbarItem {
                if let url = URL(string: project.url) {
                    Link(destination: url) {
                        Label("Open in Linear", systemImage: "arrow.up.forward.square")
                    }
                    .help("Open this project on the Linear website")
                }
            }
        }
        .onChange(of: project) { _, updated in
            if !isDirty { draft = ProjectDraft(project: updated) }
        }
    }

    private var isDirty: Bool { draft != ProjectDraft(project: project) }

    private var saveBar: some View {
        HStack {
            Text("Unsaved changes").font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button("Revert") { draft = ProjectDraft(project: project) }
            Button("Save to Linear") {
                let edit = draft.edit(from: project)
                guard !edit.isEmpty else { return }
                Task { await store.apply(edit, to: project.id) }
            }
            .keyboardShortcut("s")
            .buttonStyle(.borderedProminent)
            .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

private struct ProjectDraft: Equatable {
    var name: String
    var description: String
    var targetDate: String

    init(project: LinearProject) {
        name = project.name
        description = project.description ?? ""
        targetDate = project.targetDate ?? ""
    }

    func edit(from project: LinearProject) -> LinearProjectEdit {
        var edit = LinearProjectEdit()
        if name != project.name { edit.name = name }
        if description != (project.description ?? "") { edit.description = description }
        if targetDate != (project.targetDate ?? "") { edit.targetDate = targetDate }
        return edit
    }
}
