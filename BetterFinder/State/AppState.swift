import Foundation
import Observation
import AppKit
import SwiftUI

@Observable
final class AppState {

    // MARK: - Services

    let fileSystemService: FileSystemService
    let preferences = AppPreferences()

    // MARK: - Browser Panes

    var primaryBrowser: BrowserState
    var secondaryBrowser: BrowserState
    var isDualPane = false
    var activePaneIsSecondary = false

    var activeBrowser: BrowserState {
        activePaneIsSecondary ? secondaryBrowser : primaryBrowser
    }

    /// Swaps the current directory of the two panes.
    func swapPanes() {
        let p = primaryBrowser.currentURL
        let s = secondaryBrowser.currentURL
        primaryBrowser.navigate(to: s)
        secondaryBrowser.navigate(to: p)
    }

    /// Returns 1 if `browser` is the primary pane, 2 otherwise.
    func paneNumber(for browser: BrowserState) -> Int {
        browser === primaryBrowser ? 1 : 2
    }

    // MARK: - Cross-pane file operations

    func copySelectionToOtherPane() {
        guard isDualPane else { return }
        performTransfer(verb: "Copy", removing: false)
    }

    func moveSelectionToOtherPane() {
        guard isDualPane else { return }
        performTransfer(verb: "Move", removing: true)
    }

    private func performTransfer(verb: String, removing: Bool) {
        let src = activeBrowser
        let dst = activePaneIsSecondary ? primaryBrowser : secondaryBrowser
        let sel = src.selectedFileItems
        guard !sel.isEmpty else { return }

        let nameStr = sel.count == 1 ? "\"\(sel[0].name)\"" : "\(sel.count) items"
        let alert = NSAlert()
        alert.messageText = "\(verb) \(nameStr) to Pane \(paneNumber(for: dst))"
        alert.informativeText = dst.currentURL.path(percentEncoded: false)
        alert.addButton(withTitle: verb)
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let destination  = dst.currentURL
        let showHidden   = preferences.showHiddenFiles
        DispatchQueue.global(qos: .userInitiated).async {
            for item in sel {
                let target = destination.appendingPathComponent(item.name)
                do {
                    if removing { try FileManager.default.moveItem(at: item.url, to: target) }
                    else        { try FileManager.default.copyItem(at: item.url, to: target) }
                } catch {}
            }
            DispatchQueue.main.async {
                Task { await dst.load(showHidden: showHidden) }
                if removing { Task { await src.load(showHidden: showHidden) } }
            }
        }
    }

    // MARK: - Single-pane operations (work on active pane)

    func newFileInActivePane() {
        let alert = NSAlert()
        alert.messageText = "New File"
        alert.informativeText = "Enter a name for the new file:"
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 22))
        tf.stringValue = "untitled"
        tf.selectText(nil)
        alert.accessoryView = tf
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = tf.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let newURL = activeBrowser.currentURL.appendingPathComponent(name)
        do {
            try Data().write(to: newURL, options: .withoutOverwriting)
        } catch {
            let err = NSAlert()
            err.messageText = "Could Not Create File"
            err.informativeText = error.localizedDescription
            err.runModal()
        }
        let showHidden = preferences.showHiddenFiles
        Task { await activeBrowser.load(showHidden: showHidden) }
    }

    func newFolderInActivePane() {
        let alert = NSAlert()
        alert.messageText = "New Folder"
        alert.informativeText = "Enter a name for the new folder:"
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 22))
        tf.stringValue = "untitled folder"
        tf.selectText(nil)
        alert.accessoryView = tf
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = tf.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let newURL = activeBrowser.currentURL.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: false)
        } catch {
            let err = NSAlert(); err.messageText = "Could Not Create Folder"
            err.informativeText = error.localizedDescription; err.runModal()
        }
        let showHidden = preferences.showHiddenFiles
        Task { await activeBrowser.load(showHidden: showHidden) }
    }

    func renameInActivePane() {
        // Delegate to the inline rename handler wired up by FileTableView.Coordinator.
        activeBrowser.triggerInlineRename?()
    }

    func trashInActivePane() {
        let sel = activeBrowser.selectedFileItems
        guard !sel.isEmpty else { return }
        for item in sel { try? FileManager.default.trashItem(at: item.url, resultingItemURL: nil) }
        let showHidden = preferences.showHiddenFiles
        Task { await activeBrowser.load(showHidden: showHidden) }
    }

    /// Navigate the active pane to the other pane's current directory.
    func goToOtherPaneLocation() {
        guard isDualPane else { return }
        let otherURL = activePaneIsSecondary ? primaryBrowser.currentURL : secondaryBrowser.currentURL
        activeBrowser.navigate(to: otherURL)
    }

    /// Navigate the other pane to match the active pane (mirror).
    func mirrorActivePaneToOther() {
        guard isDualPane else { return }
        let other = activePaneIsSecondary ? primaryBrowser : secondaryBrowser
        other.navigate(to: activeBrowser.currentURL)
    }

    // MARK: - Cut / Paste clipboard

    /// URLs currently staged for a cut-paste move. Cleared after paste or on copy.
    private(set) var cutItems: [URL] = []

    func cutSelectedItems() {
        cutItems = activeBrowser.selectedFileItems.map(\.url)
        // Also write paths to the system pasteboard so external apps can see them
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(cutItems as [NSURL])
    }

    func pasteIntoActivePane() {
        guard !cutItems.isEmpty else { return }
        let destination = activeBrowser.currentURL
        let itemsToMove = cutItems
        cutItems = []
        let showHidden = preferences.showHiddenFiles
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for src in itemsToMove {
                let dst = destination.appendingPathComponent(src.lastPathComponent)
                guard src != dst,
                      !dst.path(percentEncoded: false).hasPrefix(
                          src.path(percentEncoded: false) + "/") else { continue }
                try? FileManager.default.moveItem(at: src, to: dst)
            }
            DispatchQueue.main.async {
                Task { await self?.activeBrowser.load(showHidden: showHidden) }
            }
        }
    }

    var hasCutItems: Bool { !cutItems.isEmpty }

    // MARK: - Recent Folders

    var recentFolders: [URL] = []

    func addToRecents(_ url: URL) {
        // Skip root-level paths that are not useful in recents
        guard url.pathComponents.count > 1 else { return }
        var updated = recentFolders.filter { $0.standardizedFileURL != url.standardizedFileURL }
        updated.insert(url, at: 0)
        recentFolders = Array(updated.prefix(preferences.maxRecentFolders))
        UserDefaults.standard.set(
            recentFolders.map { $0.path(percentEncoded: false) },
            forKey: "recentFolderPaths"
        )
    }

    func removeFromRecents(_ url: URL) {
        recentFolders.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        UserDefaults.standard.set(
            recentFolders.map { $0.path(percentEncoded: false) },
            forKey: "recentFolderPaths"
        )
    }

    func clearRecents() {
        recentFolders = []
        UserDefaults.standard.removeObject(forKey: "recentFolderPaths")
    }

    private func loadRecents() {
        let paths = UserDefaults.standard.stringArray(forKey: "recentFolderPaths") ?? []
        recentFolders = paths
            .compactMap { URL(fileURLWithPath: $0) }
            .filter { (try? $0.checkResourceIsReachable()) == true }
            .prefix(preferences.maxRecentFolders)
            .map { $0 }
    }

    // MARK: - Tree

    let treeController      = TreeController()
    let favoritesController = TreeController()

    // MARK: - Init

    init() {
        let home = URL.homeDirectory
        let svc  = FileSystemService()
        self.fileSystemService = svc
        self.primaryBrowser    = BrowserState(url: home, fileSystemService: svc)
        self.secondaryBrowser  = BrowserState(url: home, fileSystemService: svc)

        setupTreeRoots()
        setupFavorites()
        loadRecents()

        // Wire navigate callbacks for recents tracking
        primaryBrowser.onNavigate   = { [weak self] url in self?.addToRecents(url) }
        secondaryBrowser.onNavigate = { [weak self] url in self?.addToRecents(url) }

        // Apply startup preferences
        let prefs = preferences
        isDualPane = prefs.startInDualPane

        let defaultOpts = prefs.defaultSearchOptions
        primaryBrowser.searchOptions   = defaultOpts
        secondaryBrowser.searchOptions = defaultOpts

        if prefs.openTerminalByDefault {
            primaryBrowser.showTerminal   = true
            secondaryBrowser.showTerminal = true
        }

        let showHidden = prefs.showHiddenFiles
        Task {
            await primaryBrowser.load(showHidden: showHidden)
            // Pre-expand sidebar to home directory
            await treeController.expandPath(
                to: home,
                service: svc,
                showHidden: showHidden
            )
        }

        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.setupTreeRoots() }

        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.setupTreeRoots() }
    }

    // MARK: - Tree Roots

    private func setupTreeRoots() {
        var roots: [TreeNode] = []

        // 1. Macintosh HD (root)
        roots.append(TreeNode(url: URL(fileURLWithPath: "/"), kind: .root))

        // 2. iCloud Drive — try well-known CloudDocs path
        let icloudCandidate = URL.homeDirectory
            .appending(components: "Library", "Mobile Documents", "com~apple~CloudDocs")
        if (try? icloudCandidate.checkResourceIsReachable()) == true {
            roots.append(TreeNode(url: icloudCandidate, kind: .icloud))
        }

        // 3. Mounted volumes: local external drives first, then network shares
        let vols = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeNameKey, .volumeIsLocalKey],
            options: .skipHiddenVolumes
        ) ?? []

        var networkRoots: [TreeNode] = []
        for url in vols where url.path(percentEncoded: false) != "/" {
            let isLocal = (try? url.resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal) ?? true
            if isLocal {
                roots.append(TreeNode(url: url, kind: .volume))
            } else {
                networkRoots.append(TreeNode(url: url, kind: .network))
            }
        }
        roots.append(contentsOf: networkRoots)

        treeController.setRoots(roots)
    }

    // MARK: - Favorites

    private func setupFavorites() {
        let home = URL.homeDirectory
        let favURLs: [(URL, TreeNode.Kind)] = [
            (home,                                        .folder),
            (home.appending(component: "Desktop"),        .folder),
            (home.appending(component: "Documents"),      .folder),
            (home.appending(component: "Downloads"),      .folder),
        ]
        let nodes = favURLs.map { TreeNode(url: $0.0, kind: $0.1) }
        favoritesController.setRoots(nodes)
    }
}

// MARK: - SidebarItem (future use)
struct SidebarItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let url: URL
    let systemImage: String
    let tintColor: Color
}
