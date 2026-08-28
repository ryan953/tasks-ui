import Foundation

/// Fields a task edit may change. `nil` means "leave alone", which matters because
/// `dex edit` only touches the flags it is given.
public struct TaskEdit: Sendable, Equatable {
    public var description: String?
    public var context: String?
    public var priority: Int?
    public var parentID: String?
    public var addBlockers: [String]
    public var removeBlockers: [String]

    public init(
        description: String? = nil,
        context: String? = nil,
        priority: Int? = nil,
        parentID: String? = nil,
        addBlockers: [String] = [],
        removeBlockers: [String] = []
    ) {
        self.description = description
        self.context = context
        self.priority = priority
        self.parentID = parentID
        self.addBlockers = addBlockers
        self.removeBlockers = removeBlockers
    }

    public var isEmpty: Bool {
        description == nil && context == nil && priority == nil && parentID == nil
            && addBlockers.isEmpty && removeBlockers.isEmpty
    }
}

public struct NewTask: Sendable, Equatable {
    public var description: String
    public var context: String
    public var priority: Int
    public var parentID: String?
    public var blockedBy: [String]

    public init(
        description: String,
        context: String,
        priority: Int = 1,
        parentID: String? = nil,
        blockedBy: [String] = []
    ) {
        self.description = description
        self.context = context
        self.priority = priority
        self.parentID = parentID
        self.blockedBy = blockedBy
    }
}

/// Builds `dex` argument vectors.
///
/// Kept separate from the process plumbing so the flag spelling is unit-tested
/// without spawning anything.
public enum DexCommand {
    public static func list(includeCompleted: Bool) -> [String] {
        var args = ["list", "--json"]
        if includeCompleted { args.append("--all") }
        return args
    }

    public static func show(_ id: String) -> [String] {
        ["show", id, "--json"]
    }

    public static func create(_ task: NewTask) -> [String] {
        var args = ["create", "-d", task.description, "--context", task.context]
        args += ["-p", String(task.priority)]
        if let parentID = task.parentID, !parentID.isEmpty {
            args += ["--parent", parentID]
        }
        if !task.blockedBy.isEmpty {
            args += ["-b", task.blockedBy.joined(separator: ",")]
        }
        return args
    }

    public static func edit(_ id: String, _ edit: TaskEdit) -> [String] {
        var args = ["edit", id]
        if let description = edit.description { args += ["-d", description] }
        if let context = edit.context { args += ["--context", context] }
        if let priority = edit.priority { args += ["-p", String(priority)] }
        if let parentID = edit.parentID { args += ["--parent", parentID] }
        if !edit.addBlockers.isEmpty {
            args += ["--add-blocker", edit.addBlockers.joined(separator: ",")]
        }
        if !edit.removeBlockers.isEmpty {
            args += ["--remove-blocker", edit.removeBlockers.joined(separator: ",")]
        }
        return args
    }

    public static func complete(_ id: String, result: String) -> [String] {
        ["complete", id, "--result", result]
    }

    public static func delete(_ id: String) -> [String] {
        ["delete", id, "-f"]
    }
}
