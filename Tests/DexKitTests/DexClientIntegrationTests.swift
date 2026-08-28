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
        await client.bootstrap(override: DexProbe.binaryOverride)
        await client.setStoragePath(store.path)
        return (client, store)
    }

    @Test func createsListsAndShowsATask() async throws {
        let (client, store) = try await Self.makeClient()
        defer { try? FileManager.default.removeItem(at: store) }

        let id = try await client.create(
            NewTask(name: "Write the release workflow", details: "GitHub Actions", priority: 2)
        )
        let taskID = try #require(id)

        let tasks = try await client.list()
        #expect(tasks.count == 1)
        #expect(tasks[0].name == "Write the release workflow")
        #expect(tasks[0].priority == 2)

        let shown = try await client.show(taskID)
        #expect(shown.id == taskID)
        #expect(shown.details == "GitHub Actions")
    }

    @Test func editsFieldsIndividually() async throws {
        let (client, store) = try await Self.makeClient()
        defer { try? FileManager.default.removeItem(at: store) }

        let id = try #require(try await client.create(NewTask(name: "Before", details: "ctx", priority: 3)))
        try await client.edit(id, TaskEdit(name: "After"))

        let task = try await client.show(id)
        #expect(task.name == "After")
        // The untouched fields must survive an edit that only names one of them.
        #expect(task.details == "ctx")
        #expect(task.priority == 3)
    }

    /// dex keeps the relationship on both tasks; the app relies on that rather than
    /// writing `blocks` itself.
    @Test func blockersAreRecordedOnBothSides() async throws {
        let (client, store) = try await Self.makeClient()
        defer { try? FileManager.default.removeItem(at: store) }

        let blocker = try #require(try await client.create(NewTask(name: "First", details: "c")))
        let dependent = try #require(try await client.create(NewTask(name: "Second", details: "c")))

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

        let parent = try #require(try await client.create(NewTask(name: "Epic", details: "c")))
        let child = try #require(try await client.create(NewTask(name: "Subtask", details: "c", parentID: parent)))

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

        let id = try #require(try await client.create(NewTask(name: "Ship it", details: "c")))
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

        let parent = try #require(try await client.create(NewTask(name: "Epic", details: "c")))
        let child = try #require(try await client.create(NewTask(name: "Kid", details: "c", parentID: parent)))
        let other = try #require(try await client.create(NewTask(name: "Other", details: "c")))
        try await client.edit(other, TaskEdit(addBlockers: [child]))
        try await client.complete(child, result: "done")

        try await client.uncomplete(child)

        let index = TaskIndex(tasks: try await client.list())
        #expect(index[child]?.parentID == parent)
        #expect(index[child]?.blocks == [other])
        #expect(index[other]?.blockedBy == [child])
        #expect(index[child]?.completed == false)
    }

    /// Reopening rewrites one line of tasks.jsonl. Every other line, and any field
    /// this app does not model, must come through untouched.
    @Test func reopeningLeavesTheRestOfTheStoreAlone() async throws {
        let (client, store) = try await Self.makeClient()
        defer { try? FileManager.default.removeItem(at: store) }

        let target = try #require(try await client.create(NewTask(name: "Target", details: "d")))
        let bystander = try #require(try await client.create(NewTask(name: "Bystander", details: "d")))
        try await client.complete(target, result: "done")

        // Add a field the app's model knows nothing about.
        let file = await client.tasksFile()
        let original = try String(contentsOf: file, encoding: .utf8)
        let doctored = original
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { line -> String in
                guard line.contains("\"id\":\"\(target)\"") else { return String(line) }
                return String(line.dropLast()) + ",\"unmodelled_field\":\"keep me\"}"
            }
            .joined(separator: "\n") + "\n"
        try Data(doctored.utf8).write(to: file, options: .atomic)

        try await client.uncomplete(target)

        let after = try String(contentsOf: file, encoding: .utf8)
        #expect(after.contains("keep me"), "an unmodelled field was dropped")

        let index = TaskIndex(tasks: try await client.list())
        #expect(index[target]?.completed == false)
        #expect(index[bystander]?.name == "Bystander")
        #expect(index.tasks.count == 2)
    }

    @Test func reportsReopeningAMissingTask() async throws {
        let (client, store) = try await Self.makeClient()
        defer { try? FileManager.default.removeItem(at: store) }
        _ = try await client.create(NewTask(name: "Something", details: "d"))

        await #expect(throws: DexError.self) {
            try await client.uncomplete("nosuchid")
        }
    }

    @Test func startsATask() async throws {
        let (client, store) = try await Self.makeClient()
        defer { try? FileManager.default.removeItem(at: store) }

        let id = try #require(try await client.create(NewTask(name: "Work", details: "d")))
        var index = TaskIndex(tasks: try await client.list())
        #expect(index.state(of: index[id]!) == .ready)

        try await client.start(id)
        index = TaskIndex(tasks: try await client.list())
        #expect(index[id]?.startedAt != nil)
        #expect(index.state(of: index[id]!) == .inProgress)
    }

    @Test func deletesATask() async throws {
        let (client, store) = try await Self.makeClient()
        defer { try? FileManager.default.removeItem(at: store) }

        let id = try #require(try await client.create(NewTask(name: "Temporary", details: "c")))
        try await client.delete(id)
        #expect(try await client.list().isEmpty)
    }

    @Test func hidesCompletedTasksWhenAsked() async throws {
        let (client, store) = try await Self.makeClient()
        defer { try? FileManager.default.removeItem(at: store) }

        let done = try #require(try await client.create(NewTask(name: "Done", details: "c")))
        _ = try await client.create(NewTask(name: "Open", details: "c"))
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
        let body = "Line one\nLine \"two\" with 'quotes'\n  - a $VARIABLE and `backticks`"
        let id = try #require(try await client.create(NewTask(name: "Tricky", details: body)))
        #expect(try await client.show(id).details == body)
    }
}

/// Synchronous probe, because a suite condition cannot await.
enum DexProbe {
    /// Point the suite at a specific dex, so it can run against a pinned version
    /// without disturbing whatever is installed globally.
    static var binaryOverride: String? {
        ProcessInfo.processInfo.environment["DEX_UI_TEST_BIN"]
    }

    static let isInstalled: Bool = {
        if let binaryOverride, FileManager.default.isExecutableFile(atPath: binaryOverride) {
            return true
        }
        let path = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            + ":" + ShellEnvironment.fallbackPaths.joined(separator: ":")
        return DexLocator.find(in: path) != nil
    }()
}
