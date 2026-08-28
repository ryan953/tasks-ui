import Foundation

/// Linear's five workflow state types.
public enum LinearStateType: String, Codable, Sendable, CaseIterable {
    case backlog
    case unstarted
    case started
    case completed
    case canceled

    public var label: String {
        switch self {
        case .backlog: "Backlog"
        case .unstarted: "Todo"
        case .started: "In progress"
        case .completed: "Done"
        case .canceled: "Cancelled"
        }
    }

    /// Roughly matches the dex task states, so one sidebar can show both.
    public var symbol: String {
        switch self {
        case .backlog: "tray"
        case .unstarted: "circle"
        case .started: "play.circle.fill"
        case .completed: "checkmark.circle.fill"
        case .canceled: "xmark.circle"
        }
    }
}

public struct LinearState: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var type: LinearStateType
    /// Linear hands back a hex colour like "#5e6ad2".
    public var color: String?

    public init(id: String, name: String, type: LinearStateType, color: String? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.color = color
    }
}

public struct LinearUser: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var email: String?
    /// The workspace slug, used to build links Linear itself would produce.
    public var organizationURLKey: String?

    public init(id: String, name: String, email: String? = nil, organizationURLKey: String? = nil) {
        self.id = id
        self.name = name
        self.email = email
        self.organizationURLKey = organizationURLKey
    }
}

public struct LinearTeam: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var key: String
    public var name: String

    public init(id: String, key: String, name: String) {
        self.id = id
        self.key = key
        self.name = name
    }
}

/// Linear priority. 0 means "no priority" and sorts last, not first.
public enum LinearPriority: Int, Codable, Sendable, CaseIterable, Identifiable {
    case none = 0
    case urgent = 1
    case high = 2
    case medium = 3
    case low = 4

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .none: "No priority"
        case .urgent: "Urgent"
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }

    public var symbol: String {
        switch self {
        case .none: "minus"
        case .urgent: "exclamationmark.square.fill"
        case .high: "chart.bar.fill"
        case .medium: "chart.bar"
        case .low: "chart.bar.doc.horizontal"
        }
    }

    /// Sort key that puts "no priority" after Low rather than before Urgent.
    public var sortOrder: Int { self == .none ? Int.max : rawValue }
}

public struct LinearIssue: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    /// The human key, e.g. "REPLAY-431".
    public var identifier: String
    public var title: String
    public var description: String?
    public var priority: LinearPriority
    public var state: LinearState
    /// The canonical web link. Taken from the API rather than built by hand.
    public var url: String
    public var team: LinearTeam?
    public var projectID: String?
    public var projectName: String?
    public var assigneeName: String?
    public var updatedAt: Date?

    public init(
        id: String,
        identifier: String,
        title: String,
        description: String? = nil,
        priority: LinearPriority = .none,
        state: LinearState,
        url: String,
        team: LinearTeam? = nil,
        projectID: String? = nil,
        projectName: String? = nil,
        assigneeName: String? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.identifier = identifier
        self.title = title
        self.description = description
        self.priority = priority
        self.state = state
        self.url = url
        self.team = team
        self.projectID = projectID
        self.projectName = projectName
        self.assigneeName = assigneeName
        self.updatedAt = updatedAt
    }
}

/// Project status in Linear is a free-form set per workspace, but the underlying
/// type is one of these.
public enum LinearProjectStatusType: String, Codable, Sendable {
    case backlog, planned, started, paused, completed, canceled
}

public struct LinearProject: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var description: String?
    public var statusName: String?
    public var statusType: LinearProjectStatusType?
    public var url: String
    public var leadName: String?
    /// 0...1
    public var progress: Double?
    public var targetDate: String?
    public var updatedAt: Date?

    public init(
        id: String,
        name: String,
        description: String? = nil,
        statusName: String? = nil,
        statusType: LinearProjectStatusType? = nil,
        url: String,
        leadName: String? = nil,
        progress: Double? = nil,
        targetDate: String? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.statusName = statusName
        self.statusType = statusType
        self.url = url
        self.leadName = leadName
        self.progress = progress
        self.targetDate = targetDate
        self.updatedAt = updatedAt
    }
}
