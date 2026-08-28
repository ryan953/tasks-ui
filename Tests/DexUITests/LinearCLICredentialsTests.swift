import Foundation
import Testing
@testable import DexUI

@Suite("Borrowing the linear CLI's key")
struct LinearCLICredentialsTests {
    @Test func readsTheTokenFromAuthToken() async {
        let creds = LinearCLICredentials { arguments in
            arguments == ["auth", "token"] ? "lin_api_abcdefghijklmnopqrstuvwxyz012345\n" : nil
        }
        #expect(await creds.token() == "lin_api_abcdefghijklmnopqrstuvwxyz012345")
    }

    /// The CLI prints a banner on some paths; the key is the line that looks like one.
    @Test func picksTheKeyOutOfSurroundingOutput() {
        let output = """
        Using workspace getsentry
        lin_api_abcdefghijklmnopqrstuvwxyz012345
        """
        #expect(LinearCLICredentials.parseToken(output) == "lin_api_abcdefghijklmnopqrstuvwxyz012345")
    }

    /// Anything that is not a Linear key must be rejected rather than sent to the
    /// API as a bearer token.
    @Test func rejectsOutputThatIsNotAKey() {
        #expect(LinearCLICredentials.parseToken("Error: not logged in") == nil)
        #expect(LinearCLICredentials.parseToken("") == nil)
        #expect(LinearCLICredentials.parseToken("lin_short") == nil)
    }

    @Test func returnsNothingWhenTheCommandFails() async {
        let creds = LinearCLICredentials { _ in nil }
        #expect(await creds.token() == nil)
        #expect(await creds.workspace() == nil)
    }

    @Test func readsTheWorkspaceFromWhoami() async {
        let creds = LinearCLICredentials { arguments in
            guard arguments == ["auth", "whoami"] else { return nil }
            return """
            Workspace: Sentry
              Slug: getsentry
              URL: https://linear.app/getsentry
            User: A Person
            """
        }
        #expect(await creds.workspace() == "Sentry")
    }

    @Test func handlesWhoamiWithoutAWorkspaceLine() {
        #expect(LinearCLICredentials.parseWorkspace("User: A Person") == nil)
        #expect(LinearCLICredentials.parseWorkspace("Workspace:") == nil)
    }

    /// Not having the CLI is the normal case, not an error.
    @Test func locatingIsNilWithoutTheCLI() {
        #expect(LinearCLICredentials.locate(searchPath: "/nonexistent") == nil)
    }
}
