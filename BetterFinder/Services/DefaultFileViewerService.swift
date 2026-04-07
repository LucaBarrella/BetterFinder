import AppKit
import UniformTypeIdentifiers

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
        readGlobalDefault("NSFileViewer") == Bundle.main.bundleIdentifier
    }

    // MARK: - Registration

    func register() {
        let bundleID = Bundle.main.bundleIdentifier!

        // 1. NSFileViewer global default — NSWorkspace.activateFileViewerSelecting reads this key
        //    to decide which app to use for "Reveal in Finder". Must be in the global (-g) domain.
        writeGlobalDefault("NSFileViewer", value: bundleID)

        // 2. Launch Services — folder double-click, Dock, NSWorkspace.open
        //    Register both public.folder and public.directory: VS Code-based apps use the latter.
        let appURL = Bundle.main.bundleURL
        NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: UTType.folder) { _ in }
        NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: UTType.directory) { error in
            if let error {
                print("[DefaultFileViewerService] LSHandlers error: \(error.localizedDescription)")
            }
        }
    }

    func unregister() {
        // 1. Delete NSFileViewer so the system falls back to Finder
        deleteGlobalDefault("NSFileViewer")

        // 2. Restore Finder for both public.folder and public.directory
        if let finderURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder") {
            NSWorkspace.shared.setDefaultApplication(at: finderURL, toOpen: UTType.folder) { _ in }
            NSWorkspace.shared.setDefaultApplication(at: finderURL, toOpen: UTType.directory) { _ in }
        }
    }

    // MARK: - Private — global defaults via /usr/bin/defaults
    // CFPreferencesSetValue does not reliably target the global (-g) domain that
    // NSWorkspace reads. Using the `defaults` CLI is the proven approach used by
    // Path Finder, ForkLift, and Folders.

    private func writeGlobalDefault(_ key: String, value: String) {
        run("/usr/bin/defaults", args: ["write", "-g", key, value])
    }

    private func deleteGlobalDefault(_ key: String) {
        run("/usr/bin/defaults", args: ["delete", "-g", key])
    }

    private func readGlobalDefault(_ key: String) -> String? {
        let pipe = Pipe()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = ["read", "-g", key]
        task.standardOutput = pipe
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    private func run(_ path: String, args: [String]) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()
        return task.terminationStatus == 0
    }
}
