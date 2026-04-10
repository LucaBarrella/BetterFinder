import SwiftUI
import AppKit

// MARK: - TerminalPanelView

struct TerminalPanelView: View {
    let browser: BrowserState

    var body: some View {
        VStack(spacing: 0) {
            TerminalHeaderBar(browser: browser)
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
        HStack(spacing: 4) {
            // Shell icon
            Image(systemName: "terminal.fill")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            // Shell name
            Text(browser.shellName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)

            // Current path
            if let url = browser.terminalCurrentURL {
                Text(":")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                Text(abbreviatedPath(url))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer(minLength: 8)

            // Sync toggle
            TerminalButton(
                icon: "arrow.left.arrow.right",
                tooltip: "Toggle directory sync",
                active: browser.terminalSyncEnabled
            ) { browser.terminalSyncEnabled.toggle() }

            // cd terminal to current folder
            TerminalButton(
                icon: "arrow.right.to.line",
                tooltip: "cd terminal to current folder"
            ) {
                browser.terminalChangeDirectory?(browser.currentURL)
            }

            // Insert selected path
            TerminalButton(
                icon: "doc.on.clipboard",
                tooltip: "Insert selected path into terminal",
                enabled: !browser.selectedFileItems.isEmpty
            ) {
                guard let item = browser.selectedFileItems.first else { return }
                let path = "'" + item.url.path(percentEncoded: false)
                    .replacingOccurrences(of: "'", with: "'\\''") + "'"
                browser.terminalSendText?(path + " ")
            }

            // Font size
            TerminalButton(
                icon: "textformat.size.larger",
                tooltip: "Increase font size (⌘+)"
            ) {
                browser.terminalFontSize = min(24, browser.terminalFontSize + 1)
            }

            TerminalButton(
                icon: "textformat.size.smaller",
                tooltip: "Decrease font size (⌘-)"
            ) {
                browser.terminalFontSize = max(9, browser.terminalFontSize - 1)
            }

            // Tools setup
            TerminalButton(
                icon: "wrench.and.screwdriver",
                tooltip: "Terminal Tools Setup"
            ) {
                browser.showTerminalSetup = true
            }
            .popover(isPresented: Bindable(browser).showTerminalSetup, arrowEdge: .bottom) {
                TerminalSetupView(browser: browser)
            }

            // Close
            TerminalButton(
                icon: "chevron.down",
                tooltip: "Hide terminal (F4)"
            ) {
                browser.showTerminal = false
            }
        }
        .font(.system(size: 11))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }

    private func abbreviatedPath(_ url: URL) -> String {
        let path = url.path(percentEncoded: false)
        let home = URL.homeDirectory.path(percentEncoded: false)
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}

// MARK: - Terminal button

private struct TerminalButton: View {
    let icon: String
    let tooltip: String
    var active: Bool = false
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
                .foregroundStyle(active ? .primary : .secondary)
                .opacity(enabled ? (active ? 1.0 : 0.8) : 0.3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(active ? Color.accentColor.opacity(0.15) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(tooltip)
    }
}