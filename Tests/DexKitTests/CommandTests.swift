import Testing
@testable import DexKit

@Suite("dex argument building")
struct CommandTests {
    @Test func listOmitsAllWhenHidingCompleted() {
        #expect(DexCommand.list(includeCompleted: false) == ["list", "--json"])
        #expect(DexCommand.list(includeCompleted: true) == ["list", "--json", "--all"])
    }

    @Test func createPassesEveryField() {
        let args = DexCommand.create(
            NewTask(
                description: "Add auth",
                context: "JWT",
                priority: 3,
                parentID: "parent1",
                blockedBy: ["a1", "b2"]
            )
        )
        #expect(args == [
            "create", "-d", "Add auth", "--context", "JWT",
            "-p", "3", "--parent", "parent1", "-b", "a1,b2",
        ])
    }

    @Test func createSkipsEmptyParentAndBlockers() {
        let args = DexCommand.create(NewTask(description: "d", context: "c", parentID: ""))
        #expect(!args.contains("--parent"))
        #expect(!args.contains("-b"))
    }

    /// Only the fields the user actually changed are sent, so an untouched field
    /// cannot be clobbered by a stale value from the form.
    @Test func editSendsOnlyChangedFields() {
        let args = DexCommand.edit("abc123", TaskEdit(priority: 2))
        #expect(args == ["edit", "abc123", "-p", "2"])
    }

    @Test func editJoinsBlockerLists() {
        let args = DexCommand.edit(
            "abc123",
            TaskEdit(addBlockers: ["x1", "y2"], removeBlockers: ["z3"])
        )
        #expect(args == ["edit", "abc123", "--add-blocker", "x1,y2", "--remove-blocker", "z3"])
    }

    @Test func anEmptyEditIsRecognised() {
        #expect(TaskEdit().isEmpty)
        #expect(!TaskEdit(description: "x").isEmpty)
        #expect(!TaskEdit(addBlockers: ["a"]).isEmpty)
    }

    /// An empty string is a real edit — it clears the field — and must survive.
    @Test func clearingContextIsNotTreatedAsNoChange() {
        #expect(!TaskEdit(context: "").isEmpty)
        #expect(DexCommand.edit("a", TaskEdit(context: "")) == ["edit", "a", "--context", ""])
    }

    @Test func deleteForcesPastThePrompt() {
        #expect(DexCommand.delete("abc") == ["delete", "abc", "-f"])
    }

    @Test func parsesTheIdOutOfCreateOutput() {
        #expect(DexClient.createdID(in: "Created task xk61y2t3\nsome detail") == "xk61y2t3")
        #expect(DexClient.createdID(in: "\u{001B}[32mCreated\u{001B}[0m task \u{001B}[1mabc123\u{001B}[0m") == "abc123")
        #expect(DexClient.createdID(in: "nothing here") == nil)
    }
}
