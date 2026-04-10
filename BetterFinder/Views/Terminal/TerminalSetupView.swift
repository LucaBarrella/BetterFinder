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
    
    @State private var currentShell: ShellType = .zsh

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
                        title: "Zsh Autocomplete",
                        description: "Fish-like fast/unobtrusive autosuggestions for zsh.",
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
                        title: "Shell Autocomplete",
                        description: "Autocomplete is built-in for \(currentShell.displayName).",
                        icon: "text.cursor",
                        isWorking: false,
                        isInstalled: true,
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
        isHomebrewInstalled = checkCommandExists("brew")
        isAutocompleteInstalled = checkAutocompleteInstalled()
        isKilocodeInstalled = checkCommandExists("kilocode")
    }
    
    private func checkNodeInstalled() -> Bool {
        return checkCommandExists("node")
    }
    
    private func checkAutocompleteInstalled() -> Bool {
        // Only check for zsh-autosuggestions if using zsh
        guard currentShell == .zsh else { return false }
        
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
    
    private func checkCommandExists(_ command: String) -> Bool {
        // First try with which
        let task = Process()
        task.launchPath = "/usr/bin/which"
        task.arguments = [command]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                return true
            }
        } catch {
            // Fall through to alternative checks
        }
        
        // If which failed, try common installation paths
        switch command {
        case "brew":
            // Check common Homebrew locations
            let paths = [
                "/opt/homebrew/bin/brew",
                "/usr/local/bin/brew",
                "/usr/bin/brew"
            ]
            return paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) != nil
            
        case "kilocode":
            // Check common npm global locations
            let paths = [
                "/opt/homebrew/bin/kilocode",
                "/usr/local/bin/kilocode",
                "/usr/bin/kilocode"
            ]
            return paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) != nil
            
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isInstallingHomebrew = false
            checkInstalledTools()
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isInstallingAutocomplete = false
            checkInstalledTools()
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
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isInstallingKilocode = false
            checkInstalledTools()
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