import Foundation

public struct LinearAccount: Sendable, Equatable {
    public var user: LinearUser
    public var organizationName: String
    public var urlKey: String

    public init(user: LinearUser, organizationName: String, urlKey: String) {
        self.user = user
        self.organizationName = organizationName
        self.urlKey = urlKey
    }
}

/// Fields the app can change on an issue. `nil` means "leave alone".
public struct LinearIssueEdit: Sendable, Equatable {
    public var title: String?
    public var description: String?
    public var priority: LinearPriority?
    public var stateID: String?

    public init(
        title: String? = nil,
        description: String? = nil,
        priority: LinearPriority? = nil,
        stateID: String? = nil
    ) {
        self.title = title
        self.description = description
        self.priority = priority
        self.stateID = stateID
    }

    public var isEmpty: Bool {
        title == nil && description == nil && priority == nil && stateID == nil
    }

    public var input: [String: Any] {
        var input: [String: Any] = [:]
        if let title { input["title"] = title }
        if let description { input["description"] = description }
        if let priority { input["priority"] = priority.rawValue }
        if let stateID { input["stateId"] = stateID }
        return input
    }
}

/// Fields the app can change on a project.
///
/// Deliberately narrow: status is a per-workspace set, and everything Linear can do
/// beyond this is one click away through the project's own link.
public struct LinearProjectEdit: Sendable, Equatable {
    public var name: String?
    public var description: String?
    public var targetDate: String?

    public init(name: String? = nil, description: String? = nil, targetDate: String? = nil) {
        self.name = name
        self.description = description
        self.targetDate = targetDate
    }

    public var isEmpty: Bool {
        name == nil && description == nil && targetDate == nil
    }

    public var input: [String: Any] {
        var input: [String: Any] = [:]
        if let name { input["name"] = name }
        if let description { input["description"] = description }
        if let targetDate { input["targetDate"] = targetDate }
        return input
    }
}

public actor LinearClient {
    private let transport: LinearTransport
    private var apiKey: String?
    /// Set once the member-based project filter has been rejected by the workspace.
    private var useNarrowProjectFilter = false

    public init(transport: LinearTransport = URLSessionLinearTransport(), apiKey: String? = nil) {
        self.transport = transport
        self.apiKey = apiKey
    }

    public func setAPIKey(_ key: String?) {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        apiKey = (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    public var isConfigured: Bool { apiKey != nil }

    // MARK: - Reads

    public func account() async throws -> LinearAccount {
        let json = try await perform(query: LinearQueries.viewer, variables: [:])
        guard let viewer = json["viewer"] as? [String: Any],
            let id = viewer["id"] as? String,
            let name = viewer["name"] as? String
        else { throw LinearError.decoding("viewer was missing from the response") }
        let org = json["organization"] as? [String: Any]
        let urlKey = org?["urlKey"] as? String ?? ""
        return LinearAccount(
            user: LinearUser(
                id: id,
                name: name,
                email: viewer["email"] as? String,
                organizationURLKey: urlKey
            ),
            organizationName: org?["name"] as? String ?? "Linear",
            urlKey: urlKey
        )
    }

    /// Every issue assigned to the signed-in user.
    ///
    /// Paginated, because an active workspace holds more than one page and a
    /// half-loaded list would quietly look like a completed one.
    public func myIssues(includeDone: Bool = false, pageLimit: Int = 5) async throws -> [LinearIssue] {
        var issues: [LinearIssue] = []
        var cursor: String?
        for _ in 0..<pageLimit {
            var variables: [String: Any] = ["filter": LinearQueries.myIssuesFilter(includeDone: includeDone)]
            if let cursor { variables["after"] = cursor }
            let json = try await perform(query: LinearQueries.myIssues, variables: variables)
            guard let connection = json["issues"] as? [String: Any] else {
                throw LinearError.decoding("issues was missing from the response")
            }
            let nodes = connection["nodes"] as? [[String: Any]] ?? []
            issues += nodes.compactMap(Self.issue(from:))
            let pageInfo = connection["pageInfo"] as? [String: Any]
            guard pageInfo?["hasNextPage"] as? Bool == true,
                let next = pageInfo?["endCursor"] as? String
            else { break }
            cursor = next
        }
        return issues
    }

    public func myProjects() async throws -> [LinearProject] {
        let filter =
            useNarrowProjectFilter
            ? LinearQueries.ledProjectsFilter
            : LinearQueries.myProjectsFilter
        do {
            let json = try await perform(query: LinearQueries.myProjects, variables: ["filter": filter])
            let nodes = (json["projects"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
            return nodes.compactMap(Self.project(from:))
        } catch let LinearError.graphQL(messages) where !useNarrowProjectFilter {
            // Some workspaces reject the membership filter. Fall back to projects
            // the user leads rather than showing none at all.
            useNarrowProjectFilter = true
            _ = messages
            return try await myProjects()
        }
    }

    public func workflowStates(teamID: String) async throws -> [LinearState] {
        let json = try await perform(query: LinearQueries.teamStates, variables: ["teamId": teamID])
        let nodes = ((json["team"] as? [String: Any])?["states"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
        return nodes.compactMap(Self.state(from:))
    }

    // MARK: - Writes

    @discardableResult
    public func update(issue id: String, _ edit: LinearIssueEdit) async throws -> LinearIssue? {
        guard !edit.isEmpty else { return nil }
        let json = try await perform(
            query: LinearQueries.updateIssue,
            variables: ["id": id, "input": edit.input]
        )
        guard let payload = json["issueUpdate"] as? [String: Any],
            payload["success"] as? Bool == true
        else { throw LinearError.decoding("Linear did not confirm the issue update") }
        return (payload["issue"] as? [String: Any]).flatMap(Self.issue(from:))
    }

    @discardableResult
    public func update(project id: String, _ edit: LinearProjectEdit) async throws -> LinearProject? {
        guard !edit.isEmpty else { return nil }
        let json = try await perform(
            query: LinearQueries.updateProject,
            variables: ["id": id, "input": edit.input]
        )
        guard let payload = json["projectUpdate"] as? [String: Any],
            payload["success"] as? Bool == true
        else { throw LinearError.decoding("Linear did not confirm the project update") }
        return (payload["project"] as? [String: Any]).flatMap(Self.project(from:))
    }

    // MARK: - Plumbing

    private func perform(query: String, variables: [String: Any]) async throws -> [String: Any] {
        guard let apiKey else { throw LinearError.notConfigured }
        var payload: [String: Any] = ["query": query]
        if !variables.isEmpty { payload["variables"] = variables }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await transport.send(body: body, apiKey: apiKey)
        return try Self.unwrap(data)
    }

    /// Pull `data` out of a GraphQL envelope, turning `errors` into a thrown error.
    ///
    /// GraphQL answers with HTTP 200 even when the query failed, so the envelope has
    /// to be inspected or a failure looks like an empty list.
    static func unwrap(_ data: Data) throws -> [String: Any] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LinearError.decoding("response was not a JSON object")
        }
        if let errors = root["errors"] as? [[String: Any]], !errors.isEmpty {
            let messages = errors.map { ($0["message"] as? String) ?? "Unknown error" }
            if messages.contains(where: { $0.localizedCaseInsensitiveContains("authentication") }) {
                throw LinearError.unauthorized
            }
            throw LinearError.graphQL(messages)
        }
        guard let payload = root["data"] as? [String: Any] else {
            throw LinearError.decoding("response had no data")
        }
        return payload
    }

    // MARK: - Mapping

    static func issue(from node: [String: Any]) -> LinearIssue? {
        guard let id = node["id"] as? String,
            let identifier = node["identifier"] as? String,
            let title = node["title"] as? String,
            let stateNode = node["state"] as? [String: Any],
            let state = state(from: stateNode)
        else { return nil }
        let team = (node["team"] as? [String: Any]).flatMap { teamNode -> LinearTeam? in
            guard let id = teamNode["id"] as? String,
                let key = teamNode["key"] as? String
            else { return nil }
            return LinearTeam(id: id, key: key, name: teamNode["name"] as? String ?? key)
        }
        let project = node["project"] as? [String: Any]
        let priorityValue = (node["priority"] as? NSNumber)?.intValue ?? 0
        return LinearIssue(
            id: id,
            identifier: identifier,
            title: title,
            description: node["description"] as? String,
            priority: LinearPriority(rawValue: priorityValue) ?? .none,
            state: state,
            // Fall back to a constructed link only if Linear omitted one.
            url: node["url"] as? String ?? "https://linear.app/issue/\(identifier)",
            team: team,
            projectID: project?["id"] as? String,
            projectName: project?["name"] as? String,
            assigneeName: (node["assignee"] as? [String: Any])?["name"] as? String,
            updatedAt: (node["updatedAt"] as? String).flatMap(LinearDate.parse)
        )
    }

    static func project(from node: [String: Any]) -> LinearProject? {
        guard let id = node["id"] as? String,
            let name = node["name"] as? String
        else { return nil }
        let status = node["status"] as? [String: Any]
        return LinearProject(
            id: id,
            name: name,
            description: node["description"] as? String,
            statusName: status?["name"] as? String,
            statusType: (status?["type"] as? String).flatMap(LinearProjectStatusType.init(rawValue:)),
            url: node["url"] as? String ?? "https://linear.app",
            leadName: (node["lead"] as? [String: Any])?["name"] as? String,
            progress: (node["progress"] as? NSNumber)?.doubleValue,
            targetDate: node["targetDate"] as? String,
            updatedAt: (node["updatedAt"] as? String).flatMap(LinearDate.parse)
        )
    }

    static func state(from node: [String: Any]) -> LinearState? {
        guard let id = node["id"] as? String,
            let name = node["name"] as? String
        else { return nil }
        let type = (node["type"] as? String).flatMap(LinearStateType.init(rawValue:)) ?? .unstarted
        return LinearState(id: id, name: name, type: type, color: node["color"] as? String)
    }
}

enum LinearDate {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: (ISO8601DateFormatter, ISO8601DateFormatter)?

    /// Linear sends ISO-8601 with milliseconds; tolerate the form without them.
    static func parse(_ raw: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        let formatters: (ISO8601DateFormatter, ISO8601DateFormatter)
        if let cached {
            formatters = cached
        } else {
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            formatters = (fractional, plain)
            cached = formatters
        }
        return formatters.0.date(from: raw) ?? formatters.1.date(from: raw)
    }
}
