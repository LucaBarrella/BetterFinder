import SwiftUI

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

    @ViewBuilder
    private var detailContent: some View {
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
                .onTapGesture { appState.activePaneIsSecondary = false }
            if appState.primaryBrowser.showTerminal {
                Divider()
                TerminalPanelView(browser: appState.primaryBrowser)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if appState.preferences.showStatusBar {
                Divider()
                StatusBarView(browser: appState.primaryBrowser)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.primaryBrowser.showTerminal)
    }

    private var dualPaneLayout: some View {
        VStack(spacing: 0) {
            HSplitView {
                paneColumn(browser: appState.primaryBrowser, isActive: !appState.activePaneIsSecondary) {
                    appState.activePaneIsSecondary = false
                }
                paneColumn(browser: appState.secondaryBrowser, isActive: appState.activePaneIsSecondary) {
                    appState.activePaneIsSecondary = true
                }
            }

            if appState.preferences.showStatusBar {
                Divider()
                StatusBarView(browser: appState.activeBrowser)
            }
        }
    }

    @ViewBuilder
    private func paneColumn(
        browser: BrowserState,
        isActive: Bool,
        onActivate: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            if appState.preferences.showPathBar {
                PathBarView(browser: browser)
                    .overlay(alignment: .leading) {
                        if isActive { activePaneIndicator }
                    }
                Divider()
            }
            FilePaneView(browser: browser)
                .onTapGesture { onActivate() }
            if browser.showTerminal {
                Divider()
                TerminalPanelView(browser: browser)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: browser.showTerminal)
    }

    private var activePaneIndicator: some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(width: 2)
            .padding(.vertical, 4)
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
