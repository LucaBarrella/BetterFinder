import AppKit

/// A serialisable keyboard shortcut (keyCode + modifier mask).
struct AppShortcut: Codable, Equatable, Hashable {
    let keyCode:   UInt16
    let modifiers: UInt    // NSEvent.ModifierFlags.rawValue (device-independent mask)

    // MARK: - Matching

    func matches(_ event: NSEvent) -> Bool {
        event.keyCode == keyCode &&
        event.modifierFlags.intersection(.deviceIndependentFlagsMask) ==
            NSEvent.ModifierFlags(rawValue: modifiers).intersection(.deviceIndependentFlagsMask)
    }

    // MARK: - Display string  (⌃⌥⇧⌘ order, then key name)

    var displayString: String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option)  { s += "⌥" }
        if flags.contains(.shift)   { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        s += Self.keyName(for: keyCode)
        return s
    }

    // MARK: - Static defaults

    static let rename       = AppShortcut(keyCode: 15,  modifiers: mod(.command))
    static let newFile      = AppShortcut(keyCode: 45,  modifiers: mod(.command, .option))
    static let newFolder    = AppShortcut(keyCode: 45,  modifiers: mod(.command, .shift))
    static let trash        = AppShortcut(keyCode: 51,  modifiers: mod(.command))
    static let toggleHidden = AppShortcut(keyCode: 47,  modifiers: mod(.command, .shift))
    static let toggleTerminal = AppShortcut(keyCode: 118, modifiers: 0)  // F4
    static let toggleDualPane = AppShortcut(keyCode: 2,  modifiers: mod(.command))   // ⌘D
    static let copyToPane   = AppShortcut(keyCode: 96,  modifiers: 0)    // F5
    static let moveToPane   = AppShortcut(keyCode: 97,  modifiers: 0)    // F6

    // Context-menu actions
    static let quickLook    = AppShortcut(keyCode: 49,  modifiers: 0)              // Space
    static let copy         = AppShortcut(keyCode: 8,   modifiers: mod(.command))  // ⌘C
    static let copyPath     = AppShortcut(keyCode: 8,   modifiers: mod(.command, .shift))  // ⌘⇧C
    static let getInfo      = AppShortcut(keyCode: 34,  modifiers: mod(.command))  // ⌘I
    static let duplicate    = AppShortcut(keyCode: 2,   modifiers: mod(.command, .option)) // ⌘⌥D
    static let makeAlias       = AppShortcut(keyCode: 37,  modifiers: mod(.command))  // ⌘L
    static let globalActivate  = AppShortcut(keyCode: 11,  modifiers: mod(.command, .shift)) // ⌘⇧B

    private static func mod(_ flags: NSEvent.ModifierFlags...) -> UInt {
        flags.reduce(NSEvent.ModifierFlags()) { $0.union($1) }.rawValue
    }

    // MARK: - NSMenuItem helpers

    /// Single-character string suitable for NSMenuItem.keyEquivalent.
    /// Returns "" for keys that can't be represented (F-keys, arrows, etc.).
    var menuKeyEquivalent: String {
        switch keyCode {
        case 49: return " "         // Space
        case 36: return "\r"        // Return
        case 48: return "\t"        // Tab
        case 51: return "\u{08}"    // Delete / ⌫
        case 53: return "\u{1B}"    // Escape
        default:
            let name = Self.keyName(for: keyCode)
            // If keyName returned a multi-char string (e.g. "F5") it can't be a key equivalent
            return name.count == 1 ? name.lowercased() : ""
        }
    }

    var menuModifierMask: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers)
    }

    // MARK: - Key name table (no Carbon dependency)

    static func keyName(for keyCode: UInt16) -> String {
        switch keyCode {
        case 0:  "A";  case 1:  "S";  case 2:  "D";  case 3:  "F"
        case 4:  "H";  case 5:  "G";  case 6:  "Z";  case 7:  "X"
        case 8:  "C";  case 9:  "V";  case 11: "B";  case 12: "Q"
        case 13: "W";  case 14: "E";  case 15: "R";  case 16: "Y"
        case 17: "T";  case 31: "O";  case 32: "U";  case 34: "I"
        case 35: "P";  case 37: "L";  case 38: "J";  case 40: "K"
        case 45: "N";  case 46: "M";  case 47: "."
        case 18: "1";  case 19: "2";  case 20: "3";  case 21: "4"
        case 22: "6";  case 23: "5";  case 25: "9";  case 26: "7"
        case 27: "-";  case 28: "8";  case 29: "0"
        case 33: "[";  case 30: "]";  case 41: ";";  case 44: "/"
        case 50: "`";  case 24: "=";  case 42: "\\"
        case 36: "↩";  case 48: "⇥";  case 49: "Space"; case 51: "⌫"
        case 53: "⎋";  case 71: "⌧"
        case 96:  "F5";  case 97:  "F6";  case 98:  "F7";  case 100: "F8"
        case 101: "F9";  case 103: "F11"; case 109: "F10"; case 111: "F12"
        case 115: "↖";   case 119: "↘"
        case 118: "F4";  case 120: "F2";  case 122: "F1";  case 123: "←"
        case 124: "→";   case 125: "↓";   case 126: "↑"
        default: "(\(keyCode))"
        }
    }
}
