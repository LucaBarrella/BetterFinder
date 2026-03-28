import SwiftUI

// MARK: - Sidebar

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {

                    // MARK: Favorites
                    SectionHeader(title: "Favorites")

                    ForEach(appState.favoritesController.flatNodes) { flat in
                        TreeRow(flatNode: flat, controller: appState.favoritesController)
                            .id(flat.id)
                    }

                    // MARK: Locations
                    SectionHeader(title: "Locations")
                        .padding(.top, 6)

                    ForEach(appState.treeController.flatNodes) { flat in
                        TreeRow(flatNode: flat, controller: appState.treeController)
                            .id(flat.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(minWidth: 200, idealWidth: 230)
            .background(Color(nsColor: .controlBackgroundColor))
            // Auto-expand the sidebar tree whenever the active browser navigates
            // (handles both GUI clicks and terminal cd commands via OSC 7)
            .onChange(of: appState.activeBrowser.currentURL) { _, newURL in
                Task {
                    // Expand ancestors in Locations tree so the folder is visible
                    await appState.treeController.expandPath(
                        to: newURL,
                        service: appState.fileSystemService,
                        showHidden: appState.preferences.showHiddenFiles
                    )
                    // Expand the target node itself (show its children)
                    await appState.treeController.expandNode(
                        matching: newURL,
                        service: appState.fileSystemService,
                        showHidden: appState.preferences.showHiddenFiles
                    )
                    // Expand Favorites entry if it matches exactly
                    await appState.favoritesController.expandNode(
                        matching: newURL,
                        service: appState.fileSystemService,
                        showHidden: appState.preferences.showHiddenFiles
                    )
                    // Scroll to the matching node
                    let activeID = appState.treeController.flatNodes
                        .first { $0.node.url.standardizedFileURL == newURL.standardizedFileURL }?.id
                        ?? appState.favoritesController.flatNodes
                            .first { $0.node.url.standardizedFileURL == newURL.standardizedFileURL }?.id
                    if let id = activeID {
                        withAnimation { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
        }
    }
}

// MARK: - Section Header

private struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }
}

// MARK: - Tree Row (shared for favorites + locations)

struct TreeRow: View {
    @Environment(AppState.self) private var appState
    let flatNode: TreeController.FlatNode
    let controller: TreeController

    private var node: TreeNode { flatNode.node }

    private var isActive: Bool {
        appState.activeBrowser.currentURL.standardizedFileURL
            == node.url.standardizedFileURL
    }

    private var showChevron: Bool {
        guard let children = node.children else { return true }
        return !children.isEmpty
    }

    var body: some View {
        HStack(spacing: 0) {
            // Indentation
            Spacer()
                .frame(width: CGFloat(flatNode.depth) * 16 + 4)

            // Chevron — tall hit area, always occupies its column
            Button {
                controller.toggle(
                    node,
                    service: appState.fileSystemService,
                    showHidden: appState.preferences.showHiddenFiles
                )
            } label: {
                ZStack {
                    Color.clear
                    if showChevron {
                        Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 22, height: 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Folder icon
            Image(systemName: node.systemImage)
                .foregroundStyle(node.iconColor)
                .font(.system(size: 13))
                .frame(width: 18)

            // Name — navigate on click
            Button {
                appState.activeBrowser.navigate(to: node.url)
            } label: {
                HStack(spacing: 4) {
                    Text(node.name)
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(isActive ? Color.accentColor : Color.primary)

                    Spacer(minLength: 0)

                    if node.isLoading {
                        ProgressView()
                            .controlSize(.mini)
                            .padding(.trailing, 4)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)
        }
        .frame(height: 26)
        .background(
            isActive
                ? Color.accentColor.opacity(0.10)
                : Color.clear
        )
        .contentShape(Rectangle())
        .onDrag {
            NSItemProvider(object: node.url as NSURL)
        }
        .contextMenu {
            Button("Open in Pane") {
                appState.activeBrowser.navigate(to: node.url)
            }
            Button("Open in Other Pane") {
                appState.secondaryBrowser.navigate(to: node.url)
                appState.isDualPane = true
            }
            Divider()
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    node.url.path(percentEncoded: false),
                    forType: .string
                )
            }
            Divider()
            // Open in BetterFinder's integrated terminal (navigates both file panel + terminal)
            Button("Open in Terminal") {
                appState.activeBrowser.navigate(to: node.url)
                appState.activeBrowser.showTerminal = true
                appState.activeBrowser.terminalChangeDirectory?(node.url)
            }
        }
    }
}

#Preview {
    SidebarView()
        .environment(AppState())
}
