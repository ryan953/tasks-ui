import Foundation

/// A commit recorded against a task by `dex`.
public struct CommitMetadata: Codable, Hashable, Sendable {
    public var sha: String
    public var message: String?
    public var branch: String?
    public var url: String?
    public var timestamp: String?
}

public struct TaskMetadata: Codable, Hashable, Sendable {
    public var commit: CommitMetadata?
}

/// One task as `dex list --json` emits it.
///
/// Field names mirror the JSON on disk, which mixes snake_case (`parent_id`) and
/// camelCase (`blockedBy`), so the coding keys are spelled out rather than relying
/// on a key-decoding strategy.
public struct DexTask: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var parentID: String?
    public var description: String
    public var context: String?
    public var priority: Int
    public var completed: Bool
    public var result: String?
    public var metadata: TaskMetadata?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var completedAt: Date?
    public var blockedBy: [String]
    public var blocks: [String]
    public var children: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case parentID = "parent_id"
        case description
        case context
        case priority
        case completed
        case result
        case metadata
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case completedAt = "completed_at"
        case blockedBy
        case blocks
        case children
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        parentID = try c.decodeIfPresent(String.self, forKey: .parentID) ?? nil
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        context = try c.decodeIfPresent(String.self, forKey: .context) ?? nil
        priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 1
        completed = try c.decodeIfPresent(Bool.self, forKey: .completed) ?? false
        result = try c.decodeIfPresent(String.self, forKey: .result) ?? nil
        metadata = try c.decodeIfPresent(TaskMetadata.self, forKey: .metadata) ?? nil
        createdAt = Self.date(try c.decodeIfPresent(String.self, forKey: .createdAt))
        updatedAt = Self.date(try c.decodeIfPresent(String.self, forKey: .updatedAt))
        completedAt = Self.date(try c.decodeIfPresent(String.self, forKey: .completedAt))
        blockedBy = try c.decodeIfPresent([String].self, forKey: .blockedBy) ?? []
        blocks = try c.decodeIfPresent([String].self, forKey: .blocks) ?? []
        children = try c.decodeIfPresent([String].self, forKey: .children) ?? []
    }

    static func date(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return ISO8601.date(from: raw)
    }

    /// Memberwise init used by tests and previews.
    public init(
        id: String,
        parentID: String? = nil,
        description: String = "",
        context: String? = nil,
        priority: Int = 1,
        completed: Bool = false,
        result: String? = nil,
        metadata: TaskMetadata? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        completedAt: Date? = nil,
        blockedBy: [String] = [],
        blocks: [String] = [],
        children: [String] = []
    ) {
        self.id = id
        self.parentID = parentID
        self.description = description
        self.context = context
        self.priority = priority
        self.completed = completed
        self.result = result
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.blockedBy = blockedBy
        self.blocks = blocks
        self.children = children
    }
}

/// Where a task sits relative to its blockers.
public enum TaskState: String, Sendable {
    case completed
    /// Pending, but at least one blocker is still open.
    case blocked
    /// Pending with every blocker cleared.
    case ready

    public var symbol: String {
        switch self {
        case .completed: "checkmark.circle.fill"
        case .blocked: "exclamationmark.octagon"
        case .ready: "circle"
        }
    }
}
