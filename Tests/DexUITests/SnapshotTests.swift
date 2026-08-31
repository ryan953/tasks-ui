import AppKit
import DexKit
import LinearKit
import SwiftUI
import Testing

@testable import DexUI

/// Renders the real views into an offscreen window so the layout can be inspected
/// without launching the app. Writes PNGs under .build/snapshots.
///
/// `ImageRenderer` is not usable here: `List`, `ScrollView` and `NavigationSplitView`
/// are AppKit-backed and it renders them blank or as a "not supported" glyph. Hosting
/// the view in a real `NSWindow` and asking the layer to draw is what actually
/// exercises them.
@MainActor
@Suite("View snapshots", .serialized)
struct SnapshotTests {
    static let outputDirectory = URL(fileURLWithPath: ".build/snapshots")

    static func fixture() -> [DexTask] {
        let now = Date()
        return [
            DexTask(
                id: "4puhcjd4", name: "Ship the macOS task viewer", priority: 1,
                createdAt: now, updatedAt: now, children: ["b6n79rg4", "lxs7u9bc", "e3m27w78"]),
            DexTask(
                id: "b6n79rg4", parentID: "4puhcjd4", name: "Read tasks from the dex CLI",
                details: "Shell out to `dex list --json --all`.", priority: 1, completed: true,
                result: "Reads through the CLI so dex stays the only writer.",
                createdAt: now, updatedAt: now, completedAt: now),
            DexTask(
                id: "lxs7u9bc", parentID: "4puhcjd4",
                name: "Edit dependencies from the detail pane",
                details: """
                    Requirements:
                      - add and remove blockers
                      - reparent a task
                      - never offer a link that would make a cycle
                    Done when: the pickers refuse anything dex would reject.
                    """,
                priority: 2, createdAt: now, updatedAt: now,
                blockedBy: ["b6n79rg4"], blocks: ["e3m27w78"]),
            DexTask(
                id: "e3m27w78", parentID: "4puhcjd4", name: "Attach the build to a GitHub release",
                details: "Tag push builds a universal .app and uploads the zip.",
                priority: 3, createdAt: now, updatedAt: now, blockedBy: ["lxs7u9bc"]),
            DexTask(
                id: "qq44mm21", name: "Pull issues and projects from Linear", priority: 2,
                createdAt: now, updatedAt: now, startedAt: now),
            DexTask(
                id: "wbbnaadg", name: "Write the README", priority: 4,
                createdAt: now, updatedAt: now),
        ]
    }

    static func linearIssues() -> [LinearIssue] {
        [
            LinearIssue(
                id: "uuid-1", identifier: "ABC-12", title: "Wire up the Linear sidebar",
                description: "Show issues and projects assigned to me, and link out for the rest.",
                priority: .high,
                state: LinearState(id: "state-1", name: "In Progress", type: .started),
                url: "https://linear.app/acme/issue/ABC-12/wire-up-the-linear-sidebar",
                team: LinearTeam(id: "team-1", key: "ABC", name: "Acme"),
                projectID: "proj-1", projectName: "Launch",
                assigneeName: "Sam Rivers", updatedAt: Date()
            ),
            LinearIssue(
                id: "uuid-2", identifier: "ABC-31", title: "Handle task:// deep links",
                priority: .medium,
                state: LinearState(id: "state-2", name: "Todo", type: .unstarted),
                url: "https://linear.app/acme/issue/ABC-31/handle-deep-links",
                team: LinearTeam(id: "team-1", key: "ABC", name: "Acme"),
                updatedAt: Date()
            ),
            LinearIssue(
                id: "uuid-3", identifier: "DEV-4", title: "Store the API key in the keychain",
                priority: .none,
                state: LinearState(id: "state-3", name: "Backlog", type: .backlog),
                url: "https://linear.app/acme/issue/DEV-4/keychain",
                team: LinearTeam(id: "team-2", key: "DEV", name: "Platform"),
                updatedAt: Date()
            ),
        ]
    }

    static func linearProjects() -> [LinearProject] {
        [
            LinearProject(
                id: "proj-1", name: "Launch",
                description: "Ship the first version of the task viewer.",
                statusName: "In Progress", statusType: .started,
                url: "https://linear.app/acme/project/launch-abc",
                leadName: "Sam Rivers", progress: 0.42,
                targetDate: "2026-12-01", updatedAt: Date()
            ),
            LinearProject(
                id: "proj-2", name: "Keyboard navigation",
                statusName: "Planned", statusType: .planned,
                url: "https://linear.app/acme/project/keyboard",
                leadName: "Sam Rivers", progress: 0, updatedAt: Date()
            ),
            LinearProject(
                id: "proj-3", name: "Offline cache",
                statusName: "Backlog", statusType: .backlog,
                url: "https://linear.app/acme/project/offline",
                progress: 0, updatedAt: Date()
            ),
            LinearProject(
                id: "proj-4", name: "Old migration",
                statusName: "Completed", statusType: .completed,
                url: "https://linear.app/acme/project/old",
                progress: 1, updatedAt: Date()
            ),
        ]
    }

    /// Host `view` in a window, let it lay out, and write a PNG.
    @discardableResult
    static func snapshot(_ view: some View, size: CGSize, name: String) throws -> URL {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        // A real NSApplication has to exist before AppKit will lay anything out.
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // Paint the window background the real app (or a sheet) supplies. Without
        // it the bitmap caches as transparent-over-white while the views resolve
        // dark-appearance colours, and light text vanishes into the page.
        let framed =
            view
            .frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: framed)
        host.frame = CGRect(origin: .zero, size: size)
        window.contentView = host
        window.orderFrontRegardless()

        // Give SwiftUI a few turns of the run loop to build the AppKit view tree;
        // a List populates its rows asynchronously.
        for _ in 0..<12 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        let url = outputDirectory.appendingPathComponent("\(name).png")
        try png.write(to: url)

        window.orderOut(nil)
        return url
    }

    /// Guards against a snapshot that renders as an empty page.
    static func assertNotBlank(_ url: URL, name: String) throws {
        let data = try Data(contentsOf: url)
        let rep = try #require(NSBitmapImageRep(data: data))
        var seen = Set<UInt32>()
        // Sample a grid rather than every pixel; a real UI shows many colours.
        for x in stride(from: 2, to: rep.pixelsWide, by: max(1, rep.pixelsWide / 40)) {
            for y in stride(from: 2, to: rep.pixelsHigh, by: max(1, rep.pixelsHigh / 40)) {
                guard let color = rep.colorAt(x: x, y: y) else { continue }
                let packed =
                    UInt32(color.redComponent * 255) << 16
                    | UInt32(color.greenComponent * 255) << 8
                    | UInt32(color.blueComponent * 255)
                seen.insert(packed)
            }
        }
        #expect(seen.count > 3, "\(name) looks blank — only \(seen.count) distinct colours")
    }

    static func makeModel(source: Source = .dex, selection: String? = nil, linear: LinearSelection? = nil) -> AppModel {
        AppModel(
            dex: TaskStore(tasks: fixture(), selection: selection),
            linear: LinearStore(issues: linearIssues(), projects: linearProjects(), selection: linear),
            source: source
        )
    }

    // ContentView itself is deliberately not snapshotted: inside a
    // NavigationSplitView the sidebar column is drawn with a material that does not
    // composite into an offscreen cacheDisplay, so the shot shows a blank panel and
    // proves nothing. The two panes are captured separately instead.

    @Test func rendersTheSidebar() throws {
        let store = TaskStore(tasks: Self.fixture(), selection: "lxs7u9bc")
        let url = try Self.snapshot(
            SidebarView(store: store, isCreating: .constant(false), newTaskParent: .constant(nil)),
            size: CGSize(width: 330, height: 620),
            name: "sidebar"
        )
        try Self.assertNotBlank(url, name: "sidebar")
    }

    @Test func rendersASearchThatMatchesNothing() throws {
        let store = TaskStore(tasks: Self.fixture())
        store.query = "nothing matches this"
        let url = try Self.snapshot(
            SidebarView(store: store, isCreating: .constant(false), newTaskParent: .constant(nil)),
            size: CGSize(width: 330, height: 620),
            name: "sidebar-no-matches"
        )
        try Self.assertNotBlank(url, name: "sidebar-no-matches")
    }

    @Test func rendersAPendingTask() throws {
        let store = TaskStore(tasks: Self.fixture(), selection: "lxs7u9bc")
        let task = try #require(store.selectedTask)
        let url = try Self.snapshot(
            TaskDetailView(store: store, task: task, newTaskParent: .constant(nil), isCreating: .constant(false)),
            size: CGSize(width: 780, height: 720),
            name: "detail"
        )
        try Self.assertNotBlank(url, name: "detail")
    }

    @Test func rendersACompletedTask() throws {
        let store = TaskStore(tasks: Self.fixture(), selection: "b6n79rg4")
        let task = try #require(store.selectedTask)
        let url = try Self.snapshot(
            TaskDetailView(store: store, task: task, newTaskParent: .constant(nil), isCreating: .constant(false)),
            size: CGSize(width: 780, height: 720),
            name: "detail-completed"
        )
        try Self.assertNotBlank(url, name: "detail-completed")
    }

    @Test func rendersTheNewTaskSheet() throws {
        let store = TaskStore(tasks: Self.fixture())
        let url = try Self.snapshot(
            NewTaskSheet(store: store, parentID: nil),
            size: CGSize(width: 560, height: 620),
            name: "new-task"
        )
        try Self.assertNotBlank(url, name: "new-task")
    }

    @Test func rendersTheCompleteSheet() throws {
        let task = try #require(Self.fixture().first { $0.id == "lxs7u9bc" })
        let url = try Self.snapshot(
            CompleteSheet(task: task) { _, _ in },
            size: CGSize(width: 480, height: 340),
            name: "complete"
        )
        try Self.assertNotBlank(url, name: "complete")
    }

    @Test func rendersSettings() throws {
        let url = try Self.snapshot(
            SettingsView(model: Self.makeModel()),
            size: CGSize(width: 520, height: 460),
            name: "settings"
        )
        try Self.assertNotBlank(url, name: "settings")
    }

    // MARK: - Linear

    @Test func rendersTheLinearSidebar() throws {
        let store = LinearStore(issues: Self.linearIssues(), projects: Self.linearProjects())
        let url = try Self.snapshot(
            LinearSidebarView(store: store),
            size: CGSize(width: 330, height: 620),
            name: "linear-sidebar"
        )
        try Self.assertNotBlank(url, name: "linear-sidebar")
    }

    @Test func rendersALinearIssue() throws {
        let store = LinearStore(issues: Self.linearIssues(), projects: Self.linearProjects())
        let issue = try #require(Self.linearIssues().first)
        let url = try Self.snapshot(
            LinearIssueDetailView(store: store, issue: issue),
            size: CGSize(width: 780, height: 640),
            name: "linear-issue"
        )
        try Self.assertNotBlank(url, name: "linear-issue")
    }

    @Test func rendersALinearProject() throws {
        let store = LinearStore(issues: Self.linearIssues(), projects: Self.linearProjects())
        let project = try #require(Self.linearProjects().first)
        let url = try Self.snapshot(
            LinearProjectDetailView(store: store, project: project),
            size: CGSize(width: 780, height: 640),
            name: "linear-project"
        )
        try Self.assertNotBlank(url, name: "linear-project")
    }

    /// The state the user sees before adding an API key.
    @Test func rendersLinearBeforeItIsConnected() throws {
        let url = try Self.snapshot(
            LinearEmptyDetail(store: LinearStore()),
            size: CGSize(width: 700, height: 420),
            name: "linear-disconnected"
        )
        try Self.assertNotBlank(url, name: "linear-disconnected")
    }
}
