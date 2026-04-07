import AppKit
import UniformTypeIdentifiers
import CoreFoundation

/// Manages registration and deregistration of BetterFinder as the system-default file viewer.
///
/// Two separate mechanisms are required:
/// - `NSFileViewer` global default  → makes `NSWorkspace.activateFileViewerSelecting` and
///   `selectFile:inFileViewerRootedAtPath:` open us instead of Finder ("Reveal in Finder" from Xcode, VS Code, etc.)
/// - Launch Services `public.folder` handler → makes double-clicking folders on Desktop/Dock open us
final class DefaultFileViewerService {

    static let shared = DefaultFileViewerService()
    private init() {}

    // MARK: - State

    var isRegistered: Bool {
        let value = CFPreferencesCopyValue(
            "NSFileViewer" as CFString,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        ) as? String
        return value == Bundle.main.bundleIdentifier
    }

    // MARK: - Registration

    func register() {
        let bundleID = Bundle.main.bundleIdentifier!

        // 1. NSFileViewer — intercepted by NSWorkspace reveal/select calls
        setGlobalDefault("NSFileViewer", value: bundleID)

        // 2. Launch Services — folder double-click, Dock, NSWorkspace.open
        NSWorkspace.shared.setDefaultApplication(
            at: Bundle.main.bundleURL,
            toOpen: UTType.folder
        ) { error in
            if let error {
                print("[DefaultFileViewerService] LSHandlers error: \(error.localizedDescription)")
            }
        }
    }

    func unregister() {
        // 1. Restore Finder as NSFileViewer
        setGlobalDefault("NSFileViewer", value: "com.apple.finder")

        // 2. Restore Finder in Launch Services
        if let finderURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder") {
            NSWorkspace.shared.setDefaultApplication(at: finderURL, toOpen: UTType.folder) { _ in }
        }
    }

    // MARK: - Private

    private func setGlobalDefault(_ key: String, value: String) {
        CFPreferencesSetValue(
            key as CFString,
            value as CFString,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        CFPreferencesSynchronize(
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
    }
}
