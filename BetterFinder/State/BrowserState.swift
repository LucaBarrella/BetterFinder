import Foundation
import Observation
import Darwin

@Observable
final class BrowserState {

    // MARK: - State

    var currentURL: URL
    var items: [FileItem] = []
    var selectedItems: Set<FileItem.ID> = []
    var isLoading = false
    var searchQuery = ""
    var error: String?

    // MARK: - Terminal

    var showTerminal        = false
    var terminalHeight:   CGFloat = 220
    var terminalFontSize: CGFloat = 13
    var terminalSyncEnabled = true

    /// Last path component of the user's login shell, resolved once at init.
    let shellName: String

    /// Set by SwiftTermView when the terminal view is created.
    var terminalSendText:        ((String) -> Void)?
    var terminalChangeDirectory: ((URL) -> Void)?

    // MARK: - Private

    private var history: [URL]
    private var historyIndex: Int
    private let fileSystemService: FileSystemService
    private var watcher: DirectoryWatcher?
    private var watchedURL: URL?
    private var showHiddenCache = false

    // MARK: - Computed

    var canGoBack: Bool    { historyIndex > 0 }
    var canGoForward: Bool { historyIndex < history.count - 1 }

    var parentURL: URL? {
        let parent = currentURL.deletingLastPathComponent()
        return parent == currentURL ? nil : parent
    }

    var filteredItems: [FileItem] {
        guard !searchQuery.isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
    }

    var selectedFileItems: [FileItem] {
        items.filter { selectedItems.contains($0.id) }
    }

    // MARK: - Init

    init(url: URL, fileSystemService: FileSystemService) {
        self.currentURL = url
        self.fileSystemService = fileSystemService
        self.history = [url]
        self.historyIndex = 0

        // Resolve login shell name
        var name = "zsh"
        let uid = getuid()
        var buf = [CChar](repeating: 0, count: 1024)
        var pw  = passwd()
        var ptr: UnsafeMutablePointer<passwd>?
        if getpwuid_r(uid, &pw, &buf, buf.count, &ptr) == 0, let p = ptr {
            let s = String(cString: p.pointee.pw_shell)
            if !s.isEmpty { name = URL(fileURLWithPath: s).lastPathComponent }
        }
        self.shellName = name
    }

    // MARK: - Navigation

    func navigate(to url: URL) {
        guard url != currentURL else { return }
        if historyIndex < history.count - 1 {
            history = Array(history.prefix(historyIndex + 1))
        }
        history.append(url)
        historyIndex = history.count - 1
        currentURL = url
        selectedItems = []
        Task { await load(showHidden: showHiddenCache) }
    }

    func goBack() {
        guard canGoBack else { return }
        historyIndex -= 1
        currentURL = history[historyIndex]
        selectedItems = []
        Task { await load(showHidden: showHiddenCache) }
    }

    func goForward() {
        guard canGoForward else { return }
        historyIndex += 1
        currentURL = history[historyIndex]
        selectedItems = []
        Task { await load(showHidden: showHiddenCache) }
    }

    func goUp() {
        guard let parent = parentURL else { return }
        navigate(to: parent)
    }

    // MARK: - Loading

    /// Full load: shows the loading indicator. Used for navigation and initial load.
    func load(showHidden: Bool = false) async {
        showHiddenCache = showHidden
        isLoading = true
        error = nil

        do {
            let loaded = try await fileSystemService.children(of: currentURL, showHidden: showHidden)
            items = loaded
        } catch {
            self.error = error.localizedDescription
            items = []
        }

        isLoading = false
        updateWatcher()
    }

    /// Silent refresh: updates items WITHOUT touching isLoading.
    /// Used by the directory watcher so the UI doesn't flash "Loading…".
    private func refresh() async {
        guard !isLoading else { return }
        do {
            let loaded = try await fileSystemService.children(of: currentURL, showHidden: showHiddenCache)
            items = loaded
        } catch {
            // Ignore errors on background refresh
        }
    }

    // MARK: - Watcher

    private func updateWatcher() {
        guard currentURL != watchedURL else { return }
        watchedURL = currentURL

        watcher = DirectoryWatcher(url: currentURL) { [weak self] in
            guard let self else { return }
            Task { await self.refresh() }
        }
    }
}
