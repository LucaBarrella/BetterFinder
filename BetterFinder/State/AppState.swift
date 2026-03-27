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

    // MARK: - Tree

    let treeController     = TreeController()
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

        let showHidden = preferences.showHiddenFiles
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
