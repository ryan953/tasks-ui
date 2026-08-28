import Foundation

public struct ProcessResult: Sendable {
    public var status: Int32
    public var stdout: String
    public var stderr: String
}

public enum ProcessError: LocalizedError {
    case launchFailed(path: String, underlying: String)
    case timedOut(seconds: Double)

    public var errorDescription: String? {
        switch self {
        case let .launchFailed(path, underlying):
            "Could not launch \(path): \(underlying)"
        case let .timedOut(seconds):
            "Command timed out after \(Int(seconds))s"
        }
    }
}

public enum ProcessRunner {
    /// Run `executable` and wait for it to exit.
    ///
    /// stdout and stderr are drained on separate queues. Reading them one after the
    /// other deadlocks as soon as the child writes more than a pipe buffer, and
    /// `dex list --json --all` is comfortably larger than that.
    /// Waiting for a child blocks a thread, so the work runs on a Dispatch queue
    /// rather than inside a `Task`. Swift's cooperative pool has about one thread per
    /// core; blocking those starves every other async operation in the process,
    /// which is how a 0.2s command turned into a 20s timeout under a parallel test
    /// run on a small machine.
    public static func run(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil,
        timeout: Double = 30
    ) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try runSync(
                        executable: executable,
                        arguments: arguments,
                        environment: environment,
                        timeout: timeout
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func runSync(
        executable: String,
        arguments: [String],
        environment: [String: String]?,
        timeout: Double
    ) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw ProcessError.launchFailed(path: executable, underlying: error.localizedDescription)
        }

        let collector = OutputCollector()
        let group = DispatchGroup()
        for (handle, isStdout) in [(outPipe.fileHandleForReading, true), (errPipe.fileHandleForReading, false)] {
            DispatchQueue.global(qos: .userInitiated).async(group: group) {
                let data = handle.readDataToEndOfFile()
                collector.append(data, isStdout: isStdout)
            }
        }

        let deadline = DispatchTime.now() + timeout
        if group.wait(timeout: deadline) == .timedOut {
            process.terminate()
            _ = group.wait(timeout: .now() + 2)
            throw ProcessError.timedOut(seconds: timeout)
        }
        process.waitUntilExit()

        return ProcessResult(
            status: process.terminationStatus,
            stdout: collector.text(stdout: true),
            stderr: collector.text(stdout: false)
        )
    }
}

/// Lock-guarded buffers, because the two reader queues finish in any order.
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var out = Data()
    private var err = Data()

    func append(_ data: Data, isStdout: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if isStdout { out.append(data) } else { err.append(data) }
    }

    func text(stdout: Bool) -> String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: stdout ? out : err, as: UTF8.self)
    }
}
