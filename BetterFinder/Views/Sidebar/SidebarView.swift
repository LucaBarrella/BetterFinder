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

                    SidebarDropStackSection()

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
            .onChange(of: appState.preferences.showHiddenFiles) { _, _ in
                appState.treeController.invalidateAll()
                appState.favoritesController.invalidateAll()
            }
            .onChange(of: appState.activeBrowser.currentURL) { _, newURL in
                Task {
                    // Only expand the Locations tree when the URL is a real file path
                    // that is NOT already a visible root in either section.
                    // expandNode is intentionally omitted — we only want to make the target
                    // visible (by expanding its ancestors), not auto-open the target itself.
                    guard newURL.isFileURL else { return }
                    let isAnyRoot = appState.favoritesController.flatNodes
                        .contains { $0.depth == 0 && $0.node.url.standardizedFileURL == newURL.standardizedFileURL }
                        || appState.treeController.flatNodes
                        .contains { $0.depth == 0 && $0.node.url.standardizedFileURL == newURL.standardizedFileURL }
                    if !isAnyRoot {
                        await appState.treeController.expandPath(
                            to: newURL, service: appState.fileSystemService,
                            showHidden: appState.preferences.showHiddenFiles)
                    }
                    // Collapse branches that are no longer on the current path
                    appState.treeController.collapseIrrelevantNodes(keeping: newURL)
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
        // 10 (leading) + 10 (chevron placeholder) + 4 (spacing) = 24 → aligns text
        // with CollapsibleSectionHeader and SidebarDropStackSection
        HStack(spacing: 4) {
            Color.clear.frame(width: 10)   // placeholder for chevron width
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
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
    @State private var folderIcon: NSImage?
    @State private var isEjecting = false
    @State private var isVolumeEjectable = false

    private var node: TreeNode { flatNode.node }

    private var isActive: Bool {
        guard node.kind != .airdrop else { return false }
        return appState.activeBrowser.currentURL.standardizedFileURL
            == node.url.standardizedFileURL
    }

    private var showChevron: Bool {
        // AirDrop is not expandable
        if node.kind == .airdrop { return false }
        guard let children = node.children else { return true }
        return !children.isEmpty
    }

    @ViewBuilder
    private var nodeIcon: some View {
        if isDragTargeted {
            Image(systemName: "folder.fill.badge.plus")
                .foregroundStyle(Color.accentColor)
                .font(.system(size: 13))
        } else if !node.usesSFSymbol, let icon = folderIcon {
            // Generic subfolder: native blue macOS folder icon
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            // Special path or Locations item: matching SF Symbol (outlined, monochrome)
            Image(systemName: node.systemImage)
                .foregroundStyle(node.iconColor)
                .font(.system(size: 13))
        }
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
                nodeIcon
                    .frame(width: 18, height: 16)
                    .frame(height: 26)
                    .contentShape(Rectangle())
                    .animation(.easeInOut(duration: 0.15), value: isDragTargeted)
            }
            .buttonStyle(.plain)
            .task(id: node.url) {
                guard !node.usesSFSymbol else { folderIcon = nil; return }
                let path = node.url.path(percentEncoded: false)
                folderIcon = await Task.detached(priority: .utility) {
                    let img = NSWorkspace.shared.icon(forFile: path)
                    img.size = NSSize(width: 32, height: 32)
                    return img
                }.value
            }

            // Gap between icon and name (matches Finder's sidebar spacing)
            Color.clear.frame(width: 6)

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

            if isVolumeEjectable {
                Button {
                    isEjecting = true
                    Task {
                        await appState.ejectVolume(for: node.url)
                        isEjecting = false
                    }
                } label: {
                    Image(systemName: "eject.fill")
                        .foregroundStyle(.primary)
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .opacity(isEjecting ? 0.5 : 1)
                .disabled(isEjecting)
                .help(Text("EJECT_VOLUME_TOOLTIP"))
                .accessibilityLabel(Text("EJECT_BUTTON"))
                .padding(.trailing, 8)
            } else {
                Color.clear.frame(width: 8)
            }
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
        .task(id: node.url) {
            guard node.kind == .volume else {
                isVolumeEjectable = false
                return
            }
            isVolumeEjectable = await appState.volumeService.isEjectableVolumeAsync(node.url)
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
                    // AirDrop and Trash don't spring-load (AirDrop not expandable, Trash is a leaf)
                    guard node.kind != .airdrop else { return }
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
        var collected: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            provider.loadObject(ofClass: NSURL.self) { reading, _ in
                if let source = reading as? URL { collected.append(source) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            guard !collected.isEmpty else { return }

            // AirDrop: send via native sharing service (shows device picker with native icons)
            if node.kind == .airdrop {
                if let service = NSSharingService(named: .sendViaAirDrop) {
                    service.perform(withItems: collected as [NSURL])
                }
                return
            }

            let pairs = collected.map { src in
                (from: src, to: destination.appendingPathComponent(src.lastPathComponent))
            }
            // Route through moveFiles so the operation is undo-registered (⌘Z reverses it).
            appState.moveFiles(pairs, actionName: "Move",
                               reloadBrowsers: [appState.primaryBrowser, appState.secondaryBrowser])
        }
        return true
    }

    // MARK: - Navigation

    private func navigateAction() {
        // AirDrop: tell Finder to open its AirDrop browser window
        if node.kind == .airdrop {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-a", "Finder", "airdrop://"]
            try? task.run()
            return
        }

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
