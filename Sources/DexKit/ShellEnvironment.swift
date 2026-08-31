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

    /// The resolved PATH, computed once per process.
    ///
    /// Starting a login shell is expensive — it runs the full profile — and the
    /// answer cannot change while the app is open, so every caller shares one
    /// result instead of spawning another shell.
    private static let cache = PathCache()

    public static func loginPath() async -> String {
        await cache.value(compute: resolveLoginPath)
    }

    /// Ask the user's login shell to print its PATH.
    ///
    /// The marker brackets the value because rc files are free to print banners.
    static func resolveLoginPath() async -> String {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let script = #"command printf "\#(marker)%s\#(marker)" "$PATH""#
        let result = try? await ProcessRunner.run(
            executable: shell,
            arguments: ["-ilc", script],
            environment: nil,
            timeout: 8
        )
        let extracted = result.flatMap { extractPath(from: $0.stdout) }
        return merge(extracted ?? "")
    }

    static func extractPath(from output: String) -> String? {
        let parts = output.components(separatedBy: marker)
        guard parts.count >= 3 else { return nil }
        let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// Keep the shell's ordering, then anything already in this process's own PATH,
    /// then the fallbacks.
    ///
    /// The inherited PATH matters because `zsh -l` runs `/etc/zprofile`, which on
    /// macOS rebuilds PATH from `/etc/paths` via `path_helper`. That drops entries
    /// the current process was given — a Node installed by a CI action, or a
    /// directory exported before launching the app from a terminal — so the login
    /// shell's answer alone can be narrower than what we started with.
    public static func merge(_ path: String, inherited: String? = nil) -> String {
        let inheritedPath = inherited ?? ProcessInfo.processInfo.environment["PATH"] ?? ""
        var seen = Set<String>()
        var ordered: [String] = []
        let candidates =
            path.split(separator: ":").map(String.init)
            + inheritedPath.split(separator: ":").map(String.init)
            + fallbackPaths
        for dir in candidates where !dir.isEmpty {
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

/// Computes the PATH at most once, even when several callers ask at the same time.
private actor PathCache {
    private var resolved: String?
    private var inFlight: Task<String, Never>?

    func value(compute: @escaping @Sendable () async -> String) async -> String {
        if let resolved { return resolved }
        if let inFlight { return await inFlight.value }
        let task = Task { await compute() }
        inFlight = task
        let value = await task.value
        resolved = value
        inFlight = nil
        return value
    }
}
