import SwiftUI
import AppKit
import SwiftTerm
import Darwin

// MARK: - SwiftUI wrapper around DropTerminalView

struct SwiftTermRepresentable: NSViewRepresentable {
    let browser: BrowserState

    func makeCoordinator() -> Coordinator {
        Coordinator(browser: browser)
    }

    func makeNSView(context: Context) -> DropTerminalView {
        let view = DropTerminalView(frame: .zero)
        view.processDelegate = context.coordinator
        view.font = .monospacedSystemFont(ofSize: browser.terminalFontSize, weight: .regular)
        context.coordinator.start(view: view, initialDirectory: browser.currentURL)
        return view
    }

    func updateNSView(_ view: DropTerminalView, context: Context) {
        let desired = NSFont.monospacedSystemFont(ofSize: browser.terminalFontSize, weight: .regular)
        if view.font.pointSize != desired.pointSize {
            view.font = desired
        }
    }
}

// MARK: - Drop-capable terminal view

/// Subclass of LocalProcessTerminalView that accepts file drag-and-drop.
/// Dropping files inserts shell-quoted paths at the current cursor position.
/// Option+drop on a single directory runs `cd` instead of inserting the path.
final class DropTerminalView: LocalProcessTerminalView {

    /// Called when files are dropped. `optionHeld` is true when ⌥ is held.
    var onFileDrop: (([URL], Bool) -> Void)?

    private let highlightBorder = CALayer()
    private let highlightFill   = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        registerForDraggedTypes([.fileURL])
        setupDropHighlight()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupDropHighlight() {
        // Semi-transparent fill
        highlightFill.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.06).cgColor
        highlightFill.isHidden = true

        // Accent-color border
        highlightBorder.borderColor  = NSColor.controlAccentColor.withAlphaComponent(0.7).cgColor
        highlightBorder.borderWidth  = 2
        highlightBorder.cornerRadius = 4
        highlightBorder.isHidden     = true

        layer?.addSublayer(highlightFill)
        layer?.addSublayer(highlightBorder)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        highlightFill.frame   = bounds
        highlightBorder.frame = bounds.insetBy(dx: 1, dy: 1)
        CATransaction.commit()
    }

    // MARK: - NSDraggingDestination

    private func acceptsDrag(_ info: NSDraggingInfo) -> Bool {
        info.draggingPasteboard.canReadObject(forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard acceptsDrag(sender) else { return [] }
        showHighlight(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard acceptsDrag(sender) else { return [] }
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        showHighlight(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        showHighlight(false)
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty else { return false }

        let optionHeld = NSApp.currentEvent?.modifierFlags.contains(.option) ?? false
        onFileDrop?(urls, optionHeld)
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        showHighlight(false)
    }

    private func showHighlight(_ on: Bool) {
        highlightFill.isHidden   = !on
        highlightBorder.isHidden = !on
    }

    // MARK: - Cell metrics (mirrors SwiftTerm's computeFontDimensions)

    /// Approximate cell size computed from the current font — matches SwiftTerm's
    /// internal cellDimension so coordinate conversions are accurate.
    var cellSize: CGSize {
        let ctFont = font as CTFont
        let glyph  = CTFontGetGlyphWithName(ctFont, "W" as CFString)
        let w      = CTFontGetAdvancesForGlyphs(ctFont, .horizontal, [glyph], nil, 1)
        let h      = ceil(CTFontGetAscent(ctFont) + CTFontGetDescent(ctFont) + CTFontGetLeading(ctFont))
        let scale  = window?.backingScaleFactor ?? 1.0
        return CGSize(width:  ceil(w * scale) / scale,
                      height: ceil(h * scale) / scale)
    }
}

// MARK: - Coordinator

extension SwiftTermRepresentable {

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {

        let browser: BrowserState
        private weak var termView: DropTerminalView?

        init(browser: BrowserState) {
            self.browser = browser
            super.init()
        }

        // MARK: - Setup

        func start(view: DropTerminalView, initialDirectory: URL) {
            termView = view

            // Wire BrowserState callbacks so toolbar/panel can send text
            browser.terminalSendText = { [weak view] text in
                view?.send(txt: text)
            }
            browser.terminalChangeDirectory = { [weak view] url in
                let escaped = url.path(percentEncoded: false)
                    .replacingOccurrences(of: "'", with: "'\\''")
                view?.send(txt: " cd '\(escaped)'\r")
            }

            // Wire drag-and-drop: dropped files insert shell-quoted paths.
            // Option + single directory → cd to it instead.
            view.onFileDrop = { [weak view, weak self] urls, optionHeld in
                guard let self, let view else { return }
                if optionHeld, urls.count == 1, urls[0].hasDirectoryPath {
                    browser.terminalChangeDirectory?(urls[0])
                    return
                }
                let text = urls
                    .map { "'" + $0.path(percentEncoded: false)
                                    .replacingOccurrences(of: "'", with: "'\\''") + "'" }
                    .joined(separator: " ")
                view.send(txt: text + " ")
            }

            let shell = resolvedShell()
            let env   = buildEnvironment(shell: shell)

            view.startProcess(
                executable: shell,
                args: ["--login"],
                environment: env,
                currentDirectory: initialDirectory.path(percentEncoded: false)
            )
        }

        // MARK: - LocalProcessTerminalViewDelegate

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            // `directory` is the raw OSC 7 payload — a full file:// URL string
            // e.g. "file://hostname/Users/name/Desktop"
            // We must parse it as a URL (not use fileURLWithPath which treats it as a filename).
            guard let dirStr = directory else { return }

            let localPath: String
            if dirStr.hasPrefix("file://"), let parsed = URL(string: dirStr) {
                localPath = parsed.path(percentEncoded: false)
            } else {
                localPath = dirStr   // bare path fallback
            }
            guard !localPath.isEmpty else { return }
            let url = URL(fileURLWithPath: localPath, isDirectory: true)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                browser.terminalCurrentURL = url
                if browser.terminalSyncEnabled {
                    browser.navigate(to: url)
                }
            }
        }

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, let view = termView else { return }
                let shell = resolvedShell()
                let env   = buildEnvironment(shell: shell)
                view.startProcess(
                    executable: shell,
                    args: ["--login"],
                    environment: env,
                    currentDirectory: browser.currentURL.path(percentEncoded: false)
                )
            }
        }

        // MARK: - Shell integration injection

        /// Builds an environment that injects OSC 7 directory-tracking hooks into
        /// the shell startup without touching the user's actual dotfiles.
        private func buildEnvironment(shell: String) -> [String] {
            var env = ProcessInfo.processInfo.environment
            env["TERM"]      = "xterm-256color"
            env["COLORTERM"] = "truecolor"
            env["TERM_PROGRAM"] = "BetterFinder"

            if shell.hasSuffix("zsh") {
                if let zdotdir = injectZshIntegration() {
                    env["ZDOTDIR"] = zdotdir
                }
            } else if shell.hasSuffix("bash") {
                let existingPC = env["PROMPT_COMMAND"] ?? ""
                let osc7 = #"printf '\e]7;file://%s%s\a' "${HOSTNAME:-$(hostname)}" "${PWD}""#
                env["PROMPT_COMMAND"] = existingPC.isEmpty ? osc7 : "\(osc7); \(existingPC)"
            }
            // fish: handled natively by fish's OSC 7 support (fish 3.3+)

            return env.map { "\($0.key)=\($0.value)" }
        }

        /// Creates a temporary ZDOTDIR with `.zprofile` + `.zshrc` that source the
        /// user's real configs and append our OSC 7 precmd hook.
        private func injectZshIntegration() -> String? {
            let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("BetterFinder-zsh-\(ProcessInfo.processInfo.processIdentifier)")

            do {
                try FileManager.default.createDirectory(
                    at: tmpDir, withIntermediateDirectories: true)

                try "".write(to: tmpDir.appendingPathComponent(".zprofile"),
                             atomically: true, encoding: .utf8)

                let zshrc = """
                # Source the user's real configs (ZDOTDIR overrides where zsh looks)
                [[ -f "$HOME/.zprofile" ]] && builtin source "$HOME/.zprofile"
                [[ -f "$HOME/.zshrc"    ]] && builtin source "$HOME/.zshrc"

                # BetterFinder shell integration
                # Emit OSC 7 on every prompt so the file manager tracks the CWD.
                _betterfinder_osc7() {
                    builtin printf '\\e]7;file://%s%s\\a' "${HOSTNAME:-$(hostname)}" "${PWD}"
                }
                precmd_functions+=(_betterfinder_osc7)
                # Also fire immediately so the initial directory is captured.
                _betterfinder_osc7
                """
                try zshrc.write(to: tmpDir.appendingPathComponent(".zshrc"),
                                atomically: true, encoding: .utf8)

                return tmpDir.path(percentEncoded: false)
            } catch {
                return nil
            }
        }

        // MARK: - Helpers

        private func resolvedShell() -> String {
            let uid = getuid()
            var buf = [CChar](repeating: 0, count: 1024)
            var pw  = passwd()
            var ptr: UnsafeMutablePointer<passwd>?
            if getpwuid_r(uid, &pw, &buf, buf.count, &ptr) == 0, let p = ptr {
                let s = String(cString: p.pointee.pw_shell)
                if !s.isEmpty { return s }
            }
            return ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        }
    }
}
