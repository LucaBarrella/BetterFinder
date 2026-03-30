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
        .background(F4KeyMonitor {
            appState.activeBrowser.showTerminal.toggle()
        })
    }

    // MARK: - Detail Area

    private var previewURL: URL? {
        appState.activeBrowser.selectedFileItems.first?.url
    }

    @ViewBuilder
    private var detailContent: some View {
        if appState.preferences.showPreviewPanel {
            HSplitView {
                panesArea
                    .frame(minWidth: 380)
                PreviewPanelView(url: previewURL)
                    .frame(minWidth: 260, idealWidth: 320, maxWidth: 540)
            }
        } else {
            panesArea
        }
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
            FilePaneView(browser: appState.primaryBrowser)
            if appState.primaryBrowser.showTerminal {
                Divider()
                TerminalPanelView(browser: appState.primaryBrowser)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if appState.preferences.showStatusBar {
                Divider()
                StatusBarView(browser: appState.primaryBrowser)
            }
            Divider()
            OperationsBarView()
        }
        .animation(.easeInOut(duration: 0.2), value: appState.primaryBrowser.showTerminal)
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
            FilePaneView(browser: browser)
                .onTapGesture { onActivate() }
            if browser.showTerminal {
                Divider()
                TerminalPanelView(browser: browser)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            // Per-pane status bar (replaces the shared one in dual-pane)
            if appState.preferences.showStatusBar {
                Divider()
                StatusBarView(browser: browser)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: browser.showTerminal)
        .overlay(alignment: .top) {
            if isActive { Rectangle().fill(Color.accentColor).frame(height: 2) }
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

#Preview {
    ContentView().environment(AppState())
}
