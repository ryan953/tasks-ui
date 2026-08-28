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
