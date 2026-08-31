import Foundation

/// Watches the dex tasks directory and reports that something changed.
///
/// Uses FSEvents with file-level events so it sees a task file rewritten in place,
/// not only files added or removed from the directory — the CLI and Claude Code edit
/// tasks while the app is open, and the sidebar should follow along.
public final class TaskWatcher: @unchecked Sendable {
    private let directory: URL
    private let debounce: TimeInterval
    private let queue = DispatchQueue(label: "com.ryan953.dex-ui.watcher")
    private var stream: FSEventStreamRef?
    private var pending: DispatchWorkItem?
    private let onChange: @Sendable () -> Void

    public init(directory: URL, debounce: TimeInterval = 0.35, onChange: @escaping @Sendable () -> Void) {
        self.directory = directory
        self.debounce = debounce
        self.onChange = onChange
    }

    deinit { stop() }

    public func start() {
        queue.async { [self] in
            guard stream == nil else { return }
            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil,
                release: nil,
                copyDescription: nil
            )
            let flags = FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
            )
            guard
                let created = FSEventStreamCreate(
                    kCFAllocatorDefault,
                    { _, info, _, _, _, _ in
                        guard let info else { return }
                        Unmanaged<TaskWatcher>.fromOpaque(info).takeUnretainedValue().schedule()
                    },
                    &context,
                    [directory.path] as CFArray,
                    FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                    debounce / 2,
                    flags
                )
            else { return }
            FSEventStreamSetDispatchQueue(created, queue)
            FSEventStreamStart(created)
            stream = created
        }
    }

    public func stop() {
        queue.sync {
            pending?.cancel()
            pending = nil
            guard let stream else { return }
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    /// Collapse a burst of writes — a single `dex edit` touches two files when it
    /// syncs a blocking relationship — into one refresh.
    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [onChange] in onChange() }
        pending = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }
}
