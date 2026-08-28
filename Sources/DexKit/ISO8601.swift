import Foundation

/// Shared ISO-8601 parsing/formatting for dex timestamps.
///
/// `ISO8601DateFormatter` is neither `Sendable` nor cheap to build, and decoding a
/// full task list parses three dates per task, so the instances are cached behind a
/// lock rather than allocated per call. Both are built together: creating them
/// separately, on first use of each entry point, once left the fallback formatter
/// nil and made every timestamp without fractional seconds parse as no date.
public enum ISO8601 {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: (fractional: ISO8601DateFormatter, plain: ISO8601DateFormatter)?

    private static func withFormatters<T>(
        _ body: (_ fractional: ISO8601DateFormatter, _ plain: ISO8601DateFormatter) -> T
    ) -> T {
        lock.lock()
        defer { lock.unlock() }
        let formatters: (fractional: ISO8601DateFormatter, plain: ISO8601DateFormatter)
        if let cached {
            formatters = cached
        } else {
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            fractional.timeZone = TimeZone(identifier: "UTC")
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            plain.timeZone = TimeZone(identifier: "UTC")
            formatters = (fractional, plain)
            cached = formatters
        }
        return body(formatters.fractional, formatters.plain)
    }

    /// `dex` writes fractional seconds, but tolerate a timestamp without them.
    public static func date(from raw: String) -> Date? {
        withFormatters { fractional, plain in
            fractional.date(from: raw) ?? plain.date(from: raw)
        }
    }

    /// Matches what `dex` writes, so a rewritten task file stays consistent.
    public static func string(from date: Date) -> String {
        withFormatters { fractional, _ in fractional.string(from: date) }
    }
}
