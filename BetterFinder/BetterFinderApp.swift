import SwiftUI

@main
struct BetterFinderApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1200, height: 750)
        .commands {
            SidebarCommands()
            ToolbarCommands()

            CommandGroup(replacing: .newItem) {}

            CommandMenu("Go") {
                Button("Back") { appState.activeBrowser.goBack() }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(!appState.activeBrowser.canGoBack)

                Button("Forward") { appState.activeBrowser.goForward() }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(!appState.activeBrowser.canGoForward)

                Button("Enclosing Folder") { appState.activeBrowser.goUp() }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                    .disabled(appState.activeBrowser.parentURL == nil)

                Divider()

                Button("Home") {
                    appState.activeBrowser.navigate(to: URL.homeDirectory)
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            }

            CommandMenu("View") {
                Button(appState.preferences.showHiddenFiles ? "Hide Dot Files" : "Show Dot Files") {
                    appState.preferences.showHiddenFiles.toggle()
                }
                .keyboardShortcut(".", modifiers: [.command, .shift])

                Divider()

                Button(appState.isDualPane ? "Single Pane" : "Dual Pane") {
                    appState.isDualPane.toggle()
                }
                .keyboardShortcut("d", modifiers: .command)

                Divider()

                Button(appState.preferences.showPathBar ? "Hide Path Bar" : "Show Path Bar") {
                    appState.preferences.showPathBar.toggle()
                }

                Button(appState.preferences.showStatusBar ? "Hide Status Bar" : "Show Status Bar") {
                    appState.preferences.showStatusBar.toggle()
                }
            }
        }
    }
}
