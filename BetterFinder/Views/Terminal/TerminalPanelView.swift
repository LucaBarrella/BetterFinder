import SwiftUI
import AppKit

// MARK: - TerminalPanelView

struct TerminalPanelView: View {
    @Environment(AppState.self) private var appState
    let browser: BrowserState

    var body: some View {
        VStack(spacing: 0) {
            // Resize handle + toolbar in one bar
            TerminalHeaderBar(browser: browser)

            Divider()

            SwiftTermRepresentable(browser: browser)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: browser.terminalHeight)
        .onChange(of: browser.currentURL) { _, newURL in
            if browser.terminalSyncEnabled {
                browser.terminalChangeDirectory?(newURL)
            }
        }
    }
}

// MARK: - Header Bar (resize handle + toolbar in one NSView)

private struct TerminalHeaderBar: View {
    let browser: BrowserState

    var body: some View {
        // Access observable properties so SwiftUI re-renders (and calls updateNSView)
        // whenever they change — this keeps the NSView header in sync.
        let _ = browser.terminalCurrentURL
        let _ = browser.terminalSyncEnabled
        let _ = browser.selectedFileItems.count
        return TerminalHeaderNSRep(browser: browser)
            .frame(height: 30)
    }
}

// MARK: - AppKit-based header (drag to resize is much more reliable in AppKit)

private struct TerminalHeaderNSRep: NSViewRepresentable {
    let browser: BrowserState

    func makeNSView(context: Context) -> TerminalHeaderNSView {
        TerminalHeaderNSView(browser: browser)
    }
    func updateNSView(_ v: TerminalHeaderNSView, context: Context) {
        v.browser = browser
        v.update()
    }
}

final class TerminalHeaderNSView: NSView {
    var browser: BrowserState
    private var dragStart: CGFloat = 0
    private var heightAtDragStart: CGFloat = 0

    // Toolbar subviews
    private let shellLabel    = NSTextField(labelWithString: "")
    private let pathLabel     = NSTextField(labelWithString: "")
    private let syncButton    = NSButton()
    private let goHereButton  = NSButton()
    private let insertButton  = NSButton()
    private let fontMinusBtn  = NSButton()
    private let fontPlusBtn   = NSButton()
    private let closeButton   = NSButton()
    private let gripView      = NSView()

    init(browser: BrowserState) {
        self.browser = browser
        super.init(frame: .zero)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    func update() {
        shellLabel.stringValue = browser.shellName

        // Show abbreviated current terminal directory (or nothing if unknown)
        if let termURL = browser.terminalCurrentURL {
            pathLabel.stringValue = abbreviatedPath(termURL)
            pathLabel.isHidden = false
        } else {
            pathLabel.isHidden = true
        }

        let syncImg = browser.terminalSyncEnabled
            ? "arrow.left.arrow.right.circle.fill"
            : "arrow.left.arrow.right.circle"
        syncButton.image = NSImage(systemSymbolName: syncImg, accessibilityDescription: nil)
        let hasSelection = !browser.selectedFileItems.isEmpty
        insertButton.isEnabled = hasSelection
    }

    private func abbreviatedPath(_ url: URL) -> String {
        let path = url.path(percentEncoded: false)
        let home = URL.homeDirectory.path(percentEncoded: false)
        if path == home            { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    private func setup() {
        wantsLayer = true

        // Background
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        // Resize grip (left edge)
        gripView.wantsLayer = true
        gripView.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.6).cgColor
        gripView.layer?.cornerRadius = 2
        addSubview(gripView)

        // Shell label
        shellLabel.font = .systemFont(ofSize: 11, weight: .medium)
        shellLabel.textColor = .secondaryLabelColor
        shellLabel.stringValue = browser.shellName
        addSubview(shellLabel)

        // Terminal current-path label (right of shell name)
        pathLabel.font = .systemFont(ofSize: 10, weight: .regular)
        pathLabel.textColor = .tertiaryLabelColor
        pathLabel.isHidden = true
        addSubview(pathLabel)

        // Sync button
        configureButton(syncButton,
            image: "arrow.left.arrow.right.circle.fill",
            target: self, action: #selector(toggleSync))
        syncButton.toolTip = "Toggle directory sync (GUI ↔ terminal)"

        // "Go here" — sends the file panel's current directory to the terminal (one-shot)
        configureButton(goHereButton,
            image: "arrow.right.to.line",
            target: self, action: #selector(goHere))
        goHereButton.toolTip = "cd terminal to current folder"

        // Insert path button
        configureButton(insertButton,
            image: "arrow.down.doc",
            target: self, action: #selector(insertPath))
        insertButton.toolTip = "Insert selected file path into terminal"

        // Font size buttons
        configureButton(fontMinusBtn,
            image: "minus",
            target: self, action: #selector(fontMinus))
        configureButton(fontPlusBtn,
            image: "plus",
            target: self, action: #selector(fontPlus))

        // Close button
        configureButton(closeButton,
            image: "xmark",
            target: self, action: #selector(closeTerminal))
        closeButton.toolTip = "Close terminal (F4)"

        [syncButton, goHereButton, insertButton, fontMinusBtn, fontPlusBtn, closeButton].forEach { addSubview($0) }

        // Cursor
        addCursorRect(NSRect(origin: .zero, size: NSSize(width: 10_000, height: 30)),
                      cursor: .resizeUpDown)

        update()
    }

    private func configureButton(_ btn: NSButton, image: String, target: AnyObject, action: Selector) {
        btn.image = NSImage(systemSymbolName: image, accessibilityDescription: nil)
        btn.bezelStyle = .inline
        btn.isBordered = false
        btn.target = target
        btn.action = action
        btn.contentTintColor = .secondaryLabelColor
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        let w = bounds.width

        // Grip: centered vertically, small pill shape
        gripView.frame = NSRect(x: w/2 - 16, y: h/2 - 2, width: 32, height: 4)

        // Right-aligned buttons
        let btnW: CGFloat = 22
        let pad: CGFloat  = 4
        var x = w - btnW - pad
        closeButton.frame    = NSRect(x: x, y: 0, width: btnW, height: h); x -= btnW
        fontPlusBtn.frame    = NSRect(x: x, y: 0, width: btnW, height: h); x -= btnW
        fontMinusBtn.frame   = NSRect(x: x, y: 0, width: btnW, height: h); x -= btnW + 4
        insertButton.frame   = NSRect(x: x, y: 0, width: btnW, height: h); x -= btnW
        goHereButton.frame   = NSRect(x: x, y: 0, width: btnW, height: h); x -= btnW
        syncButton.frame     = NSRect(x: x, y: 0, width: btnW, height: h)

        // Left: shell name + terminal path
        shellLabel.sizeToFit()
        let labelH = shellLabel.frame.height
        shellLabel.frame = NSRect(x: 10, y: (h - labelH) / 2,
                                  width: shellLabel.frame.width, height: labelH)

        pathLabel.sizeToFit()
        let pathX = shellLabel.frame.maxX + 6
        pathLabel.frame = NSRect(x: pathX, y: (h - pathLabel.frame.height) / 2,
                                 width: min(pathLabel.frame.width, x - pathX - 4),
                                 height: pathLabel.frame.height)
    }

    // MARK: - Drag to resize

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil).y
        heightAtDragStart = browser.terminalHeight
    }

    override func mouseDragged(with event: NSEvent) {
        let currentY = convert(event.locationInWindow, from: nil).y
        let delta    = dragStart - currentY     // dragging up → increase height
        browser.terminalHeight = max(80, min(600, heightAtDragStart + delta))
    }

    override func mouseUp(with event: NSEvent) {
        dragStart = 0
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    // MARK: - Actions

    @objc private func toggleSync() {
        browser.terminalSyncEnabled.toggle()
        update()
    }

    @objc private func goHere() {
        browser.terminalChangeDirectory?(browser.currentURL)
    }

    @objc private func insertPath() {
        guard let item = browser.selectedFileItems.first else { return }
        let path = "'" + item.url.path(percentEncoded: false)
            .replacingOccurrences(of: "'", with: "'\\''") + "'"
        browser.terminalSendText?(path + " ")
    }

    @objc private func fontMinus() {
        browser.terminalFontSize = max(9, browser.terminalFontSize - 1)
    }

    @objc private func fontPlus() {
        browser.terminalFontSize = min(24, browser.terminalFontSize + 1)
    }

    @objc private func closeTerminal() {
        browser.showTerminal = false
    }
}
