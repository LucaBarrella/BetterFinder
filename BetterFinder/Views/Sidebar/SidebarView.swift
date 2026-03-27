import SwiftUI

// MARK: - Sidebar

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {

                // MARK: Favorites
                SectionHeader(title: "Favorites")

                ForEach(appState.favoritesController.flatNodes) { flat in
                    TreeRow(flatNode: flat, controller: appState.favoritesController)
                }

                // MARK: Locations
                SectionHeader(title: "Locations")
                    .padding(.top, 6)

                ForEach(appState.treeController.flatNodes) { flat in
                    TreeRow(flatNode: flat, controller: appState.treeController)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(minWidth: 200, idealWidth: 230)
        .background(Color(nsColor: .controlBackgroundColor))
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
                            .rotationEffect(node.isExpanded ? .zero : .zero) // explicit so SwiftUI tracks
                    }
                }
                .frame(width: 22, height: 26)  // full row height → easy tap
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
            Button("Open in Terminal") {
                let path = node.url.path(percentEncoded: false)
                    .replacingOccurrences(of: "'", with: "'\\''")
                let script = "tell application \"Terminal\"\ndo script \"cd '\\(path)'\"\nactivate\nend tell"
                NSAppleScript(source: script)?.executeAndReturnError(nil)
            }
        }
    }
}

#Preview {
    SidebarView()
        .environment(AppState())
}
