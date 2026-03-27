import Foundation
import Observation

@Observable
final class AppPreferences {

    var showHiddenFiles: Bool = false {
        didSet { UserDefaults.standard.set(showHiddenFiles, forKey: Keys.showHiddenFiles) }
    }

    var viewMode: ViewMode = .list {
        didSet { UserDefaults.standard.set(viewMode.rawValue, forKey: Keys.viewMode) }
    }

    var showPathBar: Bool = true {
        didSet { UserDefaults.standard.set(showPathBar, forKey: Keys.showPathBar) }
    }

    var showStatusBar: Bool = true {
        didSet { UserDefaults.standard.set(showStatusBar, forKey: Keys.showStatusBar) }
    }

    init() {
        let ud = UserDefaults.standard
        showHiddenFiles = ud.bool(forKey: Keys.showHiddenFiles)
        viewMode = ViewMode(rawValue: ud.string(forKey: Keys.viewMode) ?? "") ?? .list
        showPathBar = ud.object(forKey: Keys.showPathBar) as? Bool ?? true
        showStatusBar = ud.object(forKey: Keys.showStatusBar) as? Bool ?? true
    }

    // MARK: - Types

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
        static let showHiddenFiles = "showHiddenFiles"
        static let viewMode        = "viewMode"
        static let showPathBar     = "showPathBar"
        static let showStatusBar   = "showStatusBar"
    }
}
