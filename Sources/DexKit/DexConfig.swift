import Foundation

/// Reads the bits of `~/.config/dex/dex.toml` the app needs.
///
/// Only the file-storage path matters: `dex` has no command to un-complete a task,
/// so that one operation edits `<storage>/tasks/<id>.json` in place, exactly as the
/// VS Code extension does. Everything else goes through the CLI.
public enum DexConfig {
    public static var configURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".config/dex/dex.toml")
    }

    public static let defaultStoragePath = "\(NSHomeDirectory())/.dex"

    /// Directory holding one JSON file per task.
    public static func tasksDirectory(storagePath: String? = nil) -> URL {
        let base = storagePath ?? resolveStoragePath()
        return URL(fileURLWithPath: expandTilde(base)).appendingPathComponent("tasks")
    }

    public static func resolveStoragePath() -> String {
        guard let toml = try? String(contentsOf: configURL, encoding: .utf8) else {
            return defaultStoragePath
        }
        return storagePath(fromTOML: toml) ?? defaultStoragePath
    }

    /// Pull `path` out of the `[storage.file]` table.
    ///
    /// A three-line hand parser rather than a TOML dependency: the app reads exactly
    /// one key, and `dex` owns the file otherwise.
    public static func storagePath(fromTOML toml: String) -> String? {
        var inFileTable = false
        for rawLine in toml.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") { continue }
            if line.hasPrefix("[") {
                inFileTable = line.hasPrefix("[storage.file]")
                continue
            }
            guard inFileTable, line.hasPrefix("path") else { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            // Trim a trailing `# comment` before unquoting.
            var value = String(line[line.index(after: eq)...])
            if let hash = value.firstIndex(of: "#") { value = String(value[..<hash]) }
            value = value.trimmingCharacters(in: .whitespaces)
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !value.isEmpty { return value }
        }
        return nil
    }

    public static func expandTilde(_ path: String) -> String {
        path.hasPrefix("~") ? (path as NSString).expandingTildeInPath : path
    }
}
