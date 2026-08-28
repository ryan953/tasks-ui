import DexKit
import Foundation
import Observation

/// Everything the window reads from, and the only place that talks to ``DexClient``.
@MainActor
@Observable
final class TaskStore {
    private(set) var index = TaskIndex(tasks: [])
    private(set) var isLoading = false
    private(set) var isBootstrapping = true
    private(set) var errorMessage: String?
    private(set) var resolvedBinary: String?
    private(set) var searchPath = ""

    var selection: String?
    var query = ""

    var filter: StatusFilter {
        didSet { Preferences.filter = filter }
    }

    var sort: SortField {
        didSet { Preferences.sort = sort }
    }

    /// Completed tasks are fetched either way; this only decides whether they show.
    var showCompleted: Bool {
        didSet { Preferences.showCompleted = showCompleted }
    }

    private let client = DexClient()
    private var watcher: TaskWatcher?

    init() {
        filter = Preferences.filter
        sort = Preferences.sort
        showCompleted = Preferences.showCompleted
    }

    /// Seed the store without touching dex, for previews and snapshot tests.
    init(tasks: [DexTask], selection: String? = nil) {
        filter = .all
        sort = .priority
        showCompleted = true
        index = TaskIndex(tasks: tasks)
        self.selection = selection
        isBootstrapping = false
        resolvedBinary = "/preview/dex"
    }

    // MARK: - Derived

    var outline: [TaskNode] {
        index.outline(filter: effectiveFilter, query: query, sort: sort)
    }

    /// "Hide completed" narrows an otherwise unfiltered list; an explicit status
    /// filter always wins, otherwise picking "Completed" would show nothing.
    private var effectiveFilter: StatusFilter {
        if filter == .all && !showCompleted { return .pending }
        return filter
    }

    var selectedTask: DexTask? {
        selection.flatMap { index[$0] }
    }

    var counts: (done: Int, total: Int) {
        let total = index.tasks.count
        return (index.tasks.filter(\.completed).count, total)
    }

    // MARK: - Lifecycle

    func bootstrap() async {
        isBootstrapping = true
        resolvedBinary = await client.bootstrap(override: Preferences.dexPath)
        await client.setStoragePath(Preferences.storagePath)
        searchPath = await client.searchPath
        isBootstrapping = false
        await reload()
        await startWatching()
    }

    /// Re-resolve after Settings changes.
    func reconfigure() async {
        watcher?.stop()
        watcher = nil
        await bootstrap()
    }

    private func startWatching() async {
        let directory = await client.tasksDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let watcher = TaskWatcher(directory: directory) { [weak self] in
            Task { @MainActor in await self?.reload(quietly: true) }
        }
        watcher.start()
        self.watcher = watcher
    }

    // MARK: - Reads

    /// - Parameter quietly: skip the progress indicator, for refreshes the user did
    ///   not ask for (a file changed on disk).
    func reload(quietly: Bool = false) async {
        guard !isBootstrapping else { return }
        if !quietly { isLoading = true }
        defer { isLoading = false }
        do {
            index = TaskIndex(tasks: try await client.list(includeCompleted: true))
            errorMessage = nil
            // Drop a selection whose task has gone away.
            if let selection, index[selection] == nil { self.selection = nil }
        } catch {
            errorMessage = message(for: error)
        }
    }

    // MARK: - Writes
    //
    // Each mutation reloads, so the sidebar reflects the relationship updates dex
    // makes on the other side of a link.

    func create(_ task: NewTask) async -> String? {
        await perform {
            let id = try await self.client.create(task)
            await self.reload(quietly: true)
            if let id { self.selection = id }
            return id
        } ?? nil
    }

    func apply(_ edit: TaskEdit, to id: String) async {
        await perform {
            try await self.client.edit(id, edit)
            await self.reload(quietly: true)
        }
    }

    func complete(_ id: String, result: String) async {
        await perform {
            try await self.client.complete(id, result: result)
            await self.reload(quietly: true)
        }
    }

    func reopen(_ id: String) async {
        await perform {
            try await self.client.uncomplete(id)
            await self.reload(quietly: true)
        }
    }

    func delete(_ id: String) async {
        await perform {
            try await self.client.delete(id)
            if self.selection == id { self.selection = nil }
            await self.reload(quietly: true)
        }
    }

    func dismissError() { errorMessage = nil }

    @discardableResult
    private func perform<T>(_ work: @MainActor () async throws -> T) async -> T? {
        do {
            let value = try await work()
            errorMessage = nil
            return value
        } catch {
            errorMessage = message(for: error)
            return nil
        }
    }

    private func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

/// Window state that should outlive a launch.
enum Preferences {
    private static var defaults: UserDefaults { .standard }

    static var dexPath: String? {
        get { defaults.string(forKey: "dexPath") }
        set { defaults.set(newValue, forKey: "dexPath") }
    }

    static var storagePath: String? {
        get { defaults.string(forKey: "storagePath") }
        set { defaults.set(newValue, forKey: "storagePath") }
    }

    static var filter: StatusFilter {
        get { defaults.string(forKey: "filter").flatMap(StatusFilter.init) ?? .all }
        set { defaults.set(newValue.rawValue, forKey: "filter") }
    }

    static var sort: SortField {
        get { defaults.string(forKey: "sort").flatMap(SortField.init) ?? .priority }
        set { defaults.set(newValue.rawValue, forKey: "sort") }
    }

    static var showCompleted: Bool {
        get { defaults.object(forKey: "showCompleted") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showCompleted") }
    }
}
