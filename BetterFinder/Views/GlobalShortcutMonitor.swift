import SwiftUI
import AppKit

/// Global shortcut monitor that handles configurable keyboard shortcuts.
/// Attach via `.background(GlobalShortcutMonitor { ... })`.
struct GlobalShortcutMonitor: NSViewRepresentable {
    let appState: AppState
    let action: (GlobalShortcutAction) -> Void

    func makeNSView(context: Context) -> _MonitorView {
        let v = _MonitorView()
        v.appState = appState
        v.action = action
        return v
    }
    
    func updateNSView(_ v: _MonitorView, context: Context) {
        v.appState = appState
        v.action = action
    }

    final class _MonitorView: NSView {
        var appState: AppState?
        var action: ((GlobalShortcutAction) -> Void)?
        private var monitor: Any?

override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self = self, let appState = self.appState else { return event }
                    
                    let prefs = appState.preferences
                    
                    // Let simple character keys pass through to terminal (unmodified letters/numbers)
                    let isSimpleChar = event.keyCode < 127 && !event.modifierFlags.contains(.command)
                    if isSimpleChar && appState.activeBrowser.showTerminal { return event }

                    // App-level shortcuts work regardless of terminal visibility
                    if prefs.shortcutToggleTerminal.matches(event) {
                        self.action?(.toggleTerminal)
                        return nil
                    }
                    if prefs.shortcutFocusTerminal.matches(event) {
                        self.action?(.focusTerminal)
                        return nil
                    }
                    if prefs.shortcutToggleDualPane.matches(event) {
                        self.action?(.toggleDualPane)
                        return nil
                    }

                    // Terminal-only shortcuts (require terminal to be visible)
                    guard appState.activeBrowser.showTerminal else { return event }
                    
                    // Terminal font shortcuts
                    if prefs.shortcutTerminalFontUp.matches(event) {
                        self.action?(.terminalFontUp)
                        return nil
                    }
                    if prefs.shortcutTerminalFontDown.matches(event) {
                        self.action?(.terminalFontDown)
                        return nil
                    }
                    if prefs.shortcutTerminalFontReset.matches(event) {
                        self.action?(.terminalFontReset)
                        return nil
                    }
                    
                    // Clear terminal
                    if prefs.shortcutClearTerminal.matches(event) {
                        self.action?(.clearTerminal)
                        return nil
                    }
                    
                    // Let other characters pass through
                    return event
                }
            } else {
                if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
            }
        }

        deinit {
            if let m = monitor { NSEvent.removeMonitor(m) }
        }
    }
}

enum GlobalShortcutAction {
    case toggleTerminal
    case clearTerminal
    case focusTerminal
    case terminalFontUp
    case terminalFontDown
    case terminalFontReset
    case toggleDualPane
}