import SwiftUI

/// Toolbar buttons injected via `.toolbar` in ContentView.
struct BrowserToolbar: ToolbarContent {
    @Environment(AppState.self) private var appState

    var body: some ToolbarContent {
        // Navigation (always bound to active pane)
        ToolbarItemGroup(placement: .navigation) {
            Button { appState.activeBrowser.goBack() } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!appState.activeBrowser.canGoBack)
            .help("Back")

            Button { appState.activeBrowser.goForward() } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!appState.activeBrowser.canGoForward)
            .help("Forward")

            Button { appState.activeBrowser.goUp() } label: {
                Image(systemName: "arrow.up")
            }
            .disabled(appState.activeBrowser.parentURL == nil)
            .help("Enclosing Folder")
        }

        // Search — visible only in single-pane mode.
        // In dual-pane, each pane has its own search field in PaneHeaderView.
        ToolbarItem(placement: .principal) {
            if appState.isDualPane {
                EmptyView()
            } else {
                @Bindable var browser = appState.activeBrowser
                SearchField(text: $browser.searchQuery)
                    .frame(minWidth: 200, idealWidth: 260)
            }
        }

        // View mode
        ToolbarItem(placement: .primaryAction) {
            @Bindable var prefs = appState.preferences
            Picker("View", selection: $prefs.viewMode) {
                ForEach(AppPreferences.ViewMode.allCases, id: \.self) { mode in
                    Image(systemName: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 58)
            .help("Switch view mode")
        }

        // Actions
        ToolbarItemGroup(placement: .primaryAction) {
            // Swap panes — only in dual-pane mode
            if appState.isDualPane {
                Button { appState.swapPanes() } label: {
                    Image(systemName: "arrow.left.arrow.right")
                }
                .help("Swap Panes")
            }

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    appState.isDualPane.toggle()
                }
            } label: {
                Image(systemName: appState.isDualPane
                      ? "rectangle.split.2x1.fill"
                      : "rectangle.split.2x1")
            }
            .help(appState.isDualPane ? "Single Pane (⌘D)" : "Dual Pane (⌘D)")
            .keyboardShortcut("d", modifiers: .command)

            Button { appState.preferences.showHiddenFiles.toggle() } label: {
                Image(systemName: appState.preferences.showHiddenFiles ? "eye.fill" : "eye.slash")
                    .symbolRenderingMode(.hierarchical)
            }
            .help(appState.preferences.showHiddenFiles ? "Hide Dot Files" : "Show Dot Files")
            .keyboardShortcut(".", modifiers: [.command, .shift])

            Button { appState.activeBrowser.showTerminal.toggle() } label: {
                Image(systemName: appState.activeBrowser.showTerminal ? "terminal.fill" : "terminal")
                    .symbolRenderingMode(.hierarchical)
            }
            .help(appState.activeBrowser.showTerminal ? "Hide Terminal (F4)" : "Show Terminal (F4)")

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    appState.preferences.showPreviewPanel.toggle()
                }
            } label: {
                Image(systemName: appState.preferences.showPreviewPanel
                      ? "sidebar.right"
                      : "sidebar.right")
                    .symbolRenderingMode(.hierarchical)
                    .opacity(appState.preferences.showPreviewPanel ? 1.0 : 0.5)
            }
            .help(appState.preferences.showPreviewPanel ? "Hide Preview Panel" : "Show Preview Panel")
            .keyboardShortcut("p", modifiers: [.command, .option])

        }
    }
}

// MARK: - Search Field

private struct SearchField: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "Search"
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text { nsView.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        @Binding var text: String
        init(text: Binding<String>) { _text = text }

        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSSearchField { text = field.stringValue }
        }
    }
}
