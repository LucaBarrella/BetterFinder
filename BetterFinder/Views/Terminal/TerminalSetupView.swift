import SwiftUI
import AppKit
import Foundation

struct TerminalSetupView: View {
    let browser: BrowserState
    
    @State private var isInstallingHomebrew = false
    @State private var isInstallingAutocomplete = false
    @State private var isInstallingCopilot = false
    
    @State private var isHomebrewInstalled = false
    @State private var isAutocompleteInstalled = false
    @State private var isCopilotInstalled = false

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
                
                ToolRow(
                    title: "Claude Code",
                    description: "An AI coding assistant right in your terminal.",
                    icon: "sparkles",
                    isWorking: isInstallingCopilot,
                    isInstalled: isCopilotInstalled,
                    action: {
                        installCopilot()
                    }
                )
            }
            .padding(.top, 8)
        }
        .padding()
        .frame(width: 320)
        .onAppear {
            checkInstalledTools()
        }
    }
    
    private func checkInstalledTools() {
        isHomebrewInstalled = checkCommandExists("brew")
        isAutocompleteInstalled = checkDirectoryExists("~/.zsh/zsh-autosuggestions")
        isCopilotInstalled = checkCommandExists("claude-code")
    }
    
    private func checkCommandExists(_ command: String) -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/which"
        task.arguments = [command]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
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
        isInstallingAutocomplete = true
        let script = "git clone https://github.com/zsh-users/zsh-autosuggestions ~/.zsh/zsh-autosuggestions && echo 'source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh' >> ~/.zshrc && source ~/.zshrc"
        browser.terminalSendText?(script + "\r")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isInstallingAutocomplete = false
            checkInstalledTools()
        }
    }
    
    private func installCopilot() {
        isInstallingCopilot = true
        let script = "npm install -g @anthropic-ai/claude-code"
        browser.terminalSendText?(script + "\r")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isInstallingCopilot = false
            checkInstalledTools()
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
