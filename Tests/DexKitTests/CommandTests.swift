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
                name: "Add auth",
                details: "JWT",
                priority: 3,
                parentID: "parent1",
                blockedBy: ["a1", "b2"]
            )
        )
        #expect(
            args == [
                "create", "-n", "Add auth", "--description", "JWT",
                "-p", "3", "--parent", "parent1", "-b", "a1,b2",
            ])
    }

    /// A name starting with a dash must not be read as a flag, which is why the
    /// name goes through -n instead of the positional argument dex also accepts.
    @Test func createPassesTheNameAsAFlag() {
        let args = DexCommand.create(NewTask(name: "--not-a-flag", details: ""))
        #expect(args.starts(with: ["create", "-n", "--not-a-flag"]))
    }

    @Test func createSkipsEmptyParentAndBlockers() {
        let args = DexCommand.create(NewTask(name: "d", details: "c", parentID: ""))
        #expect(!args.contains("--parent"))
        #expect(!args.contains("-b"))
    }

    /// Only the fields the user actually changed are sent, so an untouched field
    /// cannot be clobbered by a stale value from the form.
    @Test func editSendsOnlyChangedFields() {
        let args = DexCommand.edit("abc123", TaskEdit(priority: 2))
        #expect(args == ["edit", "abc123", "-p", "2"])
    }

    @Test func editRenamesWithTheNameFlag() {
        #expect(DexCommand.edit("a", TaskEdit(name: "New name")) == ["edit", "a", "-n", "New name"])
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
        #expect(!TaskEdit(name: "x").isEmpty)
        #expect(!TaskEdit(addBlockers: ["a"]).isEmpty)
    }

    /// An empty string is a real edit — it clears the field — and must survive.
    @Test func clearingDescriptionIsNotTreatedAsNoChange() {
        #expect(!TaskEdit(details: "").isEmpty)
        #expect(DexCommand.edit("a", TaskEdit(details: "")) == ["edit", "a", "--description", ""])
    }

    /// dex refuses to complete a task linked to a GitHub issue unless told whether
    /// to attach a commit, and the app has no terminal to answer a prompt on.
    @Test func completeAlwaysDecidesAboutTheCommit() {
        #expect(DexCommand.complete("a", result: "done") == ["complete", "a", "--result", "done", "--no-commit"])
        #expect(
            DexCommand.complete("a", result: "done", commit: "abc123")
                == ["complete", "a", "--result", "done", "--commit", "abc123"])
        // A blank SHA is the same as none.
        #expect(DexCommand.complete("a", result: "done", commit: "  ").contains("--no-commit"))
    }

    /// Pressing Start on a task already running should not be an error.
    @Test func startForcesAReclaim() {
        #expect(DexCommand.start("abc") == ["start", "abc", "--force"])
    }

    @Test func detectsAnOldCLI() {
        #expect(DexClient.supportsModernCLI(help: "  -n, --name <text>   Task name"))
        #expect(!DexClient.supportsModernCLI(help: "  -d, --description <text>\n  --context <text>"))
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
