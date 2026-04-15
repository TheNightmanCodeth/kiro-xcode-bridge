import Foundation

/// Watches a directory for file changes and calls `onChange` on modifications.
///
/// Uses DispatchSource on Darwin. On Linux, `watch` and `stop` are no-ops —
/// steering rules are still loaded at startup, but hot-reload is unavailable.
final class FileWatcher: @unchecked Sendable {
    private let onChange: @Sendable () -> Void
#if canImport(Darwin)
    private var sources: [DispatchSourceFileSystemObject] = []
#endif

    init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
    }

    deinit { stop() }

    func watch(directory: URL) {
#if canImport(Darwin)
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.global(qos: .background)
        )
        source.setEventHandler { [weak self] in self?.onChange() }
        source.setCancelHandler { close(fd) }
        source.resume()
        sources.append(source)
#endif
    }

    func stop() {
#if canImport(Darwin)
        for source in sources { source.cancel() }
        sources.removeAll()
#endif
    }
}
