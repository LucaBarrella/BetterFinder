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

protocol VolumeServiceProtocol: Sendable {
    func volumeMountPoint(for url: URL) -> URL?
    func isEjectableVolume(_ url: URL) -> Bool
    func isEjectableVolumeAsync(_ url: URL) async -> Bool
}

final class VolumeService: VolumeServiceProtocol {

    private let diskUtilPath = "/usr/sbin/diskutil"

    nonisolated func volumeMountPoint(for url: URL) -> URL? {
        resolveVolumeMountPoint(for: url)
    }

    nonisolated func isEjectableVolume(_ url: URL) -> Bool {
        guard let volumeURL = resolveVolumeMountPoint(for: url) else { return false }
        return isLocalRemovableVolume(volumeURL)
    }

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
        let excludedPaths = ["/", "/Volumes"]
        let validVolumes = mountedVolumes.filter { volume in
            let volumePath = volume.standardizedFileURL.path
            return !excludedPaths.contains(volumePath) && normalizedPath.hasPrefix(volumePath)
        }

        return validVolumes
            .filter { volume in
                let volumePath = volume.standardizedFileURL.path
                let remaining = String(normalizedPath.dropFirst(volumePath.count))
                return remaining.isEmpty || remaining.hasPrefix("/")
            }
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