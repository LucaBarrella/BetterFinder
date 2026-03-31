import SwiftUI

// MARK: - Root

struct PreferencesView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            GeneralPrefsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            SearchPrefsTab()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            ShortcutsPrefsTab()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .environment(appState)
        .frame(width: 480, height: 520)
    }
}

// MARK: - General

private struct GeneralPrefsTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var prefs = appState.preferences
        Form {
            Section("View") {
                Toggle("Show hidden files (dot files)", isOn: $prefs.showHiddenFiles)
                Toggle("Show path bar",                 isOn: $prefs.showPathBar)
                Toggle("Show status bar",               isOn: $prefs.showStatusBar)
                Toggle("Show folders before files",     isOn: $prefs.foldersFirst)
            }
            Section("Startup") {
                Toggle("Start in dual-pane mode",        isOn: $prefs.startInDualPane)
                Toggle("Open terminal panel by default", isOn: $prefs.openTerminalByDefault)
                Toggle("Show preview panel by default",  isOn: $prefs.showPreviewPanel)
            }
            Section("Recents") {
                Stepper(
                    "Max recent folders: \(prefs.maxRecentFolders)",
                    value: $prefs.maxRecentFolders,
                    in: 3...30
                )
            }
        }
        .formStyle(.grouped)
        .padding(.top, 4)
    }
}

// MARK: - Search

private struct SearchPrefsTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var prefs = appState.preferences
        Form {
            Section("Default Search Options") {
                Picker("Scope", selection: $prefs.defaultSearchScope) {
                    ForEach(SearchOptions.SearchScope.allCases) { scope in
                        Label(scope.rawValue, systemImage: scope.icon).tag(scope)
                    }
                }

                Picker("Match mode", selection: $prefs.defaultSearchMatchMode) {
                    ForEach(SearchOptions.MatchMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                Picker("File kind", selection: $prefs.defaultSearchFileKind) {
                    ForEach(SearchOptions.FileKindFilter.allCases) { kind in
                        Label(kind.rawValue, systemImage: kind.icon).tag(kind)
                    }
                }
            }
            .pickerStyle(.menu)
        }
        .formStyle(.grouped)
        .padding(.top, 4)
    }
}

// MARK: - Shortcuts

private struct ShortcutsPrefsTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var prefs = appState.preferences
        Form {
            Section("File Operations") {
                shortcutRow("Rename",             shortcut: $prefs.shortcutRename,    default: .rename)
                shortcutRow("New File",           shortcut: $prefs.shortcutNewFile,   default: .newFile)
                shortcutRow("New Folder",         shortcut: $prefs.shortcutNewFolder, default: .newFolder)
                shortcutRow("Move to Trash",      shortcut: $prefs.shortcutTrash,     default: .trash)
                shortcutRow("Copy to Other Pane", shortcut: $prefs.shortcutCopyToPane, default: .copyToPane)
                shortcutRow("Move to Other Pane", shortcut: $prefs.shortcutMoveToPane, default: .moveToPane)
            }
            Section("Context Menu") {
                shortcutRow("Quick Look",  shortcut: $prefs.shortcutQuickLook,  default: .quickLook)
                shortcutRow("Cut",         shortcut: $prefs.shortcutCut,        default: .cut)
                shortcutRow("Copy",        shortcut: $prefs.shortcutCopy,       default: .copy)
                shortcutRow("Copy Path",   shortcut: $prefs.shortcutCopyPath,   default: .copyPath)
                shortcutRow("Get Info",    shortcut: $prefs.shortcutGetInfo,    default: .getInfo)
                shortcutRow("Duplicate",   shortcut: $prefs.shortcutDuplicate,  default: .duplicate)
                shortcutRow("Make Alias",  shortcut: $prefs.shortcutMakeAlias,  default: .makeAlias)
            }
            Section("View") {
                shortcutRow("Toggle Hidden Files", shortcut: $prefs.shortcutToggleHidden,   default: .toggleHidden)
                shortcutRow("Toggle Terminal",     shortcut: $prefs.shortcutToggleTerminal, default: .toggleTerminal)
                shortcutRow("Toggle Dual Pane",    shortcut: $prefs.shortcutToggleDualPane, default: .toggleDualPane)
            }
            Section("Global Hotkey") {
                shortcutRow("Bring BetterFinder to Front", shortcut: $prefs.shortcutGlobalActivate, default: .globalActivate)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 4)
    }

    private func shortcutRow(
        _ label: String,
        shortcut: Binding<AppShortcut>,
        default defaultShortcut: AppShortcut
    ) -> some View {
        HStack {
            Text(label)
            Spacer()
            ShortcutRecorderField(shortcut: shortcut)
                .frame(width: 130, height: 24)
            if shortcut.wrappedValue != defaultShortcut {
                Button("Reset") { shortcut.wrappedValue = defaultShortcut }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
