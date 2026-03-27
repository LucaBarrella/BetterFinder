import Foundation
import UniformTypeIdentifiers
import Darwin

/// Actor-isolated service for reading directory contents off the main thread.
actor FileSystemService {

    private static let resourceKeys: Set<URLResourceKey> = [
        .fileSizeKey,
        .isDirectoryKey,
        .isPackageKey,
        .isHiddenKey,
        .isSymbolicLinkKey,
        .contentModificationDateKey,
        .creationDateKey,
        .contentTypeKey,
    ]

    // MARK: - File Pane

    /// Returns immediate children of `url` for the main file pane.
    func children(of url: URL, showHidden: Bool) throws -> [FileItem] {
        let options: FileManager.DirectoryEnumerationOptions = showHidden ? [] : .skipsHiddenFiles
        let contents = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: Array(Self.resourceKeys),
            options: options
        )
        return contents.compactMap { makeFileItem(url: $0, showHidden: showHidden) }
    }

    // MARK: - Tree (fast POSIX path)

    /// Returns only immediate subdirectories of `url` using POSIX readdir.
    /// Avoids URLResourceValues fetching — uses d_type from the dirent struct,
    /// which is available on APFS/HFS+ without a separate stat() call.
    nonisolated func subdirectories(of url: URL, showHidden: Bool) -> [URL] {
        let path = url.path(percentEncoded: false)
        guard let dir = opendir(path) else { return [] }
        defer { closedir(dir) }

        var result: [URL] = []

        while let entry = readdir(dir) {
            // Extract the name from the fixed-size d_name buffer
            let name = withUnsafeBytes(of: entry.pointee.d_name) { raw -> String? in
                guard let base = raw.baseAddress else { return nil }
                return String(cString: base.assumingMemoryBound(to: CChar.self))
            }
            guard let name, name != ".", name != ".." else { continue }
            if !showHidden && name.hasPrefix(".") { continue }

            let dtype = entry.pointee.d_type

            if dtype == DT_DIR {
                result.append(URL(fileURLWithPath: path + "/" + name, isDirectory: true))
            } else if dtype == DT_UNKNOWN || dtype == DT_LNK {
                // Some filesystems don't fill d_type; fall back to stat
                var st = stat()
                let full = path + "/" + name
                if stat(full, &st) == 0 {
                    let mode = st.st_mode & S_IFMT
                    if mode == S_IFDIR {
                        result.append(URL(fileURLWithPath: full, isDirectory: true))
                    }
                }
            }
        }

        // Exclude .app bundles (packages) – they appear as dirs but act as files
        let filtered = result.filter { url in
            !url.pathExtension.lowercased().hasSuffix("app") &&
            !url.pathExtension.lowercased().hasSuffix("bundle")
        }

        return filtered.sorted {
            $0.lastPathComponent.localizedCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    // MARK: - Private

    private func makeFileItem(url: URL, showHidden: Bool) -> FileItem? {
        guard let resources = try? url.resourceValues(forKeys: Self.resourceKeys) else { return nil }
        let isHidden = resources.isHidden ?? false
        if !showHidden && isHidden { return nil }

        return FileItem(
            id: UUID(),
            url: url,
            size: resources.fileSize.map { Int64($0) },
            isDirectory: resources.isDirectory ?? false,
            isPackage: resources.isPackage ?? false,
            isHidden: isHidden,
            isSymlink: resources.isSymbolicLink ?? false,
            modificationDate: resources.contentModificationDate,
            creationDate: resources.creationDate,
            contentType: resources.contentType
        )
    }
}
