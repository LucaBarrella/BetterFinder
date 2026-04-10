import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            BrowserToolbar()
        }
        .background(GlobalShortcutMonitor(appState: appState) { action in
            switch action {
            case .toggleTerminal:
                appState.activeBrowser.showTerminal.toggle()
            case .clearTerminal:
                appState.activeBrowser.terminalSendText?("clear\r")
            case .focusTerminal:
                appState.activeBrowser.showTerminal = true
            case .terminalFontUp:
                appState.activeBrowser.terminalFontSize = min(24, appState.activeBrowser.terminalFontSize + 1)
            case .terminalFontDown:
                appState.activeBrowser.terminalFontSize = max(9, appState.activeBrowser.terminalFontSize - 1)
            case .terminalFontReset:
                appState.activeBrowser.terminalFontSize = 13
            case .toggleDualPane:
                appState.isDualPane.toggle()
            }
        })
        .sheet(isPresented: Binding(
            get: { appState.batchRenameState.isPresented },
            set: { appState.batchRenameState.isPresented = $0 }
        )) {
            BatchRenameSheet(state: appState.batchRenameState,
                             onApply: { await appState.applyBatchRename() })
        }
    }

    // MARK: - Detail Area

    private var previewURL: URL? {
        // Use lastSelectedURL (set directly from the table callback by URL, not UUID)
        // so the preview survives directory reloads that reassign item UUIDs.
        appState.activeBrowser.lastSelectedURL
    }

    @ViewBuilder
    private var detailContent: some View {
        // Always keep HSplitView in the hierarchy so panesArea is never destroyed
        // on preview panel toggle — avoids the jarring remount jump.
        HSplitView {
            panesArea
                .frame(minWidth: 380)
            if appState.preferences.showPreviewPanel {
                rightPanel
            }
        }
    }

    // Right column: stable VStack — no conditional tree swap → no jump.
    private var rightPanel: some View {
        VStack(spacing: 0) {
            PreviewPanelView(url: previewURL)
            TrashDropZoneView()
        }
        .frame(minWidth: 240, idealWidth: 300, maxWidth: 520)
    }

    @ViewBuilder
    private var panesArea: some View {
        if appState.isDualPane {
            dualPaneLayout
        } else {
            singlePaneLayout
        }
    }

    private var singlePaneLayout: some View {
        VStack(spacing: 0) {
            if appState.preferences.showPathBar {
                PathBarView(browser: appState.primaryBrowser)
                Divider()
            }
            filePaneWithTerminal(browser: appState.primaryBrowser)
            if appState.preferences.showStatusBar {
                Divider()
                StatusBarView(browser: appState.primaryBrowser)
            }
            Divider()
            OperationsBarView()
        }
    }

    private var dualPaneLayout: some View {
        VStack(spacing: 0) {
            HSplitView {
                paneColumn(browser: appState.primaryBrowser, paneNumber: 1,
                           isActive: !appState.activePaneIsSecondary) {
                    appState.activePaneIsSecondary = false
                }
                paneColumn(browser: appState.secondaryBrowser, paneNumber: 2,
                           isActive: appState.activePaneIsSecondary) {
                    appState.activePaneIsSecondary = true
                }
            }
            Divider()
            OperationsBarView()
        }
        // ⌘1 / ⌘2 to switch active pane
        .background(Group {
            Button("") { appState.activePaneIsSecondary = false }
                .keyboardShortcut("1", modifiers: .command)
            Button("") { appState.activePaneIsSecondary = true }
                .keyboardShortcut("2", modifiers: .command)
        }.hidden())
    }

    @ViewBuilder
    private func paneColumn(
        browser: BrowserState,
        paneNumber: Int,
        isActive: Bool,
        onActivate: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            PaneHeaderView(paneNumber: paneNumber, isActive: isActive, browser: browser)
                .onTapGesture { onActivate() }
            Divider()
            if appState.preferences.showPathBar {
                PathBarView(browser: browser)
                Divider()
            }
            filePaneWithTerminal(browser: browser, onActivate: onActivate)
            // Per-pane status bar (replaces the shared one in dual-pane)
            if appState.preferences.showStatusBar {
                Divider()
                StatusBarView(browser: browser)
            }
        }
        .overlay(alignment: .top) {
            if isActive { Rectangle().fill(Color.accentColor).frame(height: 2) }
        }
    }

    /// Returns a VSplitView (file pane on top, terminal below) when the terminal
    /// is visible, or just the file pane when it's hidden.
    /// VSplitView provides the native macOS drag handle — no custom resize needed.
    @ViewBuilder
    private func filePaneWithTerminal(
        browser: BrowserState,
        onActivate: (() -> Void)? = nil
    ) -> some View {
        if browser.showTerminal {
            VSplitView {
                FilePaneView(browser: browser)
                    .frame(minHeight: 80)
                    .applyIf(onActivate != nil) { $0.onTapGesture { onActivate?() } }
                TerminalPanelView(browser: browser)
                    .frame(minHeight: 60, idealHeight: browser.terminalHeight)
            }
        } else {
            FilePaneView(browser: browser)
                .applyIf(onActivate != nil) { $0.onTapGesture { onActivate?() } }
        }
    }
}

// MARK: - Pane Header (label + per-pane search)

private struct PaneHeaderView: View {
    let paneNumber: Int
    let isActive: Bool
    var browser: BrowserState

    var body: some View {
        @Bindable var b = browser
        HStack(spacing: 0) {
            // Active indicator dot + label
            HStack(spacing: 5) {
                Circle()
                    .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.35))
                    .frame(width: 7, height: 7)
                Text("Pane \(paneNumber)")
                    .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            }
            .padding(.leading, 12)

            Spacer()

            // Per-pane search field
            PaneSearchField(text: $b.searchQuery)
                .frame(width: 210)
                .padding(.trailing, 10)
        }
        .frame(height: 28)
        .background(isActive
            ? Color.accentColor.opacity(0.06)
            : Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Per-Pane Search Field (NSSearchField wrapper)

private struct PaneSearchField: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSSearchField {
        let f = NSSearchField()
        f.placeholderString = "Search"
        f.sendsSearchStringImmediately = true
        f.controlSize = .small
        f.delegate = context.coordinator
        return f
    }

    func updateNSView(_ f: NSSearchField, context: Context) {
        if f.stringValue != text { f.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        @Binding var text: String
        init(text: Binding<String>) { _text = text }
        func controlTextDidChange(_ obj: Notification) {
            if let f = obj.object as? NSSearchField { text = f.stringValue }
        }
    }
}

// MARK: - View helper

private extension View {
    /// Conditionally applies a transform to the view.
    @ViewBuilder
    func applyIf<T: View>(_ condition: Bool, transform: (Self) -> T) -> some View {
        if condition { transform(self) } else { self }
    }
}

#Preview {
    ContentView().environment(AppState())
}
