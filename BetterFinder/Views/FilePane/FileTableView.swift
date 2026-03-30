import AppKit
import SwiftUI
import UniformTypeIdentifiers
import QuickLookUI

// MARK: - SwiftUI wrapper

struct FileTableView: NSViewRepresentable {
    let browser: BrowserState
    let items: [FileItem]
    let appState: AppState
    var showLocationInKindColumn: Bool = false

    func makeCoordinator() -> Coordinator { Coordinator(browser: browser, appState: appState) }
    func makeNSView(context: Context) -> NSScrollView { context.coordinator.scrollView }
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.update(items: items, showLocationInKindColumn: showLocationInKindColumn)
    }
}

// MARK: - NSTableView subclass (custom context menu)

fileprivate final class BFTableView: NSTableView {
    var menuProvider: ((Int) -> NSMenu?)?
    var onActivate: (() -> Void)?
    var onKeyDown: ((NSEvent) -> Bool)?
    var onTripleClickRow: ((Int) -> Void)?
    var undoManagerProvider: (() -> UndoManager?)?
    var qlController: (QLPreviewPanelDataSource & QLPreviewPanelDelegate)?

    override var undoManager: UndoManager? { undoManagerProvider?() ?? super.undoManager }

    // MARK: Quick Look panel — responder chain hooks
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = qlController
        panel.delegate   = qlController
    }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate   = nil
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        return menuProvider?(row) ?? super.menu(for: event)
    }

    override func mouseDown(with event: NSEvent) {
        onActivate?()
        // Triple-click on name column → inline rename (intercept before super so double-action doesn't fire)
        if event.clickCount == 3 {
            let pt  = convert(event.locationInWindow, from: nil)
            let row = self.row(at: pt)
            let col = self.column(at: pt)
            if row >= 0, col >= 0, col < tableColumns.count,
               tableColumns[col].identifier.rawValue == "name" {
                selectRowIndexes([row], byExtendingSelection: false)
                onTripleClickRow?(row)
                return   // skip super → prevents doubleAction from firing
            }
        }
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true { return }
        super.keyDown(with: event)
    }
}

// MARK: - Coordinator

final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {

    let browser: BrowserState
    let appState: AppState
    fileprivate let tableView = BFTableView()
    let scrollView = NSScrollView()

    private var items: [FileItem] = []
    private var showLocationInKindColumn = false
    private let iconCache = NSCache<NSURL, NSImage>()
    private var suppressSelectionSync = false

    init(browser: BrowserState, appState: AppState) {
        self.browser = browser
        self.appState = appState
        super.init()
        setupTable()
    }

    // MARK: - Setup

    private func setupTable() {
        // Columns
        let cols: [(id: String, title: String, w: CGFloat, min: CGFloat)] = [
            ("name", "Name",          280, 160),
            ("date", "Date Modified", 160, 120),
            ("size", "Size",           80,  60),
            ("kind", "Kind",          130,  80),
        ]
        for (id, title, w, minW) in cols {
            let col = NSTableColumn(identifier: .init(id))
            col.title = title
            col.width = w
            col.minWidth = minW
            col.resizingMask = .userResizingMask
            col.sortDescriptorPrototype = NSSortDescriptor(key: id, ascending: true)
            tableView.addTableColumn(col)
        }

        tableView.dataSource   = self
        tableView.delegate     = self
        tableView.allowsMultipleSelection  = true
        tableView.allowsEmptySelection     = true
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.style        = .inset
        tableView.rowHeight    = 22
        tableView.intercellSpacing = NSSize(width: 3, height: 0)
        tableView.columnAutoresizingStyle  = .lastColumnOnlyAutoresizingStyle
        tableView.headerView   = NSTableHeaderView()

        // Double-click
        tableView.target       = self
        tableView.doubleAction = #selector(handleDoubleClick)

        // Drag source: NSTableView calls pasteboardWriterForRow automatically
        tableView.setDraggingSourceOperationMask([.copy, .move], forLocal: false)
        tableView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)

        // Drop destination
        tableView.registerForDraggedTypes([.fileURL])

        // Context menu
        tableView.menuProvider = { [weak self] row in self?.buildContextMenu(row: row) }

        // Pane activation: clicking anywhere in the table activates this pane
        tableView.onActivate = { [weak self] in self?.activateThisPane() }

        // Keyboard shortcuts: F2/⌘R rename, F5 copy, F6 move, F7 new folder, ⌘⌫ trash, ↩ open
        tableView.onKeyDown = { [weak self] event in self?.handleKeyDown(event) ?? false }

        // Triple-click on name column → inline rename
        tableView.onTripleClickRow = { [weak self] row in self?.beginInlineRename(row: row) }

        // Expose inline rename trigger to BrowserState (used by Operations Bar, menu bar, ⌘R)
        browser.triggerInlineRename = { [weak self] in self?.beginInlineRenameForSelection() }

        // Wire our app's UndoManager so ⌘Z / ⌘⇧Z work natively via the responder chain
        tableView.undoManagerProvider = { [weak self] in self?.appState.undoManager }

        // Wire Quick Look data source so Space / context menu works
        tableView.qlController = self

        // Scroll view
        scrollView.documentView  = tableView
        scrollView.hasVerticalScroller   = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers    = true
        scrollView.borderType            = .noBorder
        scrollView.drawsBackground       = false
    }

    // MARK: - Update from SwiftUI

    func update(items newItems: [FileItem], showLocationInKindColumn newShowLocation: Bool) {
        let changed = newItems.map(\.id) != items.map(\.id)
            || newShowLocation != showLocationInKindColumn

        items = newItems
        showLocationInKindColumn = newShowLocation

        // Update "Kind" column header to reflect current mode
        if let kindCol = tableView.tableColumns.first(where: { $0.identifier.rawValue == "kind" }) {
            kindCol.title = showLocationInKindColumn ? "Location" : "Kind"
        }

        // Sync sort indicator with browser state (e.g. on first load or external state change)
        let desiredSD = NSSortDescriptor(key: browser.sortColumnID, ascending: browser.sortAscending)
        if tableView.sortDescriptors.first?.key != desiredSD.key
            || tableView.sortDescriptors.first?.ascending != desiredSD.ascending {
            tableView.sortDescriptors = [desiredSD]
        }

        // Preserve scroll position: reloadData() resets NSScrollView to the top,
        // causing the visible "jump" after drag-drop, watcher refreshes, etc.
        let savedOrigin = scrollView.contentView.bounds.origin
        tableView.reloadData()
        scrollView.contentView.scroll(to: savedOrigin)
        scrollView.reflectScrolledClipView(scrollView.contentView)

        if changed { syncSelection() }
    }

    private func syncSelection() {
        suppressSelectionSync = true
        var idx = IndexSet()
        for (i, item) in items.enumerated() where browser.selectedItems.contains(item.id) {
            idx.insert(i)
        }

        // UUID fallback: if no match (items reloaded with new UUIDs) but we have a
        // remembered URL, restore selection by URL so preview stays consistent.
        if idx.isEmpty, let lastURL = browser.lastSelectedURL,
           let row = items.firstIndex(where: { $0.url.standardizedFileURL == lastURL.standardizedFileURL }) {
            idx.insert(row)
            browser.selectedItems = [items[row].id]
        }

        tableView.selectRowIndexes(idx, byExtendingSelection: false)
        suppressSelectionSync = false
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    /// One writer per row — NSTableView handles multi-row drag automatically.
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard row < items.count else { return nil }
        return items[row].url as NSURL
    }

    // MARK: Drop validation

    func tableView(_ tableView: NSTableView,
                   validateDrop info: NSDraggingInfo,
                   proposedRow row: Int,
                   proposedDropOperation drop: NSTableView.DropOperation) -> NSDragOperation {

        // Don't drop a file onto itself
        var sourceURLs: [URL] = []
        info.enumerateDraggingItems(options: [.concurrent], for: nil,
                                    classes: [NSURL.self],
                                    searchOptions: [.urlReadingFileURLsOnly: true]) { item, _, _ in
            if let u = item.item as? URL { sourceURLs.append(u) }
        }
        guard !sourceURLs.isEmpty else { return [] }

        if drop == .on, row >= 0, row < items.count {
            let target = items[row]
            if target.isDirectory && !target.isPackage &&
               !sourceURLs.contains(target.url) {
                return .move        // drop ON a folder → move into it
            }
        }

        // Any other position → redirect to whole-table drop (= current directory)
        tableView.setDropRow(-1, dropOperation: .on)
        return .move
    }

    // MARK: Drop acceptance

    func tableView(_ tableView: NSTableView,
                   acceptDrop info: NSDraggingInfo,
                   row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {

        let destination: URL
        if dropOperation == .on, row >= 0, row < items.count, items[row].isDirectory {
            destination = items[row].url
        } else {
            destination = browser.currentURL
        }

        var urlsToMove: [URL] = []
        info.enumerateDraggingItems(options: [], for: nil,
                                    classes: [NSURL.self],
                                    searchOptions: [.urlReadingFileURLsOnly: true]) { item, _, _ in
            if let u = item.item as? URL { urlsToMove.append(u) }
        }
        guard !urlsToMove.isEmpty else { return false }

        let pairs = urlsToMove.map { src in
            (from: src, to: destination.appendingPathComponent(src.lastPathComponent))
        }
        // Route through moveFiles so the operation is undo-registered (⌘Z reverses it).
        // Reload both panes: the source directory may live in the other pane.
        appState.moveFiles(pairs, actionName: "Move",
                           reloadBrowsers: [appState.primaryBrowser, appState.secondaryBrowser])
        return true
    }

    // MARK: - NSTableViewDelegate — cell views

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        guard row < items.count else { return nil }
        let item = items[row]
        switch tableColumn?.identifier.rawValue {
        case "name": return nameCellView(item: item, in: tableView)
        case "date": return labelCell(item.formattedDate, id: "date", align: .left,  in: tableView)
        case "size": return labelCell(item.formattedSize, id: "size", align: .right, in: tableView)
        case "kind":
            let kindText = showLocationInKindColumn
                ? item.url.deletingLastPathComponent().lastPathComponent
                : item.kindDescription
            return labelCell(kindText, id: "kind", align: .left, in: tableView)
        default: return nil
        }
    }

    private func nameCellView(item: FileItem, in tv: NSTableView) -> NSView {
        let id = NSUserInterfaceItemIdentifier("NameCell")
        let cell = (tv.makeView(withIdentifier: id, owner: nil) as? NameCellView) ?? {
            let v = NameCellView(); v.identifier = id; return v
        }()
        let cachedIcon = iconCache.object(forKey: item.url as NSURL)
        cell.configure(item: item, icon: cachedIcon)
        if cachedIcon == nil {
            let url = item.url
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let img = NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
                img.size = NSSize(width: 32, height: 32)
                DispatchQueue.main.async {
                    self?.iconCache.setObject(img, forKey: url as NSURL)
                    guard let self,
                          let row = self.items.firstIndex(where: { $0.url == url }),
                          let colIdx = tv.tableColumns.firstIndex(where: { $0.identifier.rawValue == "name" })
                    else { return }
                    tv.reloadData(forRowIndexes: [row], columnIndexes: [colIdx])
                }
            }
        }
        return cell
    }

    private func labelCell(_ text: String, id: String, align: NSTextAlignment,
                            in tv: NSTableView) -> NSView {
        let nsid = NSUserInterfaceItemIdentifier("Label-\(id)")
        let cell = (tv.makeView(withIdentifier: nsid, owner: nil) as? LabelCellView) ?? {
            let v = LabelCellView(); v.identifier = nsid; return v
        }()
        cell.configure(text: text, align: align)
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let id = NSUserInterfaceItemIdentifier("Row")
        return (tableView.makeView(withIdentifier: id, owner: nil) as? NSTableRowView) ?? {
            let v = NSTableRowView(); v.identifier = id; return v
        }()
    }

    // MARK: - Drag image

    /// Called by AppKit just before the drag session starts.
    /// We replace every dragging item's image with a render of the Name cell,
    /// so the ghost always shows icon + filename regardless of which column
    /// the drag was initiated from — matching Finder's behaviour.
    func tableView(_ tableView: NSTableView,
                   draggingSession session: NSDraggingSession,
                   willBeginAt screenPoint: NSPoint,
                   forRowIndexes rowIndexes: IndexSet) {
        guard let nameColIdx = tableView.tableColumns.firstIndex(where: {
            $0.identifier.rawValue == "name"
        }) else { return }

        let sortedRows = rowIndexes.sorted()
        var enumIdx    = 0

        session.enumerateDraggingItems(
            options: [], for: tableView,
            classes: [NSURL.self],
            searchOptions: [.urlReadingFileURLsOnly: true]
        ) { item, _, _ in
            guard enumIdx < sortedRows.count else { return }
            let row = sortedRows[enumIdx]; enumIdx += 1

            guard let cell = tableView.view(atColumn: nameColIdx, row: row,
                                            makeIfNecessary: false) else { return }

            // PDF rendering is coordinate-system-agnostic and always works for
            // on-screen views — no lockFocus / bitmap flipping required.
            let pdfData = cell.dataWithPDF(inside: cell.bounds)
            guard let img = NSImage(data: pdfData) else { return }

            item.setDraggingFrame(
                NSRect(origin: item.draggingFrame.origin, size: cell.bounds.size),
                contents: img
            )
        }
    }

    // MARK: - Pane activation

    private func activateThisPane() {
        guard appState.isDualPane else { return }
        let isPrimary = appState.primaryBrowser === browser
        appState.activePaneIsSecondary = !isPrimary
    }

    // MARK: - Keyboard shortcuts

    /// Returns `true` if the event was handled (suppresses NSTableView's default beep).
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let hasSelection = !tableView.selectedRowIndexes.isEmpty
        let prefs = appState.preferences

        // Space — Quick Look
        if event.keyCode == 49 {
            guard hasSelection else { return false }
            quickLook()
            return true
        }

        // ↩ Return / Enter — open selected items (not customisable)
        if event.keyCode == 36 || event.keyCode == 76 {
            guard hasSelection else { return false }
            openSelected()
            return true
        }

        // Rename (primary shortcut from preferences + legacy F2)
        if prefs.shortcutRename.matches(event) || event.keyCode == 120 {
            guard hasSelection else { return false }
            activateThisPane()
            beginInlineRenameForSelection()
            return true
        }

        // Move to Trash
        if prefs.shortcutTrash.matches(event) {
            guard hasSelection else { return false }
            activateThisPane()
            appState.trashInActivePane()
            return true
        }

        // Copy to other pane
        if prefs.shortcutCopyToPane.matches(event) {
            guard appState.isDualPane, hasSelection else { return false }
            activateThisPane()
            appState.copySelectionToOtherPane()
            return true
        }

        // Move to other pane
        if prefs.shortcutMoveToPane.matches(event) {
            guard appState.isDualPane, hasSelection else { return false }
            activateThisPane()
            appState.moveSelectionToOtherPane()
            return true
        }

        // New File
        if prefs.shortcutNewFile.matches(event) {
            activateThisPane()
            appState.newFileInActivePane()
            return true
        }

        // New Folder (primary shortcut from preferences + legacy F7)
        if prefs.shortcutNewFolder.matches(event) || event.keyCode == 98 {
            activateThisPane()
            appState.newFolderInActivePane()
            return true
        }

        // Cut  ⌘X
        let cmd = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
        if event.keyCode == 7 && cmd && hasSelection {   // X key
            activateThisPane()
            appState.cutSelectedItems()
            return true
        }

        // Paste  ⌘V
        if event.keyCode == 9 && cmd && appState.hasCutItems {  // V key
            activateThisPane()
            appState.pasteIntoActivePane()
            return true
        }

        return false
    }

    // MARK: - Selection

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !suppressSelectionSync else { return }
        let selectedRows = tableView.selectedRowIndexes
        let ids = Set(selectedRows.compactMap { $0 < items.count ? items[$0].id : nil })
        browser.selectedItems = ids
        // Store URL directly — bypasses UUID identity so preview never goes stale
        // after a directory reload assigns new UUIDs to the same physical files.
        browser.lastSelectedURL = selectedRows.min().flatMap {
            $0 < items.count ? items[$0].url : nil
        }
    }

    // MARK: - Sorting

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let sd = tableView.sortDescriptors.first, let key = sd.key else { return }
        browser.sortColumnID = key
        browser.sortAscending = sd.ascending
    }

    // MARK: - Double-click

    @objc private func handleDoubleClick() {
        let row = tableView.clickedRow
        guard row >= 0, row < items.count else { return }
        let item = items[row]
        if item.isDirectory && !item.isPackage {
            browser.navigate(to: item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    // MARK: - Context menu

    private func buildContextMenu(row: Int) -> NSMenu? {
        guard row >= 0 else { return emptySpaceMenu() }

        if !tableView.selectedRowIndexes.contains(row) {
            tableView.selectRowIndexes([row], byExtendingSelection: false)
        }
        let selection = tableView.selectedRowIndexes.compactMap {
            $0 < items.count ? items[$0] : nil
        }
        guard !selection.isEmpty else { return emptySpaceMenu() }

        let menu = NSMenu()
        let n = selection.count
        let prefs = appState.preferences

        if n == 1, let item = selection.first {
            // ── Open ──────────────────────────────────────────────────────────
            menu.addItem(menuItem("Open", #selector(openSelected),
                                  icon: "arrow.up.right.square"))

            let openWithItem = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
            openWithItem.image = NSImage(systemSymbolName: "arrow.up.right.square.fill",
                                         accessibilityDescription: nil)
            openWithItem.submenu = buildOpenWithMenu(for: item.url)
            menu.addItem(openWithItem)

            menu.addItem(menuItem("Show in Enclosing Folder", #selector(showInEnclosingFolder),
                                  icon: "arrow.up.backward"))

            // ── Destructive ───────────────────────────────────────────────────
            menu.addItem(.separator())
            menu.addItem(menuItem("Move to Trash", #selector(trashSelected),
                                  icon: "trash", shortcut: prefs.shortcutTrash))

            // ── File operations ───────────────────────────────────────────────
            menu.addItem(.separator())
            menu.addItem(menuItem("Get Info", #selector(getInfo),
                                  icon: "info.circle", shortcut: prefs.shortcutGetInfo))
            menu.addItem(menuItem("Rename", #selector(renameSelected),
                                  icon: "pencil", shortcut: prefs.shortcutRename))
            menu.addItem(menuItem("Compress \"\(item.name)\"", #selector(compress),
                                  icon: "archivebox"))
            menu.addItem(menuItem("Duplicate", #selector(duplicate),
                                  icon: "doc.on.doc", shortcut: prefs.shortcutDuplicate))
            menu.addItem(menuItem("Make Alias", #selector(makeAlias),
                                  icon: "link", shortcut: prefs.shortcutMakeAlias))
            menu.addItem(menuItem("Quick Look", #selector(quickLook),
                                  icon: "eye", shortcut: prefs.shortcutQuickLook))

            // ── Clipboard / share ─────────────────────────────────────────────
            menu.addItem(.separator())
            menu.addItem(menuItem("Copy",      #selector(copyFiles),
                                  icon: "doc.on.clipboard", shortcut: prefs.shortcutCopy))
            menu.addItem(menuItem("Copy Path", #selector(copyPath),
                                  icon: "list.clipboard", shortcut: prefs.shortcutCopyPath))
            menu.addItem(menuItem("Cut",       #selector(cutSelected), icon: "scissors"))
            menu.addItem(menuItem("Share…",    #selector(shareFiles), icon: "square.and.arrow.up"))

            // ── BetterFinder extras ───────────────────────────────────────────
            menu.addItem(.separator())
            let isPrimary = appState.primaryBrowser === browser
            let otherPane = isPrimary ? 2 : 1
            if appState.isDualPane {
                let label = (item.isDirectory && !item.isPackage)
                    ? "Open in Pane \(otherPane)" : "Reveal in Pane \(otherPane)"
                menu.addItem(menuItem(label, #selector(openInOtherPane),
                                      icon: "rectangle.split.2x1"))
            } else {
                let label = (item.isDirectory && !item.isPackage)
                    ? "Open in New Pane" : "Reveal in New Pane"
                menu.addItem(menuItem(label, #selector(openInOtherPane),
                                      icon: "rectangle.split.2x1"))
            }
            menu.addItem(menuItem("Open in Terminal", #selector(openInTerminal), icon: "terminal"))

        } else {
            // ── Multi-selection ───────────────────────────────────────────────
            menu.addItem(menuItem("Open \(n) Items", #selector(openSelected),
                                  icon: "arrow.up.right.square"))
            menu.addItem(menuItem("Quick Look", #selector(quickLook),
                                  icon: "eye", shortcut: prefs.shortcutQuickLook))

            menu.addItem(.separator())
            menu.addItem(menuItem("Move \(n) Items to Trash", #selector(trashSelected),
                                  icon: "trash", shortcut: prefs.shortcutTrash))

            menu.addItem(.separator())
            menu.addItem(menuItem("Get Info", #selector(getInfo),
                                  icon: "info.circle", shortcut: prefs.shortcutGetInfo))
            menu.addItem(menuItem("Compress \(n) Items", #selector(compress), icon: "archivebox"))
            menu.addItem(menuItem("Duplicate", #selector(duplicate),
                                  icon: "doc.on.doc", shortcut: prefs.shortcutDuplicate))
            menu.addItem(menuItem("Make Alias", #selector(makeAlias),
                                  icon: "link", shortcut: prefs.shortcutMakeAlias))

            menu.addItem(.separator())
            menu.addItem(menuItem("Copy \(n) Items", #selector(copyFiles),
                                  icon: "doc.on.clipboard", shortcut: prefs.shortcutCopy))
            menu.addItem(menuItem("Cut \(n) Items",  #selector(cutSelected), icon: "scissors"))
            menu.addItem(menuItem("Share…",          #selector(shareFiles),  icon: "square.and.arrow.up"))

            menu.addItem(.separator())
            menu.addItem(menuItem("Open in Terminal", #selector(openInTerminal), icon: "terminal"))
        }
        return menu
    }

    // MARK: - Open With submenu

    private func buildOpenWithMenu(for url: URL) -> NSMenu {
        let menu = NSMenu()
        let defaultApp = NSWorkspace.shared.urlForApplication(toOpen: url)
        let allApps    = NSWorkspace.shared.urlsForApplications(toOpen: url)

        if let def = defaultApp {
            menu.addItem(appMenuItem(file: url, app: def, suffix: " (default)"))
            menu.addItem(.separator())
        }

        let others = allApps.filter { $0 != defaultApp }.prefix(12)
        for appURL in others {
            menu.addItem(appMenuItem(file: url, app: appURL, suffix: ""))
        }

        if defaultApp != nil || !others.isEmpty { menu.addItem(.separator()) }
        menu.addItem(menuItem("Other…", #selector(openWithOther)))
        return menu
    }

    private func appMenuItem(file fileURL: URL, app appURL: URL, suffix: String) -> NSMenuItem {
        let name = appURL.deletingPathExtension().lastPathComponent + suffix
        let item = NSMenuItem(title: name, action: #selector(openWithApp(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = [fileURL, appURL] as NSArray
        let icon = NSWorkspace.shared.icon(forFile: appURL.path(percentEncoded: false))
        icon.size = NSSize(width: 16, height: 16)
        item.image = icon
        return item
    }

    private func emptySpaceMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(menuItem("New File",   #selector(newFileAction),   icon: "doc.badge.plus"))
        menu.addItem(menuItem("New Folder", #selector(newFolderAction), icon: "folder.badge.plus"))
        if appState.hasCutItems {
            menu.addItem(.separator())
            let label = "Paste Item\(appState.cutItems.count == 1 ? "" : "s")"
            menu.addItem(menuItem(label, #selector(pasteAction), icon: "clipboard"))
        }
        menu.addItem(.separator())
        menu.addItem(menuItem("Open in Terminal", #selector(openInTerminal), icon: "terminal"))
        return menu
    }

    @objc private func newFileAction()   { appState.newFileInActivePane() }
    @objc private func newFolderAction() { appState.newFolderInActivePane() }
    @objc private func cutSelected()     { activateThisPane(); appState.cutSelectedItems() }
    @objc private func pasteAction()     { activateThisPane(); appState.pasteIntoActivePane() }

    @objc private func openInTerminal() {
        // If a single file is selected, open the terminal in its parent folder.
        // For folders or empty-space, open the terminal in the current browser folder.
        let targetURL: URL
        if let idx = tableView.selectedRowIndexes.first,
           idx < items.count,
           !items[idx].isDirectory {
            targetURL = items[idx].url.deletingLastPathComponent()
        } else if let idx = tableView.selectedRowIndexes.first,
                  idx < items.count {
            targetURL = items[idx].url
        } else {
            targetURL = browser.currentURL
        }
        activateThisPane()
        // Navigate the terminal (and the pane) to the target folder
        if browser.currentURL != targetURL { browser.navigate(to: targetURL) }
        browser.showTerminal = true
        browser.terminalChangeDirectory?(targetURL)
    }

    private func menuItem(
        _ title: String,
        _ action: Selector,
        icon: String? = nil,
        shortcut: AppShortcut? = nil
    ) -> NSMenuItem {
        let keyEq = shortcut?.menuKeyEquivalent ?? ""
        return NSMenuItem(title: title, action: action, keyEquivalent: keyEq).also {
            $0.target = self
            if let shortcut {
                $0.keyEquivalentModifierMask = shortcut.menuModifierMask
            }
            if let icon {
                $0.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
            }
        }
    }

    @objc private func openSelected() {
        for idx in tableView.selectedRowIndexes where idx < items.count {
            let item = items[idx]
            if item.isDirectory && !item.isPackage { browser.navigate(to: item.url) }
            else { NSWorkspace.shared.open(item.url) }
        }
    }

    @objc private func openInOtherPane() {
        guard let first = tableView.selectedRowIndexes.first, first < items.count else { return }
        let item = items[first]
        let isPrimary = appState.primaryBrowser === browser
        let target = isPrimary ? appState.secondaryBrowser : appState.primaryBrowser
        // Folders: navigate into them. Files: reveal parent directory.
        let destination = (item.isDirectory && !item.isPackage)
            ? item.url
            : item.url.deletingLastPathComponent()
        target.navigate(to: destination)
        appState.isDualPane = true
        appState.activePaneIsSecondary = isPrimary
    }

    @objc private func renameSelected() {
        beginInlineRenameForSelection()
    }

    // MARK: - Inline rename

    private func beginInlineRenameForSelection() {
        guard let row = tableView.selectedRowIndexes.first else { return }
        beginInlineRename(row: row)
    }

    private func beginInlineRename(row: Int) {
        guard row >= 0, row < items.count else { return }
        let item = items[row]
        guard let nameColIdx = tableView.tableColumns
            .firstIndex(where: { $0.identifier.rawValue == "name" }),
              let cell = tableView.view(atColumn: nameColIdx, row: row,
                                       makeIfNecessary: false) as? NameCellView
        else { return }

        activateThisPane()
        tableView.selectRowIndexes([row], byExtendingSelection: false)

        cell.beginEditing { [weak self] newName in
            guard let self,
                  let newName,
                  !newName.trimmingCharacters(in: .whitespaces).isEmpty,
                  newName != item.name
            else { return }
            let trimmed = newName.trimmingCharacters(in: .whitespaces)
            let oldURL = item.url
            let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(trimmed)
            do {
                try FileManager.default.moveItem(at: oldURL, to: newURL)
                appState.registerRenameUndo(from: oldURL, to: newURL, in: browser)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Could Not Rename"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
            Task { await self.browser.silentRefresh() }
        }
    }

    @objc private func copyPath() {
        let paths = tableView.selectedRowIndexes
            .compactMap { $0 < items.count ? items[$0].url.path(percentEncoded: false) : nil }
            .joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths, forType: .string)
    }

    @objc private func trashSelected() {
        activateThisPane()
        appState.trashInActivePane()
    }

    // MARK: - New context-menu actions

    @objc private func showInEnclosingFolder() {
        guard let first = tableView.selectedRowIndexes.first, first < items.count else { return }
        NSWorkspace.shared.activateFileViewerSelecting([items[first].url])
    }

    @objc private func getInfo() {
        let sel = tableView.selectedRowIndexes.compactMap { $0 < items.count ? items[$0] : nil }
        for item in sel {
            let path = item.url.path(percentEncoded: false)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e",
                "tell application \"Finder\" to open information window of " +
                "(POSIX file \"\(path.replacingOccurrences(of: "\"", with: "\\\""))\")"]
            try? p.run()
        }
    }

    @objc private func compress() {
        let sel = tableView.selectedRowIndexes.compactMap { $0 < items.count ? items[$0] : nil }
        guard !sel.isEmpty else { return }
        let dir = browser.currentURL

        // Build a unique zip destination name
        let baseName = sel.count == 1
            ? sel[0].url.deletingPathExtension().lastPathComponent
            : "Archive"
        var destURL = dir.appendingPathComponent("\(baseName).zip")
        var i = 2
        while FileManager.default.fileExists(atPath: destURL.path(percentEncoded: false)) {
            destURL = dir.appendingPathComponent("\(baseName) \(i).zip")
            i += 1
        }

        // zip -r dest.zip item1 item2 … (run from the parent directory)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        p.currentDirectoryURL = dir
        p.arguments = ["-r", destURL.path(percentEncoded: false)] + sel.map(\.name)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            try? p.run()
            p.waitUntilExit()
            DispatchQueue.main.async { Task { await self?.browser.silentRefresh() } }
        }
    }

    @objc private func duplicate() {
        let sel = tableView.selectedRowIndexes.compactMap { $0 < items.count ? items[$0] : nil }
        for item in sel {
            let dir  = item.url.deletingLastPathComponent()
            let name = item.url.deletingPathExtension().lastPathComponent
            let ext  = item.url.pathExtension
            var i = 2
            var dest: URL
            repeat {
                let candidate = i == 2
                    ? (ext.isEmpty ? "\(name) copy" : "\(name) copy.\(ext)")
                    : (ext.isEmpty ? "\(name) copy \(i)" : "\(name) copy \(i).\(ext)")
                dest = dir.appendingPathComponent(candidate)
                i += 1
            } while FileManager.default.fileExists(atPath: dest.path(percentEncoded: false))
            try? FileManager.default.copyItem(at: item.url, to: dest)
        }
        Task { await browser.silentRefresh() }
    }

    @objc private func makeAlias() {
        let sel = tableView.selectedRowIndexes.compactMap { $0 < items.count ? items[$0] : nil }
        for item in sel {
            let dir  = item.url.deletingLastPathComponent()
            let name = item.url.deletingPathExtension().lastPathComponent
            let ext  = item.url.pathExtension
            let aliasName = ext.isEmpty ? "\(name) alias" : "\(name) alias.\(ext)"
            let dest = dir.appendingPathComponent(aliasName)
            try? FileManager.default.createSymbolicLink(at: dest, withDestinationURL: item.url)
        }
        Task { await browser.silentRefresh() }
    }

    @objc private func quickLook() {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible { panel.orderOut(nil) } else { panel.makeKeyAndOrderFront(nil) }
    }

    @objc private func copyFiles() {
        let urls = tableView.selectedRowIndexes
            .compactMap { $0 < items.count ? items[$0].url : nil }
        guard !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(urls as [NSURL])
    }

    @objc private func shareFiles() {
        let urls = tableView.selectedRowIndexes
            .compactMap { $0 < items.count ? items[$0].url : nil }
        guard !urls.isEmpty else { return }
        let picker = NSSharingServicePicker(items: urls)
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow
                  : tableView.selectedRowIndexes.first ?? 0
        if let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) {
            picker.show(relativeTo: cell.bounds, of: cell, preferredEdge: .minY)
        } else {
            picker.show(relativeTo: tableView.bounds, of: tableView, preferredEdge: .minY)
        }
    }

    @objc private func openWithApp(_ sender: NSMenuItem) {
        guard let arr = sender.representedObject as? [URL], arr.count == 2 else { return }
        NSWorkspace.shared.open([arr[0]], withApplicationAt: arr[1],
                                configuration: .init()) { _, _ in }
    }

    @objc private func openWithOther() {
        guard let first = tableView.selectedRowIndexes.first, first < items.count else { return }
        let fileURL = items[first].url
        let panel = NSOpenPanel()
        panel.message = "Choose an application"
        panel.prompt  = "Open"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories    = false
        panel.begin { response in
            guard response == .OK, let appURL = panel.url else { return }
            NSWorkspace.shared.open([fileURL], withApplicationAt: appURL,
                                    configuration: .init()) { _, _ in }
        }
    }
}

// MARK: - Label cell (date / size / kind)

private final class LabelCellView: NSTableCellView {
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.cell?.lineBreakMode = .byTruncatingTail
        label.cell?.usesSingleLineMode = true
        addSubview(label)
        textField = label
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(text: String, align: NSTextAlignment) {
        label.stringValue = text
        label.alignment   = align
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        let labelH = label.intrinsicContentSize.height
        label.frame = NSRect(x: 0, y: (h - labelH) / 2, width: bounds.width, height: labelH)
    }
}

// MARK: - Name cell (icon + label, with inline rename support)

private final class NameCellView: NSTableCellView, NSTextFieldDelegate {
    private let icon  = NSImageView()
    private let label = NSTextField()

    private var editCompletion: ((String?) -> Void)?
    private var originalName = ""
    private var isCancelling = false

    override init(frame: NSRect) {
        super.init(frame: frame)

        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.imageAlignment = .alignCenter
        addSubview(icon)

        // Styled as a label by default; made editable on demand
        label.isEditable      = false
        label.isSelectable    = false
        label.isBordered      = false
        label.drawsBackground = false
        label.font            = .systemFont(ofSize: 13)
        label.cell?.lineBreakMode   = .byTruncatingMiddle
        label.cell?.usesSingleLineMode = true
        addSubview(label)

        imageView = icon
        textField = label
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(item: FileItem, icon loadedIcon: NSImage?) {
        // Abort any in-progress edit if the cell is being recycled
        if label.isEditable { abortEditing() }

        label.stringValue = item.name
        label.alphaValue  = item.isHidden ? 0.45 : 1.0
        label.textColor   = .labelColor

        if let img = loadedIcon {
            icon.image = img
        } else {
            icon.image = NSImage(systemSymbolName: item.isDirectory ? "folder.fill" : "doc",
                                 accessibilityDescription: nil)
        }
    }

    // MARK: - Inline editing

    func beginEditing(completion: @escaping (String?) -> Void) {
        guard !label.isEditable else { return }
        originalName  = label.stringValue
        editCompletion = completion
        isCancelling   = false

        label.isEditable      = true
        label.isSelectable    = true
        label.isBordered      = true
        label.drawsBackground = true
        label.backgroundColor = .textBackgroundColor
        label.focusRingType   = .exterior
        label.delegate        = self
        label.textColor       = .labelColor

        window?.makeFirstResponder(label)

        // Select base name only (no extension), matching Finder behaviour
        let name = label.stringValue
        let ext  = (name as NSString).pathExtension
        let base = ext.isEmpty ? name : (name as NSString).deletingPathExtension
        label.currentEditor()?.selectedRange = NSRange(location: 0, length: (base as NSString).length)
    }

    private func commitEditing(accept: Bool) {
        guard label.isEditable else { return }
        let result: String? = accept ? label.stringValue.trimmingCharacters(in: .whitespaces) : nil

        label.isEditable      = false
        label.isSelectable    = false
        label.isBordered      = false
        label.drawsBackground = false
        label.focusRingType   = .none
        label.delegate        = nil

        if !accept { label.stringValue = originalName }

        editCompletion?(result.flatMap { $0.isEmpty ? nil : $0 })
        editCompletion = nil
    }

    private func abortEditing() {
        isCancelling = true
        window?.makeFirstResponder(nil)  // triggers controlTextDidEndEditing
    }

    // MARK: - NSTextFieldDelegate

    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            window?.makeFirstResponder(superview) // resign → triggers controlTextDidEndEditing
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            isCancelling = true
            label.stringValue = originalName
            window?.makeFirstResponder(superview)
            return true
        default:
            return false
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        commitEditing(accept: !isCancelling)
        isCancelling = false
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        let h      = bounds.height
        let labelH = label.isEditable
            ? bounds.height - 2          // fill height when editing (shows bezel)
            : label.intrinsicContentSize.height
        let labelY = label.isEditable ? 1 : (h - labelH) / 2
        icon.frame  = NSRect(x: 4, y: (h - 16) / 2, width: 16, height: 16)
        label.frame = NSRect(x: 24, y: labelY, width: bounds.width - 28, height: labelH)
    }
}

// MARK: - Quick Look data source / delegate

extension Coordinator: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        tableView.selectedRowIndexes.count
    }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        let rows = tableView.selectedRowIndexes.sorted()
        guard index < rows.count, rows[index] < items.count else { return nil }
        return items[rows[index]].url as NSURL
    }
}

// MARK: - Tiny helper

private extension NSMenuItem {
    func also(_ configure: (NSMenuItem) -> Void) -> NSMenuItem { configure(self); return self }
}
