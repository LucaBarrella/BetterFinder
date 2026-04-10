//
//  BetterFinderTests.swift
//  BetterFinderTests
//
//  Created by Francesco Albano on 26/03/26.
//

import XCTest
@testable import BetterFinder

final class BetterFinderTests: XCTestCase {
    
    // MARK: - App Shortcut Tests
    
    func testAppShortcutToggleTerminal() throws {
        let shortcut = AppShortcut.toggleTerminal
        XCTAssertEqual(shortcut.keyCode, 118)
        XCTAssertEqual(shortcut.modifiers, 0)
    }
    
    func testAppShortcutClearTerminal() throws {
        let shortcut = AppShortcut.clearTerminal
        XCTAssertEqual(shortcut.keyCode, 40)
    }
    
    func testAppShortcutFocusTerminal() throws {
        let shortcut = AppShortcut.focusTerminal
        XCTAssertEqual(shortcut.keyCode, 17)
    }
    
    func testAppShortcutToggleDualPane() throws {
        let shortcut = AppShortcut.toggleDualPane
        XCTAssertEqual(shortcut.keyCode, 2)
    }
    
    // MARK: - Display String Tests
    
    func testAppShortcutDisplayStringF4() throws {
        XCTAssertEqual(AppShortcut.toggleTerminal.displayString, "F4")
    }
    
    func testAppShortcutDisplayStringCmdK() throws {
        XCTAssertEqual(AppShortcut.clearTerminal.displayString, "⌘K")
    }
    
    func testAppShortcutDisplayStringCmdD() throws {
        XCTAssertEqual(AppShortcut.toggleDualPane.displayString, "⌘D")
    }
    
    // MARK: - Menu Key Equivalent Tests
    
    func testAppShortcutMenuKeyEquivalent() throws {
        XCTAssertEqual(AppShortcut.toggleTerminal.menuKeyEquivalent, "")
        XCTAssertEqual(AppShortcut.clearTerminal.menuKeyEquivalent, "k")
        XCTAssertEqual(AppShortcut.toggleDualPane.menuKeyEquivalent, "d")
    }
    
    // MARK: - App Preferences Tests
    
    func testAppPreferencesDefaults() throws {
        let prefs = AppPreferences()
        XCTAssertFalse(prefs.showHiddenFiles)
        XCTAssertFalse(prefs.foldersFirst)
    }
    
    func testAppPreferencesExternalTerminal() throws {
        let prefs = AppPreferences()
        XCTAssertEqual(prefs.externalTerminal, .terminal)
    }
    
    // MARK: - External Terminal Tests
    
    func testExternalTerminalBundleIdentifiers() throws {
        XCTAssertEqual(AppPreferences.ExternalTerminal.terminal.bundleIdentifier, "com.apple.Terminal")
        XCTAssertEqual(AppPreferences.ExternalTerminal.iTerm2.bundleIdentifier, "com.googlecode.iterm2")
    }
    
    func testExternalTerminalLabels() throws {
        XCTAssertEqual(AppPreferences.ExternalTerminal.terminal.label, "Terminal")
        XCTAssertEqual(AppPreferences.ExternalTerminal.iTerm2.label, "iTerm")
    }
    
    // MARK: - Shell Type Tests
    
    func testShellTypeDisplayName() throws {
        XCTAssertEqual(ShellType.zsh.displayName, "zsh")
        XCTAssertEqual(ShellType.bash.displayName, "bash")
        XCTAssertEqual(ShellType.fish.displayName, "fish")
    }
    
    func testShellTypeEquatable() throws {
        XCTAssertEqual(ShellType.zsh, ShellType.zsh)
        XCTAssertNotEqual(ShellType.zsh, ShellType.bash)
    }
}