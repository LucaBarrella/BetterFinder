import SwiftUI
import AppKit
import Foundation
import Darwin

struct TerminalSetupView: View {
    let browser: BrowserState
    
    @State private var isInstallingHomebrew = false
    @State private var isInstallingAutocomplete = false
    @State private var isInstallingKilocode = false
    
    @State private var isHomebrewInstalled = false
    @State private var isAutocompleteInstalled = false
    @State private var isKilocodeInstalled = false
    
    // Detected user shell and path
    @State private var currentShell: ShellType = .zsh
    @State private var userShellPath: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Terminal Extras")
                .font(.headline)
            
            Text("Enhance your integrated terminal with these essential developer tools.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            VStack(spacing: 12) {
                ToolRow(
                    title: "Homebrew",
                    description: "The missing package manager for macOS.",
                    icon: "cup.and.saucer",
                    isWorking: isInstallingHomebrew,
                    isInstalled: isHomebrewInstalled,
                    action: {
                        installHomebrew()
                    }
                )
                
                // Only show zsh-autosuggestions if using zsh
                if currentShell == .zsh {
                    ToolRow(
                        title: "Zsh Autosuggestions",
                        description: "Fish-like fast autosuggestions for zsh.",
                        icon: "text.cursor",
                        isWorking: isInstallingAutocomplete,
                        isInstalled: isAutocompleteInstalled,
                        action: {
                            installAutocomplete()
                        }
                    )
                } else {
                    // Show message for other shells
                    ToolRow(
                        title: "Shell Autosuggestions",
                        description: "This feature requires zsh as your default shell.",
                        icon: "text.cursor",
                        isWorking: false,
                        isInstalled: false,
                        action: {}
                    )
                }
                
                ToolRow(
                    title: "Kilocode CLI",
                    description: "Open-source AI coding assistant for your terminal.",
                    icon: "sparkles",
                    isWorking: isInstallingKilocode,
                    isInstalled: isKilocodeInstalled,
                    action: {
                        installKilocode()
                    }
                )
            }
            .padding(.top, 8)
        }
        .padding()
        .frame(width: 320)
        .onAppear {
            detectCurrentShell()
            checkInstalledTools()
        }
    }
    
    private func detectCurrentShell() {
        let uid = getuid()
        var buf = [CChar](repeating: 0, count: 1024)
        var pw = passwd()
        var ptr: UnsafeMutablePointer<passwd>?
        
        if getpwuid_r(uid, &pw, &buf, buf.count, &ptr) == 0, let p = ptr {
            let shellPath = String(cString: p.pointee.pw_shell)
            userShellPath = shellPath
            let shellName = URL(fileURLWithPath: shellPath).lastPathComponent.lowercased()
            
            switch shellName {
            case "zsh":
                currentShell = .zsh
            case "bash":
                currentShell = .bash
            case "fish":
                currentShell = .fish
            default:
                currentShell = .other(shellName)
            }
        } else {
            // Fallback to environment variable
            if let shellEnv = ProcessInfo.processInfo.environment["SHELL"] {
                userShellPath = shellEnv
                let shellName = URL(fileURLWithPath: shellEnv).lastPathComponent.lowercased()
                switch shellName {
                case "zsh":
                    currentShell = .zsh
                case "bash":
                    currentShell = .bash
                case "fish":
                    currentShell = .fish
                default:
                    currentShell = .other(shellName)
                }
            }
        }
    }
    
    private func checkInstalledTools() {
        // Capture state locally to avoid reading @State from background threads
        let shellCopy = currentShell
        let shellPathCopy = userShellPath

        DispatchQueue.global(qos: .userInitiated).async {
            let brewInstalled = self.checkCommandExistsInLoginShell("brew", shellPath: shellPathCopy)
            let autocompleteInstalled = self.checkAutocompleteInstalled(for: shellCopy)
            let kilocodeInstalled = self.checkCommandExistsInLoginShell("kilocode", shellPath: shellPathCopy)

            DispatchQueue.main.async {
                self.isHomebrewInstalled = brewInstalled
                self.isAutocompleteInstalled = autocompleteInstalled
                self.isKilocodeInstalled = kilocodeInstalled
            }
        }
    }
    
    private func checkNodeInstalled() -> Bool {
        return checkCommandExistsInLoginShell("node", shellPath: userShellPath)
    }
    
    private func checkAutocompleteInstalled(for shell: ShellType) -> Bool {
        // Only check for zsh-autosuggestions if using zsh
        guard shell == .zsh else { return false }
        
        // Check manual installation
        if checkDirectoryExists("~/.zsh/zsh-autosuggestions") {
            return true
        }
        
        // Check Homebrew installation
        let homebrewPaths = [
            "/opt/homebrew/share/zsh-autosuggestions",
            "/usr/local/share/zsh-autosuggestions",
            "/opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh",
            "/usr/local/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
        ]
        
        return homebrewPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) != nil
    }
    
    private func checkCommandExistsInLoginShell(_ command: String, shellPath: String? = nil) -> Bool {
        // Run the user's login shell so PATH matches the interactive terminal
        let shell = shellPath ?? ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        let task = Process()
        task.executableURL = URL(fileURLWithPath: shell)
        task.arguments = ["-lc", "command -v \(command) >/dev/null 2>&1"]

        task.standardOutput = Pipe()
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                return true
            }
        } catch {
            // Fall through to absolute path checks
        }

        // Fall back to checking common absolute locations
        switch command {
        case "brew":
            let paths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew", "/usr/bin/brew"]
            return paths.contains(where: { FileManager.default.isExecutableFile(atPath: $0) })
        case "kilocode":
            let paths = ["/opt/homebrew/bin/kilocode", "/usr/local/bin/kilocode", "/usr/bin/kilocode"]
            return paths.contains(where: { FileManager.default.isExecutableFile(atPath: $0) })
        case "node":
            let paths = ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"]
            return paths.contains(where: { FileManager.default.isExecutableFile(atPath: $0) })
        default:
            return false
        }
    }
    
    private func checkDirectoryExists(_ path: String) -> Bool {
        let expandedPath = NSString(string: path).expandingTildeInPath
        return FileManager.default.fileExists(atPath: expandedPath)
    }
    
    private func installHomebrew() {
        isInstallingHomebrew = true
        let script = "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        browser.terminalSendText?(script + "\r")

        // Poll for the brew command to appear instead of assuming completion
        pollUntilInstalled(check: { self.checkCommandExistsInLoginShell("brew", shellPath: self.userShellPath) }) { installed in
            self.isInstallingHomebrew = false
            if installed { self.isHomebrewInstalled = true }
        }
    }
    
    private func installAutocomplete() {
        guard currentShell == .zsh else {
            // Show message that autocomplete is not available for this shell
            let script = """
            echo "Zsh Autocomplete is only available for zsh shell."
            echo "Your current shell is: \(currentShell.displayName)"
            echo ""
            echo "For \(currentShell.displayName), autocomplete is built-in or requires different setup."
            """
            browser.terminalSendText?(script + "\r")
            return
        }
        
        isInstallingAutocomplete = true
        // Try Homebrew first, fall back to manual installation
        let script = "brew install zsh-autosuggestions 2>/dev/null || (git clone https://github.com/zsh-users/zsh-autosuggestions ~/.zsh/zsh-autosuggestions && echo 'source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh' >> ~/.zshrc && source ~/.zshrc)"
        browser.terminalSendText?(script + "\r")

        pollUntilInstalled(check: { self.checkAutocompleteInstalled(for: self.currentShell) }) { installed in
            self.isInstallingAutocomplete = false
            if installed { self.isAutocompleteInstalled = true }
        }
    }
    
    private func installKilocode() {
        isInstallingKilocode = true
        
        // Check if Node.js is already installed
        if checkNodeInstalled() {
            // Node.js is installed, install Kilocode CLI directly
            let script = "npm install -g @kilocode/cli"
            browser.terminalSendText?(script + "\r")
        } else if isHomebrewInstalled {
            // Node.js not installed but Homebrew is available, install Node.js via Homebrew
            let script = """
            echo "Installing Node.js via Homebrew..."
            brew install node
            npm install -g @kilocode/cli
            """
            browser.terminalSendText?(script + "\r")
        } else {
            // Neither Node.js nor Homebrew is installed, show clear message
            let script = """
            echo "To install Kilocode CLI, you need either:"
            echo "1. Homebrew (recommended) - install it first, then try again"
            echo "2. Node.js - install it manually, then try again"
            echo ""
            echo "Visit https://brew.sh for Homebrew installation"
            echo "Visit https://nodejs.org for Node.js installation"
            """
            browser.terminalSendText?(script + "\r")
        }

        pollUntilInstalled(check: { self.checkCommandExistsInLoginShell("kilocode", shellPath: self.userShellPath) }) { installed in
            self.isInstallingKilocode = false
            if installed { self.isKilocodeInstalled = true }
        }
    }

    // MARK: - Helpers

    /// Poll until `check()` returns true or timeout elapses.
    private func pollUntilInstalled(check: @escaping () -> Bool, timeout: TimeInterval = 120, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let start = Date()
            var delay: TimeInterval = 0.8
            while Date().timeIntervalSince(start) < timeout {
                if check() {
                    DispatchQueue.main.async { completion(true) }
                    return
                }
                Thread.sleep(forTimeInterval: delay)
                delay = min(5.0, delay * 1.5)
            }
            DispatchQueue.main.async { completion(false) }
        }
    }
}

enum ShellType: Equatable {
    case zsh
    case bash
    case fish
    case other(String)
    
    var displayName: String {
        switch self {
        case .zsh:
            return "zsh"
        case .bash:
            return "bash"
        case .fish:
            return "fish"
        case .other(let name):
            return name
        }
    }
}

private struct ToolRow: View {
    let title: String
    let description: String
    let icon: String
    let isWorking: Bool
    let isInstalled: Bool
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(description).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if isInstalled {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                    Text("Installed")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.green)
            } else {
                Button {
                    action()
                } label: {
                    if isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Install")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovering ? Color.accentColor.opacity(0.05) : Color.clear)
        )
        .onHover { hover in
            isHovering = hover
        }
    }
}
