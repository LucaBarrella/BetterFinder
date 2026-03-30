import SwiftUI

@main
struct BetterFinderApp: App {
    @State private var appState = AppState()
    @State private var serviceProvider = ServiceProvider()
    @State private var hotkeyManager: GlobalHotkeyManager?

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .onAppear {
                    // Register the Services provider so "Reveal in BetterFinder"
                    // appears in the right-click menu of any Cocoa app.
                    serviceProvider.appState = appState
                    NSApp.servicesProvider = serviceProvider
                    // Tell the system to re-scan for updated service registrations.
                    NSUpdateDynamicServices()

                    // Register the global hot key (⌘⇧B by default).
                    let mgr = GlobalHotkeyManager(appState: appState)
                    mgr.register(shortcut: appState.preferences.shortcutGlobalActivate)
                    hotkeyManager = mgr
                }
                // Re-register whenever the user changes the shortcut in Preferences.
                .onChange(of: appState.preferences.shortcutGlobalActivate) { _, newShortcut in
                    hotkeyManager?.register(shortcut: newShortcut)
                }
        }
        .windowStyle(.titleBar)

        Settings {
            PreferencesView()
                .environment(appState)
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1200, height: 750)
        .commands {
            SidebarCommands()
            ToolbarCommands()

            // Replace SwiftUI's default Undo/Redo (which uses its own internal
            // UndoManager) with explicit calls to AppState.undoManager so that
            // all file operations (move, trash, rename, new file…) are undoable.
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { appState.undoManager.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!appState.canUndo)
                Button("Redo") { appState.undoManager.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!appState.canRedo)
            }

            CommandGroup(replacing: .newItem) {
                Button("New File") { appState.newFileInActivePane() }
                    .keyboardShortcut("n", modifiers: [.command, .option])
                Button("New Folder") { appState.newFolderInActivePane() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            CommandMenu("File") {
                Button("Rename") { appState.renameInActivePane() }
                    .disabled(appState.activeBrowser.selectedItems.count != 1)

                Button("Move to Trash") { appState.trashInActivePane() }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(appState.activeBrowser.selectedItems.isEmpty)

                if appState.isDualPane {
                    Divider()

                    let otherPane = appState.activePaneIsSecondary ? 1 : 2
                    Button("Copy to Pane \(otherPane)") { appState.copySelectionToOtherPane() }
                        .disabled(appState.activeBrowser.selectedItems.isEmpty)

                    Button("Move to Pane \(otherPane)") { appState.moveSelectionToOtherPane() }
                        .disabled(appState.activeBrowser.selectedItems.isEmpty)

                    Divider()

                    Button("Go to Other Pane's Location") { appState.goToOtherPaneLocation() }
                    Button("Mirror Pane") { appState.mirrorActivePaneToOther() }
                }
            }

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

                Button(appState.preferences.showPreviewPanel ? "Hide Preview Panel" : "Show Preview Panel") {
                    appState.preferences.showPreviewPanel.toggle()
                }
                .keyboardShortcut("p", modifiers: [.command, .option])

                Divider()

                // Terminal font size — applied to whichever pane's terminal is visible.
                // In dual-pane mode, targets the active pane; otherwise the primary pane.
                Button("Increase Terminal Font Size") {
                    let b = appState.activeBrowser
                    b.terminalFontSize = min(24, b.terminalFontSize + 1)
                }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(!appState.activeBrowser.showTerminal)

                Button("Decrease Terminal Font Size") {
                    let b = appState.activeBrowser
                    b.terminalFontSize = max(9, b.terminalFontSize - 1)
                }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(!appState.activeBrowser.showTerminal)
            }
        }
    }
}
