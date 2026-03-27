import Foundation
import AppKit

// MARK: - Color

enum TermColor: Equatable {
    case `default`
    case ansi(Int)                        // 0-15
    case c256(Int)                        // 0-255
    case rgb(UInt8, UInt8, UInt8)

    func resolve(isFg: Bool, bold: Bool, dark: Bool) -> NSColor {
        switch self {
        case .default:   return isFg ? (dark ? .white : NSColor(white: 0.1, alpha: 1)) : .clear
        case .ansi(let n):  return Self.ansiPalette[(bold && isFg && n < 8) ? n + 8 : n]
        case .c256(let n):  return Self.xterm256(n)
        case .rgb(let r, let g, let b):
            return NSColor(red: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: 1)
        }
    }

    // xterm 16-color palette (matches most terminals)
    static let ansiPalette: [NSColor] = [
        NSColor(red:0.00, green:0.00, blue:0.00, alpha:1), // 0  black
        NSColor(red:0.80, green:0.10, blue:0.10, alpha:1), // 1  red
        NSColor(red:0.13, green:0.69, blue:0.13, alpha:1), // 2  green
        NSColor(red:0.80, green:0.69, blue:0.00, alpha:1), // 3  yellow
        NSColor(red:0.24, green:0.35, blue:0.87, alpha:1), // 4  blue
        NSColor(red:0.67, green:0.13, blue:0.67, alpha:1), // 5  magenta
        NSColor(red:0.13, green:0.69, blue:0.80, alpha:1), // 6  cyan
        NSColor(red:0.80, green:0.80, blue:0.80, alpha:1), // 7  white
        NSColor(red:0.50, green:0.50, blue:0.50, alpha:1), // 8  bright black
        NSColor(red:1.00, green:0.33, blue:0.33, alpha:1), // 9  bright red
        NSColor(red:0.33, green:1.00, blue:0.33, alpha:1), // 10 bright green
        NSColor(red:1.00, green:1.00, blue:0.33, alpha:1), // 11 bright yellow
        NSColor(red:0.40, green:0.53, blue:1.00, alpha:1), // 12 bright blue
        NSColor(red:1.00, green:0.33, blue:1.00, alpha:1), // 13 bright magenta
        NSColor(red:0.33, green:1.00, blue:1.00, alpha:1), // 14 bright cyan
        NSColor(red:1.00, green:1.00, blue:1.00, alpha:1), // 15 bright white
    ]

    static func xterm256(_ n: Int) -> NSColor {
        if n < 16  { return ansiPalette[n] }
        if n >= 232 {
            let v = CGFloat(8 + (n - 232) * 10) / 255
            return NSColor(white: v, alpha: 1)
        }
        let idx = n - 16
        func c(_ v: Int) -> CGFloat { v == 0 ? 0 : CGFloat(55 + v * 40) / 255 }
        return NSColor(red: c(idx/36), green: c((idx%36)/6), blue: c(idx%6), alpha: 1)
    }
}

// MARK: - Cell

struct CellStyle: Equatable {
    var fg: TermColor = .default
    var bg: TermColor = .default
    var bold       = false
    var dim        = false
    var italic     = false
    var underline  = false
    var inverse    = false
    var strike     = false
}

struct TermCell: Equatable {
    var scalar: Unicode.Scalar = " "
    var style:  CellStyle      = .init()
    var wide:   Bool           = false   // double-width character (CJK etc.)
}

// MARK: - Buffer

final class TerminalBuffer {
    static let maxScrollback = 8_000

    var cols: Int
    var rows: Int
    var lines:     [[TermCell]]   // screen lines
    var scrollback:[[TermCell]] = []

    var cursorRow: Int = 0
    var cursorCol: Int = 0
    var style:     CellStyle = .init()
    var scrollTop: Int = 0
    var scrollBot: Int

    private var savedRow: Int = 0
    private var savedCol: Int = 0
    private var savedStyle: CellStyle = .init()

    // Alternate screen
    private(set) var inAlt = false
    private var altLines:  [[TermCell]]?
    private var altRow = 0, altCol = 0

    // Character set
    var charset: [Unicode.Scalar: Unicode.Scalar] = [:]

    func hardReset() {
        lines   = Self.blank(cols: cols, rows: rows)
        scrollback.removeAll()
        cursorRow = 0; cursorCol = 0
        style     = CellStyle()
        scrollTop = 0; scrollBot = rows - 1
        if inAlt { exitAlt() }
    }

    init(cols: Int, rows: Int) {
        self.cols    = cols
        self.rows    = rows
        self.lines   = Self.blank(cols: cols, rows: rows)
        self.scrollBot = rows - 1
    }

    static func blank(cols: Int, rows: Int) -> [[TermCell]] {
        Array(repeating: Array(repeating: TermCell(), count: max(1,cols)), count: max(1,rows))
    }

    // MARK: Resize

    func resize(cols newC: Int, rows newR: Int) {
        let nc = max(1, newC), nr = max(1, newR)
        lines = lines.map { padRow($0, to: nc) }
        if lines.count < nr { lines += Self.blank(cols: nc, rows: nr - lines.count) }
        else if lines.count > nr { lines = Array(lines.suffix(nr)) }
        cols = nc; rows = nr
        scrollTop = 0; scrollBot = nr - 1
        cursorRow = min(cursorRow, nr - 1)
        cursorCol = min(cursorCol, nc - 1)
    }

    private func padRow(_ row: [TermCell], to n: Int) -> [TermCell] {
        row.count >= n ? Array(row.prefix(n)) : row + Array(repeating: TermCell(), count: n - row.count)
    }

    // MARK: Write

    func put(_ scalar: Unicode.Scalar) {
        guard cursorRow < rows, cursorCol < cols else { return }
        lines[cursorRow][cursorCol] = TermCell(scalar: scalar, style: style)
        cursorCol += 1
        if cursorCol >= cols { linewrap() }
    }

    private func linewrap() {
        cursorCol = 0
        linefeed()
    }

    func linefeed() {
        if cursorRow == scrollBot { scrollUp(1) }
        else if cursorRow < rows - 1 { cursorRow += 1 }
    }

    func carriageReturn() { cursorCol = 0 }

    func backspace() {
        if cursorCol > 0 { cursorCol -= 1 }
    }

    func tab() {
        cursorCol = min(cols - 1, ((cursorCol / 8) + 1) * 8)
    }

    // MARK: Scroll

    func scrollUp(_ n: Int) {
        for _ in 0..<n {
            if !inAlt {
                if scrollback.count >= Self.maxScrollback { scrollback.removeFirst() }
                scrollback.append(lines[scrollTop])
            }
            lines.remove(at: scrollTop)
            lines.insert(Array(repeating: TermCell(), count: cols), at: scrollBot)
        }
    }

    func scrollDown(_ n: Int) {
        for _ in 0..<n {
            lines.remove(at: scrollBot)
            lines.insert(Array(repeating: TermCell(), count: cols), at: scrollTop)
        }
    }

    // MARK: Erase

    func eraseInLine(_ mode: Int) {
        switch mode {
        case 0: for c in cursorCol..<cols { lines[cursorRow][c] = TermCell() }
        case 1: for c in 0...cursorCol   { lines[cursorRow][c] = TermCell() }
        case 2: lines[cursorRow] = Array(repeating: TermCell(), count: cols)
        default: break
        }
    }

    func eraseInDisplay(_ mode: Int) {
        switch mode {
        case 0:
            eraseInLine(0)
            for r in (cursorRow+1)..<rows { lines[r] = Array(repeating: TermCell(), count: cols) }
        case 1:
            for r in 0..<cursorRow { lines[r] = Array(repeating: TermCell(), count: cols) }
            eraseInLine(1)
        case 2:
            lines = Self.blank(cols: cols, rows: rows)
        case 3:
            lines = Self.blank(cols: cols, rows: rows)
            scrollback.removeAll()
        default: break
        }
    }

    func deleteChars(_ n: Int) {
        guard cursorRow < rows else { return }
        var row = lines[cursorRow]
        let end = min(cursorCol + n, cols)
        row.removeSubrange(cursorCol..<end)
        while row.count < cols { row.append(TermCell()) }
        lines[cursorRow] = row
    }

    func insertChars(_ n: Int) {
        guard cursorRow < rows else { return }
        var row = lines[cursorRow]
        let blanks = Array(repeating: TermCell(), count: n)
        row.insert(contentsOf: blanks, at: cursorCol)
        lines[cursorRow] = Array(row.prefix(cols))
    }

    func insertLines(_ n: Int) {
        for _ in 0..<n {
            lines.remove(at: scrollBot)
            lines.insert(Array(repeating: TermCell(), count: cols), at: cursorRow)
        }
    }

    func deleteLines(_ n: Int) {
        for _ in 0..<n {
            lines.remove(at: cursorRow)
            lines.insert(Array(repeating: TermCell(), count: cols), at: scrollBot)
        }
    }

    // MARK: Cursor

    func moveCursor(row: Int, col: Int) {
        cursorRow = max(0, min(rows - 1, row))
        cursorCol = max(0, min(cols - 1, col))
    }

    func saveCursor()    { savedRow = cursorRow; savedCol = cursorCol; savedStyle = style }
    func restoreCursor() { cursorRow = savedRow; cursorCol = savedCol; style = savedStyle }

    // MARK: Alternate screen

    func enterAlt() {
        guard !inAlt else { return }
        altLines = lines; altRow = cursorRow; altCol = cursorCol
        lines = Self.blank(cols: cols, rows: rows)
        cursorRow = 0; cursorCol = 0; inAlt = true
    }

    func exitAlt() {
        guard inAlt, let saved = altLines else { return }
        lines = saved; cursorRow = altRow; cursorCol = altCol
        altLines = nil; inAlt = false
    }

    // MARK: Rendering

    /// Renders only the recently visible portion (scrollback capped at `maxScrollbackDisplay`)
    /// so NSTextView never processes thousands of lines.
    func render(font: NSFont, dark: Bool, maxScrollbackDisplay: Int = 300) -> NSAttributedString {
        let screenLines: [[TermCell]]
        let sbLines: [[TermCell]]
        if inAlt {
            screenLines = lines
            sbLines = []
        } else {
            screenLines = lines
            // Only the last `maxScrollbackDisplay` scrollback rows
            let start = max(0, scrollback.count - maxScrollbackDisplay)
            sbLines = Array(scrollback[start...])
        }
        let all = sbLines + screenLines

        let out = NSMutableAttributedString()
        for (i, row) in all.enumerated() {
            if i > 0 { out.append(NSAttributedString(string: "\n")) }
            appendRow(row, to: out, font: font, dark: dark)
        }
        return out
    }

    /// Returns the row index (in the rendered string) of the cursor.
    func cursorRowInRendered(maxScrollbackDisplay: Int = 300) -> Int {
        if inAlt { return cursorRow }
        let sbShown = min(scrollback.count, maxScrollbackDisplay)
        return sbShown + cursorRow
    }

    // MARK: - Incremental rendering helpers

    /// Renders only the screen lines (no scrollback). Used for incremental NSTextStorage updates.
    func renderScreenOnly(font: NSFont, dark: Bool) -> NSMutableAttributedString {
        let out = NSMutableAttributedString()
        for (i, row) in lines.enumerated() {
            if i > 0 { out.append(NSAttributedString(string: "\n")) }
            appendRow(row, to: out, font: font, dark: dark)
        }
        return out
    }

    /// Renders a range of scrollback lines, each followed by `\n`.
    func renderScrollbackRange(_ range: Range<Int>, font: NSFont, dark: Bool) -> NSMutableAttributedString {
        let out = NSMutableAttributedString()
        for i in range {
            guard i < scrollback.count else { break }
            appendRow(scrollback[i], to: out, font: font, dark: dark)
            out.append(NSAttributedString(string: "\n"))
        }
        return out
    }

    func appendRow(_ row: [TermCell], to out: NSMutableAttributedString, font: NSFont, dark: Bool) {
        // Strip trailing blank cells (same style as default) for performance
        var last = row.count - 1
        while last > 0, row[last].scalar == " ", row[last].style == CellStyle() { last -= 1 }
        guard last >= 0 else { return }

        var runStart = 0
        var runStyle = row[0].style
        for j in 1...(last + 1) {
            let s = j <= last ? row[j].style : runStyle
            if s != runStyle || j == last + 1 {
                let chars = String(row[runStart..<min(j, last+1)].map { Character($0.scalar) })
                if !chars.isEmpty {
                    out.append(NSAttributedString(string: chars,
                        attributes: runStyle.attributes(font: font, dark: dark)))
                }
                runStart = j; runStyle = s
            }
        }
    }
}

extension CellStyle {
    func attributes(font: NSFont, dark: Bool) -> [NSAttributedString.Key: Any] {
        var f: NSFont = font
        var traits = font.fontDescriptor.symbolicTraits
        if bold    { traits.insert(.bold)   }
        if italic  { traits.insert(.italic) }
        if traits != font.fontDescriptor.symbolicTraits {
            f = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits), size: font.pointSize) ?? font
        }

        var fgC = fg.resolve(isFg: true,  bold: bold, dark: dark)
        var bgC = bg.resolve(isFg: false, bold: false, dark: dark)
        if dim { fgC = fgC.withAlphaComponent(0.55) }
        if inverse { swap(&fgC, &bgC) }

        var a: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: fgC]
        if bgC != .clear { a[.backgroundColor] = bgC }
        if underline { a[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if strike    { a[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        return a
    }
}

// MARK: - Engine (ANSI parser → buffer mutations)

final class TerminalEngine {

    let buffer: TerminalBuffer
    var onDirectoryChange: ((URL) -> Void)?
    var onBell: (() -> Void)?
    var onRender: (() -> Void)?    // call this to trigger a redraw
    var onHardReset: (() -> Void)? // fired when terminal is fully reset

    init(cols: Int, rows: Int) {
        buffer = TerminalBuffer(cols: cols, rows: rows)
    }

    // MARK: Parser state

    private enum State {
        case ground, escape, csi, osc, dcs, pm, apc, sos
    }

    private var state:    State  = .ground
    private var params:   String = ""
    private var oscBuf:   String = ""
    private var oscCode:  Int    = -1

    // MARK: Public

    func feed(_ data: Data) {
        for byte in data { feedByte(byte) }
        onRender?()
    }

    // MARK: Byte processing

    private func feedByte(_ b: UInt8) {
        // C0 controls are processed in any state
        switch b {
        case 0x07 where state != .osc:  onBell?(); return
        case 0x0D: buffer.carriageReturn(); return
        case 0x0A, 0x0B, 0x0C: buffer.linefeed(); return
        case 0x08: buffer.backspace(); return
        case 0x09: buffer.tab(); return
        case 0x0F, 0x0E: return // SI/SO charset switch (ignore for now)
        case 0x18, 0x1A: state = .ground; return // CAN/SUB abort
        default: break
        }

        switch state {
        case .ground:     groundByte(b)
        case .escape:     escapeByte(b)
        case .csi:        csiByte(b)
        case .osc:        oscByte(b)
        case .dcs, .pm, .apc, .sos: ignoreUntilST(b)
        }
    }

    private func groundByte(_ b: UInt8) {
        if b == 0x1B { state = .escape; params = ""; return }
        guard b >= 0x20, b != 0x7F else { return }
        // Decode UTF-8 — simplified: treat each byte ≥ 0x20 as a codepoint
        // (proper multi-byte handled below via scalar accumulation)
        feedScalar(b)
    }

    // Accumulate multi-byte UTF-8
    private var utf8Acc: [UInt8] = []
    private func feedScalar(_ b: UInt8) {
        utf8Acc.append(b)
        // Try to decode
        while !utf8Acc.isEmpty {
            if let s = String(bytes: utf8Acc, encoding: .utf8) {
                for scalar in s.unicodeScalars { buffer.put(scalar) }
                utf8Acc.removeAll()
            } else if utf8Acc.count >= 4 {
                // Invalid sequence, drop first byte
                utf8Acc.removeFirst()
            } else {
                break // wait for more bytes
            }
        }
    }

    private func escapeByte(_ b: UInt8) {
        switch b {
        case 0x5B: state = .csi; params = ""    // [  → CSI
        case 0x5D: state = .osc; oscBuf = ""    // ]  → OSC
        case 0x50: state = .dcs                  // P  → DCS
        case 0x5E: state = .pm                   // ^  → PM
        case 0x5F: state = .apc                  // _  → APC
        case 0x58: state = .sos                  // X  → SOS
        case 0x37: buffer.saveCursor(); state = .ground       // 7
        case 0x38: buffer.restoreCursor(); state = .ground    // 8
        case 0x4D: // RI — reverse index
            if buffer.cursorRow == buffer.scrollTop { buffer.scrollDown(1) }
            else if buffer.cursorRow > 0 { buffer.cursorRow -= 1 }
            state = .ground
        case 0x63: // RIS — reset
            resetBuffer(); state = .ground
        case 0x3D, 0x3E: state = .ground // keypad mode (ignore)
        default:   state = .ground
        }
    }

    private func csiByte(_ b: UInt8) {
        if b >= 0x20 && b <= 0x2F { return } // intermediate bytes, skip
        if (b >= 0x30 && b <= 0x3F) { params.append(Character(UnicodeScalar(b))); return }
        // Final byte
        state = .ground
        handleCSI(final: b, params: params)
    }

    private func handleCSI(final f: UInt8, params p: String) {
        // Parse private mode marker
        let priv = p.hasPrefix("?")
        let raw  = priv ? String(p.dropFirst()) : p
        let nums = raw.split(separator: ";", omittingEmptySubsequences: false)
            .map { Int($0) ?? 0 }

        let p1 = nums.first ?? 0
        let p2 = nums.count > 1 ? nums[1] : 0

        let r = buffer.cursorRow, c = buffer.cursorCol

        switch f {
        // Cursor movement
        case 0x41: buffer.moveCursor(row: r - max(1,p1), col: c)              // A up
        case 0x42: buffer.moveCursor(row: r + max(1,p1), col: c)              // B down
        case 0x43: buffer.moveCursor(row: r, col: c + max(1,p1))              // C right
        case 0x44: buffer.moveCursor(row: r, col: c - max(1,p1))              // D left
        case 0x45: buffer.moveCursor(row: r + max(1,p1), col: 0)              // E next line
        case 0x46: buffer.moveCursor(row: r - max(1,p1), col: 0)              // F prev line
        case 0x47: buffer.moveCursor(row: r, col: max(1,p1) - 1)              // G col abs
        case 0x48, 0x66:                                                       // H/f position
            buffer.moveCursor(row: max(1,p1) - 1, col: max(1,p2) - 1)
        case 0x49: buffer.tab()                                                // I CHT
        case 0x4A: buffer.eraseInDisplay(p1)                                  // J
        case 0x4B: buffer.eraseInLine(p1)                                     // K
        case 0x4C: buffer.insertLines(max(1,p1))                              // L
        case 0x4D: buffer.deleteLines(max(1,p1))                              // M
        case 0x50: buffer.deleteChars(max(1,p1))                              // P
        case 0x40: buffer.insertChars(max(1,p1))                              // @
        case 0x53: buffer.scrollUp(max(1,p1))                                 // S
        case 0x54: buffer.scrollDown(max(1,p1))                               // T
        case 0x58: buffer.eraseInLine(0)                                      // X ECH simplified
        case 0x64: buffer.moveCursor(row: max(1,p1) - 1, col: c)              // d row abs
        case 0x6D: handleSGR(nums)                                             // m
        case 0x72: // r — set scroll region
            buffer.scrollTop = max(0, (nums.first.map { $0 - 1 } ?? 0))
            buffer.scrollBot = max(buffer.scrollTop, (nums.count > 1 ? nums[1] - 1 : buffer.rows - 1))
        case 0x73: buffer.saveCursor()                                         // s
        case 0x75: buffer.restoreCursor()                                      // u
        case 0x68: handleMode(priv: priv, nums: nums, set: true)               // h
        case 0x6C: handleMode(priv: priv, nums: nums, set: false)              // l
        default: break
        }
    }

    private func handleMode(priv: Bool, nums: [Int], set: Bool) {
        guard priv else { return }
        for n in nums {
            switch n {
            case 1049: set ? buffer.enterAlt() : buffer.exitAlt()
            case 47, 1047: set ? buffer.enterAlt() : buffer.exitAlt()
            default: break
            }
        }
    }

    private func handleSGR(_ nums: [Int]) {
        var i = 0
        while i < nums.count {
            let n = nums[i]
            switch n {
            case 0:  buffer.style = CellStyle()
            case 1:  buffer.style.bold      = true
            case 2:  buffer.style.dim       = true
            case 3:  buffer.style.italic    = true
            case 4:  buffer.style.underline = true
            case 7:  buffer.style.inverse   = true
            case 9:  buffer.style.strike    = true
            case 22: buffer.style.bold      = false; buffer.style.dim = false
            case 23: buffer.style.italic    = false
            case 24: buffer.style.underline = false
            case 27: buffer.style.inverse   = false
            case 29: buffer.style.strike    = false
            case 30...37: buffer.style.fg = .ansi(n - 30)
            case 38:
                if i+2 < nums.count && nums[i+1] == 5 {
                    buffer.style.fg = .c256(nums[i+2]); i += 2
                } else if i+4 < nums.count && nums[i+1] == 2 {
                    buffer.style.fg = .rgb(UInt8(nums[i+2]), UInt8(nums[i+3]), UInt8(nums[i+4])); i += 4
                }
            case 39: buffer.style.fg = .default
            case 40...47: buffer.style.bg = .ansi(n - 40)
            case 48:
                if i+2 < nums.count && nums[i+1] == 5 {
                    buffer.style.bg = .c256(nums[i+2]); i += 2
                } else if i+4 < nums.count && nums[i+1] == 2 {
                    buffer.style.bg = .rgb(UInt8(nums[i+2]), UInt8(nums[i+3]), UInt8(nums[i+4])); i += 4
                }
            case 49: buffer.style.bg = .default
            case 90...97:  buffer.style.fg = .ansi(n - 90 + 8)
            case 100...107: buffer.style.bg = .ansi(n - 100 + 8)
            default: break
            }
            i += 1
        }
    }

    private func oscByte(_ b: UInt8) {
        if b == 0x07 || b == 0x9C { // BEL or ST
            processOSC(oscBuf); oscBuf = ""; state = .ground
        } else if b == 0x1B {       // start of ESC \ (ST)
            // next byte should be 0x5C (\), handle on next call
            state = .escape         // will fall through to escape handler
        } else {
            oscBuf.append(Character(UnicodeScalar(b)))
        }
    }

    private func processOSC(_ s: String) {
        // Extract code (everything before first ;)
        let parts = s.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
        guard let codeStr = parts.first, let code = Int(codeStr) else { return }
        let body = parts.count > 1 ? String(parts[1]) : ""
        switch code {
        case 7:
            if let url = URL(string: body), url.scheme == "file" {
                let dir = URL(fileURLWithPath: url.path(percentEncoded: false), isDirectory: true)
                onDirectoryChange?(dir)
            }
        case 0, 2: break // title (ignore)
        default:   break
        }
    }

    private func ignoreUntilST(_ b: UInt8) {
        if b == 0x07 || b == 0x9C { state = .ground }
        else if b == 0x1B { state = .escape }
    }

    private func resetBuffer() {
        buffer.hardReset()
        onHardReset?()
    }
}
