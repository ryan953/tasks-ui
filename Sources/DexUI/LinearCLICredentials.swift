import DexKit
import Foundation

/// Borrows the API key from the `linear` CLI, when it is installed and logged in.
///
/// The CLI keeps a personal API key of exactly the kind the GraphQL client needs,
/// so someone who has already run `linear auth login` does not have to create a
/// second key. `linear auth token` is used rather than reading
/// `~/.config/linear/credentials.toml` directly, because the CLI can also keep the
/// credential in the system keyring (`linear auth migrate`), and the file is then
/// either absent or stale.
struct LinearCLICredentials: Sendable {
    /// Runs `linear` with the given arguments and returns stdout. Injectable so the
    /// parsing and the failure paths are testable without the CLI installed.
    typealias Run = @Sendable ([String]) async -> String?

    let run: Run

    /// Build a provider backed by the real CLI, or nil when it is not installed.
    static func locate(searchPath: String) -> LinearCLICredentials? {
        guard let executable = ExecutableLocator.find(named: "linear", in: searchPath) else {
            return nil
        }
        let environment = ShellEnvironment.environment(path: searchPath)
        return LinearCLICredentials { arguments in
            guard let result = try? await ProcessRunner.run(
                executable: executable,
                arguments: arguments,
                environment: environment,
                timeout: 15
            ), result.status == 0 else { return nil }
            return result.stdout
        }
    }

    /// The API key for the CLI's default workspace, or nil when it is not logged in.
    func token() async -> String? {
        guard let output = await run(["auth", "token"]) else { return nil }
        return Self.parseToken(output)
    }

    /// The workspace the CLI is pointed at, for display.
    func workspace() async -> String? {
        guard let output = await run(["auth", "whoami"]) else { return nil }
        return Self.parseWorkspace(output)
    }

    /// The token is printed on its own line. Anything that is not a Linear key is
    /// rejected rather than passed to the API as a bearer token.
    static func parseToken(_ output: String) -> String? {
        for line in output.split(separator: "\n") {
            let candidate = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard candidate.hasPrefix("lin_"), candidate.count > 20 else { continue }
            return candidate
        }
        return nil
    }

    /// `linear auth whoami` prints `Workspace: <name>` on its first line.
    static func parseWorkspace(_ output: String) -> String? {
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("Workspace:") else { continue }
            let name = trimmed.dropFirst("Workspace:".count).trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? nil : name
        }
        return nil
    }
}
