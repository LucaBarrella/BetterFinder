import SwiftUI

struct StatusBarView: View {
    var browser: BrowserState

    private var summary: String {
        let total = browser.filteredItems.count
        let selected = browser.selectedItems.count

        if selected == 0 {
            return total == 1 ? "1 item" : "\(total) items"
        } else {
            let items = selected == 1 ? "1 item selected" : "\(selected) items selected"
            let totalBytes = browser.selectedFileItems
                .compactMap(\.size)
                .reduce(0, +)
            if totalBytes > 0 {
                let formatted = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
                return "\(items) — \(formatted)"
            }
            return items
        }
    }

    var body: some View {
        HStack {
            Spacer()
            Text(summary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(height: 22)
        .background(.bar)
    }
}
