import Foundation
import Observation
import SwiftUI

/// Manages the flat, visible representation of the filesystem tree.
/// All expand/collapse logic lives here — the view only reads `flatNodes`.
@Observable
final class TreeController {

    // MARK: - Flat Node

    struct FlatNode: Identifiable {
        var id: UUID { node.id }
        let node: TreeNode
        let depth: Int
    }

    // MARK: - State

    private(set) var flatNodes: [FlatNode] = []
    private var _roots: [TreeNode] = []

    var roots: [TreeNode] { _roots }

    // MARK: - Setup

    func setRoots(_ newRoots: [TreeNode]) {
        _roots = newRoots
        rebuild()
    }

    // MARK: - Toggle

    func toggle(_ node: TreeNode, service: FileSystemService, showHidden: Bool) {
        if node.isExpanded {
            node.isExpanded = false
            rebuild()
        } else {
            node.isExpanded = true
            if node.children == nil {
                rebuild()   // show spinner immediately
                Task {
                    await node.loadChildrenIfNeeded(service: service, showHidden: showHidden)
                    rebuild()
                }
            } else {
                rebuild()
            }
        }
    }

    // MARK: - Pre-expand

    /// Loads and expands every ancestor of `url` so the folder becomes visible.
    func expandPath(to url: URL, service: FileSystemService, showHidden: Bool) async {
        for root in roots {
            await expand(node: root, toURL: url, service: service, showHidden: showHidden)
        }
        rebuild()
    }

    /// Expands ONLY the node exactly matching `url` (no ancestors).
    /// Suitable for Favorites where expanding ancestors would be wrong.
    func expandNode(matching url: URL, service: FileSystemService, showHidden: Bool) async {
        let target = url.standardizedFileURL
        for root in roots {
            await expandExact(node: root, url: target, service: service, showHidden: showHidden)
        }
        rebuild()
    }

    // MARK: - Collapse irrelevant

    /// Collapses every expanded node that is NOT an ancestor of (or equal to) `url`.
    /// Called after navigation so only the current path stays open in the sidebar.
    func collapseIrrelevantNodes(keeping url: URL) {
        for root in roots {
            collapseIrrelevant(root, targetURL: url)
        }
        rebuild()
    }

    private func collapseIrrelevant(_ node: TreeNode, targetURL: URL) {
        let me  = node.url.path(percentEncoded: false)
        let tgt = targetURL.path(percentEncoded: false)
        let isOnPath = tgt.hasPrefix(me == "/" ? me : me + "/") || tgt == me

        if isOnPath {
            // Stay open; recurse so deeper off-path children get collapsed
            for child in node.children ?? [] {
                collapseIrrelevant(child, targetURL: targetURL)
            }
        } else {
            node.isExpanded = false
            // No need to recurse — collapsing the parent hides children
        }
    }

    // MARK: - Invalidate

    /// Collapses and clears all cached children so the tree reloads on next expand.
    func invalidateAll() {
        for root in roots { collapseAndInvalidate(root) }
        rebuild()
    }

    private func collapseAndInvalidate(_ node: TreeNode) {
        for child in node.children ?? [] { collapseAndInvalidate(child) }
        node.children = nil
        node.isExpanded = false
    }

    // MARK: - Rebuild

    /// Rebuilds `flatNodes` from the current tree state.
    func rebuild() {
        var result: [FlatNode] = []
        for root in roots {
            collect(node: root, depth: 0, into: &result)
        }
        withAnimation(.easeInOut(duration: 0.18)) {
            flatNodes = result
        }
    }

    // MARK: - Private

    private func collect(node: TreeNode, depth: Int, into result: inout [FlatNode]) {
        result.append(FlatNode(node: node, depth: depth))
        guard node.isExpanded, let children = node.children else { return }
        for child in children {
            collect(node: child, depth: depth + 1, into: &result)
        }
    }

    private func expandExact(node: TreeNode, url: URL, service: FileSystemService, showHidden: Bool) async {
        if node.url.standardizedFileURL == url {
            if node.children == nil {
                await node.loadChildrenIfNeeded(service: service, showHidden: showHidden)
            }
            node.isExpanded = true
            return
        }
        // Only recurse into already-expanded nodes (avoid loading the whole tree)
        if node.isExpanded, let children = node.children {
            for child in children {
                await expandExact(node: child, url: url, service: service, showHidden: showHidden)
            }
        }
    }

    private func expand(node: TreeNode, toURL target: URL, service: FileSystemService, showHidden: Bool) async {
        // Only auto-expand through the filesystem root ("/", Macintosh HD).
        // Other top-level nodes (Home, iCloud, volumes…) must stay collapsed during
        // navigation — expanding them causes unrelated sidebar sections to open.
        if roots.contains(where: { $0 === node }) && node.kind != .root {
            return
        }

        let me  = node.url.path(percentEncoded: false)
        let tgt = target.path(percentEncoded: false)

        // This node must be a strict ancestor of the target (not the target itself).
        // Expanding the target itself is left to the caller (expandNode); here we only
        // expand ancestors so the target becomes visible as a child of its parent.
        guard tgt.hasPrefix(me == "/" ? me : me + "/") else { return }

        if node.children == nil {
            await node.loadChildrenIfNeeded(service: service, showHidden: showHidden)
        }
        node.isExpanded = true
        rebuild()

        for child in (node.children ?? []) {
            await expand(node: child, toURL: target, service: service, showHidden: showHidden)
        }
    }
}
