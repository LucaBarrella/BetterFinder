import SwiftUI
import Foundation

// MARK: - State

@Observable
final class BatchRenameState {
    var isPresented = false
    var items: [RenameItem] = []
    var mode: RenameMode = .replace

    // Replace
    var findText = ""
    var replaceText = ""
    var caseSensitive = false

    // Prefix/Suffix
    var prefix = ""
    var suffix = ""

    // Sequential
    var baseName = ""
    var startNumber = 1
    var padding = 3

    // Case
    var caseMode: CaseMode = .lowercase

    enum RenameMode: String, CaseIterable {
        case replace = "Replace"
        case prefixSuffix = "Prefix/Suffix"
        case sequential = "Number"
        case changeCase = "Case"
    }

    enum CaseMode: String, CaseIterable {
        case lowercase, uppercase, titleCase, camelCase, snakeCase
    }

    struct RenameItem: Identifiable {
        let id = UUID()
        let originalURL: URL
        let originalName: String
        var newName: String
    }

    @ObservationIgnored private var _cachedPreview: [RenameItem]?
    @ObservationIgnored private var _cacheKey: String = ""

    var previewItems: [RenameItem] {
        let key = cacheKey()
        if _cacheKey == key, let cached = _cachedPreview { return cached }
        let result = computePreviewItems()
        _cachedPreview = result
        _cacheKey = key
        return result
    }

    private func cacheKey() -> String {
        "\(mode.rawValue)|\(findText)|\(replaceText)|\(caseSensitive)|\(prefix)|\(suffix)|\(baseName)|\(startNumber)|\(padding)|\(caseMode.rawValue)|\(items.count)"
    }

    private func computePreviewItems() -> [RenameItem] {
        items.compactMap { item in
            let newName = computeNewName(for: item.originalName)
            guard newName != item.originalName else { return nil }
            return RenameItem(originalURL: item.originalURL,
                              originalName: item.originalName,
                              newName: newName)
        }
    }

    func computeNewName(for original: String) -> String {
        let name = original as NSString
        let ext = name.pathExtension
        let base = ext.isEmpty ? name as String : name.deletingPathExtension

        switch mode {
        case .replace:
            guard !findText.isEmpty else { return original }
            if caseSensitive {
                return original.replacingOccurrences(of: findText, with: replaceText)
            } else {
                return original.replacingOccurrences(of: findText, with: replaceText,
                                                      options: .caseInsensitive)
            }

        case .prefixSuffix:
            let newBase = prefix + base + suffix
            return ext.isEmpty ? newBase : newBase + "." + ext

        case .sequential:
            let idx = (items.firstIndex(where: { $0.originalName == original }) ?? 0)
            let number = startNumber + idx
            let numStr = String(format: "%0\(padding)d", number)
            let newName = baseName.isEmpty ? numStr : "\(baseName)\(numStr)"
            return ext.isEmpty ? newName : newName + "." + ext

        case .changeCase:
            let transformed: String
            switch caseMode {
            case .lowercase:
                transformed = base.lowercased()
            case .uppercase:
                transformed = base.uppercased()
            case .titleCase:
                transformed = base.capitalized
            case .camelCase:
                let titled = base.capitalized
                transformed = titled.prefix(1).lowercased() + titled.dropFirst()
                    .replacingOccurrences(of: " ", with: "")
            case .snakeCase:
                transformed = base
                    .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1_$2",
                                          options: .regularExpression)
                    .replacingOccurrences(of: " ", with: "_")
                    .lowercased()
            }
            return ext.isEmpty ? transformed : transformed + "." + ext
        }
    }
}

// MARK: - Sheet View

struct BatchRenameSheet: View {
    @Bindable var state: BatchRenameState
    let onApply: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isApplying = false

    var body: some View {
        VStack(spacing: 0) {
            modePicker
                .padding(.horizontal)
                .padding(.top, 16)

            modeFields
                .padding(.horizontal)
                .padding(.top, 12)

            Divider()
                .padding(.top, 12)

            previewTable

            Divider()

            buttons
                .padding(.horizontal)
                .padding(.vertical, 10)
        }
        .frame(width: 560, height: 440)
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        Picker("Mode", selection: $state.mode) {
            ForEach(BatchRenameState.RenameMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Mode Fields

    @ViewBuilder
    private var modeFields: some View {
        switch state.mode {
        case .replace:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    TextField("Find", text: $state.findText)
                        .textFieldStyle(.roundedBorder)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                    TextField("Replace", text: $state.replaceText)
                        .textFieldStyle(.roundedBorder)
                }
                Toggle("Case Sensitive", isOn: $state.caseSensitive)
                    .toggleStyle(.checkbox)
            }

        case .prefixSuffix:
            HStack {
                TextField("Prefix", text: $state.prefix)
                    .textFieldStyle(.roundedBorder)
                TextField("Suffix", text: $state.suffix)
                    .textFieldStyle(.roundedBorder)
            }

        case .sequential:
            HStack {
                TextField("Base Name", text: $state.baseName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                Stepper("Start: \(state.startNumber)", value: $state.startNumber, in: 0...9999)
                    .frame(width: 140)
                Stepper("Pad: \(state.padding)", value: $state.padding, in: 1...10)
                    .frame(width: 110)
            }

        case .changeCase:
            Picker("Case", selection: $state.caseMode) {
                ForEach(BatchRenameState.CaseMode.allCases, id: \.self) { cm in
                    Text(cm.rawValue).tag(cm)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Preview Table

    private var previewTable: some View {
        let previews = state.previewItems
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Preview").font(.headline)
                Spacer()
                Text("\(previews.count) file\(previews.count == 1 ? "" : "s") will change")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            Table(previews) {
                TableColumn("Original Name") { item in
                    Text(item.originalName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                TableColumn("New Name") { item in
                    Text(item.newName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.primary)
                }
            }
            .tableStyle(.inset)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        }
    }

    // MARK: - Buttons

    private var buttons: some View {
        HStack {
            Spacer()
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button("Apply") {
                isApplying = true
                Task {
                    await onApply()
                    isApplying = false
                    dismiss()
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(state.previewItems.isEmpty || isApplying)
        }
    }
}
