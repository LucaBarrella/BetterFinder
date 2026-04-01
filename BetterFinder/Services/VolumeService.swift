@preconcurrency import Foundation

private let DISK_UTIL_TIMEOUT_SECONDS: TimeInterval = 10
private nonisolated let MAX_OUTPUT_BYTES = 8192

enum VolumeError: Error, LocalizedError {
    case notEjectable
    case mountPointNotFound
    case unmountFailed(String)

    var errorDescription: String? {
        switch self {
        case .notEjectable:
            return NSLocalizedString("VOLUME_NOT_EJECTABLE", comment: "")
        case .mountPointNotFound:
            return NSLocalizedString("VOLUME_MOUNT_NOT_FOUND", comment: "")
        case .unmountFailed(let message):
            return String(format: NSLocalizedString("EJECT_FAILED_FMT", comment: ""), message)
        }
    }
}

final class VolumeService {

    private let diskUtilPath = "/usr/sbin/diskutil"

    /// Returns the mount point URL for the volume containing the given URL.
    ///
    /// - Parameter url: The file URL to resolve against mounted volumes.
    /// - Returns: The volume mount point URL, or nil if not found.
    nonisolated func volumeMountPoint(for url: URL) -> URL? {
        resolveVolumeMountPoint(for: url)
    }

    /// Determines whether the volume at the given URL is ejectable.
    ///
    /// - Parameter url: The file URL to check.
    /// - Returns: True if the volume is ejectable, false otherwise.
    nonisolated func isEjectableVolume(_ url: URL) -> Bool {
        guard let volumeURL = resolveVolumeMountPoint(for: url) else { return false }
        return isLocalRemovableVolume(volumeURL)
    }

    /// Asynchronously determines whether the volume at the given URL is ejectable.
    ///
    /// - Parameter url: The file URL to check.
    /// - Returns: True if the volume is ejectable, false otherwise.
    func isEjectableVolumeAsync(_ url: URL) async -> Bool {
        guard let volumeURL = await resolveVolumeMountPointAsync(for: url) else { return false }
        return await isLocalRemovableVolumeAsync(volumeURL)
    }

    private func resolveVolumeMountPointAsync(for url: URL) async -> URL? {
        await Task.detached(priority: .utility) { [weak self] in
            self?.resolveVolumeMountPoint(for: url)
        }.value
    }

    private func isLocalRemovableVolumeAsync(_ url: URL) async -> Bool {
        await Task.detached(priority: .utility) {
            VolumeService.isLocalRemovableVolumeSync(url)
        }.value
    }

    private static nonisolated func isLocalRemovableVolumeSync(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.volumeIsLocalKey, .volumeIsRemovableKey, .volumeIsRootFileSystemKey])

        guard let values else { return false }

        if values.volumeIsRootFileSystem == true { return false }
        if values.volumeIsLocal != true { return false }

        return values.volumeIsRemovable == true || isExternalDriveSync(url)
    }

    private static nonisolated func isExternalDriveSync(_ url: URL) -> Bool {
        let path = url.path(percentEncoded: false)
        return path.hasPrefix("/Volumes/") && path != "/Volumes"
    }

    /// Ejects the volume at the given URL asynchronously.
    ///
    /// - Parameter url: The file URL of the volume to eject.
    /// - Throws: VolumeError.mountPointNotFound if the volume mount point cannot be found.
    ///           VolumeError.notEjectable if the volume is not ejectable.
    ///           VolumeError.unmountFailed if the unmount operation fails.
    func ejectVolume(at url: URL) async throws {
        guard let mountPoint = resolveVolumeMountPoint(for: url) else {
            throw VolumeError.mountPointNotFound
        }

        guard isLocalRemovableVolume(mountPoint) else {
            throw VolumeError.notEjectable
        }

        try await executeUnmount(for: mountPoint)
    }

    private nonisolated func resolveVolumeMountPoint(for url: URL) -> URL? {
        let mountedVolumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeURLKey],
            options: .skipHiddenVolumes
        ) ?? []

        let normalizedPath = url.standardizedFileURL.path
        return mountedVolumes
            .filter { normalizedPath.hasPrefix($0.standardizedFileURL.path) }
            .max(by: { $0.path.count < $1.path.count })
    }

    private nonisolated func isLocalRemovableVolume(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.volumeIsLocalKey, .volumeIsRemovableKey, .volumeIsRootFileSystemKey])

        guard let values else { return false }

        if values.volumeIsRootFileSystem == true { return false }
        if values.volumeIsLocal != true { return false }

        return values.volumeIsRemovable == true || isExternalDrive(url)
    }

    private nonisolated func isExternalDrive(_ url: URL) -> Bool {
        let path = url.path(percentEncoded: false)
        return path.hasPrefix("/Volumes/") && path != "/Volumes"
    }

    private func executeUnmount(for mountPoint: URL) async throws {
        let mountPath = mountPoint.path(percentEncoded: false)

        do {
            try await runDiskUtil(arguments: ["eject", mountPath])
        } catch {
            try await runDiskUtil(arguments: ["unmount", mountPath])
        }
    }

    private func runDiskUtil(arguments: [String]) async throws {
        try await Task.detached(priority: .userInitiated) { [diskUtilPath] in
            guard FileManager.default.isExecutableFile(atPath: diskUtilPath) else {
                throw VolumeError.unmountFailed(NSLocalizedString("DISKUTIL_NOT_FOUND", comment: ""))
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: diskUtilPath)
            process.arguments = arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            try process.run()

            let didExit = await VolumeService.waitForProcess(process, timeout: DISK_UTIL_TIMEOUT_SECONDS)
            if !didExit {
                process.terminate()
                throw VolumeError.unmountFailed(NSLocalizedString("DISKUTIL_TIMEOUT", comment: ""))
            }

            guard process.terminationStatus != 0 else { return }

            let stdoutMsg = VolumeService.readLimitedOutput(from: stdoutPipe.fileHandleForReading)
            let stderrMsg = VolumeService.readLimitedOutput(from: stderrPipe.fileHandleForReading)

            let combined = [stdoutMsg, stderrMsg]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: "; ")

            throw VolumeError.unmountFailed(combined.isEmpty ? NSLocalizedString("UNKNOWN_ERROR", comment: "") : combined)
        }.value
    }

    private static func waitForProcess(_ process: Process, timeout: TimeInterval) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                process.waitUntilExit()
                return true
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }

    private static nonisolated func readLimitedOutput(from fileHandle: FileHandle) -> String? {
        let limitedData = fileHandle.readData(ofLength: MAX_OUTPUT_BYTES)
        return String(data: limitedData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}