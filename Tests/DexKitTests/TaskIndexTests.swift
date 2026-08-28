import Foundation
import Testing
@testable import DexKit

@Suite("Task index, states and outline")
struct TaskIndexTests {
    /// epic ─ ready, blocked (blocked by ready), done
    static func fixture() -> TaskIndex {
        TaskIndex(tasks: [
            DexTask(id: "epic", description: "Epic", priority: 1, children: ["ready", "blocked", "done"]),
            DexTask(id: "ready", parentID: "epic", description: "Ready work", priority: 2, blocks: ["blocked"]),
            DexTask(id: "blocked", parentID: "epic", description: "Blocked work", priority: 1, blockedBy: ["ready"]),
            DexTask(id: "done", parentID: "epic", description: "Finished work", priority: 3, completed: true),
            DexTask(id: "loose", description: "No parent", priority: 4),
        ])
    }

    @Test func classifiesStates() {
        let index = Self.fixture()
        #expect(index.state(of: index["ready"]!) == .ready)
        #expect(index.state(of: index["blocked"]!) == .blocked)
        #expect(index.state(of: index["done"]!) == .completed)
    }

    /// Once the blocker completes, the dependent becomes ready without any edit.
    @Test func completingABlockerUnblocks() {
        var tasks = Self.fixture().tasks
        tasks[1].completed = true
        let index = TaskIndex(tasks: tasks)
        #expect(index.state(of: index["blocked"]!) == .ready)
        #expect(index.openBlockers(of: index["blocked"]!).isEmpty)
    }

    /// dex cleans up references on delete, but a hand-edited store can dangle.
    @Test func ignoresBlockersThatNoLongerExist() {
        let index = TaskIndex(tasks: [DexTask(id: "a", description: "A", blockedBy: ["ghost"])])
        #expect(index.state(of: index["a"]!) == .ready)
    }

    @Test func buildsTheOutline() {
        let nodes = Self.fixture().outline()
        #expect(nodes.map(\.id) == ["epic", "loose"])
        // Children sort by priority: blocked(1) before ready(2) before done(3).
        #expect(nodes[0].children.map(\.id) == ["blocked", "ready", "done"])
    }

    @Test func countsSubtreeProgress() {
        let epic = Self.fixture().outline()[0]
        #expect(epic.progress.done == 1)
        #expect(epic.progress.total == 3)
    }

    /// A matching subtask must stay reachable, so its parent is kept even though the
    /// parent itself does not match.
    @Test func keepsParentsOfMatchingChildren() {
        let nodes = Self.fixture().outline(query: "Blocked work")
        #expect(nodes.map(\.id) == ["epic"])
        #expect(nodes[0].children.map(\.id) == ["blocked"])
    }

    @Test func filtersByStatus() {
        let index = Self.fixture()
        #expect(TaskIndex.flatten(index.outline(filter: .completed)).contains { $0.id == "done" })
        let ready = TaskIndex.flatten(index.outline(filter: .ready)).map(\.id)
        #expect(ready.contains("ready"))
        #expect(!ready.contains("blocked"))
    }

    @Test func searchLooksInsideContextAndID() {
        let index = TaskIndex(tasks: [
            DexTask(id: "zz11", description: "Nothing", context: "mentions bcrypt here"),
        ])
        #expect(!index.outline(query: "bcrypt").isEmpty)
        #expect(!index.outline(query: "zz11").isEmpty)
        #expect(index.outline(query: "absent").isEmpty)
    }

    @Test func searchIgnoresCase() {
        #expect(!Self.fixture().outline(query: "READY WORK").isEmpty)
    }

    /// A task pointing at a parent that was filtered out of the list still shows.
    @Test func orphanBecomesARoot() {
        let index = TaskIndex(tasks: [DexTask(id: "kid", parentID: "gone", description: "Orphan")])
        #expect(index.outline().map(\.id) == ["kid"])
    }

    @Test func sortsByEachField() {
        let index = Self.fixture()
        let alpha = index.sorted(index.tasks, by: .alpha).map(\.description)
        #expect(alpha == ["Blocked work", "Epic", "Finished work", "No parent", "Ready work"])
        #expect(index.sorted(index.tasks, by: .priority).first?.id == "epic")
    }

    /// The blocker picker must not offer a choice dex would reject as a cycle.
    @Test func excludesRelationsThatWouldCycle() {
        let index = Self.fixture()
        let ineligible = index.ineligibleRelations(for: index["ready"]!)
        #expect(ineligible.contains("ready"))
        #expect(ineligible.contains("blocked"))
        #expect(!ineligible.contains("loose"))
    }

    @Test func excludesDescendantsAsParents() {
        let ineligible = Self.fixture().ineligibleRelations(for: Self.fixture()["epic"]!)
        #expect(ineligible.isSuperset(of: ["epic", "ready", "blocked", "done"]))
    }
}

@Suite("Config and path handling")
struct ConfigTests {
    @Test func readsThePathOutOfTheStorageFileTable() {
        let toml = """
        [storage]
        engine = "file"

        [storage.file]
        mode = "centralized"
        path = "/Users/ryan953/.dex"  # Uncomment to set custom path
        """
        #expect(DexConfig.storagePath(fromTOML: toml) == "/Users/ryan953/.dex")
    }

    /// The shipped dex.toml comments out the alternatives; none may be picked up.
    @Test func ignoresCommentedKeysAndOtherTables() {
        let toml = """
        [storage]
        engine = "file"
        # path = "/wrong/commented"

        [storage.github-issues]
        path = "/wrong/table"
        """
        #expect(DexConfig.storagePath(fromTOML: toml) == nil)
    }

    @Test func expandsTilde() {
        #expect(DexConfig.expandTilde("~/.dex").hasPrefix("/"))
        #expect(DexConfig.expandTilde("/abs") == "/abs")
    }

    @Test func tasksDirectoryHangsOffStorage() {
        #expect(DexConfig.tasksDirectory(storagePath: "/tmp/store").path == "/tmp/store/tasks")
    }
}

@Suite("Locating the dex binary")
struct LocatorTests {
    @Test func findsAnExecutableOnThePath() {
        #expect(DexLocator.find(named: "ls", in: "/nowhere:/bin") == "/bin/ls")
        #expect(DexLocator.find(named: "definitely-not-here", in: "/bin") == nil)
    }

    @Test func honoursAnAbsoluteOverride() {
        #expect(DexLocator.resolve(override: "/bin/ls", path: "") == "/bin/ls")
        #expect(DexLocator.resolve(override: "/bin/nope", path: "/bin") == nil)
    }

    @Test func aBlankOverrideFallsBackToSearching() {
        #expect(DexLocator.resolve(override: "   ", path: "/bin") == nil)
        #expect(DexLocator.resolve(override: "ls", path: "/bin") == "/bin/ls")
    }
}

@Suite("Login shell PATH recovery")
struct ShellEnvironmentTests {
    /// The marker brackets the value because rc files print banners of their own.
    @Test func extractsThePathBetweenMarkers() {
        let noisy = "Welcome!\n\(ShellEnvironment.marker)/opt/homebrew/bin:/usr/bin\(ShellEnvironment.marker)"
        #expect(ShellEnvironment.extractPath(from: noisy) == "/opt/homebrew/bin:/usr/bin")
        #expect(ShellEnvironment.extractPath(from: "no markers at all") == nil)
    }

    @Test func mergeKeepsShellOrderAndDropsDuplicates() {
        let merged = ShellEnvironment.merge("/my/bin:/usr/bin:/my/bin")
        let parts = merged.split(separator: ":").map(String.init)
        #expect(parts.first == "/my/bin")
        #expect(parts.filter { $0 == "/my/bin" }.count == 1)
        #expect(parts.contains("/opt/homebrew/bin"))
    }

    /// Regression guard for the bug that makes a launched .app show no tasks: dex is
    /// a Node script, so its shebang needs node on PATH.
    @Test func recoversARealPathContainingNode() async {
        let path = await ShellEnvironment.loginPath()
        #expect(DexLocator.find(named: "node", in: path) != nil)
    }
}
