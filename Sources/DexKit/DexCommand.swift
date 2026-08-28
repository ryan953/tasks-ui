import Foundation

/// Fields a task edit may change. `nil` means "leave alone", which matters because
/// `dex edit` only touches the flags it is given.
public struct TaskEdit: Sendable, Equatable {
    public var name: String?
    public var details: String?
    public var priority: Int?
    public var parentID: String?
    public var addBlockers: [String]
    public var removeBlockers: [String]

    public init(
        name: String? = nil,
        details: String? = nil,
        priority: Int? = nil,
        parentID: String? = nil,
        addBlockers: [String] = [],
        removeBlockers: [String] = []
    ) {
        self.name = name
        self.details = details
        self.priority = priority
        self.parentID = parentID
        self.addBlockers = addBlockers
        self.removeBlockers = removeBlockers
    }

    public var isEmpty: Bool {
        name == nil && details == nil && priority == nil && parentID == nil
            && addBlockers.isEmpty && removeBlockers.isEmpty
    }
}

public struct NewTask: Sendable, Equatable {
    public var name: String
    public var details: String
    public var priority: Int
    public var parentID: String?
    public var blockedBy: [String]

    public init(
        name: String,
        details: String = "",
        priority: Int = 1,
        parentID: String? = nil,
        blockedBy: [String] = []
    ) {
        self.name = name
        self.details = details
        self.priority = priority
        self.parentID = parentID
        self.blockedBy = blockedBy
    }
}

/// Builds `dex` argument vectors, targeting the dex 0.16 CLI.
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
        // The name is passed with -n rather than positionally: a name beginning with
        // a dash would otherwise be read as a flag.
        var args = ["create", "-n", task.name]
        if !task.details.isEmpty { args += ["--description", task.details] }
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
        if let name = edit.name { args += ["-n", name] }
        if let details = edit.details { args += ["--description", details] }
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

    public static func start(_ id: String) -> [String] {
        // --force re-claims a task already in progress, so pressing Start twice is
        // not an error the user has to think about.
        ["start", id, "--force"]
    }

    /// - Parameter commit: a SHA to link, or nil to complete without one.
    ///
    /// One of `--commit`/`--no-commit` is always sent: dex refuses to complete a
    /// task linked to a GitHub issue or Shortcut story without being told which,
    /// and the app has no terminal to answer a prompt on.
    public static func complete(_ id: String, result: String, commit: String? = nil) -> [String] {
        var args = ["complete", id, "--result", result]
        if let commit, !commit.trimmingCharacters(in: .whitespaces).isEmpty {
            args += ["--commit", commit.trimmingCharacters(in: .whitespaces)]
        } else {
            args.append("--no-commit")
        }
        return args
    }

    public static func delete(_ id: String) -> [String] {
        ["delete", id, "-f"]
    }

    public static func archive(_ id: String) -> [String] {
        ["archive", id]
    }
}
