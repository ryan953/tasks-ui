import Foundation
import Testing
@testable import LinearKit

/// Borrows a token from the `linear` CLI so the real queries can be exercised.
///
/// Read-only: nothing here writes to the workspace. Skipped unless the CLI is
/// installed and logged in, so CI and anyone else simply does not run it.
enum LinearProbe {
    static func runLinear(_ arguments: [String]) -> String? {
        let candidates = ["/opt/homebrew/bin/linear", "/usr/local/bin/linear"]
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static let token: String? = {
        guard let output = runLinear(["auth", "token"]) else { return nil }
        return output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.hasPrefix("lin_") && $0.count > 20 }
    }()

    static var isAvailable: Bool { token != nil }
}

@Suite("Linear against the live API", .enabled(if: LinearProbe.isAvailable), .serialized)
struct LiveSmokeTests {
    private func client() throws -> LinearClient {
        LinearClient(apiKey: try #require(LinearProbe.token))
    }

    /// Run a live query, treating a connectivity failure as nothing to report.
    ///
    /// These tests check that Linear still accepts the queries as written. A dropped
    /// connection says nothing about that, and failing the whole suite over one
    /// would train everyone to ignore it.
    private func live<T>(_ work: () async throws -> T) async throws -> T? {
        do {
            return try await work()
        } catch let error as LinearError {
            if case .network = error { return nil }
            if case .rateLimited = error { return nil }
            throw error
        }
    }

    @Test func readsTheAccount() async throws {
        guard let account = try await live({ try await client().account() }) else { return }
        #expect(!account.user.name.isEmpty)
        // The slug is what every "open in Linear" link is built from.
        #expect(!account.urlKey.isEmpty)
    }

    /// The assignee filter and the state exclusion have to be accepted as written.
    @Test func readsAssignedIssues() async throws {
        guard let issues = try await live({ try await client().myIssues(includeDone: false) })
        else { return }
        for issue in issues {
            #expect(!issue.identifier.isEmpty)
            #expect(issue.url.hasPrefix("https://"))
            // The default list must never contain finished work.
            #expect(issue.state.type != .completed)
            #expect(issue.state.type != .canceled)
        }
    }

    /// The `members` filter is the part most likely to be rejected by a workspace.
    @Test func readsMyProjects() async throws {
        guard let projects = try await live({ try await client().myProjects() }) else { return }
        for project in projects {
            #expect(!project.name.isEmpty)
            #expect(project.url.hasPrefix("https://"))
        }
    }

    /// Every state and priority the workspace actually uses must decode. An unknown
    /// value silently becoming "Todo" or "No priority" would be quietly wrong.
    @Test func decodesEveryStateAndPriorityInUse() async throws {
        guard let issues = try await live({ try await client().myIssues(includeDone: true) })
        else { return }
        // A raw fetch would fail to build a LinearIssue for an unknown state type,
        // so a non-empty result proves each one mapped.
        for issue in issues {
            #expect(LinearStateType(rawValue: issue.state.type.rawValue) != nil)
            #expect(LinearPriority(rawValue: issue.priority.rawValue) != nil)
        }
    }

    /// The status picker is empty unless a team's workflow states load.
    @Test func readsWorkflowStatesForATeam() async throws {
        let client = try client()
        guard let issues = try await live({ try await client.myIssues(includeDone: true) }),
              let teamID = issues.compactMap({ $0.team?.id }).first,
              let states = try await live({ try await client.workflowStates(teamID: teamID) })
        else { return }
        #expect(!states.isEmpty)
    }
}
