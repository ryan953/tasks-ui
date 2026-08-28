import Foundation
import LinearKit
import Observation

/// Which backend the window is showing.
enum Source: String, CaseIterable, Identifiable, Sendable {
    case dex
    case linear

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dex: "Dex"
        case .linear: "Linear"
        }
    }

    var symbol: String {
        switch self {
        case .dex: "checklist"
        case .linear: "circle.grid.2x2"
        }
    }
}

/// A `task://` link, parsed.
///
/// Kept as a plain value so the parsing is tested without a window: a link handler
/// that silently does nothing is hard to notice and harder to debug.
enum Route: Equatable {
    case dexTask(String)
    /// Either the UUID or the human identifier, e.g. "ABC-12".
    case linearIssue(String)
    case linearProject(String)

    /// Parse `task://dex/<id>`, `task://linear/<identifier>` and
    /// `task://linear/project/<id>`.
    ///
    /// A bare `task://<id>` is read as a dex task, which is the common case and what
    /// someone typing one by hand is most likely to mean.
    static func parse(_ url: URL) -> Route? {
        guard let scheme = url.scheme?.lowercased(), scheme == "task" || scheme == "dex" else {
            return nil
        }
        // "task://dex/abc" puts "dex" in host and "/abc" in path; "task:///abc"
        // leaves the host empty. Normalise both into one list of segments.
        var segments: [String] = []
        if let host = url.host, !host.isEmpty { segments.append(host) }
        segments += url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        segments = segments.compactMap { $0.removingPercentEncoding ?? $0 }

        guard let first = segments.first else { return nil }
        switch first.lowercased() {
        case "dex", "task", "tasks":
            guard segments.count >= 2 else { return nil }
            return .dexTask(segments[1])
        case "linear":
            guard segments.count >= 2 else { return nil }
            if segments[1].lowercased() == "project" || segments[1].lowercased() == "projects" {
                guard segments.count >= 3 else { return nil }
                return .linearProject(segments[2])
            }
            return .linearIssue(segments[1])
        default:
            // task://abc123 — treat the whole thing as a dex id.
            return .dexTask(first)
        }
    }
}

@MainActor
@Observable
final class AppModel {
    var source: Source {
        didSet { Preferences.source = source.rawValue }
    }

    let dex: TaskStore
    let linear: LinearStore

    /// Set when a link pointed at something that is not loaded.
    private(set) var routeFailure: String?

    init() {
        source = Preferences.source.flatMap(Source.init(rawValue:)) ?? .dex
        dex = TaskStore()
        linear = LinearStore()
    }

    init(dex: TaskStore, linear: LinearStore, source: Source = .dex) {
        self.source = source
        self.dex = dex
        self.linear = linear
    }

    func bootstrap() async {
        // dex resolves the login shell PATH; Linear needs the same PATH to find the
        // `linear` CLI, so it waits for that rather than resolving it twice.
        await dex.bootstrap()
        await linear.bootstrap(searchPath: dex.searchPath)
    }

    /// Follow a `task://` link. Returns false when nothing matched.
    @discardableResult
    func open(_ url: URL) -> Bool {
        guard let route = Route.parse(url) else {
            routeFailure = "“\(url.absoluteString)” is not a link this app understands."
            return false
        }
        switch route {
        case let .dexTask(id):
            guard dex.index[id] != nil else {
                routeFailure = "No dex task with ID \(id)."
                return false
            }
            source = .dex
            dex.selection = id
        case let .linearIssue(reference):
            let match = linear.issues.first {
                $0.id == reference || $0.identifier.caseInsensitiveCompare(reference) == .orderedSame
            }
            guard let match else {
                routeFailure = "No Linear issue \(reference) in your assigned list."
                return false
            }
            source = .linear
            linear.selection = .issue(match.id)
        case let .linearProject(reference):
            let match = linear.projects.first {
                $0.id == reference || $0.name.caseInsensitiveCompare(reference) == .orderedSame
            }
            guard let match else {
                routeFailure = "No Linear project \(reference) in your list."
                return false
            }
            source = .linear
            linear.selection = .project(match.id)
        }
        routeFailure = nil
        return true
    }

    func dismissRouteFailure() { routeFailure = nil }
}
