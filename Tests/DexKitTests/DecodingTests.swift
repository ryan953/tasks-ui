import Foundation
import Testing
@testable import DexKit

@Suite("Decoding dex JSON")
struct DecodingTests {
    /// A real record copied from ~/.dex/tasks.
    static let sample = """
    {
      "id": "b6n79rg4",
      "parent_id": "4puhcjd4",
      "description": "Register commands and keybindings",
      "context": "Command palette integration",
      "priority": 2,
      "completed": true,
      "result": "15 commands registered",
      "metadata": null,
      "created_at": "2026-05-14T03:20:36.305Z",
      "updated_at": "2026-05-14T03:26:20.514Z",
      "completed_at": "2026-05-14T03:26:20.514Z",
      "blockedBy": [],
      "blocks": [],
      "children": []
    }
    """

    @Test func decodesEveryField() throws {
        let task = try JSONDecoder().decode(DexTask.self, from: Data(Self.sample.utf8))
        #expect(task.id == "b6n79rg4")
        #expect(task.parentID == "4puhcjd4")
        #expect(task.description == "Register commands and keybindings")
        #expect(task.priority == 2)
        #expect(task.completed)
        #expect(task.result == "15 commands registered")
        #expect(task.createdAt != nil)
        #expect(task.completedAt != nil)
    }

    /// Older records predate some fields; a missing key must not fail the whole list.
    @Test func toleratesMissingOptionalFields() throws {
        let minimal = """
        {"id":"abc","description":"Just this","created_at":"2026-01-01T00:00:00.000Z","updated_at":"2026-01-01T00:00:00.000Z","context":""}
        """
        let task = try JSONDecoder().decode(DexTask.self, from: Data(minimal.utf8))
        #expect(task.priority == 1)
        #expect(task.completed == false)
        #expect(task.blockedBy.isEmpty)
        #expect(task.parentID == nil)
    }

    @Test func decodesCommitMetadata() throws {
        let withCommit = """
        {"id":"a","description":"d","context":"","created_at":"2026-01-01T00:00:00.000Z",
         "updated_at":"2026-01-01T00:00:00.000Z","metadata":{"commit":{"sha":"deadbeef","branch":"main"}}}
        """
        let task = try JSONDecoder().decode(DexTask.self, from: Data(withCommit.utf8))
        #expect(task.metadata?.commit?.sha == "deadbeef")
        #expect(task.metadata?.commit?.branch == "main")
    }

    @Test func parsesTimestampsWithAndWithoutFractionalSeconds() {
        #expect(ISO8601.date(from: "2026-05-14T03:20:36.305Z") != nil)
        #expect(ISO8601.date(from: "2026-05-14T03:20:36Z") != nil)
        #expect(ISO8601.date(from: "not a date") == nil)
    }

    /// Formatting first must not leave the no-fraction parser uninitialised.
    @Test func formattingFirstDoesNotBreakParsing() throws {
        _ = ISO8601.string(from: Date())
        #expect(ISO8601.date(from: "2026-05-14T03:20:36Z") != nil)
        #expect(ISO8601.date(from: "2026-05-14T03:20:36.305Z") != nil)
    }

    @Test func roundTripsATimestamp() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let text = ISO8601.string(from: now)
        let parsed = try #require(ISO8601.date(from: text))
        #expect(abs(parsed.timeIntervalSince(now)) < 0.01)
    }
}
