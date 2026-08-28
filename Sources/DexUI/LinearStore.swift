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

    private let client = LinearClient()

    init() {
        includeDone = Preferences.linearIncludeDone
    }

    /// Seed without touching the network, for previews and snapshot tests.
    init(issues: [LinearIssue], projects: [LinearProject] = [], selection: LinearSelection? = nil) {
        includeDone = false
        self.issues = issues
        self.projects = projects
        self.selection = selection
        hasKey = true
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

    var filteredProjects: [LinearProject] {
        projects
            .filter { matches($0) }
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
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

    func bootstrap() async {
        let key = LinearKeychain.load()
        hasKey = key != nil
        await client.setAPIKey(key)
        guard hasKey else { return }
        await reload()
    }

    func setAPIKey(_ key: String) async -> Bool {
        do {
            try LinearKeychain.save(key)
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
        await client.setAPIKey(key.isEmpty ? nil : key)
        hasKey = !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasKey else {
            issues = []
            projects = []
            account = nil
            return true
        }
        return await reload()
    }

    @discardableResult
    func reload() async -> Bool {
        guard hasKey else { return false }
        isLoading = true
        defer { isLoading = false }
        do {
            account = try await client.account()
            // Issues and projects are independent; fetch both before reporting.
            async let fetchedIssues = client.myIssues(includeDone: includeDone)
            async let fetchedProjects = client.myProjects()
            issues = try await fetchedIssues
            projects = try await fetchedProjects
            errorMessage = nil
            if let selection, resolve(selection) == nil { self.selection = nil }
            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
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
