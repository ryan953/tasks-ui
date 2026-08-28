import DexKit
import LinearKit
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel
    @Binding var isCreating: Bool

    /// Pre-fills the parent when the sheet is opened from "Add Subtask".
    @State private var newTaskParent: String?

    private var dex: TaskStore { model.dex }
    private var linear: LinearStore { model.linear }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                Picker("Source", selection: $model.source) {
                    ForEach(Source.allCases) { source in
                        Label(source.label, systemImage: source.symbol).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

                Divider()

                switch model.source {
                case .dex:
                    SidebarView(store: dex, isCreating: $isCreating, newTaskParent: $newTaskParent)
                case .linear:
                    LinearSidebarView(store: linear)
                }
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 330, max: 460)
        } detail: {
            detail
                .frame(minWidth: 420)
        }
        .sheet(isPresented: $isCreating) {
            NewTaskSheet(store: dex, parentID: newTaskParent)
        }
        .onChange(of: isCreating) { _, presented in
            if !presented { newTaskParent = nil }
        }
        .alert(
            "dex reported a problem",
            isPresented: Binding(
                get: { dex.errorMessage != nil },
                set: { if !$0 { dex.dismissError() } }
            )
        ) {
            Button("OK", role: .cancel) { dex.dismissError() }
        } message: {
            Text(dex.errorMessage ?? "")
        }
        .alert(
            "Linear reported a problem",
            isPresented: Binding(
                get: { linear.errorMessage != nil },
                set: { if !$0 { linear.dismissError() } }
            )
        ) {
            Button("OK", role: .cancel) { linear.dismissError() }
        } message: {
            Text(linear.errorMessage ?? "")
        }
        .alert(
            "Could not open that link",
            isPresented: Binding(
                get: { model.routeFailure != nil },
                set: { if !$0 { model.dismissRouteFailure() } }
            )
        ) {
            Button("OK", role: .cancel) { model.dismissRouteFailure() }
        } message: {
            Text(model.routeFailure ?? "")
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.source {
        case .dex:
            if let task = dex.selectedTask {
                TaskDetailView(store: dex, task: task, newTaskParent: $newTaskParent, isCreating: $isCreating)
                    // Rebuild the editing state when a different task is picked, so
                    // a half-typed edit cannot leak onto the next task.
                    .id(task.id)
            } else {
                DexEmptyDetail(store: dex, isCreating: $isCreating)
            }
        case .linear:
            if let issue = linear.selectedIssue {
                LinearIssueDetailView(store: linear, issue: issue).id(issue.id)
            } else if let project = linear.selectedProject {
                LinearProjectDetailView(store: linear, project: project).id(project.id)
            } else {
                LinearEmptyDetail(store: linear)
            }
        }
    }
}

/// Shown when no dex task is selected, and when dex itself cannot be used.
struct DexEmptyDetail: View {
    let store: TaskStore
    @Binding var isCreating: Bool

    var body: some View {
        VStack(spacing: 14) {
            if store.isBootstrapping {
                ProgressView()
            } else if store.cliTooOld {
                Image(systemName: "arrow.up.circle")
                    .font(.system(size: 34))
                    .foregroundStyle(.orange)
                Text("dex is out of date")
                    .font(.title3.weight(.medium))
                Text("This app speaks the dex 0.16 command line. Upgrade with:")
                    .foregroundStyle(.secondary)
                Text("npm install -g @zeeg/dex")
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
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

struct LinearEmptyDetail: View {
    let store: LinearStore

    var body: some View {
        VStack(spacing: 14) {
            if !store.hasKey {
                Image(systemName: "link")
                    .font(.system(size: 34))
                    .foregroundStyle(.tertiary)
                Text("Connect Linear")
                    .font(.title3.weight(.medium))
                Text("Add a personal API key in Settings to see what is assigned to you.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                SettingsLink { Text("Open Settings…") }
            } else {
                Image(systemName: "circle.grid.2x2")
                    .font(.system(size: 38))
                    .foregroundStyle(.tertiary)
                Text("Select an issue or project")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                if let url = LinearLinks.myIssues(urlKey: store.urlKey) {
                    Link("See them all in Linear", destination: url)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
