import AppKit
import Carbon.HIToolbox

/// Registers a system-wide hot key using Carbon's RegisterEventHotKey API.
/// No Accessibility permission is required.
/// The registered hot key activates BetterFinder from anywhere — even when the
/// app is hidden, minimised, or behind other windows.
final class GlobalHotkeyManager {

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    // The AppState is held weakly so we don't create a retain cycle.
    weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }

    deinit {
        unregister()
    }

    // MARK: - Public

    /// Register (or re-register) the hot key stored in preferences.
    func register(shortcut: AppShortcut) {
        unregister()

        // Skip F-keys and keys that have no single-char equivalent in Carbon
        // (Carbon keycodes map 1-to-1 with AppShortcut keyCodes, so we can
        //  use the keyCode directly).

        // Install a Carbon event handler on the application event target once.
        if eventHandlerRef == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                     eventKind:  UInt32(kEventHotKeyPressed))
            InstallEventHandler(
                GetApplicationEventTarget(),
                { (_, event, userData) -> OSStatus in
                    guard let userData else { return OSStatus(eventNotHandledErr) }
                    let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                    manager.handleHotKey(event)
                    return noErr
                },
                1,
                &spec,
                Unmanaged.passUnretained(self).toOpaque(),
                &eventHandlerRef
            )
        }

        let modifiers = carbonModifiers(from: NSEvent.ModifierFlags(rawValue: shortcut.modifiers))
        var id = EventHotKeyID(signature: fourCC("BFnd"), id: 1)
        RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            modifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    // MARK: - Private

    private func handleHotKey(_ event: EventRef?) {
        DispatchQueue.main.async { [weak self] in
            guard let appState = self?.appState else { return }
            _ = appState  // keep reference alive across async boundary

            // Un-hide the app if it was hidden
            if NSApp.isHidden { NSApp.unhide(nil) }

            // De-miniaturise any miniaturised main window
            for window in NSApp.windows {
                if window.isMiniaturized { window.deminiaturize(nil) }
            }

            // Bring app to front
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.isMainWindow || (!$0.isMiniaturized && $0.isVisible) }?
                .makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Helpers

    /// Convert NSEvent modifier flags to Carbon modifier bits.
    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option)  { carbon |= UInt32(optionKey) }
        if flags.contains(.shift)   { carbon |= UInt32(shiftKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        return carbon
    }

    /// Build an OSType (4-char code) from a 4-character ASCII string.
    private func fourCC(_ s: String) -> OSType {
        let bytes = s.utf8.prefix(4)
        var result: OSType = 0
        for byte in bytes { result = (result << 8) | OSType(byte) }
        return result
    }
}
