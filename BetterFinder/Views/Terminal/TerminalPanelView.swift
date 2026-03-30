import SwiftUI
import AppKit

// MARK: - TerminalPanelView

struct TerminalPanelView: View {
    let browser: BrowserState

    var body: some View {
        VStack(spacing: 0) {
            TerminalHeaderBar(browser: browser)
            Divider()
            SwiftTermRepresentable(browser: browser)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: browser.currentURL) { _, newURL in
            if browser.terminalSyncEnabled {
                browser.terminalChangeDirectory?(newURL)
            }
        }
    }
}

// MARK: - Header

private struct TerminalHeaderBar: View {
    let browser: BrowserState

    var body: some View {
        HStack(spacing: 2) {

            // Shell name + terminal path
            Text(browser.shellName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.leading, 8)

            if let url = browser.terminalCurrentURL {
                Text(abbreviatedPath(url))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            // Sync toggle
            HeaderButton(
                icon: browser.terminalSyncEnabled
                    ? "arrow.left.arrow.right.circle.fill"
                    : "arrow.left.arrow.right.circle",
                tooltip: "Toggle directory sync",
                active: browser.terminalSyncEnabled
            ) { browser.terminalSyncEnabled.toggle() }

            // cd terminal to current folder
            HeaderButton(icon: "arrow.right.to.line",
                         tooltip: "cd terminal to current folder") {
                browser.terminalChangeDirectory?(browser.currentURL)
            }

            // Insert selected path
            HeaderButton(
                icon: "arrow.down.doc",
                tooltip: "Insert selected path into terminal",
                enabled: !browser.selectedFileItems.isEmpty
            ) {
                guard let item = browser.selectedFileItems.first else { return }
                let path = "'" + item.url.path(percentEncoded: false)
                    .replacingOccurrences(of: "'", with: "'\\''") + "'"
                browser.terminalSendText?(path + " ")
            }

            // Font size
            HeaderButton(icon: "minus.magnifyingglass",
                         tooltip: "Decrease font size (⌘-)") {
                browser.terminalFontSize = max(9, browser.terminalFontSize - 1)
            }
            HeaderButton(icon: "plus.magnifyingglass",
                         tooltip: "Increase font size (⌘+)") {
                browser.terminalFontSize = min(24, browser.terminalFontSize + 1)
            }

            // Close
            HeaderButton(icon: "xmark", tooltip: "Close terminal (F4)") {
                browser.showTerminal = false
            }
            .padding(.trailing, 4)
        }
        .frame(height: 30)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func abbreviatedPath(_ url: URL) -> String {
        let path = url.path(percentEncoded: false)
        let home = URL.homeDirectory.path(percentEncoded: false)
        if path == home               { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}

// MARK: - Header button

private struct HeaderButton: View {
    let icon: String
    let tooltip: String
    var active: Bool  = false
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
                .foregroundStyle(active ? Color.accentColor : Color.secondary)
                .opacity(enabled ? 1.0 : 0.35)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(tooltip)
    }
}
