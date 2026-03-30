import SwiftUI
import AppKit

struct FilePaneView: View {
    @Environment(AppState.self) private var appState
    var browser: BrowserState

    private var isGlobalSearch: Bool {
        browser.searchOptions.scope.isAsync && !browser.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var sortedItems: [FileItem] {
        let items     = browser.filteredItems
        let ascending = browser.sortAscending
        let col       = browser.sortColumnID

        func before(_ a: FileItem, _ b: FileItem) -> Bool {
            switch col {
            case "date":
                let cmp = a.sortableDate.compare(b.sortableDate)
                return ascending ? cmp == .orderedAscending : cmp == .orderedDescending
            case "size":
                return ascending ? a.sortableSize < b.sortableSize : a.sortableSize > b.sortableSize
            case "kind":
                let cmp = a.kindDescription.localizedStandardCompare(b.kindDescription)
                return ascending ? cmp == .orderedAscending : cmp == .orderedDescending
            default:   // "name"
                let cmp = a.name.localizedStandardCompare(b.name)
                return ascending ? cmp == .orderedAscending : cmp == .orderedDescending
            }
        }

        if browser.foldersFirst {
            let folders = items.filter(\.isDirectory).sorted(by: before)
            let files   = items.filter { !$0.isDirectory }.sorted(by: before)
            return folders + files
        } else {
            return items.sorted(by: before)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar — slides in whenever there is an active search query
            if !browser.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
                || browser.searchOptions != SearchOptions() {
                SearchFilterBar(browser: browser)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            ZStack {
                if browser.isLoading {
                    loadingView
                } else if browser.isSearching {
                    searchingView
                } else if let err = browser.error {
                    errorView(message: err)
                } else if sortedItems.isEmpty {
                    emptyView
                } else {
                    FileTableView(
                        browser: browser,
                        items: sortedItems,
                        appState: appState,
                        showLocationInKindColumn: isGlobalSearch
                    )
                }
            }
            .animation(.easeInOut(duration: 0.15), value: browser.isSearching)
        }
        .animation(.easeInOut(duration: 0.18),
                   value: !browser.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
                        || browser.searchOptions != SearchOptions())
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
        .onChange(of: browser.searchQuery) { _, _ in
            browser.performSearchIfNeeded(showHidden: appState.preferences.showHiddenFiles)
        }
        .onChange(of: browser.searchOptions) { _, _ in
            browser.performSearchIfNeeded(showHidden: appState.preferences.showHiddenFiles)
        }
    }

    // MARK: - Placeholder Views

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Loading…").foregroundStyle(.secondary).font(.system(size: 13))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var searchingView: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Searching…").foregroundStyle(.secondary).font(.system(size: 13))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            if !browser.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 36)).foregroundStyle(.quaternary)
                Text("No Results").font(.system(size: 14, weight: .medium)).foregroundStyle(.tertiary)
                Text("Try a different search or change the scope.")
                    .font(.system(size: 12)).foregroundStyle(.quaternary)
            } else {
                Image(systemName: "folder").font(.system(size: 36)).foregroundStyle(.quaternary)
                Text("Empty Folder").font(.system(size: 14, weight: .medium)).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 32)).foregroundStyle(.orange)
            Text("Cannot Read Folder").font(.system(size: 14, weight: .medium))
            Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    let state = AppState()
    FilePaneView(browser: state.primaryBrowser)
        .environment(state)
        .frame(width: 800, height: 500)
}
