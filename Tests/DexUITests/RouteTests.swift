import Foundation
import Testing
@testable import DexUI

@Suite("task:// links")
struct RouteTests {
    private func parse(_ string: String) -> Route? {
        URL(string: string).flatMap(Route.parse)
    }

    @Test func parsesADexTask() {
        #expect(parse("task://dex/abcfef") == .dexTask("abcfef"))
        #expect(parse("task://dex/4cmymvmd") == .dexTask("4cmymvmd"))
    }

    /// A bare id is the shape someone is most likely to type by hand.
    @Test func treatsABareIdAsADexTask() {
        #expect(parse("task://abcfef") == .dexTask("abcfef"))
    }

    @Test func parsesALinearIssue() {
        #expect(parse("task://linear/ABC-12") == .linearIssue("ABC-12"))
    }

    @Test func parsesALinearProject() {
        #expect(parse("task://linear/project/launch-abc") == .linearProject("launch-abc"))
        #expect(parse("task://linear/projects/launch-abc") == .linearProject("launch-abc"))
    }

    /// The dex scheme is registered too, so older links keep working.
    @Test func acceptsTheDexScheme() {
        #expect(parse("dex://dex/abc") == .dexTask("abc"))
        #expect(parse("dex://abc") == .dexTask("abc"))
    }

    @Test func isCaseInsensitiveAboutTheSourceSegment() {
        #expect(parse("task://DEX/abc") == .dexTask("abc"))
        #expect(parse("task://Linear/ABC-1") == .linearIssue("ABC-1"))
    }

    @Test func decodesPercentEscapes() {
        #expect(parse("task://linear/project/my%20project") == .linearProject("my project"))
    }

    @Test func rejectsOtherSchemes() {
        #expect(parse("https://example.com/dex/abc") == nil)
        #expect(parse("file:///tmp/abc") == nil)
    }

    @Test func rejectsLinksWithNothingToOpen() {
        #expect(parse("task://dex") == nil)
        #expect(parse("task://linear") == nil)
        #expect(parse("task://linear/project") == nil)
        #expect(parse("task://") == nil)
    }
}

@MainActor
@Suite("Following a link")
struct RouteOpeningTests {
    private func model() -> AppModel {
        AppModel(
            dex: TaskStore(tasks: SnapshotTests.fixture()),
            linear: LinearStore(
                issues: SnapshotTests.linearIssues(),
                projects: SnapshotTests.linearProjects()
            )
        )
    }

    @Test func selectsADexTaskAndSwitchesSource() throws {
        let model = model()
        model.source = .linear
        #expect(model.open(try #require(URL(string: "task://dex/lxs7u9bc"))))
        #expect(model.source == .dex)
        #expect(model.dex.selection == "lxs7u9bc")
    }

    @Test func selectsALinearIssueByItsIdentifier() throws {
        let model = model()
        #expect(model.open(try #require(URL(string: "task://linear/ABC-12"))))
        #expect(model.source == .linear)
        #expect(model.linear.selection == .issue("uuid-1"))
    }

    /// The UUID works as well as the human key, so a link copied from the API opens.
    @Test func selectsALinearIssueByItsUUID() throws {
        let model = model()
        #expect(model.open(try #require(URL(string: "task://linear/uuid-1"))))
        #expect(model.linear.selection == .issue("uuid-1"))
    }

    @Test func selectsALinearProject() throws {
        let model = model()
        #expect(model.open(try #require(URL(string: "task://linear/project/proj-1"))))
        #expect(model.linear.selection == .project("proj-1"))
    }

    /// A link to something that is not loaded must say so rather than doing nothing.
    @Test func reportsAnUnknownTarget() throws {
        let model = model()
        #expect(!model.open(try #require(URL(string: "task://dex/nosuchid"))))
        #expect(model.routeFailure?.contains("nosuchid") == true)
        #expect(model.dex.selection == nil)
    }

    @Test func reportsAnUnparseableLink() throws {
        let model = model()
        #expect(!model.open(try #require(URL(string: "https://example.com"))))
        #expect(model.routeFailure != nil)
    }

    /// A failure must not stick around after a link that works.
    @Test func clearsTheFailureOnASuccessfulOpen() throws {
        let model = model()
        _ = model.open(try #require(URL(string: "task://dex/nosuchid")))
        #expect(model.routeFailure != nil)
        _ = model.open(try #require(URL(string: "task://dex/lxs7u9bc")))
        #expect(model.routeFailure == nil)
    }
}
