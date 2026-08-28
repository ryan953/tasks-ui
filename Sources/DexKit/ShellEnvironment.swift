import Foundation

/// Recovers the `PATH` a terminal would have.
///
/// A launched .app inherits only `/usr/bin:/bin:/usr/sbin:/sbin`. `dex` ships as a
/// Node script with a `#!/usr/bin/env node` shebang, so under that PATH it fails with
/// `env: node: No such file or directory` and the app looks empty for no visible
/// reason. Asking the login shell for its PATH once, at startup, fixes every
/// Node version manager (nvm, fnm, volta, mise, asdf) at the same time.
public enum ShellEnvironment {
    static let marker = "__DEX_UI_PATH__"

    /// Directories worth trying when the login shell cannot be consulted.
    public static let fallbackPaths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "\(NSHomeDirectory())/.local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
    ]

    /// Ask the user's login shell to print its PATH.
    ///
    /// The marker brackets the value because rc files are free to print banners.
    public static func loginPath() async -> String {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let script = #"command printf "\#(marker)%s\#(marker)" "$PATH""#
        guard
            let result = try? await ProcessRunner.run(
                executable: shell,
                arguments: ["-ilc", script],
                environment: nil,
                timeout: 8
            ),
            let extracted = extractPath(from: result.stdout)
        else {
            return fallbackPaths.joined(separator: ":")
        }
        return merge(extracted)
    }

    static func extractPath(from output: String) -> String? {
        let parts = output.components(separatedBy: marker)
        guard parts.count >= 3 else { return nil }
        let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// Keep the shell's ordering and append any fallback directory it missed.
    public static func merge(_ path: String) -> String {
        var seen = Set<String>()
        var ordered: [String] = []
        for dir in path.split(separator: ":").map(String.init) + fallbackPaths where !dir.isEmpty {
            if seen.insert(dir).inserted { ordered.append(dir) }
        }
        return ordered.joined(separator: ":")
    }

    /// An environment suitable for running `dex`.
    public static func environment(path: String) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = path
        env["NO_COLOR"] = "1"
        if env["HOME"] == nil { env["HOME"] = NSHomeDirectory() }
        return env
    }
}
