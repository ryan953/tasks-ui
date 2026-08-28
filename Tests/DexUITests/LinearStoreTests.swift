import Foundation
import LinearKit
import Testing
@testable import DexUI

/// Minimal stand-in so the store can be driven without a workspace.
private actor ScriptedTransport: LinearTransport {
    private var byOperation: [String: String]

    init(byOperation: [String: String]) {
        self.byOperation = byOperation
    }

    func send(body: Data, apiKey: String) async throws -> Data {
        let sent = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        let query = sent["query"] as? String ?? ""
        for (operation, response) in byOperation where query.contains(operation) {
            return Data(response.utf8)
        }
        return Data(#"{"data":{}}"#.utf8)
    }
}

private let accountJSON = """
{"data":{"viewer":{"id":"u","name":"Sam Rivers"},"organization":{"urlKey":"acme","name":"Acme"}}}
"""

private let issuesJSON = """
{"data":{"issues":{"pageInfo":{"hasNextPage":false},"nodes":[
  {"id":"i1","identifier":"ABC-1","title":"Still here","priority":0,"url":"u",
   "state":{"id":"s","name":"Todo","type":"unstarted"}}
]}}}
"""

@MainActor
@Suite("Linear store")
struct LinearStoreTests {
    /// The projects filter is the part most likely to be rejected by a workspace.
    /// Losing the issue list over it would be a poor trade.
    @Test func aProjectFailureDoesNotDiscardIssues() async {
        let transport = ScriptedTransport(byOperation: [
            "query Viewer": accountJSON,
            "query MyIssues": issuesJSON,
            "query MyProjects": #"{"errors":[{"message":"Invalid filter: members"}]}"#,
        ])
        let store = LinearStore(client: LinearClient(transport: transport, apiKey: "k"), hasKey: true)

        let ok = await store.reload()

        #expect(!ok)
        #expect(store.issues.map(\.identifier) == ["ABC-1"])
        // The message must say which call failed, not just that something did.
        #expect(store.errorMessage?.contains("projects") == true)
        #expect(store.account?.organizationName == "Acme")
    }

    /// A bad key is not a per-query problem; say so once and stop.
    @Test func aSignInFailureStopsEarly() async {
        let transport = ScriptedTransport(byOperation: [
            "query Viewer": #"{"errors":[{"message":"Authentication required"}]}"#,
        ])
        let store = LinearStore(client: LinearClient(transport: transport, apiKey: "bad"), hasKey: true)

        #expect(await store.reload() == false)
        #expect(store.errorMessage?.contains("Signing in") == true)
        #expect(store.issues.isEmpty)
    }

    @Test func aGoodReloadClearsTheError() async {
        let transport = ScriptedTransport(byOperation: [
            "query Viewer": accountJSON,
            "query MyIssues": issuesJSON,
            "query MyProjects": #"{"data":{"projects":{"nodes":[]}}}"#,
        ])
        let store = LinearStore(client: LinearClient(transport: transport, apiKey: "k"), hasKey: true)

        #expect(await store.reload())
        #expect(store.errorMessage == nil)
        #expect(store.issues.count == 1)
    }

    @Test func doesNothingWithoutAKey() async {
        let store = LinearStore(client: LinearClient(transport: ScriptedTransport(byOperation: [:])), hasKey: false)
        #expect(await store.reload() == false)
    }

    /// Sorting puts urgent work first and "no priority" last, not the other way
    /// round — Linear encodes "none" as 0.
    @Test func sortsUrgentFirstAndNoPriorityLast() {
        let store = LinearStore(issues: [
            LinearIssue(id: "a", identifier: "A-1", title: "None", priority: .none,
                        state: LinearState(id: "s", name: "Todo", type: .unstarted), url: "u"),
            LinearIssue(id: "b", identifier: "A-2", title: "Urgent", priority: .urgent,
                        state: LinearState(id: "s", name: "Todo", type: .unstarted), url: "u"),
            LinearIssue(id: "c", identifier: "A-3", title: "Low", priority: .low,
                        state: LinearState(id: "s", name: "Todo", type: .unstarted), url: "u"),
        ])
        #expect(store.filteredIssues.map(\.title) == ["Urgent", "Low", "None"])
    }

    // MARK: - Projects

    private static func projects() -> [LinearProject] {
        func project(_ id: String, _ name: String, _ status: String?, _ type: LinearProjectStatusType?) -> LinearProject {
            LinearProject(id: id, name: name, statusName: status, statusType: type, url: "https://linear.app/a/project/\(id)")
        }
        return [
            project("p1", "Shipped thing", "Completed", .completed),
            project("p2", "Active thing", "In Progress", .started),
            project("p3", "Dropped thing", "Cancelled", .canceled),
            project("p4", "Next thing", "Planned", .planned),
            project("p5", "Resting thing", "Paused", .paused),
            project("p6", "Unlabelled thing", nil, nil),
        ]
    }

    /// Finished projects should not pad the list any more than finished issues do.
    @Test func hidesDoneProjectsUnlessAsked() {
        let store = LinearStore(issues: [], projects: Self.projects())
        store.includeDone = false
        let visible = store.filteredProjects.map(\.name)
        #expect(!visible.contains("Shipped thing"))
        #expect(!visible.contains("Dropped thing"))
        // Paused work is coming back, so it stays.
        #expect(visible.contains("Resting thing"))
        #expect(visible.contains("Active thing"))
    }

    @Test func showsDoneProjectsWhenAsked() {
        let store = LinearStore(issues: [], projects: Self.projects())
        store.includeDone = true
        let visible = store.filteredProjects.map(\.name)
        #expect(visible.contains("Shipped thing"))
        #expect(visible.contains("Dropped thing"))
    }

    /// A project with no status must not vanish just because it cannot be grouped.
    @Test func keepsProjectsWithNoStatus() {
        let store = LinearStore(issues: [], projects: Self.projects())
        store.includeDone = false
        #expect(store.filteredProjects.map(\.name).contains("Unlabelled thing"))
    }

    @Test func groupsProjectsByStatusWithActiveWorkFirst() {
        let store = LinearStore(issues: [], projects: Self.projects())
        store.includeDone = false
        #expect(store.projectGroups.map(\.title) == ["In Progress", "Planned", "Paused", "No status"])
        #expect(store.projectGroups.first?.projects.map(\.name) == ["Active thing"])
    }

    @Test func putsFinishedGroupsLastWhenShown() {
        let store = LinearStore(issues: [], projects: Self.projects())
        store.includeDone = true
        let titles = store.projectGroups.map(\.title)
        #expect(titles.first == "In Progress")
        #expect(titles.suffix(3) == ["Completed", "Cancelled", "No status"])
    }

    /// Grouping uses the workspace's own status names, so two names sharing a type
    /// stay apart rather than being merged into one heading.
    @Test func keepsDistinctStatusNamesApart() {
        let store = LinearStore(issues: [], projects: [
            LinearProject(id: "a", name: "One", statusName: "In Review", statusType: .started, url: "u"),
            LinearProject(id: "b", name: "Two", statusName: "Building", statusType: .started, url: "u"),
        ])
        #expect(store.projectGroups.map(\.title) == ["Building", "In Review"])
    }

    @Test func searchStillNarrowsTheGroups() {
        let store = LinearStore(issues: [], projects: Self.projects())
        store.query = "Active"
        #expect(store.projectGroups.map(\.title) == ["In Progress"])
    }

    @Test func searchesTitleIdentifierAndBody() {
        let store = LinearStore(issues: SnapshotTests.linearIssues(), projects: SnapshotTests.linearProjects())
        store.query = "ABC-31"
        #expect(store.filteredIssues.map(\.identifier) == ["ABC-31"])
        store.query = "keychain"
        #expect(store.filteredIssues.map(\.identifier) == ["DEV-4"])
        store.query = "launch"
        #expect(store.filteredProjects.map(\.name) == ["Launch"])
    }
}
