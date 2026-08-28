import DexKit
import Foundation
import LinearKit
import Observation

/// What the Linear side of the window has selected.
enum LinearSelection: Hashable {
    case issue(String)
    case project(String)
}

@MainActor
@Observable
final class LinearStore {
    private(set) var issues: [LinearIssue] = []
    private(set) var projects: [LinearProject] = []
    private(set) var account: LinearAccount?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var hasKey = false
    private(set) var keySource: KeySource = .none

    /// Where the API key came from, so Settings can say so.
    enum KeySource: Equatable {
        case none
        /// Entered in Settings and kept in the login keychain.
        case keychain
        /// Borrowed from the `linear` CLI, naming its workspace when known.
        case cli(workspace: String?)
    }
    /// Workflow states per team, fetched the first time an issue from that team is
    /// opened. Teams keep their own sets, so there is no workspace-wide list.
    private(set) var statesByTeam: [String: [LinearState]] = [:]

    var selection: LinearSelection?
    var query = ""

    var includeDone: Bool {
        didSet {
            Preferences.linearIncludeDone = includeDone
            Task { await reload() }
        }
    }

    private let client: LinearClient

    init(client: LinearClient = LinearClient()) {
        self.client = client
        includeDone = Preferences.linearIncludeDone
    }

    /// Drive the store against a stub transport, for tests.
    init(client: LinearClient, hasKey: Bool) {
        self.client = client
        includeDone = false
        self.hasKey = hasKey
        keySource = hasKey ? .keychain : .none
    }

    /// Seed without touching the network, for previews and snapshot tests.
    init(issues: [LinearIssue], projects: [LinearProject] = [], selection: LinearSelection? = nil) {
        client = LinearClient()
        includeDone = false
        self.issues = issues
        self.projects = projects
        self.selection = selection
        hasKey = true
        keySource = .keychain
        account = LinearAccount(
            user: LinearUser(id: "u", name: "Preview User", organizationURLKey: "acme"),
            organizationName: "Acme",
            urlKey: "acme"
        )
    }

    // MARK: - Derived

    var filteredIssues: [LinearIssue] {
        issues.filter { matches($0) }.sorted { a, b in
            if a.priority.sortOrder != b.priority.sortOrder {
                return a.priority.sortOrder < b.priority.sortOrder
            }
            return (a.updatedAt ?? .distantPast) > (b.updatedAt ?? .distantPast)
        }
    }

    /// Completed and cancelled projects are hidden unless "Show done" is on, the
    /// same rule the issue list follows. Paused is not hidden: that work is coming
    /// back.
    var filteredProjects: [LinearProject] {
        projects
            .filter { matches($0) && (includeDone || !$0.isDone) }
            .sorted(by: Self.projectOrder)
    }

    /// Projects grouped by status, active statuses first.
    ///
    /// Grouping uses the workspace's own status name so the sidebar reads the way
    /// Linear does, while the ordering comes from the underlying type. A project
    /// with no status sorts last under its own heading rather than disappearing.
    var projectGroups: [ProjectGroup] {
        let grouped = Dictionary(grouping: filteredProjects) { project in
            project.statusName ?? "No status"
        }
        return grouped
            .map { title, projects in
                ProjectGroup(
                    title: title,
                    statusType: projects.first?.statusType,
                    projects: projects.sorted(by: Self.projectOrder)
                )
            }
            .sorted { a, b in
                let left = a.statusType?.sortOrder ?? Int.max
                let right = b.statusType?.sortOrder ?? Int.max
                if left != right { return left < right }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
    }

    struct ProjectGroup: Identifiable {
        var title: String
        var statusType: LinearProjectStatusType?
        var projects: [LinearProject]
        var id: String { title }
    }

    private static func projectOrder(_ a: LinearProject, _ b: LinearProject) -> Bool {
        let left = a.statusType?.sortOrder ?? Int.max
        let right = b.statusType?.sortOrder ?? Int.max
        if left != right { return left < right }
        return (a.updatedAt ?? .distantPast) > (b.updatedAt ?? .distantPast)
    }

    private func matches(_ issue: LinearIssue) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let haystack = [issue.title, issue.identifier, issue.description ?? "", issue.projectName ?? ""]
            .joined(separator: "\n")
        return haystack.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private func matches(_ project: LinearProject) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let haystack = [project.name, project.description ?? "", project.statusName ?? ""]
            .joined(separator: "\n")
        return haystack.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    var selectedIssue: LinearIssue? {
        guard case let .issue(id) = selection else { return nil }
        return issues.first { $0.id == id }
    }

    var selectedProject: LinearProject? {
        guard case let .project(id) = selection else { return nil }
        return projects.first { $0.id == id }
    }

    var urlKey: String { account?.urlKey ?? "" }

    // MARK: - Lifecycle

    /// Prefer a key the user entered; otherwise borrow the `linear` CLI's, so an
    /// already-authenticated CLI means nothing to set up.
    func bootstrap(searchPath: String) async {
        if let saved = LinearKeychain.load() {
            keySource = .keychain
            hasKey = true
            await client.setAPIKey(saved)
        } else if let cli = LinearCLICredentials.locate(searchPath: searchPath),
                  let token = await cli.token() {
            keySource = .cli(workspace: await cli.workspace())
            hasKey = true
            await client.setAPIKey(token)
        } else {
            keySource = .none
            hasKey = false
            await client.setAPIKey(nil)
            return
        }
        await reload()
    }

    /// Save an explicit key, or clear it and fall back to the CLI.
    func setAPIKey(_ key: String, searchPath: String) async -> Bool {
        do {
            try LinearKeychain.save(key)
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            issues = []
            projects = []
            account = nil
            // Clearing a saved key should return to the CLI's, not to nothing.
            await bootstrap(searchPath: searchPath)
            return true
        }
        keySource = .keychain
        hasKey = true
        await client.setAPIKey(key)
        return await reload()
    }

    /// Reload the account, issues and projects.
    ///
    /// The three calls are reported separately and a failure in one does not discard
    /// the others: the projects filter is the part most likely to be rejected by a
    /// given workspace, and losing the issue list over it would be a poor trade.
    /// The message names the call that failed, so an error is actionable.
    @discardableResult
    func reload() async -> Bool {
        guard hasKey else { return false }
        isLoading = true
        defer { isLoading = false }

        var failures: [String] = []

        do {
            account = try await client.account()
        } catch {
            // Without an account nothing else will work either, so stop here.
            errorMessage = "Signing in to Linear failed.\n\(describe(error))"
            return false
        }

        do {
            issues = try await client.myIssues(includeDone: includeDone)
        } catch {
            failures.append("Loading your issues failed.\n\(describe(error))")
        }

        do {
            projects = try await client.myProjects()
        } catch {
            failures.append("Loading your projects failed.\n\(describe(error))")
        }

        if let selection, resolve(selection) == nil { self.selection = nil }
        errorMessage = failures.isEmpty ? nil : failures.joined(separator: "\n\n")
        return failures.isEmpty
    }

    private func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private func resolve(_ selection: LinearSelection) -> Bool? {
        switch selection {
        case let .issue(id): issues.contains { $0.id == id } ? true : nil
        case let .project(id): projects.contains { $0.id == id } ? true : nil
        }
    }

    // MARK: - Writes

    func apply(_ edit: LinearIssueEdit, to id: String) async {
        await perform {
            guard let updated = try await self.client.update(issue: id, edit) else { return }
            self.replace(updated)
        }
    }

    func apply(_ edit: LinearProjectEdit, to id: String) async {
        await perform {
            guard let updated = try await self.client.update(project: id, edit) else { return }
            if let index = self.projects.firstIndex(where: { $0.id == updated.id }) {
                self.projects[index] = updated
            }
        }
    }

    /// Load a team's workflow states so the status picker can offer them.
    func loadStates(teamID: String) async {
        guard statesByTeam[teamID] == nil else { return }
        guard let states = try? await client.workflowStates(teamID: teamID) else { return }
        statesByTeam[teamID] = states
    }

    private func replace(_ issue: LinearIssue) {
        if let index = issues.firstIndex(where: { $0.id == issue.id }) {
            // An issue edited into a done state drops out of the default list.
            if !includeDone, issue.state.type == .completed || issue.state.type == .canceled {
                issues.remove(at: index)
                if selection == .issue(issue.id) { selection = nil }
            } else {
                issues[index] = issue
            }
        }
    }

    func dismissError() { errorMessage = nil }

    private func perform(_ work: @MainActor () async throws -> Void) async {
        do {
            try await work()
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
