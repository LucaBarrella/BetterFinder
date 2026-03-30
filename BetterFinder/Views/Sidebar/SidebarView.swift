import SwiftUI
import UniformTypeIdentifiers

// MARK: - Sidebar

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @State private var recentsExpanded = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {

                    SectionHeader(title: "Favorites")
                    ForEach(appState.favoritesController.flatNodes) { flat in
                        TreeRow(flatNode: flat, controller: appState.favoritesController)
                            .id(flat.id)
                    }

                    // ── Recents ──────────────────────────────────────────
                    if !appState.recentFolders.isEmpty {
                        CollapsibleSectionHeader(
                            title: "Recents",
                            isExpanded: $recentsExpanded
                        )
                        .padding(.top, 6)

                        if recentsExpanded {
                            ForEach(appState.recentFolders, id: \.absoluteString) { url in
                                RecentRow(url: url)
                            }
                        }
                    }

                    // ── Locations ─────────────────────────────────────────
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
            .onChange(of: appState.activeBrowser.currentURL) { _, newURL in
                Task {
                    await appState.treeController.expandPath(
                        to: newURL, service: appState.fileSystemService,
                        showHidden: appState.preferences.showHiddenFiles)
                    await appState.treeController.expandNode(
                        matching: newURL, service: appState.fileSystemService,
                        showHidden: appState.preferences.showHiddenFiles)
                    await appState.favoritesController.expandNode(
                        matching: newURL, service: appState.fileSystemService,
                        showHidden: appState.preferences.showHiddenFiles)
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

// MARK: - Collapsible Section Header (for Recents)

private struct CollapsibleSectionHeader: View {
    let title: String
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 10)
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Recent Row

private struct RecentRow: View {
    @Environment(AppState.self) private var appState
    let url: URL

    private var name: String { url.lastPathComponent.isEmpty ? "/" : url.lastPathComponent }
    private var isActive: Bool {
        appState.activeBrowser.currentURL.standardizedFileURL == url.standardizedFileURL
    }

    var body: some View {
        Button { appState.activeBrowser.navigate(to: url) } label: {
            HStack(spacing: 6) {
                Color.clear.frame(width: 20)           // indent to align with tree rows
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                Spacer(minLength: 0)
            }
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isActive ? Color.accentColor.opacity(0.10) : Color.clear)
        .contextMenu {
            Button("Open in Pane 1") {
                appState.primaryBrowser.navigate(to: url)
                appState.activePaneIsSecondary = false
            }
            Button("Open in Pane 2") {
                appState.secondaryBrowser.navigate(to: url)
                appState.isDualPane = true
                appState.activePaneIsSecondary = true
            }
            Divider()
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.path(percentEncoded: false), forType: .string)
            }
            Button("Open in Terminal") {
                appState.activeBrowser.navigate(to: url)
                appState.activeBrowser.showTerminal = true
                appState.activeBrowser.terminalChangeDirectory?(url)
            }
            Divider()
            Button("Remove from Recents") { appState.removeFromRecents(url) }
            Button("Clear All Recents")   { appState.clearRecents() }
        }
    }
}

// MARK: - Tree Row

struct TreeRow: View {
    @Environment(AppState.self) private var appState
    let flatNode: TreeController.FlatNode
    let controller: TreeController

    @State private var isDragTargeted = false
    @State private var springLoadTask: Task<Void, Never>?

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
            Color.clear.frame(width: CGFloat(flatNode.depth) * 16 + 4)

            // Chevron — expand / collapse only
            Button {
                controller.toggle(node, service: appState.fileSystemService,
                                  showHidden: appState.preferences.showHiddenFiles)
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

            // Icon — tappable, same navigate action
            Button { navigateAction() } label: {
                Image(systemName: isDragTargeted ? "folder.fill.badge.plus" : node.systemImage)
                    .foregroundStyle(isDragTargeted ? Color.accentColor : node.iconColor)
                    .font(.system(size: 13))
                    .frame(width: 18, height: 26)
                    .contentShape(Rectangle())
                    .animation(.easeInOut(duration: 0.15), value: isDragTargeted)
            }
            .buttonStyle(.plain)

            // Name — fills remaining width, tappable everywhere
            Button { navigateAction() } label: {
                HStack(spacing: 4) {
                    Text(node.name)
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                        .textSelection(.disabled)
                    Spacer(minLength: 0)
                    if node.isLoading {
                        ProgressView().controlSize(.mini).padding(.trailing, 4)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.trailing, 8)
        }
        .frame(height: 26)
        .background(
            isDragTargeted
                ? Color.accentColor.opacity(0.15)
                : isActive ? Color.accentColor.opacity(0.10) : Color.clear
        )
        .overlay {
            if isDragTargeted {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.accentColor, lineWidth: 1.5)
                    .padding(.horizontal, 2)
            }
        }
        .contentShape(Rectangle())
        .onDrag { NSItemProvider(object: node.url as NSURL) }
        .onDrop(of: [.fileURL], isTargeted: dragTargetBinding) { providers in
            acceptDrop(providers, into: node.url)
        }
        .contextMenu {
            Button("Open in Pane 1") {
                appState.primaryBrowser.navigate(to: node.url)
                appState.activePaneIsSecondary = false
            }
            Button("Open in Pane 2") {
                appState.secondaryBrowser.navigate(to: node.url)
                appState.isDualPane = true
                appState.activePaneIsSecondary = true
            }
            Divider()
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(node.url.path(percentEncoded: false), forType: .string)
            }
            Divider()
            Button("Open in Terminal") {
                appState.activeBrowser.navigate(to: node.url)
                appState.activeBrowser.showTerminal = true
                appState.activeBrowser.terminalChangeDirectory?(node.url)
            }
        }
    }

    // MARK: - Drop

    private var dragTargetBinding: Binding<Bool> {
        Binding(
            get: { isDragTargeted },
            set: { targeted in
                isDragTargeted = targeted
                if targeted {
                    springLoadTask?.cancel()
                    springLoadTask = Task {
                        try? await Task.sleep(nanoseconds: 1_200_000_000) // 1.2 s
                        guard !Task.isCancelled else { return }
                        if !node.isExpanded {
                            controller.toggle(node, service: appState.fileSystemService,
                                              showHidden: appState.preferences.showHiddenFiles)
                        }
                    }
                } else {
                    springLoadTask?.cancel()
                    springLoadTask = nil
                }
            }
        )
    }

    @discardableResult
    private func acceptDrop(_ providers: [NSItemProvider], into destination: URL) -> Bool {
        guard !providers.isEmpty else { return false }
        let showHidden = appState.preferences.showHiddenFiles
        for provider in providers {
            provider.loadObject(ofClass: NSURL.self) { reading, _ in
                guard let source = reading as? URL else { return }
                let destPath = destination.path(percentEncoded: false)
                let srcPath  = source.path(percentEncoded: false)
                guard source != destination,
                      !destPath.hasPrefix(srcPath + "/") else { return }
                let dest = destination.appendingPathComponent(source.lastPathComponent)
                do {
                    try FileManager.default.moveItem(at: source, to: dest)
                } catch {
                    try? FileManager.default.copyItem(at: source, to: dest)
                }
                DispatchQueue.main.async {
                    Task { await appState.activeBrowser.load(showHidden: showHidden) }
                }
            }
        }
        return true
    }

    // MARK: - Navigation

    private func navigateAction() {
        let alreadyHere = appState.activeBrowser.currentURL.standardizedFileURL
            == node.url.standardizedFileURL

        appState.activeBrowser.navigate(to: node.url)

        if alreadyHere || node.isExpanded {
            // Same URL: onChange won't fire, so toggle manually.
            // Already expanded from a different URL: collapse (onChange will re-expand).
            controller.toggle(node, service: appState.fileSystemService,
                              showHidden: appState.preferences.showHiddenFiles)
        }
        // Collapsed + URL changes: onChange fires and calls expandNode automatically.
    }
}

#Preview {
    SidebarView().environment(AppState())
}
