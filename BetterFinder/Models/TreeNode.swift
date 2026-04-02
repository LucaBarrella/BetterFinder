import Foundation
import SwiftUI
import Observation

/// A lazily-loaded node in the filesystem tree.
@Observable
final class TreeNode: Identifiable {
    let id = UUID()
    let url: URL
    let kind: Kind

    /// nil = not yet loaded;  [] = loaded, no subdirectories
    var children: [TreeNode]?
    var isExpanded = false
    var isLoading  = false

    // MARK: - Custom Properties (for Favorites)

    /// Custom SF Symbol icon name (instead of default folder icon)
    var customIcon: String?

    /// Custom accent color for this favorite
    var customColor: Color?

    /// Whether this favorite is an alias to another location
    var isAlias: Bool = false

    enum Kind {
        case root           // Macintosh HD  "/"
        case volume         // external / network drive
        case icloud         // iCloud Drive
        case cloudProvider  // third-party FileProvider (Nextcloud, OneDrive, Dropbox…)
        case network        // mounted network share
        case airdrop        // AirDrop (special — not a real filesystem path)
        case trash          // Trash / Bin
        case folder         // regular directory
    }

    init(url: URL, kind: Kind = .folder) {
        self.url  = url
        self.kind = kind
    }

    // MARK: - Display

    var name: String {
        switch kind {
        case .root:    return "Macintosh HD"
        case .icloud:  return "iCloud Drive"
        case .network: return url.lastPathComponent
        case .volume:
            return (try? url.resourceValues(forKeys: [.volumeNameKey]).volumeName)
                ?? url.lastPathComponent
        case .cloudProvider:
            // CloudStorage dirs follow "ProviderName-bundleid" — take the part before the first dash
            let raw = url.lastPathComponent
            return raw.components(separatedBy: "-").first ?? raw
        case .airdrop:  return "AirDrop"
        case .trash:    return "Trash"
        case .folder:
            let p = url.path(percentEncoded: false)
            if p == URL.homeDirectory.path(percentEncoded: false) { return "Home" }
            return url.lastPathComponent
        }
    }

    // Outlined SF Symbols matching Finder's sidebar style
    var systemImage: String {
        switch kind {
        case .root:          return "internaldrive"
        case .volume:        return "externaldrive"
        case .icloud:        return "cloud"
        case .cloudProvider: return "externaldrive.connected.to.line.below"
        case .airdrop:       return "dot.radiowaves.left.and.right"
        case .trash:         return "trash"
        case .network:       return "globe"
        case .folder:
            let home = URL.homeDirectory.path(percentEncoded: false)
            let p    = url.path(percentEncoded: false)
            switch p {
            case home:                return "house"
            case home + "/Desktop":   return "menubar.dock.rectangle"
            case home + "/Documents": return "doc"
            case home + "/Downloads": return "arrow.down.circle"
            case home + "/Music":     return "music.note"
            case home + "/Pictures":  return "photo"
            case home + "/Movies":    return "film"
            case "/Applications":     return "square.grid.2x2"
            default:                  return "folder"
            }
        }
    }

    // Sidebar icons are monochrome for special kinds and well-known paths.
    // Generic subfolders fall back to the native NSWorkspace folder icon (blue).
    var iconColor: Color { .secondary }

    /// True when this node should display an SF Symbol in the sidebar.
    /// False means the caller should load and display the NSWorkspace file icon instead.
    /// A node uses an SF Symbol whenever it has a dedicated icon (not the generic "folder").
    var usesSFSymbol: Bool { systemImage != "folder" }

    // MARK: - Loading

    func loadChildrenIfNeeded(service: FileSystemService, showHidden: Bool) async {
        guard children == nil, !isLoading else { return }
        isLoading = true
        // subdirectories() is nonisolated — runs concurrently, no actor bottleneck
        let dirs = service.subdirectories(of: url, showHidden: showHidden)
        children = dirs.map { TreeNode(url: $0, kind: .folder) }
        isLoading = false
    }

    func invalidate() {
        children = nil
    }
}
