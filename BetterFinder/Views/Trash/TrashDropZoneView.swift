import SwiftUI
import UniformTypeIdentifiers

struct TrashDropZoneView: View {
    @Environment(AppState.self) private var appState
    @State private var isTargeted = false
    @State private var expandedHeight: CGFloat = 190
    @State private var dragStartHeight: CGFloat = 190

    private let trashURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".Trash")

    var body: some View {
        VStack(spacing: 0) {
            if appState.showTrashZone {
                resizeHandle
            }
            header
            if appState.showTrashZone {
                dropContent
                    .frame(height: expandedHeight)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // Clip so the slide-up transition doesn't overflow
        .clipped()
    }

    // MARK: - Resize handle

    private var resizeHandle: some View {
        Color(nsColor: .separatorColor)
            .frame(maxWidth: .infinity)
            .frame(height: 1)
            .padding(.vertical, 3)        // 7pt tall hit area
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { NSCursor.resizeUpDown.push() }
                else        { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { v in
                        expandedHeight = max(60, min(420, dragStartHeight - v.translation.height))
                    }
                    .onEnded { _ in dragStartHeight = expandedHeight }
            )
            .transition(.opacity)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "trash")
                .font(.system(size: 10))
            Text("Trash")
                .font(.system(size: 11, weight: .semibold))
            Spacer()
            Image(systemName: appState.showTrashZone ? "chevron.down" : "chevron.up")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.trailing, 10)
        }
        .foregroundStyle(.secondary)
        .padding(.leading, 10)
        .frame(height: 26)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                appState.showTrashZone.toggle()
            }
        }
    }

    // MARK: - Drop content

    private var dropContent: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)
            VStack(spacing: 10) {
                Image(systemName: isTargeted ? "trash.fill" : "trash")
                    .font(.system(size: 38))
                    .foregroundStyle(isTargeted ? Color.red : Color.secondary.opacity(0.25))
                    .animation(.easeInOut(duration: 0.1), value: isTargeted)

                Text(isTargeted ? "Release to trash" : "Drop files here to trash them")
                    .font(.system(size: 11))
                    .foregroundStyle(.quaternary)
                    .multilineTextAlignment(.center)

                Button("Open Trash") { openTrash() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(isTargeted ? Color.red.opacity(0.45) : Color.clear, lineWidth: 2)
                .padding(4)
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleTrashDrop)
        .onTapGesture(count: 2) { openTrash() }
    }

    // MARK: - Actions

    private func openTrash() {
        appState.activeBrowser.navigate(to: trashURL)
    }

    private func handleTrashDrop(_ providers: [NSItemProvider]) -> Bool {
        var collected: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    collected.append(url)
                } else if let url = item as? URL {
                    collected.append(url)
                }
            }
        }
        group.notify(queue: .main) {
            guard !collected.isEmpty else { return }
            appState.trashFiles(collected, reloadBrowser: appState.activeBrowser)
        }
        return true
    }
}
