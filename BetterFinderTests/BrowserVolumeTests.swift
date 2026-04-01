import XCTest
@testable import BetterFinder

private struct MockVolumeService: VolumeServiceProtocol {
    let mountPointResult: URL?
    let isEjectableResult: Bool

    func volumeMountPoint(for url: URL) -> URL? {
        mountPointResult
    }

    func isEjectableVolume(_ url: URL) -> Bool {
        isEjectableResult
    }

    func isEjectableVolumeAsync(_ url: URL) async -> Bool {
        isEjectableResult
    }
}

final class BrowserVolumeTests: XCTestCase {

    func testVolumeMountPointReturnsNilForRootPath() {
        let service = MockVolumeService(mountPointResult: nil, isEjectableResult: false)
        let rootURL = URL(fileURLWithPath: "/")
        let result = service.volumeMountPoint(for: rootURL)
        XCTAssertNil(result)
    }

    func testVolumeMountPointReturnsNilForVolumesDirectory() {
        let service = MockVolumeService(mountPointResult: nil, isEjectableResult: false)
        let volumesURL = URL(fileURLWithPath: "/Volumes")
        let result = service.volumeMountPoint(for: volumesURL)
        XCTAssertNil(result)
    }

    func testVolumeMountPointReturnsNilForNonVolumePath() {
        let service = MockVolumeService(mountPointResult: nil, isEjectableResult: false)
        let homeURL = URL(fileURLWithPath: "/Users/testuser/Documents")
        let result = service.volumeMountPoint(for: homeURL)
        XCTAssertNil(result)
    }

    func testVolumeMountPointReturnsVolumeForPathUnderVolumes() {
        let expectedVolume = URL(fileURLWithPath: "/Volumes/TestVolume")
        let service = MockVolumeService(mountPointResult: expectedVolume, isEjectableResult: true)
        let fileURL = expectedVolume.appendingPathComponent("testfile.txt")
        let result = service.volumeMountPoint(for: fileURL)
        XCTAssertEqual(result?.standardizedFileURL, expectedVolume.standardizedFileURL)
    }

    func testIsEjectableVolumeReturnsFalseForRoot() {
        let service = MockVolumeService(mountPointResult: nil, isEjectableResult: false)
        let rootURL = URL(fileURLWithPath: "/")
        let result = service.isEjectableVolume(rootURL)
        XCTAssertFalse(result)
    }

    func testIsEjectableVolumeReturnsFalseForNonVolumePath() {
        let service = MockVolumeService(mountPointResult: nil, isEjectableResult: false)
        let homeURL = URL(fileURLWithPath: "/Users/testuser")
        let result = service.isEjectableVolume(homeURL)
        XCTAssertFalse(result)
    }

    func testBrowserStateCurrentVolumeURLReturnsNilForNonVolume() {
        let service = MockVolumeService(mountPointResult: nil, isEjectableResult: false)
        let homeURL = URL(fileURLWithPath: "/Users/testuser")
        let browserState = BrowserState(url: homeURL, fileSystemService: FileSystemService(), volumeService: service)
        XCTAssertNil(browserState.currentVolumeURL)
    }

    func testBrowserStateCurrentVolumeURLReturnsMountPoint() {
        let expectedVolume = URL(fileURLWithPath: "/Volumes/TestVolume")
        let service = MockVolumeService(mountPointResult: expectedVolume, isEjectableResult: true)
        let fileURL = expectedVolume.appendingPathComponent("testfile.txt")
        let browserState = BrowserState(url: fileURL, fileSystemService: FileSystemService(), volumeService: service)
        XCTAssertEqual(browserState.currentVolumeURL?.standardizedFileURL, expectedVolume.standardizedFileURL)
    }

    func testBrowserStateCurrentVolumeIsEjectableReflectsMock() async {
        let expectedVolume = URL(fileURLWithPath: "/Volumes/TestVolume")
        let service = MockVolumeService(mountPointResult: expectedVolume, isEjectableResult: true)
        let fileURL = expectedVolume.appendingPathComponent("testfile.txt")
        let browserState = BrowserState(url: fileURL, fileSystemService: FileSystemService(), volumeService: service)
        XCTAssertTrue(browserState.currentVolumeIsEjectable)
    }
}