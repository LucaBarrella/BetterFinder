import SwiftUI

struct PathBarView: View {
    @Environment(AppState.self) private var appState
    var browser: BrowserState

    @State private var isEditing = false
    @State private var editText  = ""
    @State private var suggestions: [PathSuggestion] = []
    @State private var history: [String] = []
    @State private var selectedIndex: Int = 0

    private static let historyKey = "goToFolderHistory"
    private static let maxHistory = 10
    private static let maxSuggestions = 8

    private var pathComponents: [(name: String, url: URL)] {
        var result: [(name: String, url: URL)] = []
        var current = browser.currentURL.standardizedFileURL

        while true {
            let segment: String
            if current.pathComponents == ["/"] {
                segment = "/"
            } else {
                segment = current.lastPathComponent
            }
            result.insert((name: segment, url: current), at: 0)
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent == current { break }
            current = parent
        }

        // Drop leading "/" when the path has deeper components
        if result.count > 1, result.first?.name == "/" {
            result.removeFirst()
        }

        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if isEditing {
                    editingBar
                } else {
                    breadcrumbs
                    copyButton
                }
            }
            .frame(height: 30)
            .background(.bar)

            if isEditing, !suggestions.isEmpty {
                suggestionDropdown
            }
        }
        .onAppear {
            browser.triggerPathEdit = { startEditing() }
        }
        .onChange(of: editText) { _, newValue in
            updateSuggestions(for: newValue)
            selectedIndex = 0
        }
    }

    // MARK: - Copy Button

    private var copyButton: some View {
        Button {
            let path = browser.currentURL.path(percentEncoded: false)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Copy Path  ⌘⇧C")
        .padding(.horizontal, 8)
        .keyboardShortcut("c", modifiers: [.command, .shift])
    }

    // MARK: - Breadcrumbs

    private var breadcrumbs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 1) {
                ForEach(Array(pathComponents.enumerated()), id: \.offset) { index, component in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 1)
                    }

                    let isLast = index == pathComponents.count - 1
                    Button {
                        if !isLast {
                            browser.navigate(to: component.url)
                        }
                    } label: {
                        Text(component.name)
                            .font(.system(size: 12, weight: isLast ? .medium : .regular))
                            .foregroundStyle(isLast ? Color.primary : Color.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(
                                isLast
                                    ? Color.primary.opacity(0.07)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 4)
                            )
                    }
                    .buttonStyle(.plain)
                    .onTapGesture(count: 2) {
                        if isLast { startEditing() }
                    }
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 12)
        }
    }

    // MARK: - Editing Bar

    private var editingBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
                .padding(.leading, 12)

            TextField("Path", text: $editText)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .onSubmit {
                    if !suggestions.isEmpty {
                        editText = suggestions[selectedIndex].path
                    }
                    commitEdit()
                }
                .onExitCommand { isEditing = false }
                .onKeyPress(.upArrow) {
                    guard !suggestions.isEmpty else { return .ignored }
                    selectedIndex = max(0, selectedIndex - 1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    guard !suggestions.isEmpty else { return .ignored }
                    selectedIndex = min(suggestions.count - 1, selectedIndex + 1)
                    return .handled
                }
                .onKeyPress(.tab) {
                    guard !suggestions.isEmpty else { return .ignored }
                    editText = suggestions[selectedIndex].path
                    updateSuggestions(for: editText)
                    return .handled
                }

            Button("Cancel") { isEditing = false }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
                .padding(.trailing, 10)
        }
    }

    // MARK: - Suggestion Dropdown

    private var suggestionDropdown: some View {
        let rowHeight: CGFloat = 28
        let dynamicHeight = min(CGFloat(suggestions.count) * rowHeight, 200)

        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                    suggestionRow(suggestion, index: index)
                }
            }
        }
        .frame(height: dynamicHeight)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .padding(.horizontal, 8)
    }

    private func suggestionRow(_ suggestion: PathSuggestion, index: Int) -> some View {
        Button {
            editText = suggestion.path
            commitEdit()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: suggestion.isHistory ? "clock" : "folder")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)

                Text(suggestion.displayName)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.head)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                index == selectedIndex
                    ? Color.accentColor.opacity(0.15)
                    : Color.clear
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { selectedIndex = index }
        }
    }

    // MARK: - Suggestions Logic

    private func updateSuggestions(for input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            // Show history when field is empty
            suggestions = history.map { path in
                let name = (path as NSString).lastPathComponent.isEmpty ? path : (path as NSString).lastPathComponent
                return PathSuggestion(path: path, displayName: name, isHistory: true)
            }
            return
        }

        let expanded = NSString(string: trimmed).expandingTildeInPath
        let fm = FileManager.default

        // Determine parent directory and partial name to match
        var searchDir: String
        var partial: String

        if trimmed.hasSuffix("/") {
            // Typing inside a directory — enumerate that directory
            searchDir = expanded
            partial = ""
        } else {
            searchDir = (expanded as NSString).deletingLastPathComponent
            partial = (expanded as NSString).lastPathComponent.lowercased()
        }

        guard let contents = try? fm.contentsOfDirectory(atPath: searchDir) else {
            suggestions = []
            return
        }

        let baseURL = URL(fileURLWithPath: searchDir)
        var results: [PathSuggestion] = []

        for name in contents.sorted() {
            // Skip hidden unless the user typed a dot
            if name.hasPrefix(".") && !partial.hasPrefix(".") { continue }

            if partial.isEmpty || name.lowercased().hasPrefix(partial) {
                let fullPath = baseURL.appendingPathComponent(name).path
                var isDir: ObjCBool = false
                fm.fileExists(atPath: fullPath, isDirectory: &isDir)
                if isDir.boolValue {
                    results.append(PathSuggestion(path: fullPath, displayName: name, isHistory: false))
                    if results.count >= Self.maxSuggestions { break }
                }
            }
        }

        suggestions = results
    }

    // MARK: - Editing Actions

    private func startEditing() {
        editText = browser.currentURL.path(percentEncoded: false)
        history = UserDefaults.standard.stringArray(forKey: Self.historyKey) ?? []
        suggestions = history.map { path in
            let name = (path as NSString).lastPathComponent.isEmpty ? path : (path as NSString).lastPathComponent
            return PathSuggestion(path: path, displayName: name, isHistory: true)
        }
        selectedIndex = 0
        isEditing = true
    }

    private func commitEdit() {
        let expanded = NSString(string: editText).expandingTildeInPath
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue {
            // Save to history
            var recent = UserDefaults.standard.stringArray(forKey: Self.historyKey) ?? []
            recent.removeAll { $0 == expanded }
            recent.insert(expanded, at: 0)
            if recent.count > Self.maxHistory { recent = Array(recent.prefix(Self.maxHistory)) }
            UserDefaults.standard.set(recent, forKey: Self.historyKey)

            browser.navigate(to: URL(fileURLWithPath: expanded))
        }
        isEditing = false
    }
}

// MARK: - Path Suggestion Model

private struct PathSuggestion {
    let path: String
    let displayName: String
    let isHistory: Bool
}

#Preview {
    let svc = FileSystemService()
    PathBarView(browser: BrowserState(url: URL.homeDirectory, fileSystemService: svc))
        .environment(AppState())
}
