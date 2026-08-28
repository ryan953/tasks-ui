import Foundation

public enum DexError: LocalizedError {
    case binaryNotFound(searchPath: String)
    case commandFailed(arguments: [String], status: Int32, stderr: String)
    case badJSON(underlying: String)
    case taskFileMissing(URL)
    case taskNotFound(String)
    case cliTooOld

    public var errorDescription: String? {
        switch self {
        case let .binaryNotFound(searchPath):
            """
            Could not find the `dex` executable.
            Searched: \(searchPath)
            Set an explicit path in Settings (⌘,).
            """
        case let .commandFailed(arguments, status, stderr):
            {
                let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let command = "dex " + arguments.joined(separator: " ")
                return detail.isEmpty
                    ? "`\(command)` exited with code \(status)."
                    : "`\(command)` failed:\n\(detail)"
            }()
        case let .badJSON(underlying):
            "Could not read the response from dex: \(underlying)"
        case let .taskFileMissing(url):
            "No task store at \(url.path)"
        case let .taskNotFound(id):
            "Task \(id) is not in the task store."
        case .cliTooOld:
            """
            This app needs dex 0.16 or later, and the dex on your PATH is older.
            Upgrade with:

                npm install -g @zeeg/dex
            """
        }
    }
}

/// Talks to the `dex` CLI.
///
/// Reads and writes both go through the CLI so that `dex` stays the single writer:
/// it keeps `blockedBy`/`blocks` in sync on both tasks and rejects dependency
/// cycles. The one exception is ``uncomplete(id:)`` — see that method.
public actor DexClient {
    public private(set) var binaryPath: String?
    public private(set) var searchPath: String
    private var environment: [String: String]
    /// Overrides where dex keeps its tasks. Empty means "whatever dex.toml says".
    private var storagePath: String?

    public init(
        binaryPath: String? = nil,
        searchPath: String = "",
        environment: [String: String] = [:],
        storagePath: String? = nil
    ) {
        self.binaryPath = binaryPath
        self.searchPath = searchPath
        self.environment = environment
        self.storagePath = storagePath
    }

    public func setStoragePath(_ path: String?) {
        let trimmed = path?.trimmingCharacters(in: .whitespaces)
        storagePath = (trimmed?.isEmpty ?? true) ? nil : DexConfig.expandTilde(trimmed!)
    }

    /// The store directory, watched for outside changes.
    public func storageDirectory() -> URL {
        DexConfig.storageDirectory(storagePath: storagePath)
    }

    /// Where task JSON lives, for the one operation that edits it directly.
    public func tasksFile() -> URL {
        DexConfig.tasksFile(storagePath: storagePath)
    }

    /// Resolve the login-shell PATH and locate the binary. Call once at launch and
    /// again when the user changes the path in Settings.
    @discardableResult
    public func bootstrap(override: String?) async -> String? {
        let path = await ShellEnvironment.loginPath()
        searchPath = path
        environment = ShellEnvironment.environment(path: path)
        binaryPath = DexLocator.resolve(override: override, path: path)
        return binaryPath
    }

    public var isReady: Bool { binaryPath != nil }

    // MARK: - Reads

    public func list(includeCompleted: Bool = true) async throws -> [DexTask] {
        let output = try await run(DexCommand.list(includeCompleted: includeCompleted), timeout: 30)
        return try decode([DexTask].self, from: output)
    }

    public func show(_ id: String) async throws -> DexTask {
        let output = try await run(DexCommand.show(id))
        return try decode(DexTask.self, from: output)
    }

    // MARK: - Writes

    /// Create a task and return its new id.
    @discardableResult
    public func create(_ task: NewTask) async throws -> String? {
        let output = try await run(DexCommand.create(task))
        return Self.createdID(in: output)
    }

    public func edit(_ id: String, _ edit: TaskEdit) async throws {
        guard !edit.isEmpty else { return }
        _ = try await run(DexCommand.edit(id, edit))
    }

    public func complete(_ id: String, result: String, commit: String? = nil) async throws {
        _ = try await run(DexCommand.complete(id, result: result, commit: commit))
    }

    public func delete(_ id: String) async throws {
        _ = try await run(DexCommand.delete(id))
    }

    public func start(_ id: String) async throws {
        _ = try await run(DexCommand.start(id))
    }

    public func archive(_ id: String) async throws {
        _ = try await run(DexCommand.archive(id))
    }

    /// Whether the located binary speaks the 0.16 CLI.
    ///
    /// Checked once at startup so an older dex produces a plain "upgrade" message
    /// rather than a confusing `Unknown option: --description` on the first edit.
    public func isSupportedVersion() async -> Bool {
        guard let output = try? await run(["create", "--help"], timeout: 10) else { return false }
        return Self.supportsModernCLI(help: output)
    }

    /// dex 0.16 renamed the text flags; `--name` on `create` is the marker.
    public static func supportsModernCLI(help: String) -> Bool {
        let plain = stripANSI(help)
        return plain.contains("--name")
    }

    /// Reopen a completed task.
    ///
    /// `dex` has no un-complete command, so this rewrites the task's JSON file the
    /// same way the VS Code extension does. It only clears `completed`,
    /// `completed_at` and `result`; no relationship fields are touched, so nothing
    /// `dex` keeps bidirectional can drift. `started_at` is deliberately left alone,
    /// so a task that had been started returns to in-progress rather than looking
    /// as though the work never happened.
    public func uncomplete(_ id: String, tasksFile file: URL? = nil) throws {
        let url = file ?? tasksFile()
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            throw DexError.taskFileMissing(url)
        }

        // Rewrite only the one line. Every other line is passed through byte for
        // byte, so a field this app does not model cannot be dropped, and a task it
        // failed to parse cannot be lost.
        var lines = contents.components(separatedBy: "\n")
        var found = false
        for (offset, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  var object = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) as? [String: Any],
                  object["id"] as? String == id
            else { continue }

            object["completed"] = false
            object["completed_at"] = NSNull()
            object["result"] = NSNull()
            object["updated_at"] = ISO8601.string(from: Date())
            let data = try JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
            lines[offset] = String(decoding: data, as: UTF8.self)
            found = true
            break
        }

        guard found else { throw DexError.taskNotFound(id) }
        try Data(lines.joined(separator: "\n").utf8).write(to: url, options: .atomic)
    }

    // MARK: - Plumbing

    @discardableResult
    private func run(_ arguments: [String], timeout: Double = 20) async throws -> String {
        guard let binaryPath else { throw DexError.binaryNotFound(searchPath: searchPath) }
        // `--storage-path` is a global flag dex strips from anywhere in argv.
        let arguments = storagePath.map { ["--storage-path", $0] + arguments } ?? arguments
        let result = try await ProcessRunner.run(
            executable: binaryPath,
            arguments: arguments,
            environment: environment,
            timeout: timeout
        )
        guard result.status == 0 else {
            throw DexError.commandFailed(
                arguments: arguments,
                status: result.status,
                stderr: result.stderr.isEmpty ? result.stdout : result.stderr
            )
        }
        return result.stdout
    }

    private func decode<T: Decodable>(_ type: T.Type, from output: String) throws -> T {
        guard let data = output.data(using: .utf8) else {
            throw DexError.badJSON(underlying: "output was not UTF-8")
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw DexError.badJSON(underlying: error.localizedDescription)
        }
    }

    /// Pull the id out of `Created task <id>`, tolerating ANSI colour codes.
    public static func createdID(in output: String) -> String? {
        let plain = stripANSI(output)
        guard let range = plain.range(of: #"Created task ([A-Za-z0-9_-]+)"#, options: .regularExpression) else {
            return nil
        }
        return plain[range].split(separator: " ").last.map(String.init)
    }

    public static func stripANSI(_ text: String) -> String {
        text.replacingOccurrences(
            of: "\u{001B}\\[[0-9;]*[a-zA-Z]",
            with: "",
            options: .regularExpression
        )
    }
}
