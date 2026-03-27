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
    private var roots: [TreeNode] = []

    // MARK: - Setup

    func setRoots(_ newRoots: [TreeNode]) {
        roots = newRoots
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

    private func expand(node: TreeNode, toURL target: URL, service: FileSystemService, showHidden: Bool) async {
        let me  = node.url.path(percentEncoded: false)
        let tgt = target.path(percentEncoded: false)

        // This node must be a strict ancestor of target (or target itself)
        guard tgt.hasPrefix(me == "/" ? me : me + "/") || tgt == me else { return }

        if node.children == nil {
            await node.loadChildrenIfNeeded(service: service, showHidden: showHidden)
        }
        node.isExpanded = true
        rebuild()   // update UI incrementally as each level expands

        for child in (node.children ?? []) {
            await expand(node: child, toURL: target, service: service, showHidden: showHidden)
        }
    }
}
