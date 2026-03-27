import Foundation

/// Watches a single directory for direct-child changes using a kqueue/DispatchSource.
/// Unlike FSEvents, this does NOT watch subdirectories — it fires only when files
/// are added, removed, or renamed inside the watched directory itself.
final class DirectoryWatcher: @unchecked Sendable {

    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var debounceTask: Task<Void, Never>?
    private let onChange: @Sendable () -> Void

    init(url: URL, onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        start(path: url.path(percentEncoded: false))
    }

    deinit {
        debounceTask?.cancel()
        source?.cancel()
        // fd is closed in the cancel handler
    }

    // MARK: - Private

    private func start(path: String) {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        fd = descriptor

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: .write,          // fires when directory contents change
            queue: .main
        )

        src.setEventHandler { [weak self] in
            self?.scheduleRefresh()
        }

        src.setCancelHandler {
            close(descriptor)
        }

        source = src
        src.resume()
    }

    private func scheduleRefresh() {
        // Debounce: wait 0.8 s after the last event before calling back.
        // This prevents a burst of kqueue events from causing many rapid reloads.
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .milliseconds(800))
            } catch {
                return  // task was cancelled — a newer event is pending
            }
            self.onChange()
        }
    }
}
