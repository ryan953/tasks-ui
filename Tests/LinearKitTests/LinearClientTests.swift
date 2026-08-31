import Foundation
import Testing

@testable import LinearKit

/// Answers with canned JSON and records what it was asked.
///
/// Fixtures here are invented. Nothing from a real workspace is committed.
actor StubTransport: LinearTransport {
    private var responses: [String]
    private var requests: [[String: Any]] = []

    init(responses: [String]) {
        self.responses = responses
    }

    init(response: String) {
        responses = [response]
    }

    func send(body: Data, apiKey: String) async throws -> Data {
        let sent = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        requests.append(sent)
        guard !responses.isEmpty else { return Data("{\"data\":{}}".utf8) }
        return Data(responses.removeFirst().utf8)
    }

    /// Accessors return only Sendable values, so results can leave the actor.
    func requestCount() -> Int { requests.count }

    func lastVariable(_ name: String) -> String? {
        variables().flatMap { $0[name] as? String }
    }

    func lastFilter() -> [String: Any]? {
        variables()?["filter"] as? [String: Any]
    }

    func lastFilterHasKey(_ key: String) -> Bool {
        lastFilter()?[key] != nil
    }

    func lastStateExclusions() -> [String]? {
        let state = lastFilter()?["state"] as? [String: Any]
        return (state?["type"] as? [String: Any])?["nin"] as? [String]
    }

    func lastInputString(_ key: String) -> String? {
        input()?[key] as? String
    }

    func lastInputInt(_ key: String) -> Int? {
        (input()?[key] as? NSNumber)?.intValue
    }

    func lastInputHasKey(_ key: String) -> Bool {
        input()?[key] != nil
    }

    private func variables() -> [String: Any]? {
        requests.last?["variables"] as? [String: Any]
    }

    private func input() -> [String: Any]? {
        variables()?["input"] as? [String: Any]
    }
}

@Suite("Linear client")
struct LinearClientTests {
    static let issueJSON = """
        {"data":{"issues":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
          {"id":"uuid-1","identifier":"ABC-12","title":"Wire up the sidebar",
           "description":"Body text","priority":2,
           "url":"https://linear.app/acme/issue/ABC-12/wire-up-the-sidebar",
           "updatedAt":"2026-08-20T10:00:00.000Z",
           "state":{"id":"state-1","name":"In Progress","type":"started","color":"#f2c94c"},
           "team":{"id":"team-1","key":"ABC","name":"Acme"},
           "project":{"id":"proj-1","name":"Launch"},
           "assignee":{"name":"Sam Rivers"}}
        ]}}}
        """

    @Test func decodesAnIssue() async throws {
        let transport = StubTransport(response: Self.issueJSON)
        let client = LinearClient(transport: transport, apiKey: "lin_api_test")
        let issues = try await client.myIssues()

        let issue = try #require(issues.first)
        #expect(issue.identifier == "ABC-12")
        #expect(issue.title == "Wire up the sidebar")
        #expect(issue.priority == .high)
        #expect(issue.state.type == .started)
        #expect(issue.team?.key == "ABC")
        #expect(issue.projectName == "Launch")
        #expect(issue.url.hasPrefix("https://linear.app/acme/issue/ABC-12"))
        #expect(issue.updatedAt != nil)
    }

    /// The default list must not be padded with work that is already finished.
    @Test func excludesDoneWorkByDefault() async throws {
        let transport = StubTransport(response: Self.issueJSON)
        let client = LinearClient(transport: transport, apiKey: "k")
        _ = try await client.myIssues(includeDone: false)

        #expect(await transport.lastStateExclusions() == ["completed", "canceled"])
        #expect(await transport.lastFilterHasKey("assignee"))
    }

    @Test func includesDoneWorkWhenAsked() async throws {
        let transport = StubTransport(response: Self.issueJSON)
        let client = LinearClient(transport: transport, apiKey: "k")
        _ = try await client.myIssues(includeDone: true)

        #expect(!(await transport.lastFilterHasKey("state")))
    }

    /// A half-loaded list looks exactly like a short one, so paging must continue
    /// while Linear says there is more.
    @Test func followsPagination() async throws {
        let firstPage = """
            {"data":{"issues":{"pageInfo":{"hasNextPage":true,"endCursor":"cursor-1"},"nodes":[
              {"id":"u1","identifier":"ABC-1","title":"One","priority":0,"url":"https://linear.app/a/issue/ABC-1",
               "state":{"id":"s","name":"Todo","type":"unstarted"}}
            ]}}}
            """
        let secondPage = """
            {"data":{"issues":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
              {"id":"u2","identifier":"ABC-2","title":"Two","priority":0,"url":"https://linear.app/a/issue/ABC-2",
               "state":{"id":"s","name":"Todo","type":"unstarted"}}
            ]}}}
            """
        let transport = StubTransport(responses: [firstPage, secondPage])
        let client = LinearClient(transport: transport, apiKey: "k")
        let issues = try await client.myIssues()

        #expect(issues.map(\.identifier) == ["ABC-1", "ABC-2"])
        #expect(await transport.lastVariable("after") == "cursor-1")
    }

    @Test func stopsPagingAtTheLimit() async throws {
        let endless = """
            {"data":{"issues":{"pageInfo":{"hasNextPage":true,"endCursor":"c"},"nodes":[
              {"id":"u","identifier":"ABC-9","title":"Loop","priority":0,"url":"u",
               "state":{"id":"s","name":"Todo","type":"unstarted"}}
            ]}}}
            """
        let transport = StubTransport(responses: Array(repeating: endless, count: 10))
        let client = LinearClient(transport: transport, apiKey: "k")
        let issues = try await client.myIssues(pageLimit: 3)
        #expect(issues.count == 3)
    }

    /// GraphQL answers 200 even when the query failed, so the envelope must be read.
    @Test func surfacesGraphQLErrors() async throws {
        let transport = StubTransport(response: #"{"errors":[{"message":"Field 'nope' doesn't exist"}]}"#)
        let client = LinearClient(transport: transport, apiKey: "k")
        await #expect(throws: LinearError.graphQL(["Field 'nope' doesn't exist"])) {
            _ = try await client.myIssues()
        }
    }

    @Test func mapsAnAuthenticationErrorToUnauthorized() async throws {
        let transport = StubTransport(response: #"{"errors":[{"message":"Authentication required"}]}"#)
        let client = LinearClient(transport: transport, apiKey: "k")
        await #expect(throws: LinearError.unauthorized) {
            _ = try await client.myIssues()
        }
    }

    @Test func refusesToWorkWithoutAKey() async throws {
        let client = LinearClient(transport: StubTransport(response: "{}"), apiKey: nil)
        await #expect(throws: LinearError.notConfigured) {
            _ = try await client.myIssues()
        }
    }

    @Test func readsTheAccountAndWorkspaceSlug() async throws {
        let json = """
            {"data":{"viewer":{"id":"u-1","name":"Sam Rivers","email":"sam@example.com"},
                     "organization":{"urlKey":"acme","name":"Acme"}}}
            """
        let client = LinearClient(transport: StubTransport(response: json), apiKey: "k")
        let account = try await client.account()
        #expect(account.user.name == "Sam Rivers")
        #expect(account.urlKey == "acme")
        #expect(account.organizationName == "Acme")
    }

    @Test func decodesProjects() async throws {
        let json = """
            {"data":{"projects":{"nodes":[
              {"id":"p-1","name":"Launch","description":"Ship it","url":"https://linear.app/acme/project/launch-abc",
               "progress":0.42,"targetDate":"2026-12-01","updatedAt":"2026-08-20T10:00:00.000Z",
               "status":{"id":"ps-1","name":"In Progress","type":"started"},
               "lead":{"name":"Sam Rivers"}}
            ]}}}
            """
        let client = LinearClient(transport: StubTransport(response: json), apiKey: "k")
        let project = try #require(try await client.myProjects().first)
        #expect(project.name == "Launch")
        #expect(project.statusType == .started)
        #expect(project.progress == 0.42)
        #expect(project.leadName == "Sam Rivers")
    }

    /// Some workspaces reject the membership filter; falling back to projects the
    /// user leads beats showing an empty list.
    @Test func fallsBackToLedProjectsWhenTheFilterIsRejected() async throws {
        let rejection = #"{"errors":[{"message":"Invalid filter: members"}]}"#
        let success = """
            {"data":{"projects":{"nodes":[
              {"id":"p-2","name":"Fallback","url":"https://linear.app/acme/project/fallback"}
            ]}}}
            """
        let transport = StubTransport(responses: [rejection, success])
        let client = LinearClient(transport: transport, apiKey: "k")

        let projects = try await client.myProjects()
        #expect(projects.map(\.name) == ["Fallback"])

        // The retry narrows the filter to `lead`.
        #expect(await transport.lastFilterHasKey("lead"))
        #expect(!(await transport.lastFilterHasKey("or")))
    }

    @Test func updatesAnIssue() async throws {
        let json = """
            {"data":{"issueUpdate":{"success":true,"issue":
              {"id":"uuid-1","identifier":"ABC-12","title":"Renamed","priority":1,"url":"u",
               "state":{"id":"s","name":"Todo","type":"unstarted"}}}}}
            """
        let transport = StubTransport(response: json)
        let client = LinearClient(transport: transport, apiKey: "k")

        let updated = try await client.update(issue: "uuid-1", LinearIssueEdit(title: "Renamed", priority: .urgent))
        #expect(updated?.title == "Renamed")

        #expect(await transport.lastInputString("title") == "Renamed")
        #expect(await transport.lastInputInt("priority") == 1)
        // Fields the user did not touch must not be sent.
        #expect(!(await transport.lastInputHasKey("description")))
        #expect(!(await transport.lastInputHasKey("stateId")))
    }

    @Test func anEmptyEditSendsNothing() async throws {
        let transport = StubTransport(response: "{}")
        let client = LinearClient(transport: transport, apiKey: "k")
        #expect(try await client.update(issue: "x", LinearIssueEdit()) == nil)
        #expect(await transport.requestCount() == 0)
    }

    /// Clearing the body is a real edit and must reach Linear.
    @Test func clearingTheDescriptionIsSent() {
        let edit = LinearIssueEdit(description: "")
        #expect(!edit.isEmpty)
        #expect(edit.input["description"] as? String == "")
    }

    @Test func failsLoudlyWhenLinearDoesNotConfirm() async throws {
        let transport = StubTransport(response: #"{"data":{"issueUpdate":{"success":false}}}"#)
        let client = LinearClient(transport: transport, apiKey: "k")
        await #expect(throws: LinearError.self) {
            _ = try await client.update(issue: "x", LinearIssueEdit(title: "t"))
        }
    }

    @Test func decodesWorkflowStates() async throws {
        let json = """
            {"data":{"team":{"states":{"nodes":[
              {"id":"s1","name":"Todo","type":"unstarted","color":"#e2e2e2"},
              {"id":"s2","name":"Done","type":"completed","color":"#5e6ad2"}
            ]}}}}
            """
        let client = LinearClient(transport: StubTransport(response: json), apiKey: "k")
        let states = try await client.workflowStates(teamID: "team-1")
        #expect(states.map(\.name) == ["Todo", "Done"])
        #expect(states.last?.type == .completed)
    }

    @Test func skipsMalformedNodesRatherThanFailing() async throws {
        let json = """
            {"data":{"issues":{"pageInfo":{"hasNextPage":false},"nodes":[
              {"id":"ok","identifier":"ABC-1","title":"Good","priority":0,"url":"u",
               "state":{"id":"s","name":"Todo","type":"unstarted"}},
              {"id":"bad","title":"Missing identifier and state"}
            ]}}}
            """
        let client = LinearClient(transport: StubTransport(response: json), apiKey: "k")
        let issues = try await client.myIssues()
        #expect(issues.map(\.identifier) == ["ABC-1"])
    }

    /// An unknown priority number must not crash or silently become Urgent.
    @Test func unknownPriorityBecomesNone() async throws {
        let json = """
            {"data":{"issues":{"pageInfo":{"hasNextPage":false},"nodes":[
              {"id":"x","identifier":"ABC-3","title":"Odd","priority":99,"url":"u",
               "state":{"id":"s","name":"Todo","type":"unstarted"}}
            ]}}}
            """
        let client = LinearClient(transport: StubTransport(response: json), apiKey: "k")
        #expect(try await client.myIssues().first?.priority == LinearPriority.none)
    }
}

@Suite("Linear links")
struct LinearLinkTests {
    @Test func buildsTheBulkViews() {
        #expect(LinearLinks.myIssues(urlKey: "acme")?.absoluteString == "https://linear.app/acme/my-issues")
        #expect(LinearLinks.createdByMe(urlKey: "acme")?.absoluteString == "https://linear.app/acme/my-issues/created")
        #expect(LinearLinks.projects(urlKey: "acme")?.absoluteString == "https://linear.app/acme/projects")
    }

    @Test func escapesASearchQuery() throws {
        let url = try #require(LinearLinks.search(urlKey: "acme", query: "sidebar bug"))
        #expect(url.absoluteString.contains("q=sidebar%20bug") || url.absoluteString.contains("q=sidebar+bug"))
    }
}

@Suite("Priority ordering")
struct LinearPriorityTests {
    /// Linear's 0 means "no priority", which belongs last, not first.
    @Test func noPrioritySortsLast() {
        let sorted = LinearPriority.allCases.sorted { $0.sortOrder < $1.sortOrder }
        #expect(sorted.first == .urgent)
        #expect(sorted.last == LinearPriority.none)
    }
}
