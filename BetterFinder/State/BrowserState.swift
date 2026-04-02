import Foundation
import Observation
import Darwin

@Observable
final class BrowserState {

    // MARK: - State

    var currentURL: URL
    var items: [FileItem] = []
    var selectedItems: Set<FileItem.ID> = []
    /// URL of the first selected item — set directly from the table's selection
    /// callback so it never goes stale when items are reloaded with new UUIDs.
    var lastSelectedURL: URL? = nil
    var isLoading = false
    var searchQuery = ""
    var searchOptions = SearchOptions()
    var searchResults: [FileItem] = []
    var isSearching = false
    var error: String?

    // MARK: - Sort
    var sortColumnID: String = "name"   // matches NSTableColumn identifier
    var sortAscending: Bool  = true

    private var searchTask: Task<Void, Never>?

    // MARK: - Terminal

    var showTerminal        = false
    var terminalHeight:   CGFloat = 220
    var terminalFontSize: CGFloat = 13
    var terminalSyncEnabled = true

    let shellName: String
    var terminalCurrentURL: URL?
    var terminalSendText:        ((String) -> Void)?
    var terminalChangeDirectory: ((URL) -> Void)?

    /// Set by FileTableView.Coordinator. Triggers inline rename on the currently selected row.
    var triggerInlineRename: (() -> Void)?

    /// Called by AppState to track recent folders whenever the user navigates.
    var onNavigate: ((URL) -> Void)?

    // MARK: - Private

    /// Each history entry stores the URL that was active and — optionally — the search
    /// state that was active at that point. When the user navigates back into an entry
    /// that carries a search snapshot, the search UI is restored without re-running the query.
    private struct HistoryEntry {
        let url: URL
        var searchSnapshot: SearchSnapshot?

        struct SearchSnapshot {
            let query:   String
            let options: SearchOptions
            let results: [FileItem]   // cached — no network round-trip on back/forward
        }
    }

    private var history: [HistoryEntry]
    private var historyIndex: Int
    private let fileSystemService: FileSystemService
    private let volumeService: VolumeServiceProtocol?
    private var watcher: DirectoryWatcher?
    private var watchedURL: URL?
    private var showHiddenCache = false
    private var currentVolumeIsEjectableCache: Bool?
    private var volumeEjectableRefreshTask: Task<Void, Never>?

    // MARK: - Computed

    var canGoBack:    Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex < history.count - 1 }

    var parentURL: URL? {
        let parent = currentURL.deletingLastPathComponent()
        return parent == currentURL ? nil : parent
    }

    var currentVolumeURL: URL? {
        volumeService?.volumeMountPoint(for: currentURL)
    }

    var currentVolumeIsEjectable: Bool {
        currentVolumeIsEjectableCache ?? false
    }

    func refreshVolumeEjectableCache() {
        volumeEjectableRefreshTask?.cancel()
        guard let volumeService, let volumeURL = currentVolumeURL else {
            currentVolumeIsEjectableCache = false
            return
        }
        let capturedVolumeURL = volumeURL
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            let isEjectable = await volumeService.isEjectableVolumeAsync(capturedVolumeURL)
            await MainActor.run {
                guard let self, !Task.isCancelled,
                      self.currentVolumeURL == capturedVolumeURL else { return }
                self.currentVolumeIsEjectableCache = isEjectable
            }
        }
        volumeEjectableRefreshTask = task
    }

    var filteredItems: [FileItem] {
        let text = searchQuery.trimmingCharacters(in: .whitespaces)
        let hasFilter = !text.isEmpty || searchOptions.fileKind != .any
        guard hasFilter else { return items }

        switch searchOptions.scope {
        case .currentFolder:
            return items.filter { localMatches($0, text: text) }
        case .recursive, .homeDirectory, .entireDisk:
            return searchResults
        }
    }

    private func localMatches(_ item: FileItem, text: String) -> Bool {
        if searchOptions.fileKind != .any {
            let kindOK: Bool
            switch searchOptions.fileKind {
            case .any:    kindOK = true
            case .folder: kindOK = item.isDirectory
            case .file:   kindOK = !item.isDirectory
            default:
                kindOK = searchOptions.fileKind.extensions
                    .contains(item.url.pathExtension.lowercased())
            }
            guard kindOK else { return false }
        }
        guard !text.isEmpty else { return true }
        return SearchService.textMatches(item.name, query: text, mode: searchOptions.matchMode)
    }

    var selectedFileItems: [FileItem] {
        items.filter { selectedItems.contains($0.id) }
    }

    // MARK: - Init

    init(url: URL, fileSystemService: FileSystemService, volumeService: VolumeServiceProtocol? = nil) {
        self.currentURL = url
        self.fileSystemService = fileSystemService
        self.volumeService = volumeService
        self.history = [HistoryEntry(url: url)]
        self.historyIndex = 0
 
        self.currentVolumeIsEjectableCache = nil
 
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
        refreshVolumeEjectableCache()
    }

    // MARK: - Navigation

    func navigate(to url: URL) {
        guard url != currentURL else { return }

        // Snapshot the current search state into the current history entry before leaving
        snapshotSearchIntoCurrentEntry()

        // Truncate forward history
        if historyIndex < history.count - 1 {
            history = Array(history.prefix(historyIndex + 1))
        }

        history.append(HistoryEntry(url: url))
        historyIndex = history.count - 1
        currentURL = url
        selectedItems = []
        lastSelectedURL = nil
        currentVolumeIsEjectableCache = nil
        refreshVolumeEjectableCache()

        // Clear search when navigating to a new location
        clearSearch()
        Task { await load(showHidden: showHiddenCache) }
        onNavigate?(url)
    }

    func goBack() {
        guard canGoBack else { return }
        snapshotSearchIntoCurrentEntry()
        historyIndex -= 1
        restoreEntry(history[historyIndex])
    }

    func goForward() {
        guard canGoForward else { return }
        snapshotSearchIntoCurrentEntry()
        historyIndex += 1
        restoreEntry(history[historyIndex])
    }

    func goUp() {
        guard let parent = parentURL else { return }
        navigate(to: parent)
    }

    // MARK: - History helpers

    /// Captures the current search state into the active history entry so it can be
    /// restored when the user navigates back.
    private func snapshotSearchIntoCurrentEntry() {
        guard historyIndex < history.count else { return }
        let hasSearch = !searchQuery.isEmpty || searchOptions != SearchOptions()
        let snapshot = hasSearch
            ? HistoryEntry.SearchSnapshot(query: searchQuery,
                                          options: searchOptions,
                                          results: searchResults)
            : nil
        history[historyIndex].searchSnapshot = snapshot
    }

    /// Applies a history entry: restores the URL and — if present — the search snapshot,
    /// otherwise loads the directory normally.
    private func restoreEntry(_ entry: HistoryEntry) {
        currentURL = entry.url
        selectedItems = []
        lastSelectedURL = nil

        if let snap = entry.searchSnapshot {
            // Restore search state from cache — no query re-execution needed
            searchQuery   = snap.query
            searchOptions = snap.options
            searchResults = snap.results
            isSearching   = false
            // For current-folder scope the filter works on `items`; still need to load the dir
            if snap.options.scope == .currentFolder {
                Task { await load(showHidden: showHiddenCache) }
            }
        } else {
            clearSearch()
            Task { await load(showHidden: showHiddenCache) }
        }
    }

    private func clearSearch() {
        searchTask?.cancel()
        searchQuery   = ""
        searchOptions = SearchOptions()
        searchResults = []
        isSearching   = false
    }

    // MARK: - Loading

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

    /// Refreshes the directory listing without showing a loading indicator.
    /// Safe to call for in-place operations (rename, trash, drop) — keeps scroll position stable.
    func silentRefresh() async {
        guard !isLoading else { return }
        do {
            let loaded = try await fileSystemService.children(of: currentURL, showHidden: showHiddenCache)
            items = loaded
        } catch {}
    }

    // MARK: - Search

    func performSearchIfNeeded(showHidden: Bool) {
        searchTask?.cancel()

        guard searchOptions.scope.isAsync else {
            searchResults = []
            isSearching = false
            return
        }

        let text = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty || searchOptions.fileKind != .any else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true
        searchResults = []
        let capturedOptions = searchOptions
        let capturedRoot    = currentURL

        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }

            let results = await SearchService.search(
                query:    text,
                options:  capturedOptions,
                inFolder: capturedRoot,
                showHidden: showHidden
            )
            guard !Task.isCancelled else { return }
            self.searchResults = results
            self.isSearching   = false
        }
    }

    // MARK: - Watcher

    private func updateWatcher() {
        guard currentURL != watchedURL else { return }
        watchedURL = currentURL
        watcher = DirectoryWatcher(url: currentURL) { [weak self] in
            guard let self else { return }
            Task { await self.silentRefresh() }
        }
    }
}
