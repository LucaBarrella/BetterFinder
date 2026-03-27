import SwiftUI

struct PathBarView: View {
    @Environment(AppState.self) private var appState
    var browser: BrowserState

    @State private var isEditing = false
    @State private var editText  = ""

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

    // MARK: - Editing

    private var editingBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
                .padding(.leading, 12)

            TextField("Path", text: $editText)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .onSubmit { commitEdit() }

            Button("Cancel") { isEditing = false }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
                .padding(.trailing, 10)
        }
    }

    private func startEditing() {
        editText  = browser.currentURL.path(percentEncoded: false)
        isEditing = true
    }

    private func commitEdit() {
        let expanded = NSString(string: editText).expandingTildeInPath
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue {
            browser.navigate(to: URL(fileURLWithPath: expanded))
        }
        isEditing = false
    }
}

#Preview {
    let svc = FileSystemService()
    PathBarView(browser: BrowserState(url: URL.homeDirectory, fileSystemService: svc))
        .environment(AppState())
}
