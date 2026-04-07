import SwiftUI
import AppKit

// MARK: - Icon Grid View

struct FileIconGridView: View {
    let browser: BrowserState
    let items: [FileItem]
    let appState: AppState

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 90, maximum: 130), spacing: 4)],
                spacing: 4
            ) {
                ForEach(items) { item in
                    IconCell(
                        item: item,
                        isSelected: browser.selectedItems.contains(item.id),
                        onSingleTap: { handleTap(item: item) },
                        onCommandTap: { handleCommandTap(item: item) },
                        onDoubleClick: { handleDoubleClick(item: item) }
                    )
                }
            }
            .padding(12)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func handleTap(item: FileItem) {
        appState.activePaneIsSecondary = browser === appState.secondaryBrowser
        browser.selectedItems = [item.id]
        browser.lastSelectedURL = item.url
    }

    private func handleCommandTap(item: FileItem) {
        appState.activePaneIsSecondary = browser === appState.secondaryBrowser
        if browser.selectedItems.contains(item.id) {
            browser.selectedItems.remove(item.id)
        } else {
            browser.selectedItems.insert(item.id)
            browser.lastSelectedURL = item.url
        }
    }

    private func handleDoubleClick(item: FileItem) {
        if item.isDirectory && !item.isPackage {
            browser.navigate(to: item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }
}

// MARK: - Icon Cell

private struct IconCell: View {
    let item: FileItem
    let isSelected: Bool
    let onSingleTap: () -> Void
    let onCommandTap: () -> Void
    let onDoubleClick: () -> Void

    @State private var icon: NSImage?

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                    .frame(width: 68, height: 68)

                Group {
                    if let icon {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .antialiased(true)
                    } else {
                        Image(systemName: item.isDirectory ? "folder.fill" : "doc")
                            .font(.system(size: 32))
                            .foregroundStyle(item.isDirectory ? .yellow : .secondary)
                    }
                }
                .frame(width: 48, height: 48)
            }

            Text(item.name)
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .frame(maxWidth: 88)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onDoubleClick() }
        .onTapGesture(count: 1) {
            let cmdHeld = NSApp.currentEvent?.modifierFlags.contains(.command) ?? false
            if cmdHeld { onCommandTap() } else { onSingleTap() }
        }
        .task(id: item.url) {
            icon = await Task.detached(priority: .utility) {
                NSWorkspace.shared.icon(forFile: item.url.path)
            }.value
        }
    }
}
