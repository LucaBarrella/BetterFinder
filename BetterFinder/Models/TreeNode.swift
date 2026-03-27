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

    enum Kind {
        case root           // Macintosh HD  "/"
        case volume         // external / network drive
        case icloud         // iCloud Drive
        case network        // mounted network share
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
        case .folder:
            let p = url.path(percentEncoded: false)
            if p == URL.homeDirectory.path(percentEncoded: false) { return "Home" }
            return url.lastPathComponent
        }
    }

    var systemImage: String {
        switch kind {
        case .root:    return "internaldrive.fill"
        case .volume:  return "externaldrive.fill"
        case .icloud:  return "icloud.fill"
        case .network: return "network"
        case .folder:
            let home = URL.homeDirectory.path(percentEncoded: false)
            let p    = url.path(percentEncoded: false)
            switch p {
            case home:                           return "house.fill"
            case home + "/Desktop":              return "menubar.dock.rectangle"
            case home + "/Documents":            return "doc.fill"
            case home + "/Downloads":            return "arrow.down.circle.fill"
            case home + "/Music":                return "music.note"
            case home + "/Pictures":             return "photo.fill"
            case home + "/Movies":               return "film.fill"
            default:                             return "folder.fill"
            }
        }
    }

    var iconColor: Color {
        switch kind {
        case .root:    return .secondary
        case .volume:  return .orange
        case .icloud:  return .blue
        case .network: return .purple
        case .folder:
            let home = URL.homeDirectory.path(percentEncoded: false)
            let p    = url.path(percentEncoded: false)
            switch p {
            case home:                return .blue
            case home + "/Desktop":   return .purple
            case home + "/Documents": return .blue
            case home + "/Downloads": return .green
            case home + "/Music":     return .pink
            case home + "/Pictures":  return .orange
            case home + "/Movies":    return .red
            default:                  return Color.accentColor
            }
        }
    }

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
