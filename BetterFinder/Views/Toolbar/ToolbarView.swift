import SwiftUI

/// Toolbar buttons injected via `.toolbar` in ContentView.
struct BrowserToolbar: ToolbarContent {
    @Environment(AppState.self) private var appState

    var body: some ToolbarContent {
        // Navigation
        ToolbarItemGroup(placement: .navigation) {
            Button {
                appState.activeBrowser.goBack()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!appState.activeBrowser.canGoBack)
            .help("Back")

            Button {
                appState.activeBrowser.goForward()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!appState.activeBrowser.canGoForward)
            .help("Forward")

            Button {
                appState.activeBrowser.goUp()
            } label: {
                Image(systemName: "arrow.up")
            }
            .disabled(appState.activeBrowser.parentURL == nil)
            .help("Enclosing Folder")
        }

        // Search
        ToolbarItem(placement: .principal) {
            @Bindable var browser = appState.activeBrowser
            SearchField(text: $browser.searchQuery)
                .frame(minWidth: 200, idealWidth: 260)
        }

        // Actions
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    appState.isDualPane.toggle()
                }
            } label: {
                Image(systemName: appState.isDualPane
                      ? "rectangle.split.2x1.fill"
                      : "rectangle.split.2x1")
            }
            .help(appState.isDualPane ? "Single Pane" : "Dual Pane")
            .keyboardShortcut("d", modifiers: .command)

            Button {
                appState.preferences.showHiddenFiles.toggle()
            } label: {
                Image(systemName: appState.preferences.showHiddenFiles
                      ? "eye.fill"
                      : "eye.slash")
                    .symbolRenderingMode(.hierarchical)
            }
            .help(appState.preferences.showHiddenFiles ? "Hide Dot Files" : "Show Dot Files")
            .keyboardShortcut(".", modifiers: [.command, .shift])

            Button {
                appState.activeBrowser.showTerminal.toggle()
            } label: {
                Image(systemName: appState.activeBrowser.showTerminal
                      ? "terminal.fill"
                      : "terminal")
                    .symbolRenderingMode(.hierarchical)
            }
            .help(appState.activeBrowser.showTerminal ? "Hide Terminal (F4)" : "Show Terminal (F4)")
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
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        @Binding var text: String
        init(text: Binding<String>) { _text = text }

        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSSearchField {
                text = field.stringValue
            }
        }
    }
}
