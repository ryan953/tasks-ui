import Foundation
import Testing
@testable import DexKit

/// Drives the real `dex` binary against a throwaway store.
///
/// Nothing here touches the user's own ~/.dex: every client gets its own
/// `--storage-path` under a temporary directory. Skipped when dex is not installed
/// so the suite still runs on a bare CI machine.
@Suite("dex client against the real CLI", .enabled(if: DexProbe.isInstalled))
struct DexClientIntegrationTests {
    /// A client pointed at a fresh, empty store.
    static func makeClient() async throws -> (DexClient, URL) {
        let store = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("dex-ui-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        let client = DexClient()
        await client.bootstrap(override: nil)
        await client.setStoragePath(store.path)
        return (client, store)
    }

    @Test func createsListsAndShowsATask() async throws {
        let (client, store) = try await Self.makeClient()
        defer { try? FileManager.default.removeItem(at: store) }

        let id = try await client.create(
            NewTask(description: "Write the release workflow", context: "GitHub Actions", priority: 2)
        )
        let taskID = try #require(id)

        let tasks = try await client.list()
        #expect(tasks.count == 1)
        #expect(tasks[0].description == "Write the release workflow")
        #expect(tasks[0].priority == 2)

        let shown = try await client.show(taskID)
        #expect(shown.id == taskID)
        #expect(shown.context == "GitHub Actions")
    }

    @Test func editsFieldsIndividually() async throws {
        let (client, store) = try await Self.makeClient()
        defer { try? FileManager.default.removeItem(at: store) }

        let id = try #require(try await client.create(NewTask(description: "Before", context: "ctx", priority: 3)))
        try await client.edit(id, TaskEdit(description: "After"))

        let task = try await client.show(id)
        #expect(task.description == "After")
        // The untouched fields must survive an edit that only names one of them.
        #expect(task.context == "ctx")
        #expect(task.priority == 3)
    }

    /// dex keeps the relationship on both tasks; the app relies on that rather than
    /// writing `blocks` itself.
    @Test func blockersAreRecordedOnBothSides() async throws {
        let (client, store) = try await Self.makeClient()
        defer { try? FileManager.default.removeItem(at: store) }

        let blocker = try #require(try await client.create(NewTask(description: "First", context: "c")))
        let dependent = try #require(try await client.create(NewTask(description: "Second", context: "c")))

        try await client.edit(dependent, TaskEdit(addBlockers: [blocker]))

        var index = TaskIndex(tasks: try await client.list())
        #expect(index[dependent]?.blockedBy == [blocker])
        #expect(index[blocker]?.blocks == [dependent])
        #expect(index.state(of: index[dependent]!) == .blocked)

        // Completing the blocker clears the dependent without editing it.
        try await client.complete(blocker, result: "done")
        index = TaskIndex(tasks: try await client.list())
        #expect(index.state(of: index[dependent]!) == .ready)

        try await client.edit(dependent, TaskEdit(removeBlockers: [blocker]))
        index = TaskIndex(tasks: try await client.list())
        #expect(index[dependent]?.blockedBy.isEmpty == true)
        #expect(index[blocker]?.blocks.isEmpty == true)
    }

    @Test func parentAndChildAreLinkedBothWays() async throws {
        let (client, store) = try await Self.makeClient()
        defer { try? FileManager.default.removeItem(at: store) }

        let parent = try #require(try await client.create(NewTask(description: "Epic", context: "c")))
        let child = try #require(try await client.create(NewTask(description: "Subtask", context: "c", parentID: parent)))

        let index = TaskIndex(tasks: try await client.list())
        #expect(index[child]?.parentID == parent)
        #expect(index[parent]?.children == [child])

        let outline = index.outline()
        #expect(outline.map(\.id) == [parent])
        #expect(outline[0].children.map(\.id) == [child])
    }

    @Test func completesAndReopensATask() async throws {
        let (client, store) = try await Self.makeClient()
        defer { try? FileManager.default.removeItem(at: store) }

        let id = try #require(try await client.create(NewTask(description: "Ship it", context: "c")))
        try await client.complete(id, result: "Shipped in v1.0")

        var task = try await client.show(id)
        #expect(task.completed)
        #expect(task.result == "Shipped in v1.0")
        #expect(task.completedAt != nil)

        // dex has no un-complete command, so this rewrites the JSON in place.
        try await client.uncomplete(id)

        task = try await client.show(id)
        #expect(!task.completed)
        #expect(task.result == nil)
        #expect(task.completedAt == nil)
    }

    /// Reopening must not disturb anything dex keeps in sync on another task.
    @Test func reopeningPreservesRelationships() async throws {
        let (client, store) = try await Self.makeClient()
        defer { try? FileManager.default.removeItem(at: store) }

        let parent = try #require(try await client.create(NewTask(description: "Epic", context: "c")))
        let child = try #require(try await client.create(NewTask(description: "Kid", context: "c", parentID: parent)))
        let other = try #require(try await client.create(NewTask(description: "Other", context: "c")))
        try await client.edit(other, TaskEdit(addBlockers: [child]))
        try await client.complete(child, result: "done")

        try await client.uncomplete(child)

        let index = TaskIndex(tasks: try await client.list())
        #expect(index[child]?.parentID == parent)
        #expect(index[child]?.blocks == [other])
        #expect(index[other]?.blockedBy == [child])
        #expect(index[child]?.completed == false)
    }

    @Test func deletesATask() async throws {
        let (client, store) = try await Self.makeClient()
        defer { try? FileManager.default.removeItem(at: store) }

        let id = try #require(try await client.create(NewTask(description: "Temporary", context: "c")))
        try await client.delete(id)
        #expect(try await client.list().isEmpty)
    }

    @Test func hidesCompletedTasksWhenAsked() async throws {
        let (client, store) = try await Self.makeClient()
        defer { try? FileManager.default.removeItem(at: store) }

        let done = try #require(try await client.create(NewTask(description: "Done", context: "c")))
        _ = try await client.create(NewTask(description: "Open", context: "c"))
        try await client.complete(done, result: "r")

        #expect(try await client.list(includeCompleted: true).count == 2)
        #expect(try await client.list(includeCompleted: false).count == 1)
    }

    /// A failing command must surface dex's own message, not a bare exit code.
    @Test func reportsCliErrors() async throws {
        let (client, store) = try await Self.makeClient()
        defer { try? FileManager.default.removeItem(at: store) }

        await #expect(throws: DexError.self) {
            try await client.show("nosuchid")
        }
    }

    @Test func multilineContentSurvivesTheRoundTrip() async throws {
        let (client, store) = try await Self.makeClient()
        defer { try? FileManager.default.removeItem(at: store) }

        // Quotes and newlines go straight through argv, so nothing needs escaping —
        // this guards against anyone "fixing" that with a shell string.
        let context = "Line one\nLine \"two\" with 'quotes'\n  - a $VARIABLE and `backticks`"
        let id = try #require(try await client.create(NewTask(description: "Tricky", context: context)))
        #expect(try await client.show(id).context == context)
    }
}

/// Synchronous probe, because a suite condition cannot await.
enum DexProbe {
    static let isInstalled: Bool = {
        let path = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            + ":" + ShellEnvironment.fallbackPaths.joined(separator: ":")
        return DexLocator.find(in: path) != nil
    }()
}
