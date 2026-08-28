import Foundation

/// A commit recorded against a task by `dex`.
public struct CommitMetadata: Codable, Hashable, Sendable {
    public var sha: String
    public var message: String?
    public var branch: String?
    public var url: String?
    public var timestamp: String?
}

/// A GitHub issue `dex` has linked to a task.
public struct GitHubMetadata: Codable, Hashable, Sendable {
    public var repo: String?
    public var number: Int?
    public var state: String?
    public var url: String?
}

public struct TaskMetadata: Codable, Hashable, Sendable {
    public var commit: CommitMetadata?
    public var github: GitHubMetadata?
}

/// One task as `dex list --json` emits it.
///
/// Field names mirror the JSON on disk, which mixes snake_case (`parent_id`) and
/// camelCase (`blockedBy`), so the coding keys are spelled out.
///
/// dex 0.16 renamed the two text fields: what used to be `description` (a short
/// title) is now `name`, and what used to be `context` (the long details) is now
/// `description`. Decoding accepts both shapes, keyed off whether `name` is present
/// — the same test dex itself uses to migrate a file — so a store written by an
/// older dex still displays correctly instead of showing blank titles.
public struct DexTask: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var parentID: String?
    /// The short title. dex 0.16 `name`; dex 0.1 `description`.
    public var name: String
    /// The long details. dex 0.16 `description`; dex 0.1 `context`.
    public var details: String?
    public var priority: Int
    public var completed: Bool
    public var result: String?
    public var metadata: TaskMetadata?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var startedAt: Date?
    public var completedAt: Date?
    public var archivedAt: Date?
    public var blockedBy: [String]
    public var blocks: [String]
    public var children: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case parentID = "parent_id"
        case name
        case details = "description"
        case legacyDetails = "context"
        case priority
        case completed
        case result
        case metadata
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case archivedAt = "archived_at"
        case blockedBy
        case blocks
        case children
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        parentID = try c.decodeIfPresent(String.self, forKey: .parentID) ?? nil

        if let modernName = try c.decodeIfPresent(String.self, forKey: .name) {
            name = modernName
            details = try c.decodeIfPresent(String.self, forKey: .details) ?? nil
        } else {
            // Pre-0.16 file: `description` held the title and `context` the details.
            name = try c.decodeIfPresent(String.self, forKey: .details) ?? ""
            details = try c.decodeIfPresent(String.self, forKey: .legacyDetails) ?? nil
        }

        priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 1
        completed = try c.decodeIfPresent(Bool.self, forKey: .completed) ?? false
        result = try c.decodeIfPresent(String.self, forKey: .result) ?? nil
        metadata = try c.decodeIfPresent(TaskMetadata.self, forKey: .metadata) ?? nil
        createdAt = Self.date(try c.decodeIfPresent(String.self, forKey: .createdAt))
        updatedAt = Self.date(try c.decodeIfPresent(String.self, forKey: .updatedAt))
        startedAt = Self.date(try c.decodeIfPresent(String.self, forKey: .startedAt))
        completedAt = Self.date(try c.decodeIfPresent(String.self, forKey: .completedAt))
        archivedAt = Self.date(try c.decodeIfPresent(String.self, forKey: .archivedAt))
        blockedBy = try c.decodeIfPresent([String].self, forKey: .blockedBy) ?? []
        blocks = try c.decodeIfPresent([String].self, forKey: .blocks) ?? []
        children = try c.decodeIfPresent([String].self, forKey: .children) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(parentID, forKey: .parentID)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(details, forKey: .details)
        try c.encode(priority, forKey: .priority)
        try c.encode(completed, forKey: .completed)
        try c.encodeIfPresent(result, forKey: .result)
        try c.encodeIfPresent(metadata, forKey: .metadata)
        try c.encode(blockedBy, forKey: .blockedBy)
        try c.encode(blocks, forKey: .blocks)
        try c.encode(children, forKey: .children)
    }

    static func date(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return ISO8601.date(from: raw)
    }

    /// Memberwise init used by tests and previews.
    public init(
        id: String,
        parentID: String? = nil,
        name: String = "",
        details: String? = nil,
        priority: Int = 1,
        completed: Bool = false,
        result: String? = nil,
        metadata: TaskMetadata? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        archivedAt: Date? = nil,
        blockedBy: [String] = [],
        blocks: [String] = [],
        children: [String] = []
    ) {
        self.id = id
        self.parentID = parentID
        self.name = name
        self.details = details
        self.priority = priority
        self.completed = completed
        self.result = result
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.archivedAt = archivedAt
        self.blockedBy = blockedBy
        self.blocks = blocks
        self.children = children
    }
}

/// Where a task sits relative to its blockers and its own progress.
public enum TaskState: String, Sendable {
    case completed
    /// Started but not finished.
    case inProgress
    /// Pending, with at least one blocker still open.
    case blocked
    /// Pending, with every blocker cleared.
    case ready

    public var label: String {
        switch self {
        case .completed: "Completed"
        case .inProgress: "In progress"
        case .blocked: "Blocked"
        case .ready: "Ready"
        }
    }

    public var symbol: String {
        switch self {
        case .completed: "checkmark.circle.fill"
        case .inProgress: "play.circle.fill"
        case .blocked: "exclamationmark.octagon"
        case .ready: "circle"
        }
    }
}
