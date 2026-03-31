import SwiftUI
import Darwin

// MARK: - FDA Detection

enum FullDiskAccessChecker {
    /// Returns true if the app can read the TCC database, which requires Full Disk Access.
    static func isGranted() -> Bool {
        let fd = Darwin.open("/Library/Application Support/com.apple.TCC/TCC.db", O_RDONLY)
        guard fd >= 0 else { return false }
        Darwin.close(fd)
        return true
    }
}

// MARK: - Onboarding Sheet

struct FullDiskAccessView: View {
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 28) {

            // Icon
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue)
                .symbolRenderingMode(.hierarchical)
                .padding(.top, 8)

            // Title + subtitle
            VStack(spacing: 8) {
                Text("Full Disk Access Required")
                    .font(.title2.weight(.semibold))

                Text("BetterFinder needs Full Disk Access to browse all folders — including protected directories like Library, System, and hidden paths — and to run system-wide Spotlight searches.\n\nWithout it some folders will appear empty.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 400)
            }

            // Step-by-step instructions
            VStack(alignment: .leading, spacing: 10) {
                StepRow(n: "1", text: "Open **System Settings → Privacy & Security**")
                StepRow(n: "2", text: "Scroll down to **Full Disk Access**")
                StepRow(n: "3", text: "Click the **＋** button and add **BetterFinder**")
                StepRow(n: "4", text: "Relaunch BetterFinder")
            }
            .padding(.horizontal, 24)

            // Buttons
            HStack(spacing: 12) {
                Button("Later") {
                    onDismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

                Button {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
                    )
                    onDismiss()
                } label: {
                    Label("Open Privacy Settings", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.bottom, 8)
        }
        .padding(40)
        .frame(minWidth: 500)
    }
}

// MARK: - Step Row

private struct StepRow: View {
    let n: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(n)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor)
                .clipShape(Circle())
                .padding(.top, 1)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
