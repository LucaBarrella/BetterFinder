import Foundation
import Observation

@Observable
final class AppPreferences {

    // MARK: - View

    var showHiddenFiles: Bool = false {
        didSet { ud.set(showHiddenFiles, forKey: Keys.showHiddenFiles) }
    }
    var foldersFirst: Bool = false {
        didSet { ud.set(foldersFirst, forKey: Keys.foldersFirst) }
    }
    var viewMode: ViewMode = .list {
        didSet { ud.set(viewMode.rawValue, forKey: Keys.viewMode) }
    }
    var showPathBar: Bool = true {
        didSet { ud.set(showPathBar, forKey: Keys.showPathBar) }
    }
    var showStatusBar: Bool = true {
        didSet { ud.set(showStatusBar, forKey: Keys.showStatusBar) }
    }

    // MARK: - Startup

    var startInDualPane: Bool = false {
        didSet { ud.set(startInDualPane, forKey: Keys.startInDualPane) }
    }
    var openTerminalByDefault: Bool = false {
        didSet { ud.set(openTerminalByDefault, forKey: Keys.openTerminalByDefault) }
    }
    var showPreviewPanel: Bool = false {
        didSet { ud.set(showPreviewPanel, forKey: Keys.showPreviewPanel) }
    }
    var maxRecentFolders: Int = 10 {
        didSet { ud.set(maxRecentFolders, forKey: Keys.maxRecentFolders) }
    }

    // MARK: - Sorting

    var defaultSortColumn: SortColumn = .dateModified {
        didSet { ud.set(defaultSortColumn.rawValue, forKey: Keys.defaultSortColumn) }
    }
    var defaultSortAscending: Bool = false {
        didSet { ud.set(defaultSortAscending, forKey: Keys.defaultSortAscending) }
    }

    // MARK: - Search defaults

    var defaultSearchScope: SearchOptions.SearchScope = .currentFolder {
        didSet { ud.set(defaultSearchScope.rawValue, forKey: Keys.defaultSearchScope) }
    }
    var defaultSearchMatchMode: SearchOptions.MatchMode = .nameContains {
        didSet { ud.set(defaultSearchMatchMode.rawValue, forKey: Keys.defaultSearchMatchMode) }
    }
    var defaultSearchFileKind: SearchOptions.FileKindFilter = .any {
        didSet { ud.set(defaultSearchFileKind.rawValue, forKey: Keys.defaultSearchFileKind) }
    }

    var defaultSearchOptions: SearchOptions {
        SearchOptions(matchMode: defaultSearchMatchMode,
                      scope:     defaultSearchScope,
                      fileKind:  defaultSearchFileKind)
    }

    // MARK: - Shortcuts

    var shortcutRename: AppShortcut = .rename {
        didSet { saveShortcut(shortcutRename, forKey: Keys.shortcutRename) }
    }
    var shortcutNewFile: AppShortcut = .newFile {
        didSet { saveShortcut(shortcutNewFile, forKey: Keys.shortcutNewFile) }
    }
    var shortcutNewFolder: AppShortcut = .newFolder {
        didSet { saveShortcut(shortcutNewFolder, forKey: Keys.shortcutNewFolder) }
    }
    var shortcutTrash: AppShortcut = .trash {
        didSet { saveShortcut(shortcutTrash, forKey: Keys.shortcutTrash) }
    }
    var shortcutToggleHidden: AppShortcut = .toggleHidden {
        didSet { saveShortcut(shortcutToggleHidden, forKey: Keys.shortcutToggleHidden) }
    }
    var shortcutToggleTerminal: AppShortcut = .toggleTerminal {
        didSet { saveShortcut(shortcutToggleTerminal, forKey: Keys.shortcutToggleTerminal) }
    }
    var shortcutToggleDualPane: AppShortcut = .toggleDualPane {
        didSet { saveShortcut(shortcutToggleDualPane, forKey: Keys.shortcutToggleDualPane) }
    }
    var shortcutCopyToPane: AppShortcut = .copyToPane {
        didSet { saveShortcut(shortcutCopyToPane, forKey: Keys.shortcutCopyToPane) }
    }
    var shortcutMoveToPane: AppShortcut = .moveToPane {
        didSet { saveShortcut(shortcutMoveToPane, forKey: Keys.shortcutMoveToPane) }
    }
    var shortcutQuickLook: AppShortcut = .quickLook {
        didSet { saveShortcut(shortcutQuickLook, forKey: Keys.shortcutQuickLook) }
    }
    var shortcutCut: AppShortcut = .cut {
        didSet { saveShortcut(shortcutCut, forKey: Keys.shortcutCut) }
    }
    var shortcutCopy: AppShortcut = .copy {
        didSet { saveShortcut(shortcutCopy, forKey: Keys.shortcutCopy) }
    }
    var shortcutCopyPath: AppShortcut = .copyPath {
        didSet { saveShortcut(shortcutCopyPath, forKey: Keys.shortcutCopyPath) }
    }
    var shortcutGetInfo: AppShortcut = .getInfo {
        didSet { saveShortcut(shortcutGetInfo, forKey: Keys.shortcutGetInfo) }
    }
    var shortcutDuplicate: AppShortcut = .duplicate {
        didSet { saveShortcut(shortcutDuplicate, forKey: Keys.shortcutDuplicate) }
    }
    var shortcutMakeAlias: AppShortcut = .makeAlias {
        didSet { saveShortcut(shortcutMakeAlias, forKey: Keys.shortcutMakeAlias) }
    }
    var shortcutGlobalActivate: AppShortcut = .globalActivate {
        didSet { saveShortcut(shortcutGlobalActivate, forKey: Keys.shortcutGlobalActivate) }
    }

    // MARK: - Init

    private let ud = UserDefaults.standard

    init() {
        showHiddenFiles   = ud.bool(forKey: Keys.showHiddenFiles)
        foldersFirst      = ud.object(forKey: Keys.foldersFirst) as? Bool ?? false
        viewMode          = ViewMode(rawValue: ud.string(forKey: Keys.viewMode) ?? "") ?? .list
        showPathBar       = ud.object(forKey: Keys.showPathBar)   as? Bool ?? true
        showStatusBar     = ud.object(forKey: Keys.showStatusBar) as? Bool ?? true
        startInDualPane        = ud.bool(forKey: Keys.startInDualPane)
        openTerminalByDefault  = ud.bool(forKey: Keys.openTerminalByDefault)
        showPreviewPanel       = ud.bool(forKey: Keys.showPreviewPanel)
        maxRecentFolders       = ud.object(forKey: Keys.maxRecentFolders) as? Int ?? 10
        defaultSortColumn    = SortColumn(rawValue: ud.string(forKey: Keys.defaultSortColumn) ?? "") ?? .dateModified
        defaultSortAscending = ud.object(forKey: Keys.defaultSortAscending) as? Bool ?? false
        defaultSearchScope     = SearchOptions.SearchScope(rawValue:
                                     ud.string(forKey: Keys.defaultSearchScope) ?? "") ?? .currentFolder
        defaultSearchMatchMode = SearchOptions.MatchMode(rawValue:
                                     ud.string(forKey: Keys.defaultSearchMatchMode) ?? "") ?? .nameContains
        defaultSearchFileKind  = SearchOptions.FileKindFilter(rawValue:
                                     ud.string(forKey: Keys.defaultSearchFileKind) ?? "") ?? .any
        shortcutRename        = loadShortcut(forKey: Keys.shortcutRename)        ?? .rename
        shortcutNewFile       = loadShortcut(forKey: Keys.shortcutNewFile)       ?? .newFile
        shortcutNewFolder     = loadShortcut(forKey: Keys.shortcutNewFolder)     ?? .newFolder
        shortcutTrash         = loadShortcut(forKey: Keys.shortcutTrash)         ?? .trash
        shortcutToggleHidden  = loadShortcut(forKey: Keys.shortcutToggleHidden)  ?? .toggleHidden
        shortcutToggleTerminal = loadShortcut(forKey: Keys.shortcutToggleTerminal) ?? .toggleTerminal
        shortcutToggleDualPane = loadShortcut(forKey: Keys.shortcutToggleDualPane) ?? .toggleDualPane
        shortcutCopyToPane    = loadShortcut(forKey: Keys.shortcutCopyToPane)    ?? .copyToPane
        shortcutMoveToPane    = loadShortcut(forKey: Keys.shortcutMoveToPane)    ?? .moveToPane
        shortcutQuickLook     = loadShortcut(forKey: Keys.shortcutQuickLook)     ?? .quickLook
        shortcutCut           = loadShortcut(forKey: Keys.shortcutCut)           ?? .cut
        shortcutCopy          = loadShortcut(forKey: Keys.shortcutCopy)          ?? .copy
        shortcutCopyPath      = loadShortcut(forKey: Keys.shortcutCopyPath)      ?? .copyPath
        shortcutGetInfo       = loadShortcut(forKey: Keys.shortcutGetInfo)       ?? .getInfo
        shortcutDuplicate     = loadShortcut(forKey: Keys.shortcutDuplicate)     ?? .duplicate
        shortcutMakeAlias        = loadShortcut(forKey: Keys.shortcutMakeAlias)        ?? .makeAlias
        shortcutGlobalActivate   = loadShortcut(forKey: Keys.shortcutGlobalActivate)   ?? .globalActivate
    }

    // MARK: - Shortcut helpers

    private func saveShortcut(_ shortcut: AppShortcut, forKey key: String) {
        if let data = try? JSONEncoder().encode(shortcut) {
            ud.set(data, forKey: key)
        }
    }

    private func loadShortcut(forKey key: String) -> AppShortcut? {
        guard let data = ud.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(AppShortcut.self, from: data)
    }

    // MARK: - Types

    enum SortColumn: String, CaseIterable {
        case name         = "name"
        case dateModified = "date"
        case size         = "size"
        case kind         = "kind"

        var label: String {
            switch self {
            case .name:         return "Name"
            case .dateModified: return "Date Modified"
            case .size:         return "Size"
            case .kind:         return "Kind"
            }
        }

        /// Sensible default direction for each column
        var defaultAscending: Bool {
            switch self {
            case .name, .kind: return true
            case .dateModified, .size: return false
            }
        }
    }

    enum ViewMode: String, CaseIterable {
        case list, icons

        var label: String {
            switch self {
            case .list:  "List"
            case .icons: "Icons"
            }
        }

        var systemImage: String {
            switch self {
            case .list:  "list.bullet"
            case .icons: "square.grid.2x2"
            }
        }
    }

    // MARK: - Keys

    private enum Keys {
        static let defaultSortColumn     = "defaultSortColumn"
        static let defaultSortAscending  = "defaultSortAscending"
        static let showHiddenFiles       = "showHiddenFiles"
        static let foldersFirst          = "foldersFirst"
        static let viewMode              = "viewMode"
        static let showPathBar           = "showPathBar"
        static let showStatusBar         = "showStatusBar"
        static let startInDualPane       = "startInDualPane"
        static let openTerminalByDefault = "openTerminalByDefault"
        static let defaultSearchScope     = "defaultSearchScope"
        static let defaultSearchMatchMode = "defaultSearchMatchMode"
        static let defaultSearchFileKind  = "defaultSearchFileKind"
        static let shortcutRename         = "shortcutRename"
        static let shortcutNewFile        = "shortcutNewFile"
        static let shortcutNewFolder      = "shortcutNewFolder"
        static let shortcutTrash          = "shortcutTrash"
        static let shortcutToggleHidden   = "shortcutToggleHidden"
        static let shortcutToggleTerminal = "shortcutToggleTerminal"
        static let shortcutToggleDualPane = "shortcutToggleDualPane"
        static let shortcutCopyToPane     = "shortcutCopyToPane"
        static let shortcutMoveToPane     = "shortcutMoveToPane"
        static let shortcutQuickLook      = "shortcutQuickLook"
        static let shortcutCut            = "shortcutCut"
        static let shortcutCopy           = "shortcutCopy"
        static let shortcutCopyPath       = "shortcutCopyPath"
        static let shortcutGetInfo        = "shortcutGetInfo"
        static let shortcutDuplicate      = "shortcutDuplicate"
        static let shortcutMakeAlias       = "shortcutMakeAlias"
        static let shortcutGlobalActivate  = "shortcutGlobalActivate"
        static let showPreviewPanel        = "showPreviewPanel"
        static let maxRecentFolders       = "maxRecentFolders"
    }
}
