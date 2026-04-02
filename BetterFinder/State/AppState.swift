import Foundation
import Observation
import AppKit
import SwiftUI

@Observable
final class AppState {

    // MARK: - Services
 
    let fileSystemService: FileSystemService
    let volumeService: VolumeServiceProtocol
    let preferences = AppPreferences()
    let undoManager = UndoManager()
    /// Tracked so SwiftUI menu items can observe canUndo / canRedo reactively.
    private(set) var canUndo = false
    private(set) var canRedo = false
    var alertPresenter: ((String, String) -> Void)?

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

        let destination = dst.currentURL
        let showHidden  = preferences.showHiddenFiles

        if removing {
            let pairs = sel.map { (from: $0.url, to: destination.appendingPathComponent($0.name)) }
            moveFiles(pairs, actionName: "Move", reloadBrowsers: [src, dst])
        } else {
            // Copy — no undo needed for non-destructive op, but still run on background thread
            DispatchQueue.global(qos: .userInitiated).async {
                for item in sel {
                    let target = destination.appendingPathComponent(item.name)
                    try? FileManager.default.copyItem(at: item.url, to: target)
                }
                DispatchQueue.main.async { Task { await dst.silentRefresh() } }
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
        let browser = activeBrowser
        do {
            try Data().write(to: newURL, options: .withoutOverwriting)
            undoManager.setActionName("New File")
            undoManager.registerUndo(withTarget: self) { s in
                s.trashFiles([newURL], reloadBrowser: browser)
            }
        } catch {
            let err = NSAlert()
            err.messageText = "Could Not Create File"
            err.informativeText = error.localizedDescription
            err.runModal()
        }
        Task { await browser.silentRefresh() }
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
        let browser = activeBrowser
        do {
            try FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: false)
            undoManager.setActionName("New Folder")
            undoManager.registerUndo(withTarget: self) { s in
                s.trashFiles([newURL], reloadBrowser: browser)
            }
        } catch {
            let err = NSAlert(); err.messageText = "Could Not Create Folder"
            err.informativeText = error.localizedDescription; err.runModal()
        }
        Task { await browser.silentRefresh() }
    }

    func renameInActivePane() {
        // Delegate to the inline rename handler wired up by FileTableView.Coordinator.
        activeBrowser.triggerInlineRename?()
    }

    func trashInActivePane() {
        let sel = activeBrowser.selectedFileItems
        guard !sel.isEmpty else { return }
        trashFiles(sel.map(\.url), reloadBrowser: activeBrowser)
    }

    // MARK: - Undo helpers

    /// Trashes `urls` and registers an undo action that restores them.
    func trashFiles(_ urls: [URL], reloadBrowser browser: BrowserState) {
        var pairs: [(original: URL, inTrash: URL)] = []
        for url in urls {
            var result: NSURL?
            try? FileManager.default.trashItem(at: url, resultingItemURL: &result)
            if let t = result as URL? { pairs.append((url, t)) }
        }
        if !pairs.isEmpty {
            undoManager.setActionName("Move to Trash")
            undoManager.registerUndo(withTarget: self) { s in
                s.restoreFiles(pairs, reloadBrowser: browser)
            }
        }
        Task { await browser.silentRefresh() }
    }

    /// Restores previously trashed files and registers an undo action that re-trashes them.
    private func restoreFiles(_ pairs: [(original: URL, inTrash: URL)], reloadBrowser browser: BrowserState) {
        let succeeded = pairs.filter {
            (try? FileManager.default.moveItem(at: $0.inTrash, to: $0.original)) != nil
        }
        if !succeeded.isEmpty {
            undoManager.setActionName("Move to Trash")
            undoManager.registerUndo(withTarget: self) { s in
                s.trashFiles(succeeded.map(\.original), reloadBrowser: browser)
            }
        }
        Task { await browser.silentRefresh() }
    }

    /// Moves `pairs` of (from → to) and registers an inverse undo.
    /// Passing the swapped pairs as undo automatically handles redo too.
    func moveFiles(_ pairs: [(from: URL, to: URL)], actionName: String, reloadBrowsers: [BrowserState]) {
        var succeeded: [(from: URL, to: URL)] = []
        for (from, to) in pairs {
            guard from != to,
                  !to.path(percentEncoded: false).hasPrefix(from.path(percentEncoded: false) + "/")
            else { continue }
            if (try? FileManager.default.moveItem(at: from, to: to)) != nil {
                succeeded.append((from, to))
            }
        }
        if !succeeded.isEmpty {
            undoManager.setActionName(actionName)
            undoManager.registerUndo(withTarget: self) { s in
                s.moveFiles(succeeded.map { ($0.to, $0.from) },
                            actionName: actionName, reloadBrowsers: reloadBrowsers)
            }
        }
        for b in reloadBrowsers { Task { await b.silentRefresh() } }
    }

    /// Registers an undo for a rename already performed by the caller.
    func registerRenameUndo(from oldURL: URL, to newURL: URL, in browser: BrowserState) {
        undoManager.setActionName("Rename")
        undoManager.registerUndo(withTarget: self) { s in
            do {
                try FileManager.default.moveItem(at: newURL, to: oldURL)
                s.registerRenameUndo(from: newURL, to: oldURL, in: browser)
            } catch {}
            Task { await browser.silentRefresh() }
        }
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
        let pairs = cutItems.map { src in
            (from: src, to: destination.appendingPathComponent(src.lastPathComponent))
        }
        cutItems = []
        moveFiles(pairs, actionName: "Move", reloadBrowsers: [activeBrowser])
    }

    var hasCutItems: Bool { !cutItems.isEmpty }

    // MARK: - Drop Stack

    var dropStackItems: [URL] = []
    var showDropStack: Bool = false
    var showTrashZone: Bool = false

    func addToDropStack(_ urls: [URL]) {
        for url in urls where !dropStackItems.contains(url) {
            dropStackItems.append(url)
        }
    }

    func removeFromDropStack(_ url: URL) {
        dropStackItems.removeAll { $0 == url }
    }

    func clearDropStack() {
        dropStackItems.removeAll()
    }

    func moveDropStackToActivePane() {
        guard !dropStackItems.isEmpty else { return }
        let destination = activeBrowser.currentURL
        let pairs = dropStackItems.map { src in
            (from: src, to: destination.appendingPathComponent(src.lastPathComponent))
        }
        clearDropStack()
        moveFiles(pairs, actionName: "Move from Stack",
                  reloadBrowsers: [primaryBrowser, secondaryBrowser])
    }

    func copyDropStackToActivePane() {
        guard !dropStackItems.isEmpty else { return }
        let destination = activeBrowser.currentURL
        let urls = dropStackItems
        DispatchQueue.global(qos: .userInitiated).async {
            for url in urls {
                let target = destination.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.copyItem(at: url, to: target)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                Task { await self.activeBrowser.silentRefresh() }
            }
        }
    }

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
        let svc: FileSystemService = FileSystemService()
        let vol: VolumeServiceProtocol = VolumeService()
        self.fileSystemService = svc
        self.volumeService = vol
        self.primaryBrowser    = BrowserState(url: home, fileSystemService: svc, volumeService: vol)
        self.secondaryBrowser  = BrowserState(url: home, fileSystemService: svc, volumeService: vol)

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
        }

        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.setupTreeRoots() }

        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.setupTreeRoots() }

        // Keep canUndo / canRedo in sync so SwiftUI can observe them.
        let updateUndo = { [weak self] (_: Notification) in
            guard let self else { return }
            self.canUndo = self.undoManager.canUndo
            self.canRedo = self.undoManager.canRedo
        }
        for name: Notification.Name in [
            .NSUndoManagerDidCloseUndoGroup,
            .NSUndoManagerDidUndoChange,
            .NSUndoManagerDidRedoChange
        ] {
            NotificationCenter.default.addObserver(
                forName: name, object: undoManager, queue: .main, using: updateUndo)
        }
    }

    // MARK: - Tree Roots

    private func setupTreeRoots() {
        var roots: [TreeNode] = []

        // 1. Macintosh HD (root filesystem)
        roots.append(TreeNode(url: URL(fileURLWithPath: "/"), kind: .root))

        // 2. Cloud storage providers — enumerate ~/Library/CloudStorage (Ventura+)
        //    This covers iCloud Drive, Nextcloud, OneDrive, Dropbox, etc. automatically.
        let cloudStorageDir = URL.homeDirectory
            .appending(components: "Library", "CloudStorage")
        var foundICloudViaCloudStorage = false

        if let entries = try? FileManager.default.contentsOfDirectory(
            at: cloudStorageDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            // Sort alphabetically for a stable order
            for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                guard isDir else { continue }
                if entry.lastPathComponent.lowercased().hasPrefix("icloud") {
                    roots.append(TreeNode(url: entry, kind: .icloud))
                    foundICloudViaCloudStorage = true
                } else {
                    roots.append(TreeNode(url: entry, kind: .cloudProvider))
                }
            }
        }

        // Fallback: legacy iCloud path (pre-Ventura or if CloudStorage doesn't exist)
        if !foundICloudViaCloudStorage {
            let icloudLegacy = URL.homeDirectory
                .appending(components: "Library", "Mobile Documents", "com~apple~CloudDocs")
            if (try? icloudLegacy.checkResourceIsReachable()) == true {
                roots.append(TreeNode(url: icloudLegacy, kind: .icloud))
            }
        }

        // 3. Home directory
        roots.append(TreeNode(url: URL.homeDirectory, kind: .folder))

        // 5. Mounted volumes — local external drives first, then network shares
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

        // 6. Trash
        let trashURL = URL.homeDirectory.appending(component: ".Trash")
        roots.append(TreeNode(url: trashURL, kind: .trash))

        treeController.setRoots(roots)
    }

    // MARK: - Favorites

    private func setupFavorites() {
        let home = URL.homeDirectory
        let favURLs: [(URL, TreeNode.Kind)] = [
            (URL(fileURLWithPath: "/Applications"),       .folder),
            (home.appending(component: "Desktop"),        .folder),
            (home.appending(component: "Documents"),      .folder),
            (home.appending(component: "Downloads"),      .folder),
        ]
        let nodes = favURLs.map { TreeNode(url: $0.0, kind: $0.1) }
        favoritesController.setRoots(nodes)
    }

    var alertPresenter: ((String, String) -> Void)?

    func ejectVolume(for url: URL) async {
        do {
            try await volumeService.ejectVolume(at: url)
            await MainActor.run { self.refreshAfterEject() }
        } catch {
            await MainActor.run { self.showAlertForEjectError(error) }
        }
    }

    @MainActor
    private func refreshAfterEject() {
        setupTreeRoots()
        primaryBrowser.refreshVolumeEjectableCache()
        secondaryBrowser.refreshVolumeEjectableCache()
        Task {
            await primaryBrowser.silentRefresh()
            await secondaryBrowser.silentRefresh()
        }
    }

    @MainActor
    private func showAlertForEjectError(_ error: Error) {
        if let presenter = alertPresenter {
            presenter(
                NSLocalizedString("EJECT_ALERT_TITLE", comment: ""),
                error.localizedDescription
            )
            return
        }
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("EJECT_ALERT_TITLE", comment: "")
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: NSLocalizedString("EJECT_ALERT_OK", comment: ""))
        if let window = NSApp.mainWindow {
            alert.beginSheetModal(for: window) { _ in }
        } else {
            alert.runModal()
        }
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
