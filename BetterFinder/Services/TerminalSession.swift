import Foundation
import Darwin

// MARK: - TerminalSession
// Manages the PTY + shell process. Thread-safe via @unchecked Sendable.
// All callbacks fire on the main queue.

final class TerminalSession: @unchecked Sendable {

    // MARK: Public state

    private(set) var currentShellName: String = "zsh"

    // MARK: Callbacks

    /// Raw bytes from the shell (parse + display these).
    var onData: ((Data) -> Void)?
    /// Fired when the shell emits OSC 7 with a new CWD.
    var onDirectoryChange: ((URL) -> Void)?
    /// Fired when the process exits.
    var onExit: (() -> Void)?

    // MARK: Private

    private var masterFD: Int32 = -1
    private var process: Process?
    private var readSource: DispatchSourceRead?
    private var osc7Buf = ""          // accumulates OSC 7 escape sequence bytes
    private var escBuf  = ""          // accumulates current escape sequence
    private var inOSC   = false       // currently inside an OSC sequence

    // MARK: - Lifecycle

    func start(shell: String? = nil, directory: URL, cols: Int = 80, rows: Int = 24) {
        let shellPath = shell ?? resolvedShell()
        currentShellName = URL(fileURLWithPath: shellPath).lastPathComponent
        var master: Int32 = -1
        var slave:  Int32 = -1
        // Pass initial window size so the shell knows its dimensions from the start
        var ws = winsize()
        ws.ws_col = UInt16(max(20, cols))
        ws.ws_row = UInt16(max(4,  rows))
        guard openpty(&master, &slave, nil, nil, &ws) == 0 else { return }
        masterFD = master

        var env = ProcessInfo.processInfo.environment
        env["TERM"]      = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LANG"]      = env["LANG"] ?? "en_US.UTF-8"
        // Shell integration: ask zsh/fish/bash to emit OSC 7 on every prompt
        if shellPath.hasSuffix("zsh") {
            env["ZDOTDIR"] = nil   // use user's real dotdir
        }

        let p = Process()
        p.executableURL        = URL(fileURLWithPath: shellPath)
        p.arguments            = ["--login"]
        p.currentDirectoryURL  = directory
        p.environment          = env
        let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        p.standardInput  = slaveHandle
        p.standardOutput = slaveHandle
        p.standardError  = slaveHandle
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.onExit?() }
        }

        do { try p.run() } catch { close(slave); close(master); return }
        close(slave)
        process = p

        let src = DispatchSource.makeReadSource(fileDescriptor: master, queue: .main)
        src.setEventHandler  { [weak self] in self?.readAvailable() }
        src.setCancelHandler { close(master) }
        src.resume()
        readSource = src
    }

    func terminate() {
        readSource?.cancel()
        readSource = nil
        process?.terminate()
        process = nil
        masterFD = -1
    }

    // MARK: - I/O

    func write(_ data: Data) {
        guard masterFD >= 0 else { return }
        data.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            _ = Darwin.write(masterFD, base, data.count)
        }
    }

    func writeString(_ s: String) {
        if let d = s.data(using: .utf8) { write(d) }
    }

    /// Change shell CWD programmatically (GUI → Terminal sync).
    func changeDirectory(to url: URL) {
        let p = url.path(percentEncoded: false)
            .replacingOccurrences(of: "'", with: "'\\''")
        writeString(" cd '\(p)'\r")     // leading space hides from history (HISTCONTROL=ignorespace)
    }

    /// Notify the PTY of a terminal resize.
    func resize(cols: Int, rows: Int) {
        guard masterFD >= 0 else { return }
        var ws       = winsize()
        ws.ws_col    = UInt16(cols)
        ws.ws_row    = UInt16(rows)
        ws.ws_xpixel = 0
        ws.ws_ypixel = 0
        _ = ioctl(masterFD, TIOCSWINSZ, &ws)
    }

    // MARK: - Private

    private func readAvailable() {
        var buf = [UInt8](repeating: 0, count: 8192)
        let n   = Darwin.read(masterFD, &buf, buf.count)
        guard n > 0 else { return }
        let data = Data(buf[..<n])
        scanForOSC7(data)
        onData?(data)
    }

    /// Quick-scan bytes for OSC 7 sequences without full VT100 parsing.
    /// OSC 7 format: ESC ] 7 ; file://hostname/path BEL  (or ST = ESC \)
    private func scanForOSC7(_ data: Data) {
        for byte in data {
            let ch = Character(UnicodeScalar(byte))
            if inOSC {
                if byte == 0x07 || (byte == 0x1C) { // BEL or ST
                    processOSC(escBuf)
                    escBuf  = ""
                    inOSC   = false
                } else {
                    escBuf.append(ch)
                }
            } else if byte == 0x1B {
                escBuf = "\u{1B}"
            } else if escBuf == "\u{1B}" && byte == 0x5D { // ESC ]
                escBuf = ""
                inOSC  = true
            } else {
                escBuf = ""
            }
        }
    }

    private func processOSC(_ content: String) {
        // content is the OSC body, e.g. "7;file://hostname/path"
        guard content.hasPrefix("7;") else { return }
        let urlString = String(content.dropFirst(2))
        guard let url  = URL(string: urlString) else { return }
        // file:// → local path
        if url.scheme == "file" {
            let path = url.path(percentEncoded: false)
            let dirURL = URL(fileURLWithPath: path, isDirectory: true)
            onDirectoryChange?(dirURL)
        }
    }

    private func resolvedShell() -> String {
        // Prefer user's login shell from /etc/passwd
        let uid   = getuid()
        var buf   = [CChar](repeating: 0, count: 1024)
        var pw    = passwd()
        var pwPtr: UnsafeMutablePointer<passwd>?
        if getpwuid_r(uid, &pw, &buf, buf.count, &pwPtr) == 0, let ptr = pwPtr {
            let shell = String(cString: ptr.pointee.pw_shell)
            if !shell.isEmpty { return shell }
        }
        return ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }
}
