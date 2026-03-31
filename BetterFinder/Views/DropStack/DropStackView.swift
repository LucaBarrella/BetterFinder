import SwiftUI
import UniformTypeIdentifiers

// MARK: - Sidebar section (above Favorites)

struct SidebarDropStackSection: View {
    @Environment(AppState.self) private var appState
    @State private var isExpanded = false
    @State private var isTargeted = false
    @State private var isDragHoveringHeader = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if isExpanded {
                content
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .clipped()
        .padding(.bottom, isExpanded ? 4 : 0)
    }

    // MARK: - Header

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(isDragHoveringHeader ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                    .frame(width: 10)

                Text("Drop Stack".uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)

                if !appState.dropStackItems.isEmpty {
                    Text("\(appState.dropStackItems.count)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Auto-expand when a drag hovers over the header
        .onDrop(of: [.fileURL], isTargeted: $isDragHoveringHeader, perform: handleDrop)
        .onChange(of: isDragHoveringHeader) { _, hovering in
            if hovering && !isExpanded {
                withAnimation(.easeInOut(duration: 0.18)) { isExpanded = true }
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if appState.dropStackItems.isEmpty {
            emptyDropZone
        } else {
            VStack(spacing: 0) {
                fileList
                Divider()
                actionBar
            }
        }
    }

    private var emptyDropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    isTargeted ? Color.accentColor : Color(nsColor: .separatorColor),
                    style: StrokeStyle(lineWidth: 1.5, dash: isTargeted ? [] : [4, 3])
                )
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isTargeted
                              ? Color.accentColor.opacity(0.06)
                              : Color.clear)
                )

            VStack(spacing: 5) {
                Image(systemName: "tray")
                    .font(.system(size: 18))
                    .foregroundStyle(.quaternary)
                Text("Drag files here to hold them")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
                    .multilineTextAlignment(.center)
            }
            .padding(8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(height: 72)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
    }

    private var fileList: some View {
        VStack(spacing: 0) {
            ForEach(appState.dropStackItems, id: \.self) { url in
                fileRow(url: url)
                if url != appState.dropStackItems.last {
                    Divider().padding(.leading, 32)
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
        .overlay(alignment: .top) {
            if isTargeted {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.accentColor, lineWidth: 1)
                    .padding(2)
            }
        }
    }

    private func fileRow(url: URL) -> some View {
        HStack(spacing: 7) {
            Image(nsImage: {
                let img = NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
                img.size = NSSize(width: 14, height: 14)
                return img
            }())
            .frame(width: 14, height: 14)

            Text(url.lastPathComponent)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button { withAnimation { appState.removeFromDropStack(url) } } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onDrag { NSItemProvider(object: url as NSURL) }
    }

    private var actionBar: some View {
        HStack(spacing: 0) {
            Button {
                appState.copyDropStackToActivePane()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "doc.on.doc")
                    Text("Copy")
                }
                .font(.system(size: 10))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
            .disabled(appState.dropStackItems.isEmpty)

            Divider().frame(height: 16)

            Button {
                appState.moveDropStackToActivePane()
            } label: {
                HStack(spacing: 3) {
                    Text("Move")
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 10, weight: .medium))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .padding(.vertical, 6)
            .disabled(appState.dropStackItems.isEmpty)

            Divider().frame(height: 16)

            Button { withAnimation { appState.clearDropStack() } } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 6)
            .disabled(appState.dropStackItems.isEmpty)
            .help("Clear stack")
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Drop handler

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let u = item as? URL {
                    url = u
                }
                if let url {
                    DispatchQueue.main.async { appState.addToDropStack([url]) }
                }
            }
        }
        return true
    }
}
