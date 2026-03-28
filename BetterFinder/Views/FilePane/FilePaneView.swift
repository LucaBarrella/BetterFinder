import SwiftUI
import AppKit

struct FilePaneView: View {
    @Environment(AppState.self) private var appState
    var browser: BrowserState

    @State private var sortOrder: [KeyPathComparator<FileItem>] = [
        KeyPathComparator(\.name, comparator: .localizedStandard)
    ]

    private var sortedItems: [FileItem] {
        let items = browser.filteredItems
        let folders = items.filter(\.isDirectory).sorted(using: sortOrder)
        let files   = items.filter { !$0.isDirectory }.sorted(using: sortOrder)
        return folders + files
    }

    var body: some View {
        ZStack {
            if browser.isLoading {
                loadingView
            } else if let err = browser.error {
                errorView(message: err)
            } else if sortedItems.isEmpty {
                emptyView
            } else {
                fileTable
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            Task { await browser.load(showHidden: appState.preferences.showHiddenFiles) }
        }
        .onChange(of: browser.currentURL) { _, _ in
            Task { await browser.load(showHidden: appState.preferences.showHiddenFiles) }
        }
        .onChange(of: appState.preferences.showHiddenFiles) { _, newVal in
            Task { await browser.load(showHidden: newVal) }
        }
    }

    // MARK: - Table

    @ViewBuilder
    private var fileTable: some View {
        @Bindable var bnd = browser

        Table(sortedItems, selection: $bnd.selectedItems, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { item in
                FileNameCell(item: item, browser: browser)
                    .onDrag {
                        // When dragging a selected item, carry all selected items' paths.
                        let urls: [URL]
                        if browser.selectedItems.contains(item.id) && browser.selectedItems.count > 1 {
                            urls = browser.selectedFileItems.map(\.url)
                        } else {
                            urls = [item.url]
                        }
                        return NSItemProvider.makeFileDrag(urls: urls)
                    }
            }
            .width(min: 160, ideal: 280)

            TableColumn("Date Modified", value: \.sortableDate) { item in
                Text(item.formattedDate)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 160)

            TableColumn("Size", value: \.sortableSize) { item in
                Text(item.formattedSize)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 80)

            TableColumn("Kind", value: \.kindDescription) { item in
                Text(item.kindDescription)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 130)
        }
        .contextMenu(forSelectionType: FileItem.ID.self) { ids in
            itemContextMenu(for: ids)
        } primaryAction: { ids in
            openItems(with: ids)
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func itemContextMenu(for ids: Set<FileItem.ID>) -> some View {
        let selection = sortedItems.filter { ids.contains($0.id) }

        if let item = selection.first, selection.count == 1 {
            Button("Open") { openItem(item) }

            if item.isDirectory {
                Button("Open in \(appState.isDualPane ? "Other" : "New") Pane") {
                    appState.secondaryBrowser.navigate(to: item.url)
                    appState.isDualPane = true
                }
            }

            Divider()

            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url.path(percentEncoded: false), forType: .string)
            }

            Divider()

            Button("Move to Trash") { trash(items: [item]) }
        } else if selection.count > 1 {
            Button("Open \(selection.count) Items") {
                selection.forEach { openItem($0) }
            }
            Divider()
            Button("Move \(selection.count) Items to Trash") {
                trash(items: selection)
            }
        }
    }

    // MARK: - Actions

    private func openItems(with ids: Set<FileItem.ID>) {
        sortedItems.filter { ids.contains($0.id) }.forEach { openItem($0) }
    }

    private func openItem(_ item: FileItem) {
        if item.isDirectory && !item.isPackage {
            browser.navigate(to: item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    private func trash(items: [FileItem]) {
        for item in items {
            try? FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
        }
    }

    // MARK: - Placeholder Views

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Loading…")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 36))
                .foregroundStyle(.quaternary)
            Text("Empty Folder")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.orange)
            Text("Cannot Read Folder")
                .font(.system(size: 14, weight: .medium))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - File Name Cell

private struct FileNameCell: View {
    let item: FileItem
    let browser: BrowserState

    @State private var icon: NSImage?

    var body: some View {
        HStack(spacing: 7) {
            fileIconView
            Text(item.name)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)
                .opacity(item.isHidden ? 0.45 : 1.0)
        }
    }

    private var fileIconView: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
            } else {
                Image(systemName: item.isDirectory ? "folder.fill" : "doc")
                    .foregroundStyle(item.isDirectory ? .blue : .secondary)
            }
        }
        .frame(width: 16, height: 16)
        .task(id: item.url) {
            icon = await withCheckedContinuation { cont in
                DispatchQueue.global(qos: .userInitiated).async {
                    let img = NSWorkspace.shared.icon(forFile: item.url.path(percentEncoded: false))
                    img.size = NSSize(width: 32, height: 32)
                    cont.resume(returning: img)
                }
            }
        }
    }
}

// MARK: - Drag helper

private extension NSItemProvider {
    /// Creates an item provider suitable for dragging file URLs.
    /// - Provides the first URL as a fileURL item so external apps (Finder, Discord…) can receive it.
    /// - Provides all paths as a plain-text string so terminal views can insert them as shell tokens.
    static func makeFileDrag(urls: [URL]) -> NSItemProvider {
        let provider = NSItemProvider()

        // File URL registration — external apps can receive the actual file
        if let first = urls.first {
            provider.registerObject(first as NSURL, visibility: .all)
        }

        // Plain text — shell-quoted paths for terminal insertion (all items)
        let text = urls
            .map { "'" + $0.path(percentEncoded: false)
                            .replacingOccurrences(of: "'", with: "'\\''") + "'" }
            .joined(separator: " ")
        provider.registerObject(text as NSString, visibility: .all)

        return provider
    }
}

#Preview {
    let state = AppState()
    FilePaneView(browser: state.primaryBrowser)
        .environment(state)
        .frame(width: 800, height: 500)
}
