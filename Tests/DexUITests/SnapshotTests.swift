import AppKit
import DexKit
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
            DexTask(id: "4puhcjd4", description: "Ship the macOS task viewer", priority: 1,
                    createdAt: now, updatedAt: now, children: ["b6n79rg4", "lxs7u9bc", "e3m27w78"]),
            DexTask(id: "b6n79rg4", parentID: "4puhcjd4", description: "Read tasks from the dex CLI",
                    context: "Shell out to `dex list --json --all`.", priority: 1, completed: true,
                    result: "Reads through the CLI so dex stays the only writer.",
                    createdAt: now, updatedAt: now, completedAt: now),
            DexTask(id: "lxs7u9bc", parentID: "4puhcjd4",
                    description: "Edit dependencies from the detail pane",
                    context: """
                    Requirements:
                      - add and remove blockers
                      - reparent a task
                      - never offer a link that would make a cycle
                    Done when: the pickers refuse anything dex would reject.
                    """,
                    priority: 2, createdAt: now, updatedAt: now,
                    blockedBy: ["b6n79rg4"], blocks: ["e3m27w78"]),
            DexTask(id: "e3m27w78", parentID: "4puhcjd4", description: "Attach the build to a GitHub release",
                    context: "Tag push builds a universal .app and uploads the zip.",
                    priority: 3, createdAt: now, updatedAt: now, blockedBy: ["lxs7u9bc"]),
            DexTask(id: "wbbnaadg", description: "Write the README", priority: 4,
                    createdAt: now, updatedAt: now),
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
        let framed = view
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
                let packed = UInt32(color.redComponent * 255) << 16
                    | UInt32(color.greenComponent * 255) << 8
                    | UInt32(color.blueComponent * 255)
                seen.insert(packed)
            }
        }
        #expect(seen.count > 3, "\(name) looks blank — only \(seen.count) distinct colours")
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
            CompleteSheet(task: task) { _ in },
            size: CGSize(width: 480, height: 340),
            name: "complete"
        )
        try Self.assertNotBlank(url, name: "complete")
    }

    @Test func rendersSettings() throws {
        let store = TaskStore(tasks: Self.fixture())
        let url = try Self.snapshot(
            SettingsView(store: store),
            size: CGSize(width: 480, height: 420),
            name: "settings"
        )
        try Self.assertNotBlank(url, name: "settings")
    }
}
