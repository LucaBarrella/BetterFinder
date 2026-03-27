import SwiftUI
import AppKit
import SwiftTerm
import Darwin

// MARK: - SwiftUI wrapper around SwiftTerm's LocalProcessTerminalView

struct SwiftTermRepresentable: NSViewRepresentable {
    let browser: BrowserState

    func makeCoordinator() -> Coordinator {
        Coordinator(browser: browser)
    }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        view.processDelegate = context.coordinator
        view.font = .monospacedSystemFont(ofSize: browser.terminalFontSize, weight: .regular)
        context.coordinator.start(view: view, initialDirectory: browser.currentURL)
        return view
    }

    func updateNSView(_ view: LocalProcessTerminalView, context: Context) {
        let desired = NSFont.monospacedSystemFont(ofSize: browser.terminalFontSize, weight: .regular)
        if view.font.pointSize != desired.pointSize {
            view.font = desired
        }
    }
}

// MARK: - Coordinator

extension SwiftTermRepresentable {

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {

        let browser: BrowserState
        private weak var termView: LocalProcessTerminalView?

        init(browser: BrowserState) {
            self.browser = browser
            super.init()
        }

        // MARK: - Setup

        func start(view: LocalProcessTerminalView, initialDirectory: URL) {
            termView = view

            // Wire BrowserState callbacks so toolbar buttons can send text
            browser.terminalSendText = { [weak view] text in
                view?.send(txt: text)
            }
            browser.terminalChangeDirectory = { [weak view] url in
                let escaped = url.path(percentEncoded: false)
                    .replacingOccurrences(of: "'", with: "'\\''")
                view?.send(txt: " cd '\(escaped)'\r")
            }

            // Launch login shell, starting directly in the current browser directory
            view.startProcess(
                executable: resolvedShell(),
                args: ["--login"],
                currentDirectory: initialDirectory.path(percentEncoded: false)
            )
        }

        // MARK: - LocalProcessTerminalViewDelegate

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            guard let dir = directory, browser.terminalSyncEnabled else { return }
            let url = URL(fileURLWithPath: dir, isDirectory: true)
            DispatchQueue.main.async { [weak self] in
                self?.browser.navigate(to: url)
            }
        }

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            // Auto-restart shell on exit
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, let view = termView else { return }
                view.startProcess(
                    executable: resolvedShell(),
                    args: ["--login"],
                    currentDirectory: browser.currentURL.path(percentEncoded: false)
                )
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
