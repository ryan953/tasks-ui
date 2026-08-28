import Foundation

public enum StatusFilter: String, CaseIterable, Identifiable, Sendable {
    case all, ready, inProgress, blocked, pending, completed
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .all: "All"
        case .ready: "Ready"
        case .inProgress: "In progress"
        case .blocked: "Blocked"
        case .pending: "Pending"
        case .completed: "Completed"
        }
    }
}

public enum SortField: String, CaseIterable, Identifiable, Sendable {
    case priority, created, updated, alpha
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .priority: "Priority"
        case .created: "Created"
        case .updated: "Recently updated"
        case .alpha: "Alphabetical"
        }
    }
}

/// One node of the sidebar outline.
public struct TaskNode: Identifiable, Hashable, Sendable {
    public var task: DexTask
    public var children: [TaskNode]
    public var id: String { task.id }

    public init(task: DexTask, children: [TaskNode]) {
        self.task = task
        self.children = children
    }

    /// `nil` rather than `[]` for leaves: SwiftUI draws a disclosure triangle for an
    /// empty array but not for nil.
    public var outlineChildren: [TaskNode]? { children.isEmpty ? nil : children }

    /// Completed and total counts across this node's descendants, excluding itself.
    public var progress: (done: Int, total: Int) {
        var done = 0
        var total = 0
        for child in children {
            total += 1
            if child.task.completed { done += 1 }
            let nested = child.progress
            done += nested.done
            total += nested.total
        }
        return (done, total)
    }
}

/// Read-only view over a task list: lookups, states, filtering and the outline.
public struct TaskIndex: Sendable {
    public let tasks: [DexTask]
    private let byID: [String: DexTask]

    public init(tasks: [DexTask]) {
        self.tasks = tasks
        byID = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    }

    public subscript(id: String) -> DexTask? { byID[id] }

    public func tasks(ids: [String]) -> [DexTask] { ids.compactMap { byID[$0] } }

    /// A pending task is blocked while any task in `blockedBy` is still open.
    /// Blockers that no longer exist are ignored, matching `dex`'s own behaviour.
    ///
    /// Blocked outranks in-progress: a started task whose blocker reopened is a
    /// problem the user should see, not something to hide behind a "working on it".
    public func state(of task: DexTask) -> TaskState {
        if task.completed { return .completed }
        let hasOpenBlocker = task.blockedBy.contains { id in
            guard let blocker = byID[id] else { return false }
            return !blocker.completed
        }
        if hasOpenBlocker { return .blocked }
        return task.startedAt != nil ? .inProgress : .ready
    }

    public func openBlockers(of task: DexTask) -> [DexTask] {
        task.blockedBy.compactMap { byID[$0] }.filter { !$0.completed }
    }

    public func matches(_ task: DexTask, filter: StatusFilter) -> Bool {
        switch filter {
        case .all: true
        case .completed: task.completed
        case .pending: !task.completed
        case .ready: state(of: task) == .ready
        case .inProgress: state(of: task) == .inProgress
        case .blocked: state(of: task) == .blocked
        }
    }

    public func matches(_ task: DexTask, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let haystack = [task.name, task.details ?? "", task.id, task.result ?? ""]
            .joined(separator: "\n")
        return haystack.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    /// Build the outline.
    ///
    /// A task is kept when it matches, and also when any descendant matches — losing
    /// the parent would orphan a matching subtask and hide it from the sidebar.
    public func outline(filter: StatusFilter = .all, query: String = "", sort: SortField = .priority) -> [TaskNode] {
        var childrenByParent: [String: [DexTask]] = [:]
        var roots: [DexTask] = []
        for task in tasks {
            // Treat a task whose parent is missing from the list as a root, so it
            // cannot vanish entirely.
            if let parentID = task.parentID, byID[parentID] != nil {
                childrenByParent[parentID, default: []].append(task)
            } else {
                roots.append(task)
            }
        }

        func build(_ task: DexTask) -> TaskNode? {
            let children = sorted(childrenByParent[task.id] ?? [], by: sort).compactMap(build)
            let selfMatches = matches(task, filter: filter) && matches(task, query: query)
            guard selfMatches || !children.isEmpty else { return nil }
            return TaskNode(task: task, children: children)
        }

        return sorted(roots, by: sort).compactMap(build)
    }

    /// Every task, flattened in outline order, for keyboard navigation and pickers.
    public static func flatten(_ nodes: [TaskNode]) -> [DexTask] {
        nodes.flatMap { [$0.task] + flatten($0.children) }
    }

    public func sorted(_ tasks: [DexTask], by field: SortField) -> [DexTask] {
        tasks.sorted { a, b in
            switch field {
            case .priority:
                if a.priority != b.priority { return a.priority < b.priority }
                return (a.createdAt ?? .distantPast) < (b.createdAt ?? .distantPast)
            case .created:
                return (a.createdAt ?? .distantPast) > (b.createdAt ?? .distantPast)
            case .updated:
                return (a.updatedAt ?? .distantPast) > (b.updatedAt ?? .distantPast)
            case .alpha:
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        }
    }

    /// Ids that may not become a blocker or parent of `task`: itself, and anything
    /// that would close a loop. `dex` rejects these too; filtering them out of the
    /// pickers means the user never sees the error.
    public func ineligibleRelations(for task: DexTask) -> Set<String> {
        var blocked: Set<String> = [task.id]
        // Anything downstream of this task would create a blocking cycle.
        var queue = task.blocks
        while let id = queue.popLast() {
            guard blocked.insert(id).inserted, let next = byID[id] else { continue }
            queue.append(contentsOf: next.blocks)
        }
        // Descendants cannot become the parent.
        var descendants = task.children
        while let id = descendants.popLast() {
            guard blocked.insert(id).inserted, let next = byID[id] else { continue }
            descendants.append(contentsOf: next.children)
        }
        return blocked
    }
}
