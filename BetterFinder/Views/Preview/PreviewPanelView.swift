import SwiftUI
import UniformTypeIdentifiers

/// Right-side preview panel — shows a live preview of the active selection
/// plus a compact metadata strip at the bottom.
struct PreviewPanelView: View {
    let url: URL?

    var body: some View {
        VStack(spacing: 0) {
            header

            if let url {
                FilePreviewContent(url: url)
                    .id(url)                 // force renderer swap on file change
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                FileInfoBar(url: url)
                    .id(url)
            } else {
                emptyState
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: "eye")
                .font(.system(size: 10))
            Text("Preview")
                .font(.system(size: 11, weight: .semibold))
            Spacer()
            if let url {
                Text(url.lastPathComponent)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.trailing, 6)
            }
        }
        .foregroundStyle(.secondary)
        .padding(.leading, 10)
        .frame(height: 26)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "eye.slash")
                .font(.system(size: 38))
                .foregroundStyle(.quaternary)
            Text("No Selection")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
            Text("Select a file to see its preview")
                .font(.system(size: 11))
                .foregroundStyle(.quaternary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
