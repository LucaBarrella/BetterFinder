import Foundation
import UniformTypeIdentifiers

struct FileItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let url: URL
    let size: Int64?
    let isDirectory: Bool
    let isPackage: Bool
    let isHidden: Bool
    let isSymlink: Bool
    let modificationDate: Date?
    let creationDate: Date?
    let contentType: UTType?

    var name: String {
        let component = url.lastPathComponent
        return component.isEmpty ? "/" : component
    }

    var kindDescription: String {
        if isSymlink { return "Alias" }
        if isPackage { return contentType?.localizedDescription ?? "Application" }
        if isDirectory { return "Folder" }
        if let desc = contentType?.localizedDescription { return desc }
        let ext = url.pathExtension
        return ext.isEmpty ? "Document" : "\(ext.uppercased()) File"
    }

    var formattedSize: String {
        guard !isDirectory else { return "—" }
        guard let size else { return "—" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var formattedDate: String {
        guard let date = modificationDate else { return "" }
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return "Today " + date.formatted(date: .omitted, time: .shortened)
        }
        if cal.isDateInYesterday(date) {
            return "Yesterday " + date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    // Sortable non-optional proxies for TableColumn
    var sortableDate: Date { modificationDate ?? .distantPast }
    var sortableSize: Int64 { size ?? -1 }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: FileItem, rhs: FileItem) -> Bool { lhs.id == rhs.id }
}
