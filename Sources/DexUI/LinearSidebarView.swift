import LinearKit
import SwiftUI

struct LinearSidebarView: View {
    @Bindable var store: LinearStore

    var body: some View {
        List(selection: $store.selection) {
            if !store.filteredIssues.isEmpty {
                Section("Assigned to me") {
                    ForEach(store.filteredIssues) { issue in
                        LinearIssueRow(issue: issue)
                            .tag(LinearSelection.issue(issue.id))
                    }
                }
            }
            if !store.filteredProjects.isEmpty {
                Section("My projects") {
                    ForEach(store.filteredProjects) { project in
                        LinearProjectRow(project: project)
                            .tag(LinearSelection.project(project.id))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $store.query, placement: .sidebar, prompt: "Search Linear")
        .overlay { emptyOverlay }
        .safeAreaInset(edge: .bottom) { statusBar }
        .toolbar { toolbarItems }
    }

    @ViewBuilder
    private var emptyOverlay: some View {
        if !store.hasKey {
            ContentUnavailableView {
                Label("Linear is not connected", systemImage: "link")
            } description: {
                Text("Add a personal API key in Settings to see the issues and projects assigned to you.")
            } actions: {
                SettingsLink { Text("Open Settings…") }
            }
        } else if store.filteredIssues.isEmpty, store.filteredProjects.isEmpty, !store.isLoading {
            ContentUnavailableView {
                Label(store.query.isEmpty ? "Nothing assigned" : "No matches", systemImage: "tray")
            } description: {
                Text(store.query.isEmpty
                    ? "Nothing in Linear is assigned to you right now."
                    : "Nothing matches “\(store.query)”.")
            } actions: {
                if !store.query.isEmpty {
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
            Text("\(store.filteredIssues.count) \(store.filteredIssues.count == 1 ? "issue" : "issues") · \(store.filteredProjects.count) \(store.filteredProjects.count == 1 ? "project" : "projects")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Toggle("Show done", isOn: $store.includeDone)
                .toggleStyle(.checkbox)
                .font(.caption)
                .help("Include completed and cancelled issues")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem {
            // The bulk views live on the website; the app does not try to clone them.
            Menu {
                if let url = LinearLinks.myIssues(urlKey: store.urlKey) {
                    Link("My Issues in Linear", destination: url)
                }
                if let url = LinearLinks.createdByMe(urlKey: store.urlKey) {
                    Link("Created by Me", destination: url)
                }
                if let url = LinearLinks.projects(urlKey: store.urlKey) {
                    Link("All Projects", destination: url)
                }
                if !store.query.isEmpty,
                   let url = LinearLinks.search(urlKey: store.urlKey, query: store.query) {
                    Divider()
                    Link("Search “\(store.query)” in Linear", destination: url)
                }
            } label: {
                Label("Open in Linear", systemImage: "arrow.up.forward.square")
            }
            .disabled(store.urlKey.isEmpty)
            .help("Open a bulk view on the Linear website")
        }
        ToolbarItem {
            Button {
                Task { await store.reload() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(!store.hasKey)
            .help("Reload from Linear (⌘R)")
        }
    }
}

struct LinearIssueRow: View {
    let issue: LinearIssue

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: issue.state.type.symbol)
                .foregroundStyle(StateTint.color(for: issue.state.type))
                .font(.system(size: 12))
                .help(issue.state.name)

            VStack(alignment: .leading, spacing: 1) {
                Text(issue.title)
                    .lineLimit(1)
                    .strikethrough(issue.state.type == .canceled, color: .secondary)
                Text(issue.identifier)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 4)

            if issue.priority != .none {
                Image(systemName: issue.priority.symbol)
                    .font(.caption2)
                    .foregroundStyle(PriorityTint.color(for: issue.priority))
                    .help(issue.priority.label)
            }
        }
        .padding(.vertical, 1)
    }
}

struct LinearProjectRow: View {
    let project: LinearProject

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "square.stack.3d.up")
                .foregroundStyle(.purple)
                .font(.system(size: 12))
            VStack(alignment: .leading, spacing: 1) {
                Text(project.name).lineLimit(1)
                if let status = project.statusName {
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 4)
            if let progress = project.progress {
                Text("\(Int(progress * 100))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 1)
    }
}

enum StateTint {
    static func color(for type: LinearStateType) -> Color {
        switch type {
        case .backlog: .secondary
        case .unstarted: .secondary
        case .started: .blue
        case .completed: .green
        case .canceled: .red
        }
    }
}

enum PriorityTint {
    static func color(for priority: LinearPriority) -> Color {
        switch priority {
        case .urgent: .red
        case .high: .orange
        case .medium: .yellow
        case .low: .secondary
        case .none: .secondary
        }
    }
}
