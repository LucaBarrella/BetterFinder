import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - TerminalDisplayView
// NSTextView that never steals keyboard focus from TerminalNSView.

final class TerminalDisplayView: NSTextView {
    weak var inputTarget: TerminalNSView?

    override var acceptsFirstResponder: Bool { false }
    override func becomeFirstResponder() -> Bool { false }

    override func mouseDown(with event: NSEvent) {
        if let t = inputTarget { t.window?.makeFirstResponder(t) }
        super.mouseDown(with: event)
    }
    override func keyDown(with event: NSEvent) {
        inputTarget?.keyDown(with: event)
    }
    override func keyUp(with event: NSEvent) {}
}

// MARK: - TerminalNSView

final class TerminalNSView: NSView {

    var session: TerminalSession?
    var engine:  TerminalEngine?

    private let scrollView = NSScrollView()
    private let textView   = TerminalDisplayView()
    private(set) var font: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular)

    // Cell metrics (monospace)
    private var cellW: CGFloat = 7
    private var cellH: CGFloat = 15

    private var isDark = false

    // Throttle: at most one render per display frame
    private var renderPending = false

    // Cursor blink
    private var blinkTimer:   Timer?
    private var cursorVisible = true
    private var hasFocus      = false

    // MARK: - Incremental rendering state

    /// NSTextStorage offset where the current screen begins (after all scrollback).
    private var screenStartLocation: Int = 0
    /// How many scrollback lines have been appended to NSTextStorage.
    private var lastScrollbackCount: Int = 0

    // MARK: - Setup

    override init(frame: CGRect) { super.init(frame: frame); setup() }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        wantsLayer = true

        // ── Text view ──────────────────────────────────────────────────
        textView.inputTarget   = self
        textView.isEditable    = false
        textView.isSelectable  = true
        textView.drawsBackground = true
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 6, height: 6)

        // CRITICAL: disable word wrap so terminal lines stay on their row
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineBreakMode = .byClipping
        textView.textContainer?.containerSize = NSSize(width: 1_000_000,
                                                       height: CGFloat.greatestFiniteMagnitude)

        textView.isAutomaticQuoteSubstitutionEnabled  = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled      = false
        textView.usesFontPanel = false
        textView.usesFindBar   = false
        textView.isRichText    = false
        textView.font          = font

        // Non-contiguous layout: only lays out visible text, critical for large scrollbacks
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.layoutManager?.backgroundLayoutEnabled   = false

        // ── Scroll view ────────────────────────────────────────────────
        scrollView.documentView      = textView
        scrollView.hasVerticalScroller   = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers    = true
        scrollView.drawsBackground       = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        measureCell()
        registerForDraggedTypes([.fileURL, .string])

        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.53, repeats: true) { [weak self] _ in
            guard let self else { return }
            cursorVisible.toggle()
            scheduleRender()
        }
    }

    deinit { blinkTimer?.invalidate() }

    // MARK: - Font

    func setFontSize(_ size: CGFloat) {
        font = .monospacedSystemFont(ofSize: size, weight: .regular)
        textView.font = font
        measureCell()
        resetDisplay()
    }

    private func measureCell() {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let sz = ("M" as NSString).size(withAttributes: attrs)
        cellW = max(sz.width,  7)
        cellH = max(font.ascender - font.descender + font.leading + 1, 12)
    }

    // MARK: - Display reset

    /// Call when the terminal session is fully reset (e.g., shell exit/restart or font change).
    func resetDisplay() {
        guard let storage = textView.textStorage else { return }
        storage.beginEditing()
        storage.deleteCharacters(in: NSRange(location: 0, length: storage.length))
        storage.endEditing()
        screenStartLocation = 0
        lastScrollbackCount = 0
        scheduleRender()
    }

    // MARK: - Rendering (incremental, throttled)

    func scheduleRender() {
        guard !renderPending else { return }
        renderPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            renderPending = false
            renderNow()
        }
    }

    private func renderNow() {
        guard let eng = engine, let storage = textView.textStorage else { return }

        isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let buf = eng.buffer

        // Update background
        let bg: NSColor = isDark
            ? NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1)
            : NSColor(red: 0.97, green: 0.97, blue: 0.96, alpha: 1)
        if scrollView.backgroundColor != bg {
            scrollView.backgroundColor = bg
            textView.backgroundColor   = bg
        }

        // ── Step 1: Append new scrollback lines (skip when alt screen active) ──
        if !buf.inAlt {
            let newCount = buf.scrollback.count
            if newCount > lastScrollbackCount {
                // Render only the newly added lines
                let newAttr = buf.renderScrollbackRange(lastScrollbackCount..<newCount,
                                                        font: font, dark: isDark)
                applyParaStyle(to: newAttr)
                storage.beginEditing()
                // Insert before screen portion
                storage.replaceCharacters(
                    in: NSRange(location: screenStartLocation, length: 0),
                    with: newAttr)
                storage.endEditing()
                screenStartLocation  += newAttr.length
                lastScrollbackCount   = newCount
            } else if newCount < lastScrollbackCount {
                // Scrollback shrank (shouldn't happen except after hardReset, which
                // fires onHardReset → resetDisplay). Guard here just in case.
                resetDisplay()
                return
            }
        }

        // ── Step 2: Build the new screen content ──────────────────────────────
        let screenAttr = buf.renderScreenOnly(font: font, dark: isDark)

        // Draw cursor into the screen string
        drawCursor(in: screenAttr, buf: buf)

        // Apply paragraph style (no wrap, fixed line spacing)
        applyParaStyle(to: screenAttr)

        // ── Step 3: Replace only the screen portion ───────────────────────────
        let screenLen = storage.length - screenStartLocation
        storage.beginEditing()
        storage.replaceCharacters(
            in: NSRange(location: screenStartLocation, length: screenLen),
            with: screenAttr)
        storage.endEditing()

        scrollToBottom()
    }

    // MARK: - Cursor drawing

    /// Draws the cursor by inverting attributes at [cursorRow, cursorCol] within `s`.
    /// `s` contains only the screen lines (no scrollback), so we use `buf.cursorRow` directly.
    private func drawCursor(in s: NSMutableAttributedString, buf: TerminalBuffer) {
        let nsStr = s.string as NSString
        guard nsStr.length > 0 else { return }

        // Scan for the start of cursorRow by counting '\n' chars
        let targetRow = buf.cursorRow
        var rowStart  = 0
        var rowIdx    = 0
        var pos       = 0
        while pos < nsStr.length {
            if rowIdx == targetRow { rowStart = pos; break }
            if nsStr.character(at: pos) == 10 { rowIdx += 1 } // '\n'
            pos += 1
        }
        if rowIdx < targetRow { return } // row not found

        // Find character at cursorCol within this row
        var colPos    = rowStart
        var col       = 0
        let targetCol = buf.cursorCol
        while col < targetCol, colPos < nsStr.length {
            if nsStr.character(at: colPos) == 10 { break }
            colPos += 1; col += 1
        }

        let cursorBg: NSColor = hasFocus && cursorVisible
            ? (isDark ? .white : NSColor(white: 0.1, alpha: 1))
            : (isDark ? NSColor(white: 1, alpha: 0.3) : NSColor(white: 0, alpha: 0.2))

        if colPos < nsStr.length, nsStr.character(at: colPos) != 10 {
            let existing = s.attributes(at: colPos, effectiveRange: nil)
            let cellFg   = (existing[.foregroundColor] as? NSColor)
                           ?? (isDark ? NSColor.black : NSColor.white)
            s.addAttributes([
                .foregroundColor: cellFg,
                .backgroundColor: cursorBg,
            ], range: NSRange(location: colPos, length: 1))
        } else if hasFocus && cursorVisible {
            // Cursor past end of trimmed content — append a block
            s.append(NSAttributedString(string: " ", attributes: [
                .font: font,
                .foregroundColor: isDark ? NSColor.black : NSColor.white,
                .backgroundColor: cursorBg,
            ]))
        }
    }

    // MARK: - Helpers

    private func applyParaStyle(to s: NSMutableAttributedString) {
        guard s.length > 0 else { return }
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byClipping
        para.lineSpacing   = 0
        s.addAttribute(.paragraphStyle, value: para,
                        range: NSRange(location: 0, length: s.length))
    }

    private func scrollToBottom() {
        guard let storage = textView.textStorage else { return }
        textView.scrollRangeToVisible(NSRange(location: storage.length, length: 0))
    }

    // MARK: - Resize

    override func layout() {
        super.layout()
        updateTerminalSize()
    }

    private func updateTerminalSize() {
        guard cellW > 0, cellH > 0 else { return }
        let sz   = scrollView.contentSize
        let cols = max(20, Int((sz.width  - 12) / cellW))
        let rows = max(4,  Int((sz.height - 12) / cellH))
        guard cols != engine?.buffer.cols || rows != engine?.buffer.rows else { return }
        engine?.buffer.resize(cols: cols, rows: rows)
        session?.resize(cols: cols, rows: rows)
        scheduleRender()
    }

    // MARK: - Focus

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        hasFocus = true; cursorVisible = true; scheduleRender()
        return true
    }

    override func resignFirstResponder() -> Bool {
        guard super.resignFirstResponder() else { return false }
        hasFocus = false; scheduleRender()
        return true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            DispatchQueue.main.async { [weak self] in
                guard let self, let win = window else { return }
                win.makeFirstResponder(self)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        guard let session else { return }

        let flags  = event.modifierFlags
        let chars  = event.characters ?? ""
        let unmod  = event.charactersIgnoringModifiers ?? ""
        let meta   = flags.contains(.option) && !flags.contains(.command)

        // Ctrl+<letter>
        if flags.contains(.control), !flags.contains(.command) {
            if let c = unmod.unicodeScalars.first {
                let v = c.value
                if v >= 64 && v <= 95  { session.write(Data([UInt8(v - 64)])); return }
                if v >= 96 && v <= 127 { session.write(Data([UInt8(v - 96)])); return }
            }
        }

        switch event.keyCode {
        case 126: session.writeString(meta ? "\u{1B}[1;3A" : "\u{1B}[A")   // ↑
        case 125: session.writeString(meta ? "\u{1B}[1;3B" : "\u{1B}[B")   // ↓
        case 124: session.writeString(meta ? "\u{1B}[1;3C" : "\u{1B}[C")   // →
        case 123: session.writeString(meta ? "\u{1B}[1;3D" : "\u{1B}[D")   // ←
        case 116: session.writeString("\u{1B}[5~")   // Page Up
        case 121: session.writeString("\u{1B}[6~")   // Page Down
        case 115: session.writeString("\u{1B}[H")    // Home
        case 119: session.writeString("\u{1B}[F")    // End
        case 117: session.writeString("\u{1B}[3~")   // Fwd Delete
        case  51: session.write(Data([0x7F]))          // Backspace → DEL
        case  53: session.writeString("\u{1B}")        // Escape
        case  76, 36: session.writeString("\r")        // Return/Enter
        case  48: session.writeString("\t")            // Tab
        default:
            if !chars.isEmpty, let d = chars.data(using: .utf8) {
                if meta { session.writeString("\u{1B}") }
                session.write(d)
            }
        }
    }

    override func keyUp(with event: NSEvent) {}   // suppress beeps

    // MARK: - Drag & Drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pb = sender.draggingPasteboard
        return (pb.canReadObject(forClasses: [NSURL.self], options: nil) ||
                pb.canReadObject(forClasses: [NSString.self], options: nil)) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        var pieces: [String] = []
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            pieces = urls.map {
                "'" + $0.path(percentEncoded: false)
                    .replacingOccurrences(of: "'", with: "'\\''") + "'"
            }
        } else if let str = pb.string(forType: .string) {
            pieces = [str]
        }
        guard !pieces.isEmpty else { return false }
        session?.writeString(pieces.joined(separator: " ") + " ")
        window?.makeFirstResponder(self)
        return true
    }
}

// MARK: - SwiftUI Representable

struct TerminalRepresentable: NSViewRepresentable {
    let session:  TerminalSession
    let engine:   TerminalEngine
    let fontSize: CGFloat

    func makeNSView(context: Context) -> TerminalNSView {
        let v = TerminalNSView()
        v.session = session
        v.engine  = engine
        engine.onRender    = { [weak v] in v?.scheduleRender() }
        engine.onHardReset = { [weak v] in v?.resetDisplay() }
        v.scheduleRender()
        return v
    }

    func updateNSView(_ v: TerminalNSView, context: Context) {
        v.session = session
        v.engine  = engine
        if v.font.pointSize != fontSize {
            v.setFontSize(fontSize)
        }
    }
}
