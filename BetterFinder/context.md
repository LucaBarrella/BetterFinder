# NativeFinder â€” AI Agent Build Prompt

## Project Overview

You are tasked with building **NativeFinder**, a native, open-source macOS file manager built with SwiftUI, designed as a **developer-first replacement for Apple Finder**. The app targets **macOS 26+**, is distributed as a **signed DMG for Apple Silicon (arm64)**, and will be published open source on GitHub.

The core philosophy is: **power-user functionality with a native, intuitive macOS interface**. The UI must feel like a first-party Apple app â€” no Electron, no cross-platform compromises â€” while fixing every structural limitation of the default Finder.

The visual layout is inspired by file managers on **Windows Explorer and Linux (Nautilus/Dolphin/Nemo)**: persistent sidebar tree, always-visible path, dual-pane support.

---

## Tech Stack & Language Policy

### Primary Language: Swift + SwiftUI
All UI, navigation logic, state management, and high-level file operations must be written in **Swift using SwiftUI** with AppKit bridging where necessary (`NSViewRepresentable`, `NSWindowController`, etc.).

### Performance-Critical Exceptions (C or C++)
When performance is essential, you **may** use C or C++ via Swift Package bridging or a dedicated `.c`/`.cpp` target in the Swift Package. Apply this **only** for:
- Directory tree scanning and recursive file enumeration (can involve millions of inodes)
- File size computation for large directory trees (disk usage maps)
- File content diffing (folder compare algorithm)
- Low-level filesystem watchers (`kqueue` or `FSEvents` via C wrappers if the Swift API is insufficient)

### Package Manager
Use **Swift Package Manager (SPM)** exclusively. No CocoaPods, no Carthage.

### Minimum Target
- macOS 26.0+
- Apple Silicon (arm64) primary target; universal binary (arm64 + x86_64) as stretch goal

---

## Code Architecture

### Principles
Write **clean, modular, maintainable** code. Every module must be independently testable. Avoid massive monolithic view files. Follow these rules strictly:

1. **MVVM + Unidirectional Data Flow** â€” Views observe `@Observable` or `ObservableObject` models. No business logic inside View structs.
2. **Feature Modules** â€” Each major feature lives in its own Swift module (SPM target). Features communicate through clearly defined interfaces/protocols, never through direct imports of sibling modules.
3. **Dependency Injection** â€” No singletons except for app-wide services (e.g., `FileSystemService`). Pass dependencies via initializers or SwiftUI `Environment`.
4. **Protocol-Oriented Design** â€” Define `FileSystemProviding`, `SearchProviding`, `TerminalProviding`, etc. as protocols. Concrete implementations are swappable for testing.
5. **No force-unwrap, no `try!`** â€” Handle all errors explicitly. Use `Result<T, AppError>` or typed `throws`.

### Module Structure

```
NativeFinder/
+-- App/                          # Entry point, AppDelegate, scene setup
+-- Modules/
|   +-- FileSystem/               # Core FS operations, watchers, metadata
|   +-- TreeNavigator/            # Sidebar tree view, directory graph
|   +-- FilePane/                 # Main file list pane (single & dual)
|   +-- Search/                   # Search engine, index, results UI
|   +-- Terminal/                 # Embedded terminal emulator
|   +-- SizeBrowser/              # Disk usage treemap visualization
|   +-- BatchRename/              # Rename engine with regex
|   +-- FolderSync/               # Diff & sync between two folders
|   +-- Clipboard/                # Clipboard history manager
|   +-- QuickLook/                # Extended preview integration
|   +-- Permissions/              # Permissions viewer and chmod UI
|   +-- Preferences/              # Settings UI and persistent config
+-- SharedUI/                     # Reusable SwiftUI components, tokens, icons
+-- SharedModels/                 # Value types shared across modules (FileItem, etc.)
+-- Bridge/                       # C/C++ performance modules exposed via Swift
+-- Tests/                        # Unit + integration tests per module
```

### Key Shared Model: FileItem

```swift
struct FileItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let url: URL
    let name: String
    let size: Int64?
    let kind: FileKind          // .directory, .regularFile, .symlink, .package
    let isHidden: Bool
    let permissions: FilePermissions
    let modificationDate: Date
    let creationDate: Date
    var gitStatus: GitStatus?   // nil if not in a git repo
    var children: [FileItem]?   // populated lazily for directories
}
```

---

## UI/UX Design Guidelines

### Layout: Three-Panel Structure

```
+---------------+------------------------------------+----------+
|               |  PATH BAR (always visible)         |          |
|  SIDEBAR      +------------------+-----------------+  DETAIL  |
|  TREE         |  FILE PANE 1     |  FILE PANE 2    |  PANEL   |
|  NAVIGATOR    |  (primary)       |  (optional dual)|  (info / |
|               |                  |                 |  preview)|
|               +------------------+-----------------+          |
|               |  TERMINAL (collapsible drawer)     |          |
+---------------+------------------------------------+----------+
```

### Native macOS 26 Aesthetics
- Use liquid glass materials where appropriate (`ultraThinMaterial`, `regularMaterial`)
- Follow macOS 26 design language: rounded corners, vibrancy, SF Symbols 6
- Respect the system accent color and Dark Mode / Light Mode automatically
- Sidebar uses `List` with `listStyle(.sidebar)` â€” exact match to Finder/Mail sidebar feel
- Toolbar uses `ToolbarItem` with semantic placements â€” no custom chrome
- Context menus use native `Menu` and `contextMenu` modifiers with correct grouping separators
- Do **not** use UIKit-style layouts; embrace SwiftUI layout primitives (`Grid`, `ViewThatFits`, etc.)

### Typography & Icons
- Use **SF Symbols** for every icon â€” no custom image assets unless strictly necessary
- File type icons via `NSWorkspace.shared.icon(for:)` bridged to SwiftUI `Image`
- Font sizing follows macOS HIG (body: 13pt, sidebar label: 12pt, monospace terminal: 13pt)

---

## Feature Specifications

### 1. Persistent Sidebar Tree Navigator

**Problem solved:** Finder has no always-visible tree view. Users never know where they are in the hierarchy.

**Requirements:**
- Left sidebar shows the **full directory tree** starting from `/` (root), `~` (home), mounted volumes, and network shares
- Tree nodes expand/collapse lazily â€” children loaded on demand using async `FileSystemService.children(of:)`
- Currently open folder is **always highlighted** and auto-scrolled into view
- Navigating in the main pane updates the tree selection, and vice versa (bidirectional binding)
- Drag & drop reordering for Favorites section (pinned folders)
- Right-click on any node: Open in New Tab, Open in Terminal, Copy Path, Reveal in Pane, New Folder
- Show git status badge on folders that are git repos (colored dot: clean/dirty/untracked)
- Support `Cmd+Click` to expand all children recursively

**Implementation notes:**
- Use `OutlineGroup` or a custom recursive `List` with `disclosureGroupStyle`
- Directory scanning must be non-blocking: use `async/await` + `Actor`-isolated `FileSystemActor`
- Use `FSEvents` (via `FileSystemWatcher` C bridge) to auto-refresh tree when files change on disk

---

### 2. Always-Visible & Editable Path Bar

**Problem solved:** Finder hides the path, making it hard to know or share your current location.

**Requirements:**
- Persistent path bar below the toolbar, always visible, showing the full path as **clickable breadcrumbs**
- Each segment is a tappable button that navigates to that ancestor directory
- The final segment (current folder name) is **double-click to edit** â€” type a path manually and press Enter to navigate
- A **Copy Path button** (or `Cmd+Shift+C`) copies the current full POSIX path to clipboard instantly
- On hover of any breadcrumb, show a popover with the child folders for fast navigation
- Show file path in path bar when a file is selected (not just folders)

---

### 3. Context-Aware, Developer-Friendly Search

**Problem solved:** Finder resets the search scope to "This Mac" and does not show where results were found.

**Requirements:**
- Search **always defaults to the current folder** â€” "This Mac" is a secondary toggle, not the default
- Scope toggle bar below the search field: `Current Folder` | `Home` | `This Mac` | `Custom...`
- Results always show the **full parent path** for each result item
- Substring matching is prioritized: filename match > content match > metadata match
- Filter chips: `Kind`, `Date Modified`, `Size`, `Extension`, `Hidden files included`
- Real-time incremental results using `NSMetadataQuery` for Spotlight-backed search with custom scoping
- Search history dropdown (last 20 queries, persisted to `UserDefaults`)
- Regex search mode toggled by a `.*` button in the search bar

**Implementation:**
- Wrap `NSMetadataQuery` in a `SearchService` conforming to `SearchProviding`
- For local/current-folder search, fall back to recursive `FileManager` enumeration with `AsyncStream` for streaming results

---

### 4. Integrated Terminal

**Problem solved:** Developers must leave the file manager to open a terminal.

**Requirements:**
- Terminal drawer slides up from the bottom of the main pane (collapsible, resizable)
- Toggle shortcut: `` Ctrl+` `` (same as VS Code)
- Terminal **automatically `cd`s** to the current folder when opened or when navigation changes
- Option to sync terminal CWD to pane (navigate the file pane to the terminal's current directory)
- Supports multiple terminal tabs within the drawer
- Full color support (ANSI 256 + Truecolor), working arrow keys, tab completion
- Uses the user's default shell (`$SHELL` env var: `zsh`, `bash`, `fish`, etc.)
- Font and color scheme configurable in Preferences
- Copy/paste works natively; right-click shows context menu

**Implementation:**
- Use `SwiftTerm` (open source Swift terminal emulator library) as the rendering backend
- Manage the shell process via `Foundation.Process` + PTY (pseudo-terminal via `posix_openpt`)
- Create a `TerminalViewController: NSViewController` wrapped in `NSViewControllerRepresentable`

---

### 5. Hidden Files Toggle

**Problem solved:** Developers need dotfiles visible constantly without re-toggling every session.

**Requirements:**
- Persistent toggle in the toolbar (SF Symbol: `eye` / `eye.slash`)
- State persisted to `UserDefaults` â€” survives app restart
- Shortcut: `Cmd+Shift+.` (same as Finder for muscle memory)
- When hidden files are shown, they render with **50% opacity** to visually distinguish them
- Hidden folders also expand and show in the sidebar tree

---

### 6. Dual Pane View

**Problem solved:** Moving files between two locations requires multiple Finder windows.

**Requirements:**
- Toggle dual pane with a toolbar button or `Cmd+D`
- Two independent file panes side-by-side with a draggable divider
- Each pane has its own path bar, search bar, and navigation history
- **Mirror mode**: both panes navigate in sync (useful for comparing folder contents)
- Drag & drop between panes to move/copy files
- `F5` copies selected files from the active pane to the other pane's current path
- `F6` moves selected files to the other pane's current path
- Active pane indicated by a colored accent border

---

### 7. Batch Rename

**Problem solved:** Finder has no advanced batch renaming capability.

**Requirements:**
- Select multiple files, then right-click > "Batch Rename..." to open a sheet
- Rename modes:
  - **Replace text**: find/replace substring (with regex option)
  - **Add prefix/suffix**: prepend or append a string
  - **Number sequentially**: `photo_001.jpg`, `photo_002.jpg`, ...
  - **Change case**: lowercase, UPPERCASE, Title Case
  - **Remove characters**: strip specific patterns (spaces, special chars, etc.)
  - **Use metadata**: insert date, resolution, EXIF data for media files
- Live preview: show original name and new name for every selected file before confirming
- Undo-able as a single transaction via `UndoManager`

---

### 8. Size Browser (Disk Usage Treemap)

**Problem solved:** Finder has no visual way to find what is consuming disk space.

**Requirements:**
- Accessible from the View menu or a toolbar button
- Renders a **treemap visualization** of disk usage for the current folder
- Each rectangle represents a file or folder; size is proportional to disk usage
- Color-coded by file type (video: blue, images: green, code: yellow, archives: red, etc.)
- Click a rectangle to navigate into that folder
- Hover shows a tooltip: name, size, and percentage of parent
- Computed in a C background task (recursive `du`-style scan) to avoid blocking the main thread
- Progress bar displayed during computation for large directories

**Implementation:**
- Directory size scanning in C (via `Bridge/` module) using `opendir`/`readdir`/`stat` syscalls
- Squarified treemap layout algorithm implemented in Swift
- Rendered with SwiftUI `Canvas` for performance

---

### 9. Folder Diff & Sync

**Problem solved:** Finder cannot compare or synchronize two folders.

**Requirements:**
- Accessible from the dual pane view via a "Compare Panes" button
- Shows a diff view: left folder vs right folder with color-coded status:
  - Green: only in left; Red: only in right; Yellow: same name but different content or date; White: identical
- Filter by: Show All / Only Differences / Only Left / Only Right
- Sync actions: copy left to right, copy right to left, delete items unique to one side
- Dry-run mode: preview all sync operations before executing
- Recursive diff with progress indicator

---

### 10. Clipboard History

**Problem solved:** macOS has no native clipboard history; Finder has no global file shortcuts.

**Requirements:**
- Maintains a history of the last **50 copy operations** (files, folders, text copied from the path bar)
- Accessible via `Cmd+Shift+V` â€” opens a popover showing recent clipboard entries
- Each entry shows: filename, path, time of copy, file type icon
- Click an entry to re-copy it to the current clipboard
- "Paste from history" directly into the active pane
- History is **not persisted to disk** (privacy by default â€” session only)
- A separate "Pinned" section for items dragged to pin (survive the session)

---

### 11. Extended Quick Look

**Problem solved:** Finder's Quick Look does not handle developer file types.

**Requirements:**
- `Space` key triggers Quick Look for the selected file (same as Finder)
- Enhanced preview for developer file types without external plugins:
  - `.md`, `.markdown`: rendered Markdown with syntax highlighting
  - `.json`: syntax-highlighted, collapsible tree viewer
  - `.csv`: rendered as a sortable table
  - `.log`: monospaced, with ANSI color support
  - `.swift`, `.py`, `.js`, `.ts`, `.c`, `.cpp`, `.sh`: syntax-highlighted code
- Use `WKWebView` for Markdown rendering with a custom CSS theme
- Fallback to native `QLPreviewController` for all other file types

---

### 12. Permissions Viewer & Quick chmod

**Problem solved:** Developers frequently need to check and change file permissions.

**Requirements:**
- File info panel (right sidebar) shows `rwxrwxrwx` permissions in both symbolic and octal notation
- Quick chmod buttons: `+x`, `-x`, `777`, `755`, `644` â€” one click
- Full permissions editor: checkbox grid for owner/group/other x read/write/execute
- Show owner and group names (`ls -la` style)
- Supports privilege escalation via macOS Security Framework prompt for protected files

---

## Preferences & Configuration

All user preferences stored in `UserDefaults` with a typed `AppPreferences` model:

| Preference             | Type                        | Default      |
|------------------------|-----------------------------|--------------|
| Show hidden files      | Bool                        | false        |
| Default view mode      | Enum (list/grid/columns)    | list         |
| Default sort           | Enum (name/date/size/kind)  | name         |
| Show path bar          | Bool                        | true         |
| Show status bar        | Bool                        | true         |
| Terminal shell         | String                      | $SHELL       |
| Terminal font          | String                      | SF Mono 13pt |
| Dual pane on startup   | Bool                        | false        |
| Search default scope   | Enum (current/home/mac)     | current      |
| Hidden files opacity   | Double                      | 0.5          |
| Tree auto-expand depth | Int                         | 2            |

---

## Git Integration (Stretch Goal / v2)

- When a folder is a git repository, show status badges on files and folders in both tree and pane:
  - Green: Modified; Blue: Staged; Yellow: Untracked; Red: Conflict
- Toolbar shows the current branch name when inside a git repo
- Right-click file > "Git" submenu: Stage, Unstage, Discard Changes, View Log
- Use `libgit2` via Swift bridge or shell out to `git` CLI via `Foundation.Process`

---

## Build & Distribution

- Build system: **Xcode + SPM**, no external build tools
- Signing: Developer ID Application (for notarization outside the App Store)
- Distribution: **DMG with background image**, app dragged to `/Applications`
- Create DMG using `create-dmg` or `hdiutil` in a shell script / Makefile target
- GitHub Actions CI pipeline:
  - Build on every push to `main`
  - Run unit tests
  - Create notarized `.dmg` on tagged releases
- Minimum deployment target: **macOS 26.0**
- Architecture: **arm64** (Apple Silicon primary), universal binary as stretch goal

---

## Naming & Branding

- App name: **NativeFinder** (working title)
- Bundle ID: `com.nativefinder.app`
- License: **MIT**

---

## First Steps for the Agent

Implement in this exact order. Do not skip ahead to later steps before earlier ones are fully functional.

1. Set up SPM project structure with all module targets declared in `Package.swift`
2. Implement `FileSystemService` (async, Actor-isolated, with FSEvents watcher)
3. Build the sidebar tree navigator with lazy loading â€” this is the spine of the entire app
4. Implement the path bar with breadcrumb navigation
5. Wire bidirectional navigation: tree selection <-> main pane selection
6. Add hidden files toggle (quick win, high value)
7. Integrate SwiftTerm for the terminal drawer
8. Implement context-aware search
9. Add dual pane support
10. Implement all remaining features as independent modules

Do **not** start building UI polish, animations, or Preferences until the core navigation loop (tree + pane + path bar + terminal) is fully functional.

---

> **Code quality rule:** Every public function must have a doc comment. Every module must have at least one unit test. No TODO comments in committed code â€” open a GitHub Issue instead. Keep PRs small and feature-scoped.
